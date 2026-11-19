import 'dart:convert';
import 'package:chainvault/core/token_transfer_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Only known mainnet USDT accepts a zero return after successful execution', () {
    final simulation = <String, dynamic>{'result': {'result': true}, 'constant_result': ['0'.padLeft(64, '0')], 'energy_used': 130285, 'transaction': {'ret': [{}]}};
    const usdt = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
    expect(() => TokenTransferService.validateTronSimulation(simulation, contractAddress: usdt), returnsNormally);
    expect(() => TokenTransferService.validateTronSimulation(simulation, contractAddress: 'another-token'), throwsFormatException);
    expect(() => TokenTransferService.validateTronSimulation({...simulation, 'result': {'result': false}}, contractAddress: usdt), throwsFormatException);
    expect(() => TokenTransferService.validateTronSimulation({...simulation, 'transaction': {'ret': [{'contractRet': 'REVERT'}]}}, contractAddress: usdt), throwsFormatException);
    expect(() => TokenTransferService.validateTronSimulation({...simulation, 'constant_result': ['2'.padLeft(64, '0')]}, contractAddress: usdt), throwsFormatException);
  });
  test('Simulation failure includes raw return and decoded node reason', () {
    final result = {
      'result': {
        'result': true,
        'message': base64.encode(utf8.encode('REVERT opcode executed')),
      },
      'constant_result': ['0'.padLeft(64, '0')],
      'energy_used': 123,
    };
    expect(
      () => TokenTransferService.validateTronSimulation(result),
      throwsA(
        isA<FormatException>()
            .having(
              (e) => e.message,
              'reason',
              contains('REVERT opcode executed'),
            )
            .having((e) => e.message, 'raw return', contains('constant_result'))
            .having((e) => e.message, 'not sent', contains('未签名、未发送')),
      ),
    );
  });
  test('Successful simulation is accepted; missing return remains blocked', () {
    expect(
      () => TokenTransferService.validateTronSimulation({
        'result': {'result': true},
        'constant_result': ['1'.padLeft(64, '0')],
      }),
      returnsNormally,
    );
    expect(
      () => TokenTransferService.validateTronSimulation({
        'result': {'result': true},
      }),
      throwsFormatException,
    );
  });
}
