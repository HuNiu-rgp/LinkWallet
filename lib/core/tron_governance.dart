import 'package:on_chain/on_chain.dart' as oc;
import 'wallet.dart';

class TronGovernance {
  final ChainService service;
  TronGovernance(this.service);
  Future<Map<String, dynamic>> load(String address) async {
    final account = await service.tron('getaccount', {
      'address': address,
      'visible': true,
    });
    final resources = await service.tron('getaccountresource', {
      'address': address,
      'visible': true,
    });
    final witnesses = await service.tron('listwitnesses', {'visible': true});
    final reward = await service.tron('getReward', {
      'address': address,
      'visible': true,
    });
    final parameters = await service.tron('getchainparameters', {});
    return {
      'account': account,
      'resources': resources,
      'witnesses': witnesses['witnesses'] ?? [],
      'reward': reward['reward'] ?? 0,
      'parameters': parameters['chainParameter'] ?? [],
    };
  }

  Future<List<Map<String, dynamic>>> resourceDelegations(
    String address, {
    required bool incoming,
  }) async {
    final index = await service.tron('getdelegatedresourceaccountindexv2', {
      'value': address,
      'visible': true,
    });
    final peers =
        (index[incoming ? 'fromAccounts' : 'toAccounts'] as List? ?? [])
            .map((a) => oc.TronAddress(a as String).address)
            .toSet();
    final rows = <Map<String, dynamic>>[];
    for (final peer in peers) {
      final response = await service.tron('getdelegatedresourcev2', {
        'fromAddress': incoming ? peer : address,
        'toAddress': incoming ? address : peer,
        'visible': true,
      });
      rows.addAll(delegationRows(peer, response));
    }
    return rows;
  }

