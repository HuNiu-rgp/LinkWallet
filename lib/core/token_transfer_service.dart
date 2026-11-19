import 'dart:typed_data';
import 'dart:convert';
import 'package:on_chain/on_chain.dart' as oc;
import 'package:web3dart/web3dart.dart';
import 'package:wallet/wallet.dart';
import 'address_codec.dart';
import 'amount.dart';
import 'chain_service.dart';
import 'models.dart';
import 'token.dart';
import 'token_service.dart';
import 'token_transfer_quote.dart';
import 'solana_token_transfer.dart';

class TokenTransferService {
  final ChainService service;
  TokenTransferService(this.service);
  Chain get chain => service.chain;
  static String transferData(String recipientWord, BigInt amount) {
    if (amount <= BigInt.zero || amount.bitLength > 256) {
      throw const FormatException('代币金额无效');
    }
    return 'a9059cbb$recipientWord${amount.toRadixString(16).padLeft(64, '0')}';
  }

  static Uint8List hexBytes(String hex) => Uint8List.fromList(
    List.generate(
      hex.length ~/ 2,
      (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
    ),
  );

  /// Older USDT returns no data; standard ERC20 must explicitly return true.
  static void validateReturn(String value) {
    final hex = value.replaceFirst(RegExp(r'^0x'), '');
    if (hex.isEmpty) return;
    if (TokenService.uint256(hex) != BigInt.one) {
      throw const FormatException('代币合约拒绝转账，未发送交易');
    }
  }

  static void validateTronSimulation(
    Map<String, dynamic> simulation, {
    String? contractAddress,
  }) {
    try {
      if (simulation['result']?['result'] != true) {
        throw const FormatException('节点报告模拟执行失败');
      }
      final results = simulation['constant_result'];
      if (results is! List || results.isEmpty || results.first is! String) {
        throw const FormatException('节点未返回有效的合约执行结果');
      }
      final statuses = simulation['transaction']?['ret'];
      if (statuses is List &&
          statuses.any(
            (status) =>
                status is Map &&
                status['contractRet'] != null &&
                status['contractRet'] != 'SUCCESS',
          )) {
        throw const FormatException('合约模拟执行状态失败');
      }
      if (simulation['resMessage']?.toString().isNotEmpty == true ||
          simulation['result']?['message']?.toString().isNotEmpty == true) {
        throw const FormatException('节点返回执行异常说明');
      }
      final value = results.first as String;
      // Mainnet Tether's transfer returns false even on successful execution.
      // Restrict this compatibility rule to the exact known USDT contract.
      final legacyUsdtZero =
          contractAddress == 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t' &&
          RegExp(r'^(0x)?0{64}$').hasMatch(value);
      if (!legacyUsdtZero) {
        validateReturn(value);
      }
    } on FormatException catch (e) {
      String decodeMessage(Object? value) {
        final raw = value?.toString() ?? '';
        if (raw.isEmpty) return '未提供';
        try {
          if (raw.length.isEven && RegExp(r'^[0-9a-fA-F]+$').hasMatch(raw)) {
            return utf8.decode(hexBytes(raw));
          }
          // TRON nodes may encode result.message as base64.
          final decoded = utf8.decode(base64.decode(raw));
          if (decoded.runes.every((c) => c >= 32 || c == 10 || c == 13)) {
            return decoded;
          }
        } catch (_) {
          // Preserve readable node messages when they are not encoded.
        }
        return raw;
      }

      final result = simulation['result'];
      final details = {
        'result': result,
        'constant_result': simulation['constant_result'],
        if (simulation.containsKey('energy_used'))
          'energy_used': simulation['energy_used'],
        if (simulation.containsKey('resMessage'))
          'resMessage': simulation['resMessage'],
        if (simulation.containsKey('transaction'))
          'execution_status': simulation['transaction']?['ret'],
      };
      throw FormatException(
        '转账模拟未通过，未签名、未发送交易。\n'
        '${e.message}\n'
        '节点说明：${decodeMessage(simulation['resMessage'] ?? (result is Map ? result['message'] : null))}\n'
        '模拟返回：${jsonEncode(details)}',
      );
    }
  }

  Future<TokenTransferQuote> quote(
    TokenDefinition token,
    String from,
    String to,
    BigInt amount,
  ) async {
    if (token.chainId != chain.id) throw const FormatException('代币与当前网络不匹配');
    validateAddress(token.address, chain.family);
    validateAddress(from, chain.family);
    final recipient = validateAddress(to, chain.family);
    if (amount <= BigInt.zero || amount.bitLength > 256) {
      throw const FormatException('金额必须大于 0 且在代币范围内');
    }
    if (chain.family == Family.solana) {
      return SolanaTokenTransfer(service).quote(token, from, recipient, amount);
    }
    final tokens = TokenService(service);
    if (await tokens.decimals(token, from) != token.decimals) {
      throw const FormatException('链上精度已变化，请移除后重新添加代币');
    }
    if (amount > await tokens.balance(token, from)) {
      throw const FormatException('代币余额不足');
    }
    if (chain.family == Family.tron) {
      return _tronQuote(token, from, recipient, amount);
    }
    if (await service.client.getChainId() != BigInt.from(chain.id)) {
      throw const FormatException('RPC 网络不匹配');
    }
    final data = transferData(TokenService.evmWord(recipient), amount);
    validateReturn(
      await service.rpc('eth_call', [
            {
              'from': from,
              'to': token.address,
              'value': '0x0',
              'data': '0x$data',
            },
            'latest',
          ])
          as String,
    );
    final gas =
        (await service.client.estimateGas(
          sender: EthereumAddress.fromHex(from),
          to: EthereumAddress.fromHex(token.address),
          value: EtherAmount.inWei(BigInt.zero),
          data: hexBytes(data),
        )) *
        BigInt.from(120) ~/
        BigInt.from(100);
    final price = (await service.client.getGasPrice()).getInWei;
    final nativeBalance = await service.balance(from);
    if (nativeBalance < gas * price) {
      throw FormatException(
        '${chain.symbol} 不足以支付手续费，需要预留 ${formatEther(gas * price, chain.decimals)} ${chain.symbol}',
      );
    }
    final tx = Transaction(
      to: EthereumAddress.fromHex(token.address),
      value: EtherAmount.inWei(BigInt.zero),
      data: hexBytes(data),
      maxGas: gas.toInt(),
      gasPrice: EtherAmount.inWei(price),
    );
    return TokenTransferQuote(
      token: token,
      from: from,
      recipient: recipient,
      amount: amount,
      gas: gas,
      price: price,
      balance: nativeBalance,
      transaction: tx,
    );
  }

  static BigInt estimateTronBurn({
    required BigInt energyBudget,
    required BigInt bandwidthBytes,
    required BigInt energyPrice,
    required BigInt bandwidthPrice,
    required Map<String, dynamic> resources,
  }) {
    BigInt remaining(String limit, String used) {
      final value =
          BigInt.parse((resources[limit] ?? 0).toString()) -
          BigInt.parse((resources[used] ?? 0).toString());
      return value > BigInt.zero ? value : BigInt.zero;
    }

    final shortfall = energyBudget - remaining('EnergyLimit', 'EnergyUsed');
    final energyBurn =
        (shortfall > BigInt.zero ? shortfall : BigInt.zero) * energyPrice;
    // Bandwidth pools cannot be combined to cover a single transaction.
    final covered =
        remaining('NetLimit', 'NetUsed') >= bandwidthBytes ||
        remaining('freeNetLimit', 'freeNetUsed') >= bandwidthBytes;
    return energyBurn +
        (covered ? BigInt.zero : bandwidthBytes * bandwidthPrice);
  }

  Future<TokenTransferQuote> _tronQuote(
    TokenDefinition token,
    String from,
    String recipient,
    BigInt amount,
  ) async {
    final data = transferData(TokenService.tronWord(recipient), amount);
    final simulation = await service.tron('triggerconstantcontract', {
      'owner_address': from,
      'contract_address': token.address,
      'function_selector': 'transfer(address,uint256)',
      'parameter': data.substring(8),
      'visible': true,
    });
    try {
      validateTronSimulation(simulation, contractAddress: token.address);
    } on FormatException catch (e) {
      throw FormatException(
        '${e.message}\n\n网络：${chain.name}\n代币合约：${token.address}\n发送地址：$from\n收款地址：$recipient\n金额：${formatEther(amount, token.decimals)} ${token.symbol}',
      );
    }
    final energyUsed = BigInt.parse(
      (simulation['energy_used'] ?? 0).toString(),
    );
    if (energyUsed <= BigInt.zero) throw const FormatException('无法估算合约能量费用');
    final parameters =
        (await service.tron('getchainparameters', {}))['chainParameter']
            as List;
    BigInt parameter(String key) => BigInt.parse(
      parameters.firstWhere((e) => e['key'] == key)['value'].toString(),
    );
    final energyPrice = parameter('getEnergyFee'),
        bandwidthPrice = parameter('getTransactionFee');
    if (energyPrice <= BigInt.zero || bandwidthPrice <= BigInt.zero) {
      throw const FormatException('无法读取当前链上费率');
    }
    final energyBudget =
        (energyUsed * BigInt.from(130) + BigInt.from(99)) ~/ BigInt.from(100);
    final feeLimit = energyBudget * energyPrice;
    if (feeLimit > parameter('getMaxFeeLimit')) {
      throw const FormatException('合约能量预算超过链上上限');
    }
    final block = oc.TronBlock.fromJson(await service.tron('getnowblock', {}));
    final raw = oc.TronTransactionraw(
      refBlockBytes: block.refBlockBytes,
      refBlockHash: block.refBlockHash,
      expiration: BigInt.from(
        DateTime.now().add(const Duration(minutes: 3)).millisecondsSinceEpoch,
      ),
      timestamp: block.blockHeader!.rawData!.timestamp,
      feeLimit: feeLimit,
      contract: [
        oc.TronTransactionContract(
          parameter: oc.TronTriggerSmartContract(
            ownerAddress: oc.TronAddress(from),
            contractAddress: oc.TronAddress(token.address),
            callValue: BigInt.zero,
            data: hexBytes(data),
          ),
        ),
      ],
    );
    // Signed transaction envelope + conservative bandwidth buffer.
    final bandwidthBytes = BigInt.from(raw.toBuffer().length + 256);
    final resources = await service.tron('getaccountresource', {
      'address': from,
      'visible': true,
    });
    final fee = estimateTronBurn(
      energyBudget: energyBudget,
      bandwidthBytes: bandwidthBytes,
      energyPrice: energyPrice,
      bandwidthPrice: bandwidthPrice,
      resources: resources,
    );
    final nativeBalance = await service.balance(from);
    if (nativeBalance < fee) {
      throw FormatException(
        'TRX 余额不足，抵扣当前能量和带宽后仍需预留 ${formatEther(fee, 6)} TRX',
      );
    }
    return TokenTransferQuote(
      token: token,
      from: from,
      recipient: recipient,
      amount: amount,
      gas: BigInt.one,
      price: fee,
      balance: nativeBalance,
      transaction: raw,
      feeNote:
          '模拟能量 $energyUsed，含 30% 余量的能量预算 $energyBudget；带宽预算 $bandwidthBytes。已抵扣当前能量及可覆盖整笔交易的带宽，预计 TRX 消耗上限 ${formatEther(fee, 6)}。链上 fee_limit 为 ${formatEther(feeLimit, 6)} TRX（能量预算，并非必扣金额）。资源会随其他交易变化，实际费用以链上结果为准。',
    );
  }

  Future<String> send(TokenTransferQuote quote, String secret) async {
    if (quote.token.chainId != chain.id ||
        DateTime.now().difference(quote.created).inSeconds > 45) {
      throw const FormatException('交易预览已过期，请重新预览');
    }
    final signer = addressForKey(secret, chain.family);
    if (validateAddress(signer, chain.family) !=
        validateAddress(quote.from, chain.family)) {
      throw const FormatException('签名钱包与转出地址不匹配');
    }
    if (chain.family != Family.evm) {
      return service.send(secret, quote.recipient, quote.amount, quote);
    }
    if (await service.client.getChainId() != BigInt.from(chain.id)) {
      throw const FormatException('RPC 网络不匹配');
    }
    return service.client.sendTransaction(
      EthPrivateKey.fromHex(secret),
      quote.payload as Transaction,
      chainId: chain.id,
    );
  }
}
