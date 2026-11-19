import 'dart:math';
import 'package:web3dart/web3dart.dart';

String encryptBackup(List<String> args) => Wallet.createNew(
  EthPrivateKey.fromHex(args[0]),
  args[1],
  Random.secure(),
  scryptN: 32768,
).toJson();
String decryptBackup(List<String> args) => Wallet.fromJson(
  args[0],
  args[1],
).privateKey.privateKeyInt.toRadixString(16).padLeft(64, '0');