  Future<BigInt> reclaimableStake(
    String owner,
    String receiver,
    String resource,
  ) async {
    final response = await service.tron('getdelegatedresourcev2', {
      'fromAddress': owner,
      'toAddress': receiver,
      'visible': true,
    });
    return reclaimableAmount(
      response,
      resource,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static BigInt reclaimableAmount(Map response, String resource, int now) =>
      delegationRows('', response)
          .where(
            (row) =>
                row['resource'] == resource &&
                (row['expires'] as BigInt) <= BigInt.from(now),
          )
          .fold(BigInt.zero, (sum, row) => sum + (row['sun'] as BigInt));

  static List<Map<String, dynamic>> delegationRows(String peer, Map response) =>
      [
        for (final record in response['delegatedResource'] as List? ?? [])
          for (final resource in ['ENERGY', 'BANDWIDTH'])
            if (number(record['frozen_balance_for_${resource.toLowerCase()}']) >
                BigInt.zero)
              {
                'peer': peer,
                'resource': resource,
                'sun': number(
                  record['frozen_balance_for_${resource.toLowerCase()}'],
                ),
                'expires': number(
                  record['expire_time_for_${resource.toLowerCase()}'],
                ),
              },
      ];

  static BigInt? resourceEstimate(BigInt sun, String resource, Map resources) {
    final prefix = resource == 'ENERGY' ? 'Energy' : 'Net';
    final weight = number(resources['Total${prefix}Weight']);
    final limit = number(resources['Total${prefix}Limit']);
    if (weight <= BigInt.zero || limit <= BigInt.zero) return null;
    return sun * limit ~/ (BigInt.from(1000000) * weight);
  }

  Future<DelegationBudget> delegationBudget(
    String owner,
    String resource,
  ) async {
    final limit = await service.tron('getcandelegatedmaxsize', {
      'owner_address': owner,
      'type': resource == 'ENERGY' ? 1 : 0,
      'visible': true,
    });
    final resources = await service.tron('getaccountresource', {
      'address': owner,
      'visible': true,
    });
    final prefix = resource == 'ENERGY' ? 'Energy' : 'Net';
    if (number(resources['Total${prefix}Weight']) <= BigInt.zero ||
        number(resources['Total${prefix}Limit']) <= BigInt.zero) {
      throw const FormatException('无法获取资源兑换比例，请刷新后重试');
    }
    return DelegationBudget(
      number(limit['max_size']),
      number(resources['Total${prefix}Weight']),
      number(resources['Total${prefix}Limit']),
    );
  }

  static BigInt number(Object? value) =>
      BigInt.tryParse(value?.toString() ?? '') ?? BigInt.zero;
  static BigInt stake(Map account, String resource) =>
      (account['frozenV2'] as List? ?? [])
          .where((e) => (e['type'] ?? 'BANDWIDTH') == resource)
          .fold(BigInt.zero, (sum, e) => sum + number(e['amount']));
  static Map<String, BigInt> votes(Map account) => {
    for (final vote in account['votes'] as List? ?? [])
      oc.TronAddress(vote['vote_address'] as String).address: number(
        vote['vote_count'],
      ),
  };
  static oc.ITronContract contract(
    String kind,
    String owner, {
    String resource = 'ENERGY',
    BigInt? amount,
    String? receiver,
    Map<String, BigInt> votes = const {},
  }) {
    final address = oc.TronAddress(owner);
    final code = resource == 'ENERGY'
        ? oc.TronResourceCode.energy
        : oc.TronResourceCode.bandwidth;
    if (kind == 'stake' ||
        kind == 'unstake' ||
        kind == 'delegate' ||
        kind == 'undelegate') {
      if (amount == null || amount < BigInt.from(1000000)) {
        throw const FormatException('数量至少为 1 TRX');
      }
    }
    return switch (kind) {
      'stake' => oc.TronFreezeBalanceV2Contract(
        ownerAddress: address,
        frozenBalance: amount,
        resource: code,
      ),
      'unstake' => oc.TronUnfreezeBalanceV2Contract(
        ownerAddress: address,
        unfreezeBalance: amount,
        resource: code,
      ),
      'delegate' => oc.TronDelegateResourceContract(
        ownerAddress: address,
        resource: code,
        balance: amount,
        receiverAddress: oc.TronAddress(
          validateAddress(receiver!, Family.tron),
        ),
        lock: false,
      ),
      'undelegate' => oc.TronUnDelegateResourceContract(
        ownerAddress: address,
        resource: code,
        balance: amount,
        receiverAddress: oc.TronAddress(
          validateAddress(receiver!, Family.tron),
        ),
      ),
      'withdraw' => oc.TronWithdrawExpireUnfreezeContract(
        ownerAddress: address,
      ),
      'reward' => oc.TronWithdrawBalanceContract(ownerAddress: address),
      'vote' => voteContract(owner, votes),
      _ => throw const FormatException('不支持的操作'),
    };
  }

  static oc.TronVoteWitnessContract voteContract(
    String owner,
    Map<String, BigInt> votes,
  ) {
    if (votes.isEmpty ||
        votes.length > 30 ||
        votes.values.any((v) => v <= BigInt.zero)) {
      throw const FormatException('请选择 1 至 30 个代表并填写正整数票数');
    }
    return oc.TronVoteWitnessContract(
      ownerAddress: oc.TronAddress(owner),
      votes: votes.entries
          .map(
            (e) => _SerializedVote(
              voteAddress: oc.TronAddress(e.key),
              voteCount: e.value,
            ),
          )
          .toList(),
    );
  }

  Future<TransferQuote> preview(
    Account account,
    oc.ITronContract contract, {
    BigInt? spend,
  }) async {
    if (!account.signing || account.family != Family.tron) {
      throw const FormatException('需要 TRON 签名钱包');
    }
    if (contract.ownerAddress.address != account.address) {
      throw const FormatException('操作钱包不匹配');
    }
    if (contract is oc.TronDelegateResourceContract) {
      if (contract.receiverAddress?.address == account.address) {
        throw const FormatException('资源接收地址不能是当前钱包自己');
      }
      final budget = await delegationBudget(
        account.address,
        contract.resource == oc.TronResourceCode.energy
            ? 'ENERGY'
            : 'BANDWIDTH',
      );
      if (contract.balance! > budget.maxSun) {
        throw FormatException(
          '超过可代理上限：当前最多可代理 ${formatEther(budget.maxSun, 6)} TRX 对应的资源。该额度不是能量或带宽的数量。',
        );
      }
    }
    // Ask the node to validate eligibility; only the locally built payload is signed.
    final endpoint = switch (contract) {
      oc.TronFreezeBalanceV2Contract() => 'freezebalancev2',
      oc.TronUnfreezeBalanceV2Contract() => 'unfreezebalancev2',
      oc.TronDelegateResourceContract() => 'delegateresource',
      oc.TronUnDelegateResourceContract() => 'undelegateresource',
      oc.TronWithdrawExpireUnfreezeContract() => 'withdrawexpireunfreeze',
      oc.TronWithdrawBalanceContract() => 'withdrawbalance',
      oc.TronVoteWitnessContract() => 'votewitnessaccount',
      _ => throw const FormatException('不支持的操作'),
    };
    final validation = await service.tron(endpoint, {
      ...contract.toJson(config: const oc.TronProtoJsonConfig(visible: true)),
      'visible': true,
    });
    if (validation['raw_data'] == null &&
        validation['transaction']?['raw_data'] == null) {
      throw const FormatException('节点未通过操作校验，请检查可用质押、投票权或领取条件');
    }
    final block = oc.TronBlock.fromJson(await service.tron('getnowblock', {}));
    final raw = oc.TronTransactionraw(
      refBlockBytes: block.refBlockBytes,
      refBlockHash: block.refBlockHash,
      expiration: BigInt.from(
        DateTime.now().add(const Duration(minutes: 3)).millisecondsSinceEpoch,
      ),
      timestamp: block.blockHeader!.rawData!.timestamp,
      contract: [oc.TronTransactionContract(parameter: contract)],
    );
    final parameters =
        (await service.tron('getchainparameters', {}))['chainParameter']
            as List;
    BigInt param(String key) =>
        number(parameters.where((e) => e['key'] == key).firstOrNull?['value']);
    final bytePrice = param('getTransactionFee');
    if (bytePrice <= BigInt.zero) throw const FormatException('无法获取链上手续费');
    var fee = BigInt.from(raw.toBuffer().length + 256) * bytePrice;
    if (contract is oc.TronVoteWitnessContract) {
      fee += param('getVoteWitnessFee');
    }
    final balance = await service.balance(account.address);
    if (balance < (spend ?? BigInt.zero) + fee) {
      throw const FormatException('TRX 余额不足以支付操作金额和手续费预留');
    }
    return TransferQuote(BigInt.one, fee, balance, raw);
  }

  Future<String> send(
    Account account,
    WalletStore store,
    TransferQuote quote,
  ) async {
    final secret = await store.secret(account);
    if (addressForKey(secret, Family.tron) != account.address) {
      throw const FormatException('签名私钥与当前钱包不匹配');
    }
    return service.send(secret, account.address, BigInt.zero, quote);
  }
}

// on_chain 9.0.2 passes TronAddress directly to its bytes encoder for Vote.
// Supply the wire bytes without changing the SDK or the signed vote contents.
class _SerializedVote extends oc.TronVoteWitnessContractVote {
  const _SerializedVote({super.voteAddress, super.voteCount});
  @override
  List<Object?> get protoValues => [voteAddress?.toBytes(), voteCount];
}

class DelegationBudget {
  final BigInt maxSun, weight, limit;
  const DelegationBudget(this.maxSun, this.weight, this.limit);
  BigInt get estimatedMaxResource => resourceForSun(maxSun);
  BigInt resourceForSun(BigInt sun) {
    if (weight <= BigInt.zero || limit <= BigInt.zero) {
      throw const FormatException('无法获取资源兑换比例');
    }
    return sun * limit ~/ (weight * BigInt.from(1000000));
  }

  BigInt sunForResource(BigInt resource) {
    if (resource <= BigInt.zero) throw const FormatException('资源数量必须为正整数');
    if (weight <= BigInt.zero || limit <= BigInt.zero) {
      throw const FormatException('无法获取资源兑换比例');
    }
    return (resource * weight * BigInt.from(1000000) + limit - BigInt.one) ~/
        limit;
  }
}
