import 'package:chainvault/shared/formatters.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Balances round to three decimals without floating point loss', () {
    expect(formatBalance(BigInt.parse('231070338248683745418'), 18), '231.070');
    expect(formatBalance(BigInt.from(377581089), 6), '377.581');
    expect(formatBalance(BigInt.from(2017486535), 6), '2017.487');
    expect(formatBalance(BigInt.from(999999), 6), '1.000');
    expect(formatBalance(BigInt.zero, 18), '0.000');
    expect(formatBalance(BigInt.from(12), 2), '0.120');
    expect(
      formatBalance(BigInt.parse('123456789012345678901234000000'), 6),
      '123456789012345678901234.000',
    );
  });
}
