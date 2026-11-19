import 'package:chainvault/core/tron_governance.dart';
import 'package:chainvault/core/wallet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:on_chain/on_chain.dart' as oc;

void main() {
  test(
    'Stake totals include outgoing delegation without increasing unstakeable balance',
    () {
      final account = {
        'frozenV2': [
          {'amount': 1507204993},
          {'type': 'ENERGY', 'amount': 36533556568},
        ],
        'delegated_frozenV2_balance_for_bandwidth': 492795007,
        'account_resource': {
          'delegated_frozenV2_balance_for_energy': 13466443432,
        },
        'acquired_delegated_frozenV2_balance_for_bandwidth': 999999999,
      };
      expect(
        TronGovernance.totalStake(account, 'ENERGY'),
        BigInt.from(50000000000),
      );
      expect(
        TronGovernance.totalStake(account, 'BANDWIDTH'),
        BigInt.from(2000000000),
      );
      expect(TronGovernance.stake(account, 'ENERGY'), BigInt.from(36533556568));
    },
  );
  test('Reclaim all includes only unlocked stake of the selected resource', () {
    final response = {
      'delegatedResource': [
        {
          'frozen_balance_for_energy': 1000000,
          'frozen_balance_for_bandwidth': 9000000,
        },
        {'frozen_balance_for_energy': 2000000, 'expire_time_for_energy': 100},
        {'frozen_balance_for_energy': 4000000, 'expire_time_for_energy': 300},
      ],
    };
    expect(
      TronGovernance.reclaimableAmount(response, 'ENERGY', 200),
      BigInt.from(3000000),
    );
    expect(
      TronGovernance.reclaimableAmount(response, 'BANDWIDTH', 200),
      BigInt.from(9000000),
    );
    expect(TronGovernance.reclaimableAmount({}, 'ENERGY', 200), BigInt.zero);
  });
  test('Delegation rows preserve locked and unlocked resource amounts', () {
    final rows = TronGovernance.delegationRows('peer', {
      'delegatedResource': [
        {'frozen_balance_for_energy': 1000000},
        {
          'frozen_balance_for_energy': 2000000,
          'expire_time_for_energy': 1800000000000,
          'frozen_balance_for_bandwidth': 3000000,
        },
      ],
    });
    expect(rows.length, 3);
    expect(rows[0]['expires'], BigInt.zero);
    expect(rows[1]['sun'], BigInt.from(2000000));
    expect(rows[1]['expires'], BigInt.from(1800000000000));
    expect(rows[2]['resource'], 'BANDWIDTH');
    expect(TronGovernance.delegationRows('peer', {}), isEmpty);
    expect(
      TronGovernance.resourceEstimate(BigInt.from(2000000), 'ENERGY', {
        'TotalEnergyWeight': 100,
        'TotalEnergyLimit': 100000,
      }),
      BigInt.from(2000),
    );
    expect(TronGovernance.resourceEstimate(BigInt.one, 'ENERGY', {}), isNull);
  });
  test(
    'Energy units convert upward to exact sun without exceeding requested precision',
    () {
      final budget = DelegationBudget(
        BigInt.from(27476430206),
        BigInt.from(18644813843),
        BigInt.from(180000000000),
      );
      final amount = budget.sunForResource(BigInt.from(65000));
      expect(amount < budget.maxSun, isTrue);
      expect(budget.resourceForSun(amount), BigInt.from(65000));
      expect(
        budget.resourceForSun(amount - BigInt.one) < BigInt.from(65000),
        isTrue,
      );
      expect(() => budget.sunForResource(BigInt.zero), throwsFormatException);
    },
  );
  final owner = addressForKey('1'.padLeft(64, '0'), Family.tron);
  final recipient = addressForKey('2'.padLeft(64, '0'), Family.tron);
  test('Stake 2.0 operations preserve owner resource and exact sun amount', () {
    final stake =
        TronGovernance.contract('stake', owner, amount: BigInt.from(1234567))
            as oc.TronFreezeBalanceV2Contract;
    expect(stake.ownerAddress.address, owner);
    expect(stake.frozenBalance, BigInt.from(1234567));
    expect(stake.resource, oc.TronResourceCode.energy);
    final decoded = oc.TronFreezeBalanceV2Contract.deserialize(
      stake.toBuffer(),
    );
    expect(decoded.frozenBalance, stake.frozenBalance);
    final delegate =
        TronGovernance.contract(
              'delegate',
              owner,
              amount: BigInt.from(2000000),
              receiver: recipient,
              resource: 'BANDWIDTH',
            )
            as oc.TronDelegateResourceContract;
    expect(delegate.receiverAddress!.address, recipient);
    expect(delegate.lock, isFalse);
    expect(delegate.resource, oc.TronResourceCode.bandwidth);
    expect(delegate.toBuffer(), isNotEmpty);
    for (final kind in ['unstake', 'undelegate', 'withdraw', 'reward']) {
      expect(
        TronGovernance.contract(
          kind,
          owner,
          amount: BigInt.from(2000000),
          receiver: recipient,
        ).toBuffer(),
        isNotEmpty,
      );
    }
    expect(
      () => TronGovernance.contract('stake', owner, amount: BigInt.one),
      throwsFormatException,
    );
  });
  test(
    'Complete existing vote allocation survives editing another witness',
    () {
      final allocations = TronGovernance.votes({
        'votes': [
          {'vote_address': recipient, 'vote_count': 20},
          {'vote_address': owner, 'vote_count': 30},
        ],
      });
      allocations[recipient] = BigInt.from(40);
      final contract = TronGovernance.voteContract(owner, allocations);
      expect(contract.toBuffer(), isNotEmpty);
      expect(contract.votes.length, 2);
      expect(contract.votes.last.voteCount, BigInt.from(30));
      expect(
        () => TronGovernance.voteContract(owner, {}),
        throwsFormatException,
      );
      expect(
        () => TronGovernance.voteContract(owner, {recipient: BigInt.from(-1)}),
        throwsFormatException,
      );
    },
  );
}
