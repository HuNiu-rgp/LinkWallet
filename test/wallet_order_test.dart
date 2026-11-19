import 'package:chainvault/app/wallet_sidebar.dart';
import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/wallets/wallet_actions.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class OrderStore extends WalletStore {
  List<Account> saved = [];
  bool fail = false;
  @override
  Future<void> save(List<Account> accounts) async {
    if (fail) throw StateError('write failed');
    saved = List.of(accounts);
  }

  @override
  Future<List<Account>> load() async => List.of(saved);
}

const a = Account('A', 'TronAddressA', true, Family.tron);
const b = Account('B', 'TronAddressB', true, Family.tron);
const d = Account('C', 'TronAddressC', true, Family.tron);
const eth = Account('ETH', 'EvmAddress', false, Family.evm);

void main() {
  test(
    'Reordering preserves other network slots, selection and stored order',
    () async {
      final store = OrderStore();
      final c = WalletController(store)
        ..accounts = [a, eth, b, d]
        ..selected = b;
      addTearDown(c.dispose);
      expect(await c.reorderWallets(0, 3), isTrue);
      expect(c.accounts, [b, eth, d, a]);
      expect(await store.load(), [b, eth, d, a]);
      expect(c.selected, same(b));
      expect(await c.reorderWallets(2, 0), isTrue);
      expect(c.accounts, [a, eth, b, d]);
    },
  );

  test('Failed persistence restores order and retains selection', () async {
    final store = OrderStore()..fail = true;
    final c = WalletController(store)
      ..accounts = [a, b]
      ..selected = b;
    addTearDown(c.dispose);
    expect(await c.reorderWallets(0, 2), isFalse);
    expect(c.accounts, [a, b]);
    expect(c.selected, same(b));
    expect(c.reorderingWallets, isFalse);
  });

  testWidgets(
    'Dragging a wallet animates its position and saves without selecting it',
    (tester) async {
      final store = OrderStore();
      final c = WalletController(store)
        ..accounts = [a, b, d]
        ..selected = b;
      addTearDown(c.dispose);
      await tester.pumpWidget(
        ShadApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ListenableBuilder(
                listenable: c,
                builder: (_, _) => WalletSidebar(
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
      final item = find.byKey(const ValueKey('sidebar-wallet-TronAddressA'));
      final gesture = await tester.startGesture(tester.getCenter(item));
      await gesture.moveBy(const Offset(0, 20));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveTo(
        Offset(
          tester.getCenter(item).dx,
          tester.getBottomRight(find.text('C')).dy + 100,
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(c.accounts, [b, d, a]);
      expect(await store.load(), [b, d, a]);
      expect(c.selected, same(b));
      expect(
        tester.getTopLeft(find.text('A')).dy,
        greaterThan(tester.getTopLeft(find.text('C')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
