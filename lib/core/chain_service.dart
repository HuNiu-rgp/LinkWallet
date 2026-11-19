import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:web3dart/web3dart.dart';
import 'package:wallet/wallet.dart';
import 'package:on_chain/on_chain.dart' as oc;
import 'models.dart';
import 'address_codec.dart';
import 'amount.dart';

class ChainService {
  final Chain chain;
  final http.Client httpClient;
  late final Web3Client client = Web3Client(chain.rpc, httpClient);
  ChainService(this.chain, {http.Client? httpClient})
    : httpClient = httpClient ?? http.Client();
  static Future<void> _tronQueue = Future<void>.value();

  Future<http.Response> _tronRequest(
    Future<http.Response> Function() send, {
    bool retry = true,
  }) {
    final request = _tronQueue.then((_) async {
      for (var attempt = 0; ; attempt++) {
        final response = await send().timeout(const Duration(seconds: 20));
        if (!retry || response.statusCode != 429 || attempt >= 2) {
          return response;
        }
        await Future<void>.delayed(Duration(seconds: attempt + 1));
      }
    });
    _tronQueue = request
        .then<void>((_) {}, onError: (Object error, StackTrace stack) {})
        .then((_) => Future<void>.delayed(const Duration(milliseconds: 500)));
    return request;
  }

