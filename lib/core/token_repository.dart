import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'address_codec.dart';
import 'models.dart';
import 'token.dart';

class TokenRepository {
  static const key = 'linkwallet.tokens.v1';
  Future<List<TokenDefinition>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return [];
    final tokens = (jsonDecode(raw) as List)
        .map((j) => TokenDefinition.fromJson(j as Map<String, dynamic>))
        .toList();
    final ids = <String>{};
    for (final token in tokens) {
      final chain = Chain.all.firstWhere((c) => c.id == token.chainId);
      validateAddress(token.address, chain.family);
      if (token.decimals < 0 ||
          token.decimals > 36 ||
          token.symbol.isEmpty ||
          token.symbol.runes.length > 24 ||
          !ids.add(token.id)) {
        throw const FormatException('代币配置无效');
      }
    }
    return tokens;
  }

  Future<void> save(List<TokenDefinition> tokens) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.setString(
      key,
      jsonEncode(tokens.map((t) => t.toJson()).toList()),
    )) {
      throw StateError('无法保存代币配置');
    }
  }
}
