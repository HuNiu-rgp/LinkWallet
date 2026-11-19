import 'package:flutter_test/flutter_test.dart';
import 'package:chainvault/core/chain_service.dart';
import 'package:on_chain/on_chain.dart' as oc;

void main() {
  test('TRC20 history uses token precision, symbol and direction', () {
    final from = oc.TronAddress(
      '410000000000000000000000000000000000000001',
    ).address;
    final to = oc.TronAddress(
      '410000000000000000000000000000000000000002',
    ).address;
    final event = {
      'transaction_id': 'token-hash',
      'block_timestamp': 1700000000000,
      'type': 'Transfer',
      'from': from,
      'to': to,
      'value': '1398520000',
      'token_info': {'symbol': 'USDT', 'decimals': 6, 'address': 'contract'},
    };
    final row = ChainService.parseTrc20History(event, to);
    expect(row['amount'], '1398.52');
    expect(row['symbol'], 'USDT');
    expect(row['incoming'], true);
    expect(row['counterparty'], from);
    expect(row['tokenAddress'], 'contract');
    expect(ChainService.parseTrc20History(event, from)['incoming'], false);
  });
  test('TRX history decodes addresses and keeps exact transfer amounts', () {
    final from = oc.TronAddress(
      '410000000000000000000000000000000000000001',
    ).address;
    final to = oc.TronAddress(
      '410000000000000000000000000000000000000002',
    ).address;
    final transaction = {
      'txID': 'hash',
      'block_timestamp': 1700000000000,
      'ret': [
        {'contractRet': 'SUCCESS'},
      ],
      'raw_data': {
        'contract': [
          {
            'type': 'TransferContract',
            'parameter': {
              'value': {
                'owner_address': '410000000000000000000000000000000000000001',
                'to_address': '410000000000000000000000000000000000000002',
                'amount': 1398520000,
              },
            },
          },
        ],
      },
    };
    final received = ChainService.parseTronHistory(transaction, to);
    expect(received['incoming'], true);
    expect(received['counterparty'], from);
    expect(received['amount'], '1398.52');
    final sent = ChainService.parseTronHistory(transaction, from);
    expect(sent['incoming'], false);
    expect(sent['counterparty'], to);
    (transaction['raw_data'] as Map)['contract'][0]['type'] =
        'TriggerSmartContract';
    expect(ChainService.parseTronHistory(transaction, from)['amount'], isNull);
  });
}
