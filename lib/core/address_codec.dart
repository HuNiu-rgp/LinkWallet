import 'package:wallet/wallet.dart';
import 'package:on_chain/on_chain.dart' as oc;
import 'models.dart';

String validateAddress(String value, Family family) {
  final input = value.trim();
  if (family == Family.evm) {
    if (!RegExp(r'^(0x)?[a-fA-F0-9]{40}$').hasMatch(input)) {
      throw const FormatException('无效 EVM 地址');
    }
    return EthereumAddress.fromHex(input, enforceEip55: true).eip55With0x;
  }
  return family == Family.tron
      ? oc.TronAddress(input).address
      : oc.SolAddress.uncheckCurve(input).address;
}

String addressForKey(String value, Family family) {
  switch (family) {
    case Family.evm:
      final key = oc.ETHPrivateKey.fromHex(value);
      try {
        return validateAddress(key.publicKey().toAddress().address, family);
      } finally {
        key.dispose();
      }
    case Family.tron:
      final key = oc.TronPrivateKey.fromHex(value);
      try {
        return key.publicKey().toAddress().address;
      } finally {
        key.dispose();
      }
    case Family.solana:
      final key = oc.SolanaPrivateKey.fromSeedHex(value);
      try {
        return key.publicKey().toAddress().address;
      } finally {
        key.dispose();
      }
  }
}
