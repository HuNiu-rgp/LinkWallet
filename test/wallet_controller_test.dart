import 'dart:async';
import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:chainvault/features/wallets/wallet_actions.dart';
import 'package:flutter_test/flutter_test.dart';

class DeferredWalletStore extends WalletStore {
  final completer = Completer<List<Account>>();
  @override
  Future<List<Account>> load() => completer.future;
}

class RenameStore extends WalletStore {
  List<Account>? saved;
  bool fail = false;
  @override
  Future<void> save(List<Account> accounts) async {
    if (fail) throw StateError('Storage unavailable');
    saved = accounts;
  }
}

void main() {
  test(
    'A chain-specific wallet retains its chain through serialization and rename',
    () async {
      final store = RenameStore();
      final controller = WalletController(store);
      addTearDown(controller.dispose);
      const account = Account(
        'Ethereum',
        'address',
        true,
        Family.evm,
        chainId: 1,
      );
      final restored = Account.fromJson(account.toJson());
      expect(restored.preferredChain.id, 1);
      expect(
        restored.supportsChain(Chain.all.firstWhere((c) => c.id == 137)),
        isFalse,
      );
      controller.accounts = [restored];
      controller.selected = restored;
      await controller.renameAccount(restored, '新名称');
      expect(store.saved!.single.chainId, 1);
      expect(controller.selected!.chainId, 1);
      const legacy = Account('Legacy', 'address', false, Family.evm);
      expect(
        legacy.supportsChain(Chain.all.firstWhere((c) => c.id == 137)),
        isTrue,
      );
    },
  );
  test('Renaming persists the name and updates the selected wallet', () async {
    final store = RenameStore();
    final controller = WalletController(store);
    addTearDown(controller.dispose);
    const account = Account('旧名称', 'address', true, Family.tron);
    controller.accounts = [account];
    controller.selected = account;
    await controller.renameAccount(account, ' 新名称 ');
    expect(store.saved!.single.name, '新名称');
    expect(controller.selected, same(controller.accounts.single));
    expect(controller.selected!.address, account.address);
    expect(controller.selected!.signing, isTrue);
    await expectLater(
      controller.renameAccount(account, '  '),
      throwsFormatException,
    );
    store.fail = true;
    await expectLater(
      controller.renameAccount(account, '失败修改'),
      throwsStateError,
    );
    expect(controller.accounts.single.name, '新名称');
    expect(controller.selected!.name, '新名称');
  });
  test('Disposing controller ignores an outstanding keychain load', () async {
    final store = DeferredWalletStore();
    final controller = WalletController(store);
    var notifications = 0;
    controller.addListener(() => notifications++);
    final loading = controller.load();
    controller.dispose();
    store.completer.complete([]);
    await loading;
    await controller.refresh();
    expect(notifications, 0);
  });
  test('Late notification never accesses a disposed route context', () {
    final controller = WalletController(DeferredWalletStore());
    final actions = WalletActions(
      () => throw StateError('Disposed context accessed'),
      controller,
      () => false,
    );
    expect(() => actions.notify('Completed'), returnsNormally);
    controller.dispose();
  });
}
