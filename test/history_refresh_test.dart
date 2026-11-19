import 'dart:async';
import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/tokens/token_portfolio.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class HistoryService extends ChainService {
  HistoryService() : super(Chain.all.first);
  final result = Completer<List<Map<String, dynamic>>>();
  int historyCalls = 0, otherCalls = 0, balanceCalls = 0, resourceCalls = 0;
  @override
  Future<List<Map<String, dynamic>>> history(String address) {
    historyCalls++;
    return result.future;
  }

  @override
  Future<BigInt> balance(String address) async {
    otherCalls++;
    balanceCalls++;
    return BigInt.zero;
  }

  @override
  Future<TronResources> resources(String address) async {
    otherCalls++;
    resourceCalls++;
    return TronResources(BigInt.zero, BigInt.zero);
  }
}

class CountingTokens extends TokenPortfolio {
  int calls = 0;
  @override
  Future<void> refresh(Chain chain, String? owner) async {
    calls++;
  }
}

void main() {
  test(
    'Broadcast appears immediately, survives index lag and reconciles by hash',
    () async {
      final first = HistoryService(), second = HistoryService();
      var calls = 0;
      final c = WalletController(
        WalletStore(),
        serviceFactory: (_) => calls++ == 0 ? first : second,
      )..selected = const Account('Test', 'address', false, Family.tron);
      addTearDown(c.dispose);
      c.recordBroadcast(c.chain, c.selected!, {
        'hash': 'sent',
        'pending': true,
        'amount': '0.1',
      });
      expect(c.visibleTransactions.single['hash'], 'sent');
      first.result.complete([]);
      await c.refreshHistory();
      expect(c.transactions.single['pending'], true);
      second.result.complete([
        {'hash': 'sent', 'status': 'SUCCESS'},
      ]);
      await c.refreshHistory();
      expect(c.transactions.length, 1);
      expect(c.transactions.single['status'], 'SUCCESS');
      expect(c.transactions.single['pending'], isNull);
    },
  );
  test('Assets refresh queries only balances', () async {
    final service = HistoryService();
    final tokens = CountingTokens();
    final c =
        WalletController(
            WalletStore(),
            tokens: tokens,
            serviceFactory: (_) => service,
          )
          ..selected = const Account('Test', 'address', false, Family.tron)
          ..transactions = [
            {'hash': 'preserved'},
          ]
          ..resources = TronResources(BigInt.one, BigInt.one);
    addTearDown(c.dispose);
    await c.refreshAssets();
    expect(service.balanceCalls, 1);
    expect(tokens.calls, 1);
    expect(service.historyCalls, 0);
    expect(service.resourceCalls, 0);
    expect(c.transactions.single['hash'], 'preserved');
    expect(c.resources!.energy, BigInt.one);
    expect(c.assetsLoading, false);
  });
  test('Resources refresh queries only energy and bandwidth', () async {
    final service = HistoryService();
    final tokens = CountingTokens();
    final c =
        WalletController(
            WalletStore(),
            tokens: tokens,
            serviceFactory: (_) => service,
          )
          ..selected = const Account('Test', 'address', false, Family.tron)
          ..transactions = [
            {'hash': 'preserved'},
          ]
          ..balance = BigInt.from(42);
    addTearDown(c.dispose);
    await c.refreshResources();
    expect(service.resourceCalls, 1);
    expect(service.balanceCalls, 0);
    expect(service.historyCalls, 0);
    expect(tokens.calls, 0);
    expect(c.balance, BigInt.from(42));
    expect(c.transactions.single['hash'], 'preserved');
    expect(c.resourcesLoading, false);
  });
  test(
    'Refreshing history preserves balances and queries only history',
    () async {
      final service = HistoryService();
      final tokens = CountingTokens();
      final c =
          WalletController(
              WalletStore(),
              tokens: tokens,
              serviceFactory: (_) => service,
            )
            ..selected = const Account('Test', 'address', false, Family.tron)
            ..balance = BigInt.from(42)
            ..resources = TronResources(BigInt.from(10), BigInt.from(600));
      addTearDown(c.dispose);
      final pending = c.refreshHistory();
      expect(c.historyLoading, true);
      expect(c.loading, false);
      service.result.complete([
        {'hash': 'new'},
      ]);
      await pending;
      expect(c.historyLoading, false);
      expect(c.transactions.single['hash'], 'new');
      expect(c.balance, BigInt.from(42));
      expect(c.resources!.energy, BigInt.from(10));
      expect(service.historyCalls, 1);
      expect(service.otherCalls, 0);
      expect(tokens.calls, 0);
    },
  );
}
