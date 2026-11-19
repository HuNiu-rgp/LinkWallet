import 'dart:convert';
import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/core/token.dart';
import 'package:chainvault/features/dashboard/history_card.dart';
import 'package:chainvault/features/wallets/wallet_actions.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:on_chain/on_chain.dart' as oc;
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> row(int i) => {
  'hash': '$i',
  'detail': 'TransferContract',
  'amount': '${100 + i}',
  'symbol': 'TRX',
  'incoming': true,
  'status': 'SUCCESS',
  'timestamp': '2026-11-19T10:00:00',
};

class PageService extends ChainService {
  PageService() : super(Chain.all.first);
  @override
  Future<List<Map<String, dynamic>>> history(String address) async {
    final start = historyCursor?['offset'] as int? ?? 0;
    if (start < 14) nextHistoryCursor = {'offset': start + 7};
    return [
      for (var i = start; i < (start == 14 ? 17 : start + 7); i++) row(i),
    ];
  }
}

class RetryPageService extends PageService {
  final bool fail;
  RetryPageService(this.fail);
  @override
  Future<List<Map<String, dynamic>>> history(String address) async {
    if (fail && historyCursor != null) throw StateError('offline');
    return super.history(address);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
    'Seven rows per page, remote continuation, back, filter reset and last-page disable',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = WalletController(
        WalletStore(),
        serviceFactory: (_) => PageService(),
      )..selected = const Account('Test', 'address', false, Family.tron);
      addTearDown(c.dispose);
      await c.refreshHistory();
      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ListenableBuilder(
                listenable: c,
                builder: (_, _) => HistoryCard(
                  c: c,
                  actions: WalletActions(
                    () => context,
                    c,
                    () => context.mounted,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.pagedTransactions.length, 7);
      expect(find.text('+100 TRX'), findsOneWidget);
      expect(find.text('+107 TRX'), findsNothing);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(c.historyPage, 1);
      expect(find.text('+107 TRX'), findsOneWidget);
      expect(find.text('+100 TRX'), findsNothing);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(c.pagedTransactions.length, 3);
      expect(
        tester
            .widget<ShadButton>(find.widgetWithText(ShadButton, '下一页'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.text('上一页'));
      await tester.pumpAndSettle();
      expect(c.historyPage, 1);
      c.setHideSmallTransactions(false);
      await tester.pumpAndSettle();
      expect(c.historyPage, 0);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'TRON cursors merge native/token streams in order without dropping buffered rows',
    () async {
      final token = presetTokens(Chain.all.first).single;
      final from = oc.TronAddress.zero.address;
      final to = oc.TronAddress(
        '410000000000000000000000000000000000000001',
      ).address;
      Map<String, dynamic> native(int time) => {
        'txID': 'native-$time',
        'block_timestamp': time,
        'raw_data': {
          'contract': [
            {
              'type': 'TransferContract',
              'parameter': {
                'value': {
                  'owner_address': from,
                  'to_address': to,
                  'amount': 1000000,
                },
              },
            },
          ],
        },
      };
      Map<String, dynamic> trc(int time) => {
        'transaction_id': 'token-$time',
        'block_timestamp': time,
        'from': from,
        'to': to,
        'value': '2000000',
        'type': 'Transfer',
        'token_info': {
          'address': token.address,
          'symbol': 'USDT',
          'decimals': 6,
        },
      };
      final requests = <Uri>[];
      Map<String, dynamic>? cursor;
      final all = <Map<String, dynamic>>[];
      for (var page = 0; page < 3; page++) {
        final service =
            ChainService(
                Chain.all.first,
                httpClient: MockClient((request) async {
                  requests.add(request.url);
                  final fp = request.url.queryParameters['fingerprint'];
                  final isToken = request.url.path.endsWith('/trc20');
                  final times = isToken
                      ? (fp == null
                            ? [110, 105]
                            : fp == 't1'
                            ? [104, 103]
                            : [102, 99])
                      : (fp == null ? [100, 90] : [80, 70]);
                  final next = isToken
                      ? (fp == null
                            ? 't1'
                            : fp == 't1'
                            ? 't2'
                            : null)
                      : fp == null
                      ? 'n1'
                      : null;
                  return http.Response(
                    jsonEncode({
                      'success': true,
                      'data': times.map(isToken ? trc : native).toList(),
                      'meta': {'fingerprint': ?next},
                    }),
                    200,
                  );
                }),
              )
              ..paginateHistory = true
              ..historyCursor = cursor
              ..historyTokenContracts = {token.address};
        all.addAll(await service.history(to));
        cursor = service.nextHistoryCursor;
        service.dispose();
      }
      expect(cursor, isNull);
      expect(all.map((e) => e['timestampMs']), [
        110,
        105,
        104,
        103,
        102,
        100,
        99,
        90,
        80,
        70,
      ]);
      expect(all.map((e) => e['hash']).toSet().length, all.length);
      expect(
        requests
            .where((r) => r.path.endsWith('/trc20'))
            .map((r) => r.queryParameters['fingerprint']),
        [null, 't1', 't2'],
      );
      expect(requests.where((r) => !r.path.endsWith('/trc20')).length, 2);
    },
  );
  test('Failed next page keeps existing rows and cursor for retry', () async {
    var fail = true;
    final c = WalletController(
      WalletStore(),
      serviceFactory: (_) => RetryPageService(fail),
    )..selected = const Account('Test', 'address', false, Family.tron);
    addTearDown(c.dispose);
    await c.refreshHistory();
    await c.nextHistoryPage();
    expect(c.historyPage, 0);
    expect(c.pagedTransactions.length, 7);
    expect(c.historyError, 'offline');
    fail = false;
    await c.nextHistoryPage();
    expect(c.historyPage, 1);
    expect(c.pagedTransactions.first['hash'], '7');
    expect(c.historyError, isNull);
  });

  test(
    'EVM forwards next_page_params and clears cursor on the final response',
    () async {
      final urls = <Uri>[];
      final service = ChainService(
        Chain.all.last,
        httpClient: MockClient((request) async {
          urls.add(request.url);
          return http.Response(
            jsonEncode({
              'items': [],
              'next_page_params': urls.length == 1
                  ? {'block_number': 12, 'index': 2}
                  : null,
            }),
            200,
          );
        }),
      )..paginateHistory = true;
      addTearDown(service.dispose);
      await service.history('0x1111111111111111111111111111111111111111');
      service.historyCursor = service.nextHistoryCursor;
      await service.history('0x1111111111111111111111111111111111111111');
      expect(urls.last.queryParameters, {'block_number': '12', 'index': '2'});
      expect(service.nextHistoryCursor, isNull);
    },
  );
}
