import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:web3dart/web3dart.dart';
import 'models.dart';
import 'address_codec.dart';

class WalletStore {
  final FlutterSecureStorage storage;
  WalletStore({FlutterSecureStorage? storage})
    : storage =
          storage ??
          const FlutterSecureStorage(
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );
  Future<List<Account>> load() async {
    final value = await storage.read(key: 'chainvault.accounts');
    return value == null
        ? []
        : (jsonDecode(value) as List)
              .map((e) => Account.fromJson(e as Map<String, dynamic>))
              .toList();
  }

  Future<void> save(List<Account> accounts) =>
      storage.write(key: 'chainvault.accounts', value: jsonEncode(accounts));
  Future<String> secret(Account account) async {
    final value = await storage.read(
      key: 'chainvault.key.${account.family.name}.${account.address}',
    );
    if (value == null) throw StateError('该钱包没有可用私钥');
    return value;
  }

  Future<Account> add(
    String name,
    String value,
    bool private,
    Family family,
    List<Account> existing, {
    int? chainId,
  }) async {
    final normalized = value.trim().replaceFirst(RegExp(r'^0x'), '');
    if (private && !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(normalized)) {
      throw const FormatException('私钥需为 32 字节十六进制；Solana 使用 seed');
    }
    final address = private
        ? addressForKey(normalized, family)
        : validateAddress(value, family);
    if (existing.any(
      (a) =>
          a.family == family &&
          a.address == address &&
          (a.chainId == null || chainId == null || a.chainId == chainId),
    )) {
      throw StateError('该地址已经存在');
    }
    final account = Account(
      name.trim().isEmpty ? '我的钱包 ${existing.length + 1}' : name.trim(),
      address,
      private,
      family,
      chainId: chainId,
    );
    if (private) {
      await storage.write(
        key: 'chainvault.key.${family.name}.$address',
        value: normalized,
      );
    }
    await save([...existing, account]);
    return account;
  }

  String generateKey() => EthPrivateKey.createRandom(
    Random.secure(),
  ).privateKeyInt.toRadixString(16).padLeft(64, '0');
}
