String short(String value) => value.length <= 24
    ? value
    : '${value.substring(0, 10)}…${value.substring(value.length - 8)}';

/// Display-only rounding; keep on-chain amounts as integers elsewhere.
String formatBalance(BigInt amount, int decimals) {
  final magnitude = amount.abs();
  final BigInt scaled;
  if (decimals > 3) {
    final divisor = BigInt.from(10).pow(decimals - 3);
    scaled = (magnitude + divisor ~/ BigInt.two) ~/ divisor;
  } else {
    scaled = magnitude * BigInt.from(10).pow(3 - decimals);
  }
  final whole = scaled ~/ BigInt.from(1000);
  final fraction = (scaled % BigInt.from(1000)).toString().padLeft(3, '0');
  final sign = amount.isNegative && scaled != BigInt.zero ? '-' : '';
  return '$sign$whole.$fraction';
}
