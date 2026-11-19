import 'dart:async';
import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/core/tron_governance.dart';
import 'package:chainvault/features/governance/tron_governance_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/on_chain.dart' as oc;
import 'package:shadcn_ui/shadcn_ui.dart';

final owner = addressForKey('1'.padLeft(64, '0'), Family.tron);
final sr = addressForKey('2'.padLeft(64, '0'), Family.tron);

class FixtureService extends ChainService {
  FixtureService() : super(Chain.all.first);
  int broadcasts = 0;
  bool reject = false;
  Map<String, dynamic>? validated;
  @override
  Future<BigInt> balance(String address) async => BigInt.from(1000000000);
  @override
  Future<Map<String, dynamic>> tron(
    String path,
    Map<String, dynamic> data,
  ) async {
    switch (path) {
      case 'getaccount':
        return {
          'balance': 1000000000,
          'frozenV2': [
            {'type': 'ENERGY', 'amount': 100000000},
          ],
          'votes': [
            {'vote_address': sr, 'vote_count': 50},
          ],
        };
      case 'getaccountresource':
        return {
          'EnergyLimit': 10000,
          'TotalEnergyWeight': 20000,
          'TotalEnergyLimit': 200000,
          'EnergyUsed': 200,
          'freeNetLimit': 600,
          'tronPowerLimit': 100,
        };
      case 'listwitnesses':
        return {
          'witnesses': [
            {'address': sr, 'url': 'Representative', 'voteCount': 100000},
          ],
        };
      case 'getcandelegatedmaxsize':
        return {'max_size': 100000000};
      case 'getReward':
        return {'reward': 2000000};
      case 'getchainparameters':
        return {
          'chainParameter': [
            {'key': 'getTransactionFee', 'value': 1000},
            {'key': 'getUnfreezeDelayDays', 'value': 14},
          ],
        };
      case 'getnowblock':
        return oc.TronBlock(
          blockHeader: oc.TronBlockHeader(
            rawData: oc.TronBlockHeaderraw(
              timestamp: BigInt.from(DateTime.now().millisecondsSinceEpoch),
              number: BigInt.from(100),
            ),
          ),
        ).toJson();
      case 'delegateresource':
      case 'freezebalancev2':
      case 'votewitnessaccount':
        validated = data;
        if (reject) return {};
        return {
          'raw_data': {'untrusted': 'not signed'},
        };
      case 'broadcasttransaction':
        broadcasts++;
        return {'result': true};
      default:
        throw StateError(path);
    }
  }
}

class FixtureStore extends WalletStore {
  final String key;
  FixtureStore(this.key);
  @override
  Future<String> secret(Account account) async => key;
}

class DelayedAccountService extends FixtureService {
  final pendingOwner = Completer<Map<String, dynamic>>();
  final requested = <String>[];
  @override
  Future<Map<String, dynamic>> tron(
    String path,
    Map<String, dynamic> data,
  ) async {
    if (path == 'getaccount') {
      requested.add(data['address'] as String);
      if (data['address'] == owner) return pendingOwner.future;
      return {'balance': 2000000, 'frozenV2': [], 'votes': []};
    }
    return super.tron(path, data);
  }
}

