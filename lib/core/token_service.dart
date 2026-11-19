import 'dart:convert';
import 'package:on_chain/on_chain.dart' as oc;
import 'address_codec.dart';
import 'chain_service.dart';
import 'models.dart';
import 'token.dart';

class TokenService {
  final ChainService service;
  TokenService(this.service);
  Chain get chain => service.chain;
  static const tokenPrograms = {
    'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA',
    'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb',
  };
  static String evmWord(String address) =>
      address.replaceFirst(RegExp(r'^0x'), '').toLowerCase().padLeft(64, '0');
  static String tronWord(String address) =>
      oc.TronAddress(address).toHex().substring(2).padLeft(64, '0');
  static BigInt uint256(String value) {
    final hex = value.replaceFirst(RegExp(r'^0x'), '');
    if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex)) {
      throw const FormatException('无效合约响应');
    }
    return BigInt.parse(hex, radix: 16);
  }

  Future<String> _call(
    String contract,
    String selector,
    String data,
    String owner,
  ) async {
    if (chain.family == Family.evm) {
      return await service.rpc('eth_call', [
            {'to': contract, 'data': '0x$selector$data'},
            'latest',
          ])
          as String;
    }
    final function = switch (selector) {
      '70a08231' => 'balanceOf(address)',
      '313ce567' => 'decimals()',
      '95d89b41' => 'symbol()',
      _ => throw StateError('不支持的方法'),
    };
    final j = await service.tron('triggerconstantcontract', {
      'owner_address': owner,
      'contract_address': contract,
      'function_selector': function,
      if (data.isNotEmpty) 'parameter': data,
      'visible': true,
    });
    if (j['result']?['result'] != true ||
        j['constant_result'] is! List ||
        (j['constant_result'] as List).isEmpty) {
      throw StateError('合约查询失败');
    }
    return j['constant_result'][0] as String;
  }

  Future<int> decimals(TokenDefinition token, String owner) async =>
      uint256(await _call(token.address, '313ce567', '', owner)).toInt();

  Future<BigInt> balance(TokenDefinition token, String owner) async {
    if (token.chainId != chain.id) throw StateError('代币网络不匹配');
    if (chain.family == Family.solana) {
      final j = await service.rpc('getTokenAccountsByOwner', [
        owner,
        {'mint': token.address},
        {'encoding': 'jsonParsed', 'commitment': 'confirmed'},
      ]);
      return sumSolanaAccounts(j as Map, token, owner);
    }
    final word = chain.family == Family.tron ? tronWord(owner) : evmWord(owner);
    return uint256(await _call(token.address, '70a08231', word, owner));
  }

  static BigInt sumSolanaAccounts(
    Map result,
    TokenDefinition token,
    String owner,
  ) {
    var total = BigInt.zero;
    for (final account in result['value'] as List) {
      final data = account['account'] as Map;
      if (!tokenPrograms.contains(data['owner'])) {
        throw const FormatException('非 SPL 账户');
      }
      final info = data['data']['parsed']['info'] as Map;
      final amount = info['tokenAmount'] as Map;
      if (info['mint'] != token.address ||
          info['owner'] != owner ||
          amount['decimals'] != token.decimals) {
        throw const FormatException('代币账户不匹配');
      }
      final units = BigInt.parse(amount['amount'] as String);
      if (units.isNegative) throw const FormatException('无效余额');
      total += units;
    }
    return total;
  }

  /// Read precision from chain; a Solana symbol is a user label, not issuer metadata.
  Future<TokenDefinition> inspect(
    String input,
    String owner, {
    String label = '',
  }) async {
    final address = validateAddress(input, chain.family);
    late int decimals;
    String symbol = label.trim();
    if (chain.family == Family.solana) {
      final account = (await service.rpc('getAccountInfo', [
        address,
        {'encoding': 'jsonParsed', 'commitment': 'confirmed'},
      ]))['value'];
      if (account == null ||
          !tokenPrograms.contains(account['owner']) ||
          account['data']['parsed']['type'] != 'mint') {
        throw const FormatException('请输入有效的 SPL Mint 地址');
      }
      decimals = account['data']['parsed']['info']['decimals'] as int;
      if (symbol.isEmpty) throw const FormatException('请填写 Solana 代币的显示名称');
    } else {
      decimals = uint256(await _call(address, '313ce567', '', owner)).toInt();
      if (symbol.isEmpty) {
        try {
          symbol = decodeSymbol(await _call(address, '95d89b41', '', owner));
        } catch (_) {
          throw const FormatException('无法读取符号，请手动填写显示名称');
        }
      }
      // Ensure the supplied contract actually supports balanceOf.
      uint256(
        await _call(
          address,
          '70a08231',
          chain.family == Family.tron ? tronWord(owner) : evmWord(owner),
          owner,
        ),
      );
    }
    if (decimals < 0 ||
        decimals > 36 ||
        symbol.isEmpty ||
        symbol.runes.length > 24 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(symbol)) {
      throw const FormatException('代币精度或显示名称无效');
    }
    return TokenDefinition(
      chainId: chain.id,
      address: address,
      symbol: symbol,
      decimals: decimals,
      name: '自定义代币',
      custom: true,
    );
  }

  static String decodeSymbol(String value) {
    final hex = value.replaceFirst(RegExp(r'^0x'), '');
    if (hex.length < 64 ||
        hex.length > 4096 ||
        !RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex) ||
        hex.length.isOdd) {
      throw const FormatException();
    }
    final bytes = List.generate(
      hex.length ~/ 2,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    );
    if (bytes.length == 32) {
      return utf8.decode(bytes.takeWhile((b) => b != 0).toList());
    }
    final offset = uint256(hex.substring(0, 64)).toInt();
    if (offset != 32 || bytes.length < 64) throw const FormatException();
    final length = uint256(hex.substring(64, 128)).toInt();
    if (length < 1 || length > 96 || 64 + length > bytes.length) {
      throw const FormatException();
    }
    return utf8.decode(bytes.sublist(64, 64 + length));
  }
}
