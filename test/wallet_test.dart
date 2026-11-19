import 'dart:convert';
import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/core/backup_codec.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/on_chain.dart' as oc;

void main() {
  const one =
      '0000000000000000000000000000000000000000000000000000000000000001';
  test('Native precision is exact on all chain families', () {
    expect(parseEther('0.000001', 6), BigInt.one);
    expect(parseEther('0.000000001', 9), BigInt.one);
    expect(
      parseEther('9007199254740993.123456789012345678'),
      BigInt.parse('9007199254740993123456789012345678'),
    );
    for (final d in [6, 9, 18]) {
      final amount = parseEther('1234.000001', d);
      expect(formatEther(amount, d), '1234.000001');
      expect(() => parseEther('0.${'0' * d}1', d), throwsFormatException);
    }
    for (final value in ['-1', '1e9', 'NaN', '', '1.2.3']) {
      expect(() => parseEther(value), throwsFormatException);
    }
  });
  test('Known secp256k1 key derives Ethereum and TRON addresses', () {
    expect(
      addressForKey(one, Family.evm).toLowerCase(),
      '0x7e5f4552091a69125d5dfcb7b8c2659029395bdf',
    );
    expect(
      addressForKey(one, Family.tron),
      'TMVQGm1qAQYVdetCeGRRkTWYYrLXuHK2HC',
    );
    expect(() => addressForKey('0' * 64, Family.evm), throwsA(anything));
  });
  test('Solana derivation matches RFC8032 Ed25519 vector', () {
    const seed =
        '9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60';
    const pub =
        'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a';
    final bytes = List.generate(
      32,
      (i) => int.parse(pub.substring(i * 2, i * 2 + 2), radix: 16),
    );
    expect(
      addressForKey(seed, Family.solana),
      oc.SolAddress.fromPublicKey(bytes).address,
    );
  });
  test('Address validation rejects cross-chain and trailing garbage', () {
    final eth = addressForKey(one, Family.evm);
    expect(
      () => validateAddress(
        '$eth'
        'aa',
        Family.evm,
      ),
      throwsFormatException,
    );
    expect(() => validateAddress(eth, Family.tron), throwsA(anything));
    expect(
      () => validateAddress('not-a-solana-address', Family.solana),
      throwsA(anything),
    );
    expect(validateAddress(eth, Family.evm).toLowerCase(), eth.toLowerCase());
  });
  test(
    'Password encrypted backup restores secret and rejects wrong password',
    () {
      final encoded = encryptBackup([one, 'test password 12345']);
      expect((jsonDecode(encoded) as Map)['version'], 3);
      expect(encoded.contains(one), isFalse);
      expect(decryptBackup([encoded, 'test password 12345']), one);
      expect(
        () => decryptBackup([encoded, 'incorrect password']),
        throwsA(anything),
      );
    },
  );
}
