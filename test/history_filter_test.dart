import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Dust filter preserves boundary and unknown amounts and can be disabled',
    () {
      final c = WalletController(WalletStore());
      addTearDown(c.dispose);
      c.transactions = [
        {'amount': '0.000005'},
        {'amount': '0.999999999999999999'},
        {'amount': '1'},
        {'amount': '-1.2'},
        {'detail': 'TransferAssetContract'},
      ];
      expect(c.visibleTransactions, c.transactions.sublist(2));
      c.setHideSmallTransactions(false);
      expect(c.visibleTransactions, c.transactions);
    },
  );
}
