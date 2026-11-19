BigInt parseEther(String input, [int decimals = 18]) {
  if (decimals < 0 || decimals > 36) {
    throw const FormatException('代币精度超出范围');
  }
  final pattern = decimals == 0 ? r'^\d+$' : '^\\d+(\\.\\d{1,$decimals})?\$';
  if (!RegExp(pattern).hasMatch(input.trim())) {
    throw const FormatException('请输入有效金额');
  }
  final parts = input.trim().split('.');
  return BigInt.parse(parts[0]) * BigInt.from(10).pow(decimals) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(decimals, '0'));
}

String formatEther(BigInt wei, [int decimals = 18]) {
  final base = BigInt.from(10).pow(decimals);
  final fraction = (wei % base)
      .toString()
      .padLeft(decimals, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${wei ~/ base}${fraction.isEmpty ? '' : '.$fraction'}';
}
