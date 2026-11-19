import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/wallets/wallet_actions.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class KeyStore extends WalletStore {
  int reads = 0;
  bool fail = false;
  @override
  Future<String> secret(Account account) async {
    reads++;
    if (fail) throw StateError('unavailable');
    return 'test-private-key';
  }
}

void main() {
  testWidgets('Private key is read only after reveal and hidden on reopen', (
    tester,
  ) async {
    final store = KeyStore();
    final controller = WalletController(store);
    addTearDown(controller.dispose);
    const account = Account('Test wallet', 'Test address', true, Family.tron);
    await tester.pumpWidget(
      ShadApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              final actions = WalletActions(
                () => context,
                controller,
                () => context.mounted,
              );
              return TextButton(
                onPressed: () => actions.viewPrivateKey(account),
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(store.reads, 0);
    expect(find.text('test-private-key'), findsNothing);
    await tester.tap(find.text('显示私钥'));
    await tester.pumpAndSettle();
    expect(store.reads, 1);
    expect(find.text('test-private-key'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('test-private-key'), findsNothing);
    store.fail = true;
    await tester.tap(find.text('显示私钥'));
    await tester.pumpAndSettle();
    expect(find.text('无法读取私钥，请检查系统钥匙串权限后重试'), findsOneWidget);
    expect(find.text('test-private-key'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