void main() {
  testWidgets(
    'Delegation wallet picker excludes self and other chains and fills recipient',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = FixtureService();
      addTearDown(service.dispose);
      final current = Account('当前钱包', owner, true, Family.tron);
      final recipient = Account('接收钱包', sr, false, Family.tron);
      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(
            body: GovernanceOperationDialog(
              api: TronGovernance(service),
              account: current,
              store: WalletStore(),
              kind: 'delegate',
              resource: 'ENERGY',
              votes: const {},
              totalPower: BigInt.zero,
              unstakeDays: '14',
              accounts: [
                current,
                recipient,
                const Account(
                  'Ethereum钱包',
                  '0x0000000000000000000000000000000000000001',
                  true,
                  Family.evm,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('select-resource-wallet')));
      await tester.pumpAndSettle();
      expect(find.text('接收钱包'), findsOneWidget);
      expect(find.text('Ethereum钱包'), findsNothing);
      expect(find.text('当前钱包'), findsNothing);
      await tester.tap(find.text('接收钱包'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText).last)
            .controller
            .text,
        sr,
      );
      expect(find.text('选择资源接收钱包'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test(
    'Node validates operation; local transaction is signed only on explicit send',
    () async {
      final service = FixtureService();
      addTearDown(service.dispose);
      final api = TronGovernance(service);
      final account = Account('Wallet', owner, true, Family.tron);
      final contract = TronGovernance.contract(
        'stake',
        owner,
        amount: BigInt.from(5000000),
      );
      final quote = await api.preview(
        account,
        contract,
        spend: BigInt.from(5000000),
      );
      expect(service.validated!['owner_address'], owner);
      expect(service.validated!['visible'], isTrue);
      expect(service.broadcasts, 0);
      expect(
        (quote.payload as oc.TronTransactionraw).contract.single.parameter,
        isA<oc.TronFreezeBalanceV2Contract>(),
      );
      await expectLater(
        api.send(account, FixtureStore('2'.padLeft(64, '0')), quote),
        throwsFormatException,
      );
      expect(service.broadcasts, 0);
      await api.send(account, FixtureStore('1'.padLeft(64, '0')), quote);
      expect(service.broadcasts, 1);
      await api.preview(
        account,
        TronGovernance.voteContract(owner, {sr: BigInt.from(60)}),
      );
      final tooLarge = TronGovernance.contract(
        'delegate',
        owner,
        amount: BigInt.from(101000000),
        receiver: sr,
      );
      await expectLater(
        api.preview(account, tooLarge),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'maximum',
            contains('超过可代理上限'),
          ),
        ),
      );
      expect(service.broadcasts, 1);
      service.reject = true;
      await expectLater(api.preview(account, contract), throwsFormatException);
      expect(service.broadcasts, 1);
    },
  );
  testWidgets('Native resource and voting pages load and preserve allocation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ShadApp(
        home: TronGovernancePage(
          account: Account('Wallet', owner, true, Family.tron),
          store: WalletStore(),
          vote: false,
          service: FixtureService(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('质押获取资源'), findsOneWidget);
    expect(find.text('自行质押：100 TRX'), findsOneWidget);
    await tester.tap(find.text('投票'));
    await tester.pumpAndSettle();
    expect(find.text('分配 50 票'), findsOneWidget);
    await tester.tap(find.text('分配 50 票'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(
            of: find.byType(ShadDialog),
            matching: find.byType(EditableText),
          )
          .last,
      '60',
    );
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();
    expect(find.text('分配 60 票'), findsOneWidget);
    await tester.tap(find.text('预览并提交投票'));
    await tester.pumpAndSettle();
    expect(find.text('本次完整投票分配：'), findsOneWidget);
    expect(find.text('$sr：60 票'), findsOneWidget);
    await tester.tap(find.text('预览操作'));
    await tester.pumpAndSettle();
    expect(find.text('确认并签名发送'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 400));
  });
  testWidgets(
    'Switching governance wallet drops old responses and applies watch-only permissions',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final service = DelayedAccountService();
      final primary = Account('质押钱包', owner, true, Family.tron);
      final watch = Account('观察钱包', sr, false, Family.tron);
      Account? changed;
      await tester.pumpWidget(
        ShadApp(
          home: TronGovernancePage(
            account: primary,
            accounts: [
              primary,
              watch,
              Account('EVM wallet', '0x${'1' * 40}', true, Family.evm),
            ],
            store: WalletStore(),
            vote: false,
            service: service,
            onAccountChanged: (account) => changed = account,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(
        find.byKey(const ValueKey('governance-wallet-selector')),
      );
      // Advance the select overlay while the intentionally pending old wallet
      // keeps its progress indicator animating (so pumpAndSettle is unsuitable).
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('EVM wallet'), findsNothing);
      await tester.tap(find.text('观察钱包 · 仅观察'));
      await tester.pumpAndSettle();
      expect(changed!.address, sr);
      expect(service.requested.last, sr);
      expect(find.text('2'), findsOneWidget);
      service.pendingOwner.complete({
        'balance': 1000000000,
        'votes': [
          {'vote_address': sr, 'vote_count': 50},
        ],
        'frozenV2': [
          {'type': 'ENERGY', 'amount': 100000000},
        ],
      });
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      expect(find.text('自行质押：100 TRX'), findsNothing);
      await tester.tap(find.text('投票'));
      await tester.pumpAndSettle();
      expect(find.text('分配 0 票'), findsOneWidget);
      expect(find.text('分配 50 票'), findsNothing);
      final voteButton = find.widgetWithText(ShadButton, '分配 0 票');
      expect(tester.widget<ShadButton>(voteButton).onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