  Future<dynamic> rpc(String method, List<dynamic> params) async {
    final r = await httpClient
        .post(
          Uri.parse(chain.rpc),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'jsonrpc': '2.0',
            'id': 1,
            'method': method,
            'params': params,
          }),
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw StateError('RPC 服务不可用 (${r.statusCode})');
    final j = jsonDecode(r.body) as Map;
    if (j['error'] != null) throw StateError('RPC: ${j['error']['message']}');
    return j['result'];
  }

  Future<Map<String, dynamic>> tron(
    String path,
    Map<String, dynamic> data,
  ) async {
    final r = await _tronRequest(
      () => httpClient.post(
        Uri.parse('${chain.rpc}/wallet/$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      ),
      retry: path != 'broadcasttransaction',
    );
    if (r.statusCode == 429) throw StateError('公共节点请求过于频繁（429），请稍后重试');
    if (r.statusCode != 200) throw StateError('TRON 服务不可用 (${r.statusCode})');
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    if (j['Error'] != null) {
      throw FormatException('节点拒绝操作：${j['Error']}');
    }
    return j;
  }

  Future<TronResources> resources(String address) async {
    if (chain.family != Family.tron) throw StateError('此网络不支持 TRON 资源');
    return TronResources.fromJson(
      await tron('getaccountresource', {'address': address, 'visible': true}),
    );
  }

  Future<BigInt> balance(String address) async {
    switch (chain.family) {
      case Family.evm:
        return (await client
                .getBalance(EthereumAddress.fromHex(address))
                .timeout(const Duration(seconds: 20)))
            .getInWei;
      case Family.solana:
        return BigInt.from(
          (await rpc('getBalance', [
                address,
                {'commitment': 'confirmed'},
              ]))['value']
              as num,
        );
      case Family.tron:
        return BigInt.from(
          (await tron('getaccount', {
                    'address': address,
                    'visible': true,
                  }))['balance']
                  as num? ??
              0,
        );
    }
  }

  Future<List<Map<String, dynamic>>> history(String address) async {
    if (chain.family == Family.solana) {
      final items =
          await rpc('getSignaturesForAddress', [
                address,
                {'limit': 25},
              ])
              as List;
      return items
          .map(
            (e) => <String, dynamic>{
              'hash': e['signature'],
              'status': e['err'] == null ? e['confirmationStatus'] : '失败',
              'timestamp': e['blockTime'] == null
                  ? ''
                  : DateTime.fromMillisecondsSinceEpoch(
                      (e['blockTime'] as int) * 1000,
                    ).toLocal().toString(),
              'detail': 'Solana 链上交易',
            },
          )
          .toList();
    }
    if (chain.family == Family.tron) {
      Future<List> fetch(String suffix) async {
        final r = await _tronRequest(
          () => httpClient.get(
            Uri.parse(
              '${chain.rpc}/v1/accounts/$address/transactions$suffix?limit=25&only_confirmed=true&order_by=block_timestamp,desc',
            ),
          ),
        );
        if (r.statusCode == 429) throw StateError('公共节点请求过于频繁（429），请稍后重试');
        if (r.statusCode != 200) {
          throw StateError('交易记录服务不可用 (${r.statusCode})');
        }
        final body = jsonDecode(r.body) as Map;
        if (body['success'] == false || body['data'] is! List) {
          throw StateError('交易记录响应无效');
        }
        return body['data'] as List;
      }

      final pages = await Future.wait([fetch(''), fetch('/trc20')]);
      final assets = <String, Future<Map<String, dynamic>>>{};
      final native = await Future.wait(
        pages[0].map((e) async {
          final row = parseTronHistory(e as Map, address);
          final contract = (e['raw_data']['contract'] as List).first as Map;
          if (contract['type'] == 'TransferAssetContract') {
            final value = contract['parameter']['value'] as Map;
            final id = _tronText(value['asset_name'].toString());
            final asset = await assets.putIfAbsent(
              id,
              () => tron('getassetissuebyid', {'value': id}),
            );
            if (asset['id'] != null) {
              final from = oc.TronAddress(
                value['owner_address'] as String,
              ).address;
              final to = oc.TronAddress(value['to_address'] as String).address;
              row.addAll({
                'incoming': to == address,
                'counterparty': to == address ? from : to,
                'from': from,
                'to': to,
                'amount': formatEther(
                  BigInt.parse(value['amount'].toString()),
                  asset['precision'] as int? ?? 0,
                ),
                'symbol': _tronText(
                  (asset['abbr'] ?? asset['name'] ?? id).toString(),
                ),
                'assetId': id,
              });
            }
          }
          return row;
        }),
      );
      final tokens = pages[1]
          .where(
            (e) =>
                e['type'] == 'Transfer' && e['token_info']?['decimals'] != null,
          )
          .map((e) => parseTrc20History(e as Map, address))
          .toList();
      final tokenHashes = tokens.map((e) => e['hash']).toSet();
      final combined = [
        ...native.where(
          (e) =>
              e['detail'] != 'TriggerSmartContract' ||
              !tokenHashes.contains(e['hash']),
        ),
        ...tokens,
      ];
      combined.sort(
        (a, b) => (b['timestampMs'] as int).compareTo(a['timestampMs'] as int),
      );
      return combined.take(25).toList();
    }
    if (chain.id == 56) throw StateError('BNB 历史记录需要区块浏览器 API Key；请使用「浏览器查看」');
    final r = await httpClient
        .get(
          Uri.parse('${chain.explorer}/api/v2/addresses/$address/transactions'),
        )
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw StateError('交易记录服务暂不可用 (${r.statusCode})');
    return ((jsonDecode(r.body) as Map)['items'] as List)
        .map(
          (e) => <String, dynamic>{
            'hash': e['hash'],
            'status': e['status'] ?? '待确认',
            'timestamp': e['timestamp'] ?? '',
            'detail':
                '${formatEther(BigInt.parse(e['value'] ?? '0'))} ${chain.symbol}',
          },
        )
        .toList();
  }

  static Map<String, dynamic> parseTronHistory(Map e, String address) {
    final contract = (e['raw_data']['contract'] as List).first as Map;
    final value = contract['parameter']['value'] as Map;
    final isTransfer = contract['type'] == 'TransferContract';
    final from = value['owner_address'] == null
        ? null
        : oc.TronAddress(value['owner_address'] as String).address;
    final to = value['to_address'] == null
        ? null
        : oc.TronAddress(value['to_address'] as String).address;
    final incoming = to == address;
    return {
      'hash': e['txID'],
      'timestampMs': e['block_timestamp'],
      'status': (e['ret'] as List?)?.firstOrNull?['contractRet'] ?? '已确认',
      'timestamp': DateTime.fromMillisecondsSinceEpoch(
        e['block_timestamp'] as int,
      ).toLocal().toString(),
      'detail': contract['type'],
      if (isTransfer) ...{
        'incoming': incoming,
        'counterparty': incoming ? from : to,
        'amount': formatEther(BigInt.parse(value['amount'].toString()), 6),
        'symbol': 'TRX',
      },
    };
  }

  static String _tronText(String value) {
    if (value.length.isEven && RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
      try {
        return utf8.decode(
          List.generate(
            value.length ~/ 2,
            (i) => int.parse(value.substring(i * 2, i * 2 + 2), radix: 16),
          ),
        );
      } catch (_) {
        return value;
      }
    }
    return value;
  }

  static Map<String, dynamic> parseTrc20History(Map e, String address) {
    final token = e['token_info'] as Map;
    final from = oc.TronAddress(e['from'] as String).address;
    final to = oc.TronAddress(e['to'] as String).address;
    return {
      'hash': e['transaction_id'],
      'timestampMs': e['block_timestamp'],
      'timestamp': DateTime.fromMillisecondsSinceEpoch(
        e['block_timestamp'] as int,
      ).toLocal().toString(),
      'status': '已确认',
      'detail': 'TRC20 转账',
      'incoming': to == address,
      'counterparty': to == address ? from : to,
      'from': from,
      'to': to,
      'amount': formatEther(
        BigInt.parse(e['value'].toString()),
        int.parse(token['decimals'].toString()),
      ),
      'symbol': token['symbol'] ?? token['name'] ?? token['address'],
      'tokenAddress': token['address'],
    };
  }

  Future<Map<String, String>> transactionDetails(String hash) async {
    if (chain.family == Family.tron) {
      final tx = await tron('gettransactionbyid', {'value': hash});
      if (tx.isEmpty) throw StateError('未找到交易');
      final info = await tron('gettransactioninfobyid', {'value': hash});
      final contract = (tx['raw_data']['contract'] as List).first as Map;
      final value = contract['parameter']['value'] as Map;
      return {
        '交易哈希': hash,
        '网络': chain.name,
        '状态':
            (tx['ret'] as List?)?.firstOrNull?['contractRet']?.toString() ??
            '待确认',
        '交易类型': contract['type'].toString(),
        if (value['owner_address'] != null)
          '发送地址': oc.TronAddress(value['owner_address'] as String).address,
        if (value['to_address'] != null)
          '接收地址': oc.TronAddress(value['to_address'] as String).address,
        if (contract['type'] == 'TransferContract')
          '金额':
              '${formatEther(BigInt.parse(value['amount'].toString()), 6)} TRX',
        if (value['asset_name'] != null) '资产标识': value['asset_name'].toString(),
        if (info['blockNumber'] != null) '区块高度': info['blockNumber'].toString(),
        if (info['blockTimeStamp'] != null)
          '交易时间': DateTime.fromMillisecondsSinceEpoch(
            info['blockTimeStamp'] as int,
          ).toLocal().toString().split('.').first,
        if (info.isNotEmpty)
          '手续费':
              '${formatEther(BigInt.parse((info['fee'] ?? 0).toString()), 6)} TRX',
      };
    }
    if (chain.family == Family.solana) {
      final tx = await rpc('getTransaction', [
        hash,
        {'encoding': 'jsonParsed', 'maxSupportedTransactionVersion': 0},
      ]);
      if (tx == null) throw StateError('未找到交易');
      return {
        '交易哈希': hash,
        '网络': chain.name,
        '状态': tx['meta']?['err'] == null ? '成功' : '失败',
        '区块高度（Slot）': '${tx['slot']}',
        if (tx['meta']?['fee'] != null)
          '手续费':
              '${formatEther(BigInt.parse(tx['meta']['fee'].toString()), 9)} SOL',
        '交易数据': const JsonEncoder.withIndent('  ').convert(tx),
      };
    }
    final tx = await rpc('eth_getTransactionByHash', [hash]);
    if (tx == null) throw StateError('未找到交易');
    final receipt = await rpc('eth_getTransactionReceipt', [hash]);
    return {
      '交易哈希': hash,
      '网络': chain.name,
      '状态': receipt == null
          ? '待确认'
          : receipt['status'] == '0x1'
          ? '成功'
          : '失败',
      '发送地址': '${tx['from']}',
      '接收地址': tx['to']?.toString() ?? '创建合约',
      '金额':
          '${formatEther(BigInt.parse(tx['value'] as String), chain.decimals)} ${chain.symbol}',
      if (tx['blockNumber'] != null)
        '区块高度': BigInt.parse(tx['blockNumber'] as String).toString(),
      if (receipt?['effectiveGasPrice'] != null)
        '手续费':
            '${formatEther(BigInt.parse(receipt['gasUsed'] as String) * BigInt.parse(receipt['effectiveGasPrice'] as String), chain.decimals)} ${chain.symbol}',
    };
  }

  Future<TransferQuote> quote(String from, String to, BigInt amount) async {
    if (amount <= BigInt.zero) throw const FormatException('金额必须大于 0');
    validateAddress(to, chain.family);
    if (chain.family == Family.solana) {
      final block = await rpc('getLatestBlockhash', [
        {'commitment': 'confirmed'},
      ]);
      final tx = oc.SolanaTransaction(
        instructions: [
          oc.SystemProgram.transfer(
            from: oc.SolAddress(from),
            to: oc.SolAddress(to),
            layout: oc.SystemTransferLayout(lamports: amount),
          ),
        ],
        recentBlockhash: oc.SolAddress.uncheckCurve(
          block['value']['blockhash'] as String,
        ),
        payerKey: oc.SolAddress(from),
      );
      final fee = (await rpc('getFeeForMessage', [
        base64Encode(tx.serializeMessage()),
        {'commitment': 'confirmed'},
      ]))['value'];
      if (fee == null) throw StateError('无法估算手续费');
      final q = TransferQuote(
        BigInt.one,
        BigInt.from(fee as num),
        await balance(from),
        tx,
      );
      if (amount + q.fee > q.balance) throw StateError('余额不足以支付金额和手续费');
      return q;
    }
    if (chain.family == Family.tron) {
      final block = oc.TronBlock.fromJson(await tron('getnowblock', {}));
      final raw = oc.TronTransactionraw(
        refBlockBytes: block.refBlockBytes,
        refBlockHash: block.refBlockHash,
        expiration: BigInt.from(
          DateTime.now().add(const Duration(minutes: 3)).millisecondsSinceEpoch,
        ),
        timestamp: block.blockHeader!.rawData!.timestamp,
        contract: [
          oc.TronTransactionContract(
            parameter: oc.TronTransferContract(
              amount: amount,
              ownerAddress: oc.TronAddress(from),
              toAddress: oc.TronAddress(to),
            ),
          ),
        ],
      );
      // Conservative reserve covers bandwidth burn and new-account activation.
      final q = TransferQuote(
        BigInt.one,
        BigInt.from(2000000),
        await balance(from),
        raw,
      );
      if (amount + q.fee > q.balance) throw StateError('余额不足，需额外预留 2 TRX 资源费用');
      return q;
    }
    if (await client.getChainId() != BigInt.from(chain.id)) {
      throw StateError('RPC 网络不匹配');
    }
    final price = (await client.getGasPrice()).getInWei;
    final gas = await client.estimateGas(
      sender: EthereumAddress.fromHex(from),
      to: EthereumAddress.fromHex(to),
      value: EtherAmount.inWei(amount),
    );
    final q = TransferQuote(
      gas * BigInt.from(120) ~/ BigInt.from(100),
      price,
      await balance(from),
    );
    if (amount + q.fee > q.balance) throw StateError('余额不足以支付金额和手续费');
    return q;
  }

  Future<String> send(
    String secret,
    String to,
    BigInt amount,
    TransferQuote quote,
  ) async {
    if (DateTime.now().difference(quote.created).inSeconds > 45) {
      throw StateError('报价已过期，请重新预览');
    }
    if (chain.family == Family.solana) {
      final tx = quote.payload as oc.SolanaTransaction;
      final key = oc.SolanaPrivateKey.fromSeedHex(secret);
      try {
        tx.sign([key]);
        return await rpc('sendTransaction', [
              base64Encode(tx.serialize(verifySignatures: true)),
              {
                'encoding': 'base64',
                'skipPreflight': false,
                'preflightCommitment': 'confirmed',
              },
            ])
            as String;
      } finally {
        key.dispose();
      }
    }
    if (chain.family == Family.tron) {
      final raw = quote.payload as oc.TronTransactionraw;
      final key = oc.TronPrivateKey.fromHex(secret);
      try {
        final tx = oc.TronTransaction(
          rawData: raw,
          signature: [key.sign(raw.toBuffer())],
        );
        final response = await tron(
          'broadcasttransaction',
          tx.toJson(txID: true, rawDataHex: true),
        );
        if (response['result'] != true) {
          throw StateError('广播失败: ${response['code'] ?? '未知错误'}');
        }
        return raw.txID;
      } finally {
        key.dispose();
      }
    }
    final key = EthPrivateKey.fromHex(secret);
    if (await client.getChainId() != BigInt.from(chain.id)) {
      throw StateError('RPC 网络不匹配');
    }
    return client.sendTransaction(
      key,
      Transaction(
        to: EthereumAddress.fromHex(to),
        value: EtherAmount.inWei(amount),
        maxGas: quote.gas.toInt(),
        gasPrice: EtherAmount.inWei(quote.price),
      ),
      chainId: chain.id,
    );
  }

  void dispose() {
    client.dispose();
    httpClient.close();
  }
}
