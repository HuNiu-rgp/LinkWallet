import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/core/token.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'History includes only portfolio transfers then applies the dust filter',
    () {
      final c = WalletController(WalletStore());
      addTearDown(c.dispose);
      Map<String, dynamic> native(String amount) => {
        'amount': amount,
        'incoming': true,
        'symbol': 'TRX',
        'detail': 'TransferContract',
      };
      final usdt = {
        'amount': '268.56',
        'incoming': true,
        'symbol': 'USDT',
        'tokenAddress': presetTokens(c.chain).single.address,
      };
      c.transactions = [
        native('0.000005'),
        native('0.999999999999999999'),
        native('1'),
        usdt,
        {
          'amount': '8888888',
          'incoming': true,
          'symbol': 'USDT',
          'tokenAddress': 'fake-contract',
        },
        {'detail': 'UnDelegateResourceContract', 'status': 'SUCCESS'},
        {
          'amount': '9999',
          'incoming': true,
          'symbol': 'spam',
          'assetId': '123',
        },
      ];
      expect(c.visibleTransactions, [c.transactions[2], usdt]);
      c.setHideSmallTransactions(false);
      expect(c.visibleTransactions, c.transactions.sublist(0, 4));
    },
  );
}
