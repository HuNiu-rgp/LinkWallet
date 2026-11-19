import 'models.dart';
import 'token.dart';

/// Binds the approved token, recipient, units and serialized transaction.
class TokenTransferQuote extends TransferQuote {
  final TokenDefinition token;
  final String from, recipient, feeNote;
  final BigInt amount;
  TokenTransferQuote({
    required this.token,
    required this.from,
    required this.recipient,
    required this.amount,
    required BigInt gas,
    required BigInt price,
    required BigInt balance,
    required Object transaction,
    this.feeNote = '',
  }) : super(gas, price, balance, transaction);
}
