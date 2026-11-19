import 'dart:async';
import 'dart:convert';
import 'package:chainvault/core/amount.dart';
import 'package:chainvault/core/chain_service.dart';
import 'package:chainvault/core/models.dart';
import 'package:chainvault/core/token.dart';
import 'package:chainvault/core/token_repository.dart';
import 'package:chainvault/core/token_service.dart';
import 'package:chainvault/features/tokens/token_portfolio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

String word(BigInt n) => n.toRadixString(16).padLeft(64, '0');
http.Response rpcReply(Map request, Object? result) => http.Response(
  jsonEncode({'jsonrpc': '2.0', 'id': request['id'], 'result': result}),
  200,
);

class MemoryTokens extends TokenRepository {
  List<TokenDefinition> saved = [];
  @override
  Future<List<TokenDefinition>> load() async => List.of(saved);
  @override
  Future<void> save(List<TokenDefinition> tokens) async {
    saved = List.of(tokens);
  }
}

void main() {
  final eth = Chain.all.firstWhere((c) => c.id == 1);
  final tron = Chain.all.first;
  final sol = Chain.all.firstWhere((c) => c.family == Family.solana);
  const owner = '0x7e5f4552091a69125d5dfcb7b8c2659029395bdf';
  const tronOwner = 'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC';
  test(
    'ERC20 balanceOf uses exact units and addresses, no floating point',
    () async {
      final units = BigInt.parse('900719925474099312345678');
      final service = ChainService(
        eth,
        httpClient: MockClient((r) async {
          final request = jsonDecode(r.body) as Map;
          expect(request['method'], 'eth_call');
          expect(
            request['params'][0]['data'],
            '0x70a08231${TokenService.evmWord(owner)}',
          );
          expect(request['params'][0]['to'], presetTokens(eth).first.address);
          return rpcReply(request, '0x${word(units)}');
        }),
      );
      final amount = await TokenService(
        service,
      ).balance(presetTokens(eth).first, owner);
      expect(formatEther(amount, 6), '900719925474099312.345678');
      service.dispose();
    },
  );
  test(
    'TRC20 strips network prefix in ABI argument; failure is not zero',
    () async {
      final service = ChainService(
        tron,
        httpClient: MockClient((r) async {
          final request = jsonDecode(r.body) as Map;
          expect(request['visible'], true);
          expect(request['function_selector'], 'balanceOf(address)');
          expect(
            request['parameter'],
            '${'0' * 24}7e5f4552091a69125d5dfcb7b8c2659029395bdf',
          );
          return http.Response(
            jsonEncode({
              'result': {'result': true},
              'constant_result': [word(BigInt.from(123456789))],
            }),
            200,
          );
        }),
      );
      expect(
        await TokenService(
          service,
        ).balance(presetTokens(tron).first, tronOwner),
        BigInt.from(123456789),
      );
      service.dispose();
      final failing = ChainService(
        tron,
        httpClient: MockClient(
          (_) async => http.Response('{"result":{"result":false}}', 200),
        ),
      );
      await expectLater(
        TokenService(failing).balance(presetTokens(tron).first, tronOwner),
        throwsStateError,
      );
      failing.dispose();
    },
  );
  test(
    'SPL sums all matching accounts, ignores imprecise uiAmount, validates ownership',
    () {
      final token = presetTokens(sol).first;
      const owner = 'So11111111111111111111111111111111111111112';
      Map account(String amount) => {
        'account': {
          'owner': TokenService.tokenPrograms.first,
          'data': {
            'parsed': {
              'info': {
                'owner': owner,
                'mint': token.address,
                'tokenAmount': {'amount': amount, 'decimals': 6, 'uiAmount': 0},
              },
            },
          },
        },
      };
      final result = {
        'value': [account('9007199254740993123'), account('7')],
      };
      expect(
        TokenService.sumSolanaAccounts(result, token, owner),
        BigInt.parse('9007199254740993130'),
      );
      expect(
        TokenService.sumSolanaAccounts({'value': []}, token, owner),
        BigInt.zero,
      );
      expect(
        () => TokenService.sumSolanaAccounts(result, token, 'different-owner'),
        throwsFormatException,
      );
    },
  );
  test(
    'Symbol supports bytes32 and dynamic ABI strings, rejects invalid payload',
    () {
      expect(
        TokenService.decodeSymbol(
          utf8
              .encode('USDT')
              .map((b) => b.toRadixString(16).padLeft(2, '0'))
              .join()
              .padRight(64, '0'),
        ),
        'USDT',
      );
      expect(
        TokenService.decodeSymbol(
          '${word(BigInt.from(32))}${word(BigInt.from(4))}55534443${'0' * 56}',
        ),
        'USDC',
      );
      expect(() => TokenService.decodeSymbol('0x'), throwsFormatException);
      expect(() => TokenService.uint256('0x'), throwsFormatException);
    },
  );
  test('Custom token precision and symbol are read from chain', () async {
    final service = ChainService(
      eth,
      httpClient: MockClient((r) async {
        final request = jsonDecode(r.body) as Map;
        final data = request['params'][0]['data'] as String;
        return rpcReply(request, switch (data.substring(0, 10)) {
          '0x313ce567' => '0x${word(BigInt.from(8))}',
          '0x95d89b41' => '0x${'54455354'.padRight(64, '0')}',
          _ => '0x${word(BigInt.zero)}',
        });
      }),
    );
    final token = await TokenService(service).inspect(owner, owner);
    expect(token.symbol, 'TEST');
    expect(token.decimals, 8);
    expect(token.custom, true);
    service.dispose();
  });
  test(
    'Custom token definitions persist and remain scoped to their network',
    () async {
      SharedPreferences.setMockInitialValues({});
      final t = TokenDefinition(
        chainId: 1,
        address: owner,
        symbol: 'TEST',
        decimals: 8,
        name: '自定义代币',
        custom: true,
      );
      await TokenRepository().save([t]);
      final loaded = await TokenRepository().load();
      expect(loaded.single.id, t.id);
      expect(loaded.single.decimals, 8);
      expect(
        presetTokens(
          Chain.all.firstWhere((c) => c.id == 56),
        ).every((t) => t.decimals == 18),
        true,
      );
    },
  );
  test(
    'One failed token never wipes another balance or fabricates zero',
    () async {
      final portfolio = TokenPortfolio(
        repository: MemoryTokens(),
        serviceFactory: (chain) => ChainService(
          chain,
          httpClient: MockClient((r) async {
            final request = jsonDecode(r.body) as Map;
            if (request['params'][0]['to'] == presetTokens(eth).last.address) {
              return http.Response('unavailable', 503);
            }
            return rpcReply(request, '0x${word(BigInt.zero)}');
          }),
        ),
      );
      await portfolio.refresh(eth, owner);
      expect(portfolio.balances.first.amount, BigInt.zero);
      expect(portfolio.balances.last.amount, isNull);
      expect(portfolio.balances.last.error, isNotNull);
      expect(portfolio.loading, false);
      portfolio.dispose();
    },
  );
  test(
    'Switching networks discards an outstanding old balance response',
    () async {
      final pending = Completer<http.Response>();
      final started = Completer<void>();
      final portfolio = TokenPortfolio(
        repository: MemoryTokens(),
        serviceFactory: (chain) => ChainService(
          chain,
          httpClient: MockClient((r) async {
            if (!started.isCompleted) started.complete();
            return pending.future;
          }),
        ),
      );
      final old = portfolio.refresh(eth, owner);
      await started.future;
      await portfolio.refresh(sol, null);
      pending.complete(
        http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'result': '0x${word(BigInt.from(999))}',
          }),
          200,
        ),
      );
      await old;
      expect(
        portfolio.balances.every(
          (b) => b.token.chainId == sol.id && b.amount == null,
        ),
        true,
      );
      portfolio.dispose();
    },
  );
}
