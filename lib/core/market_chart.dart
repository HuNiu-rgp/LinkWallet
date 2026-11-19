import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'token.dart';

class MarketChart {
  static Uri? directUrl(Chain chain, TokenDefinition? token) {
    if (token == null) {
      return Uri.https('www.tradingview.com', '/chart/', {
        'symbol': 'BINANCE:${chain.symbol}USDT',
      });
    }
    if (token.chainId != chain.id) {
      throw const FormatException('币种与当前链不匹配');
    }
    final preset = presetTokens(chain).where((t) => t.id == token.id).firstOrNull;
    if (preset != null && (preset.symbol == 'USDT' || preset.symbol == 'USDC')) {
      return Uri.https('www.tradingview.com', '/chart/', {
        'symbol': 'COINBASE:${preset.symbol}USD',
      });
    }
    return null;
  }

  static Future<Uri> resolve(Chain chain, TokenDefinition? token) async {
    final direct = directUrl(chain, token);
    if (direct != null) return direct;
    final network = switch (chain.id) {
      728126428 => 'tron',
      0 => 'solana',
      137 => 'polygon',
      56 => 'bsc',
      1 => 'ethereum',
      _ => throw const FormatException('暂不支持当前链的行情'),
    };
    final response = await http.get(Uri.https('api.dexscreener.com', '/token-pairs/v1/$network/${token!.address}')).timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw const FormatException('行情服务暂不可用，请稍后重试');
    }
    final pairs = (jsonDecode(response.body) as List).whereType<Map>().where((pair) {
      final address = pair['baseToken']?['address']?.toString();
      return pair['chainId'] == network && address != null &&
          (chain.family == Family.evm ? address.toLowerCase() == token.address.toLowerCase() : address == token.address);
    }).toList();
    double liquidity(Map pair) => (pair['liquidity']?['usd'] as num?)?.toDouble() ?? 0;
    pairs.sort((a, b) => liquidity(b).compareTo(liquidity(a)));
    for (final pair in pairs) {
      final url = Uri.tryParse(pair['url']?.toString() ?? '');
      if (url != null && url.scheme == 'https' && url.host == 'dexscreener.com') {
        return url;
      }
    }
    throw const FormatException('未找到该币种的 K 线交易对');
  }
}
