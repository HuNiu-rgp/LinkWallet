import 'package:chainvault/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Resources subtract usage and combine both bandwidth sources', () {
    final r = TronResources.fromJson({
      'EnergyLimit': 100000,
      'EnergyUsed': 5000,
      'freeNetLimit': 600,
      'freeNetUsed': 120,
      'NetLimit': 1500,
      'NetUsed': 320,
    });
    expect(r.energy, BigInt.from(95000));
    expect(r.bandwidth, BigInt.from(1660));
  });
  test(
    'Missing fields default to zero and overuse cannot reduce another pool',
    () {
      final r = TronResources.fromJson({'freeNetLimit': 600, 'NetUsed': 100});
      expect(r.energy, BigInt.zero);
      expect(r.bandwidth, BigInt.from(600));
      expect(TronResources.fromJson({}).bandwidth, BigInt.zero);
    },
  );
}
