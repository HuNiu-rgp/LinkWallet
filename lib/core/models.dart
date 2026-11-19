enum Family { evm, tron, solana }

class Chain {
  final String name, rpc, explorer, symbol;
  final int id, decimals;
  final Family family;
  const Chain(
    this.name,
    this.id,
    this.rpc,
    this.explorer,
    this.symbol,
    this.decimals,
    this.family,
  );
  static const all = [
    Chain(
      'TRON',
      728126428,
      'https://api.trongrid.io',
      'https://tronscan.org',
      'TRX',
      6,
      Family.tron,
    ),
    Chain(
      'Solana',
      0,
      'https://api.mainnet-beta.solana.com',
      'https://explorer.solana.com',
      'SOL',
      9,
      Family.solana,
    ),
    Chain(
      'Polygon',
      137,
      'https://polygon-bor-rpc.publicnode.com',
      'https://polygon.blockscout.com',
      'POL',
      18,
      Family.evm,
    ),
    Chain(
      'BNB Chain',
      56,
      'https://bsc-rpc.publicnode.com',
      'https://bscscan.com',
      'BNB',
      18,
      Family.evm,
    ),
    Chain(
      'Ethereum',
      1,
      'https://ethereum-rpc.publicnode.com',
      'https://eth.blockscout.com',
      'ETH',
      18,
      Family.evm,
    ),
  ];
}

class Account {
  final String name, address;
  final bool signing;
  final Family family;
  final int? chainId;
  const Account(
    this.name,
    this.address,
    this.signing,
    this.family, {
    this.chainId,
  });
  bool supportsChain(Chain chain) =>
      chain.family == family && (chainId == null || chain.id == chainId);
  Chain get preferredChain =>
      Chain.all.firstWhere((chain) => supportsChain(chain));
  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'signing': signing,
    'family': family.name,
    if (chainId != null) 'chainId': chainId,
  };
  factory Account.fromJson(Map<String, dynamic> j) => Account(
    j['name'] as String,
    j['address'] as String,
    j['signing'] == true,
    Family.values.byName(j['family'] as String),
    chainId: j['chainId'] as int?,
  );
}

class TransferQuote {
  final BigInt gas, price, balance;
  final Object? payload;
  final DateTime created = DateTime.now();
  TransferQuote(this.gas, this.price, this.balance, [this.payload]);
  BigInt get fee => gas * price;
}

class TronResources {
  final BigInt energy, bandwidth;
  final BigInt? energyLimit, bandwidthLimit;
  const TronResources(
    this.energy,
    this.bandwidth, {
    this.energyLimit,
    this.bandwidthLimit,
  });
  factory TronResources.fromJson(Map<String, dynamic> json) {
    BigInt remaining(String limit, String used) {
      final value =
          BigInt.parse((json[limit] ?? 0).toString()) -
          BigInt.parse((json[used] ?? 0).toString());
      return value < BigInt.zero ? BigInt.zero : value;
    }

    return TronResources(
      remaining('EnergyLimit', 'EnergyUsed'),
      remaining('freeNetLimit', 'freeNetUsed') +
          remaining('NetLimit', 'NetUsed'),
      energyLimit: BigInt.parse((json['EnergyLimit'] ?? 0).toString()),
      bandwidthLimit:
          BigInt.parse((json['freeNetLimit'] ?? 0).toString()) +
          BigInt.parse((json['NetLimit'] ?? 0).toString()),
    );
  }
}
