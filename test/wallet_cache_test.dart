import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/tokens/token_portfolio.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CachedTokens extends TokenPortfolio {
  int calls = 0;
  @override
  Future<void> refresh(Chain chain, String? owner) async {
    calls++;
  }
}

class Queries {
  final counts = <String, int>{};
  Completer<BigInt>? delayedA;
  void count(String kind, String address) =>
      counts.update('$kind:$address', (v) => v + 1, ifAbsent: () => 1);
}

class CacheService extends ChainService {
  final Queries queries;
  CacheService(super.chain, this.queries);
  @override
  Future<BigInt> balance(String address) async {
    queries.count('balance', address);
    if (address == 'A' && queries.delayedA != null) {
      return queries.delayedA!.future;
    }
    return BigInt.from(address == 'A' ? 10 : 20);
  }

  @override
  Future<TronResources> resources(String address) async {
    queries.count('resources', address);
    return TronResources(
      BigInt.from(address == 'A' ? 100 : 200),
      BigInt.from(600),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> history(String address) async {
    queries.count('history', address);
    return [
      {'hash': address},
    ];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  const a = Account('A', 'A', false, Family.tron);
  const b = Account('B', 'B', false, Family.tron);
  test('Token balances restore from memory without new RPC requests', () async {
    var calls = 0;
    final chain = Chain.all.firstWhere((c) => c.id == 56);
    final portfolio = TokenPortfolio(
      serviceFactory: (network) => ChainService(
        network,
        httpClient: MockClient((request) async {
          calls++;
          final body = jsonDecode(request.body) as Map;
          return http.Response(
            jsonEncode({
              'jsonrpc': '2.0',
              'id': body['id'],
              'result': BigInt.from(calls).toRadixString(16).padLeft(64, '0'),
            }),
            200,
          );
        }),
      ),
    );
    addTearDown(portfolio.dispose);
    const first = '0x0000000000000000000000000000000000000001';
    const second = '0x0000000000000000000000000000000000000002';
    await portfolio.refresh(chain, first);
    final amounts = portfolio.balances.map((b) => b.amount).toList();
    await portfolio.refresh(chain, second);
    final count = calls;
    portfolio.restore(chain, first);
    expect(portfolio.balances.map((b) => b.amount).toList(), amounts);
    expect(calls, count);
    expect(portfolio.loading, false);
  });
  test(
    'Wallet switching uses session cache; explicit refresh and restart query again',
    () async {
      final queries = Queries();
      final tokens = CachedTokens();
      final c = WalletController(
        WalletStore(),
        tokens: tokens,
        serviceFactory: (chain) => CacheService(chain, queries),
      );
      addTearDown(c.dispose);
      c.selected = a;
      await c.showWallet();
      c.selected = b;
      await c.showWallet();
      c.selected = a;
      await c.showWallet();
      expect(c.balance, BigInt.from(10));
      expect(c.resources!.energy, BigInt.from(100));
      expect(c.transactions.single['hash'], 'A');
      expect(queries.counts['balance:A'], 1);
      expect(queries.counts['history:A'], 1);
      expect(tokens.calls, 2);
      await c.refreshHistory();
      expect(queries.counts['history:A'], 2);
      expect(queries.counts['balance:A'], 1);
      final fresh = WalletController(
        WalletStore(),
        tokens: CachedTokens(),
        serviceFactory: (chain) => CacheService(chain, queries),
      )..selected = a;
      addTearDown(fresh.dispose);
      await fresh.showWallet();
      expect(queries.counts['balance:A'], 2);
    },
  );
  test('Switching away during first load reuses its pending query', () async {
    final queries = Queries()..delayedA = Completer<BigInt>();
    final c = WalletController(
      WalletStore(),
      tokens: CachedTokens(),
      serviceFactory: (chain) => CacheService(chain, queries),
    )..selected = a;
    addTearDown(c.dispose);
    final first = c.showWallet();
    c.selected = b;
    await c.showWallet();
    expect(c.balance, BigInt.from(20));
    c.selected = a;
    final returning = c.showWallet();
    queries.delayedA!.complete(BigInt.from(33));
    await Future.wait([first, returning]);
    expect(c.balance, BigInt.from(33));
    expect(queries.counts['balance:A'], 1);
    expect(c.transactions.single['hash'], 'A');
  });
}
