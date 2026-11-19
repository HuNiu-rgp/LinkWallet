import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/wallets/wallet_actions.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

void main() {
  testWidgets('Wallet dialogs close with Escape or a barrier click', (
    tester,
  ) async {
    final c = WalletController(WalletStore());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final actions = WalletActions(
                () => context,
                c,
                () => context.mounted,
              );
              return TextButton(
                onPressed: () => actions.viewPrivateKey(
                  const Account('Test', 'address', true, Family.tron),
                ),
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(ShadDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ShadDialog), findsNothing);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.byType(ShadDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
