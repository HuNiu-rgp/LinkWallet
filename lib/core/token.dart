import 'models.dart';

class TokenDefinition {
  final int chainId, decimals;
  final String address, symbol, name;
  final bool custom;
  const TokenDefinition({
    required this.chainId,
    required this.address,
    required this.symbol,
    required this.decimals,
    required this.name,
    this.custom = false,
  });
  String get id =>
      '$chainId:${chainId == 0 || chainId == 728126428 ? address : address.toLowerCase()}';
  Map<String, dynamic> toJson() => {
    'chainId': chainId,
    'address': address,
    'symbol': symbol,
    'decimals': decimals,
    'name': name,
  };
  factory TokenDefinition.fromJson(Map<String, dynamic> j) => TokenDefinition(
    chainId: j['chainId'] as int,
    address: j['address'] as String,
    symbol: j['symbol'] as String,
    decimals: j['decimals'] as int,
    name: j['name'] as String,
    custom: true,
  );
}

class TokenBalance {
  final TokenDefinition token;
  final BigInt? amount;
  final String? error;
  const TokenBalance(this.token, {this.amount, this.error});
}

/// Presets are a watch list, not a claim that these are all assets at an address.
/// Sources and bridge distinctions are recorded in docs/token-assets.md.
List<TokenDefinition> presetTokens(Chain chain) => switch (chain.id) {
  728126428 => [
    const TokenDefinition(
      chainId: 728126428,
      address: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      symbol: 'USDT',
      decimals: 6,
      name: 'Tether USD · TRC20',
    ),
  ],
  0 => [
    const TokenDefinition(
      chainId: 0,
      address: 'Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB',
      symbol: 'USDT',
      decimals: 6,
      name: 'Tether USD · SPL',
    ),
    const TokenDefinition(
      chainId: 0,
      address: 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v',
      symbol: 'USDC',
      decimals: 6,
      name: 'USD Coin · SPL',
    ),
  ],
  137 => [
    const TokenDefinition(
      chainId: 137,
      address: '0xc2132d05d31c914a87c6611c10748aeb04b58e8f',
      symbol: 'USDT0',
      decimals: 6,
      name: 'USDT0 · Polygon',
    ),
    const TokenDefinition(
      chainId: 137,
      address: '0x3c499c542cef5e3811e1192ce70d8cc03d5c3359',
      symbol: 'USDC',
      decimals: 6,
      name: 'USD Coin · 原生 USDC',
    ),
  ],
  56 => [
    const TokenDefinition(
      chainId: 56,
      address: '0x55d398326f99059ff775485246999027b3197955',
      symbol: 'USDT',
      decimals: 18,
      name: 'Binance-Peg BSC-USD',
    ),
    const TokenDefinition(
      chainId: 56,
      address: '0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d',
      symbol: 'USDC',
      decimals: 18,
      name: 'Binance-Peg USD Coin',
    ),
  ],
  1 => [
    const TokenDefinition(
      chainId: 1,
      address: '0xdac17f958d2ee523a2206206994597c13d831ec7',
      symbol: 'USDT',
      decimals: 6,
      name: 'Tether USD · ERC20',
    ),
    const TokenDefinition(
      chainId: 1,
      address: '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48',
      symbol: 'USDC',
      decimals: 6,
      name: 'USD Coin · ERC20',
    ),
  ],
  _ => [],
};
