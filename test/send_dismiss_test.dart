import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/wallets/wallet_actions.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:chainvault/features/transfers/send_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('Transfer dialog closes on backdrop click and Escape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = WalletController(WalletStore());
    addTearDown(controller.dispose);
    controller.selected = const Account('钱包', 'address', true, Family.tron);
    await tester.pumpWidget(
      ShadApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => WalletActions(
                () => context,
                controller,
                () => context.mounted,
              ).send(),
              child: const Text('打开转账'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开转账'));
    await tester.pumpAndSettle();
    expect(find.byType(SendDialog), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byType(SendDialog), findsNothing);
    await tester.tap(find.text('打开转账'));
    await tester.pumpAndSettle();
    expect(find.byType(SendDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(SendDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
