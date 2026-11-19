import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const account = Account('TRON wallet', 'test-address', true, Family.tron);
  test(
    'Deleting the last wallet removes its record and stored private key',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'chainvault.key.tron.test-address': 'test-key',
      });
      final store = WalletStore();
      await store.save([account]);
      final c = WalletController(store)
        ..accounts = [account]
        ..selected = account;
      addTearDown(c.dispose);
      await c.deleteAccount(account);
      expect(await store.load(), isEmpty);
      expect(c.accounts, isEmpty);
      expect(c.selected, isNull);
      expect(c.transactions, isEmpty);
      await expectLater(store.secret(account), throwsStateError);
    },
  );
  test(
    'Deleting one chain wallet preserves a private key used by another chain',
    () async {
      const eth = Account('ETH', 'same-address', true, Family.evm, chainId: 1);
      const polygon = Account(
        'Polygon',
        'same-address',
        true,
        Family.evm,
        chainId: 137,
      );
      FlutterSecureStorage.setMockInitialValues({
        'chainvault.key.evm.same-address': 'test-key',
      });
      final store = WalletStore();
      await store.save([eth, polygon]);
      await store.remove(polygon, [eth, polygon]);
      expect((await store.load()).single.chainId, 1);
      expect(await store.secret(eth), 'test-key');
    },
  );
}
