import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/core/tron_governance.dart';
import 'package:chainvault/features/governance/resource_details.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class DetailsApi extends TronGovernance {
  DetailsApi(super.service);
  @override
  Future<List<Map<String, dynamic>>> resourceDelegations(
    String address, {
    required bool incoming,
  }) async => [
    {
      'peer': 'TestRecipientAddress',
      'resource': 'ENERGY',
      'sun': BigInt.from(2000000),
      'expires': BigInt.zero,
    },
  ];
}

void main() {
  testWidgets('Actions stay visible at right in a narrow resource table', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = ChainService(Chain.all.first);
    addTearDown(service.dispose);
    String? operation, recipient;
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ResourceDetails(
              api: DetailsApi(service),
              owner: const Account('Test', 'owner', true, Family.tron),
              account: {
                'frozenV2': [
                  {'type': 'ENERGY', 'amount': 1000000},
                ],
              },
              resources: const {},
              onOperate: (kind, resource, receiver) async {
                operation = kind;
                recipient = receiver;
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ShadTabs<int>), findsOneWidget);
    expect(find.byType(ShadTable), findsNWidgets(2));
    await tester.tap(find.text('解除质押').last);
    expect(operation, 'unstake');
    await tester.tap(find.text('代理给他人'));
    await tester.pumpAndSettle();
    expect(find.text('搜索接收账户地址'), findsOneWidget);
    expect(find.text('收回').hitTestable(), findsOneWidget);
    await tester.drag(
      find.byKey(const ValueKey('resource-table-2-data')),
      const Offset(-500, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('收回').hitTestable(), findsOneWidget);
    await tester.tap(find.text('收回'));
    expect(operation, 'undelegate');
    expect(recipient, 'TestRecipientAddress');
    expect(tester.takeException(), isNull);
  });
}
