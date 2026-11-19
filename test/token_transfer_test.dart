import 'dart:convert';
import 'package:chainvault/core/address_codec.dart';
import 'package:chainvault/core/amount.dart';
import 'package:chainvault/core/chain_service.dart';
import 'package:chainvault/core/models.dart';
import 'package:chainvault/core/token.dart';
import 'package:chainvault/core/token_service.dart';
import 'package:chainvault/core/token_transfer_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:on_chain/on_chain.dart' as oc;
import 'package:web3dart/web3dart.dart';

String word(BigInt n) => n.toRadixString(16).padLeft(64, '0');
http.Response reply(Map r, Object? value) => http.Response(
  jsonEncode({'jsonrpc': '2.0', 'id': r['id'], 'result': value}),
  200,
);
String key(int value) => value.toRadixString(16).padLeft(64, '0');
void main() {
  test('TRON budget offsets energy and uses whole bandwidth pools', () {
    BigInt estimate(Map<String, dynamic> r) =>
        TokenTransferService.estimateTronBurn(
          energyBudget: BigInt.from(13000),
          bandwidthBytes: BigInt.from(500),
          energyPrice: BigInt.from(100),
          bandwidthPrice: BigInt.from(1000),
          resources: r,
        );
    expect(estimate({'EnergyLimit': 20000, 'freeNetLimit': 600}), BigInt.zero);
    expect(
      estimate({'EnergyLimit': 10000, 'EnergyUsed': 2000, 'NetLimit': 1000}),
      BigInt.from(500000),
    );
    expect(
      estimate({'EnergyLimit': 20000, 'freeNetLimit': 300, 'NetLimit': 300}),
      BigInt.from(500000),
    );
    expect(estimate({}), BigInt.from(1800000));
  });
  final eth = Chain.all.firstWhere((c) => c.id == 1);
  final tron = Chain.all.first;
  final sol = Chain.all.firstWhere((c) => c.family == Family.solana);
  test(
    'Whole-unit tokens reject fractional input without losing integer precision',
    () {
      expect(
        parseEther('12345678901234567890', 0),
        BigInt.parse('12345678901234567890'),
      );
      expect(() => parseEther('1.1', 0), throwsFormatException);
    },
  );
  test(
    'EVM preview and signed transaction target token contract, never send native value',
    () async {
      final token = presetTokens(eth).first;
      final from = addressForKey(key(1), Family.evm),
          to = addressForKey(key(2), Family.evm);
      final units = BigInt.from(1234567);
      var broadcasts = 0;
      final service = ChainService(
        eth,
        httpClient: MockClient((r) async {
          final j = jsonDecode(r.body) as Map;
          Object result;
          switch (j['method']) {
            case 'eth_call':
              final call = j['params'][0] as Map;
              final data = call['data'] as String;
              expect((call['to'] as String).toLowerCase(), token.address);
              result = data == '0x313ce567'
                  ? '0x${word(BigInt.from(6))}'
                  : data.startsWith('0x70a08231')
                  ? '0x${word(BigInt.from(9999999))}'
                  : '0x${word(BigInt.one)}';
            case 'eth_chainId':
              result = '0x1';
            case 'eth_estimateGas':
              expect(j['params'][0]['value'], '0x0');
              expect(
                j['params'][0]['data'],
                '0x${TokenTransferService.transferData(TokenService.evmWord(to), units)}',
              );
              result = '0xc350';
            case 'eth_gasPrice':
              result = '0x3b9aca00';
            case 'eth_getBalance':
              result = '0xde0b6b3a7640000';
            case 'eth_getTransactionCount':
              result = '0x0';
            case 'eth_sendRawTransaction':
              broadcasts++;
              final raw = j['params'][0] as String;
              expect(raw.toLowerCase(), contains(token.address.substring(2)));
              expect(
                raw,
                contains(
                  TokenTransferService.transferData(
                    TokenService.evmWord(to),
                    units,
                  ),
                ),
              );
              result = '0x${'a' * 64}';
            default:
              throw StateError('Unexpected ${j['method']}');
          }
          return reply(j, result);
        }),
      );
      final transfers = TokenTransferService(service);
      final q = await transfers.quote(token, from, to, units);
      final tx = q.payload as Transaction;
      expect(tx.value!.getInWei, BigInt.zero);
      expect(tx.to!.with0x.toLowerCase(), token.address);
      expect(q.amount, units);
      expect(q.fee, BigInt.from(60000) * BigInt.from(1000000000));
      await expectLater(transfers.send(q, key(2)), throwsFormatException);
      expect(broadcasts, 0);
      expect(await transfers.send(q, key(1)), '0x${'a' * 64}');
      expect(broadcasts, 1);
      service.dispose();
    },
  );
  test(
    'False-returning tokens reject preview while legacy no-return USDT is accepted',
    () {
      expect(() => TokenTransferService.validateReturn('0x'), returnsNormally);
      expect(
        () => TokenTransferService.validateReturn(word(BigInt.one)),
        returnsNormally,
      );
      expect(
        () => TokenTransferService.validateReturn(word(BigInt.zero)),
        throwsFormatException,
      );
      expect(
        () => TokenTransferService.validateReturn('deadbeef'),
        throwsFormatException,
      );
    },
  );
  test(
    'TRC20 constructs local zero-TRX smart-contract payload and preserves it through signing',
    () async {
      final token = presetTokens(tron).single;
      final from = addressForKey(key(1), Family.tron),
          to = addressForKey(key(2), Family.tron);
      final units = BigInt.from(1234567);
      final data = TokenTransferService.transferData(
        TokenService.tronWord(to),
        units,
      );
      var broadcasts = 0;
      final block = oc.TronBlock(
        blockHeader: oc.TronBlockHeader(
          rawData: oc.TronBlockHeaderraw(
            timestamp: BigInt.from(DateTime.now().millisecondsSinceEpoch),
            number: BigInt.from(100),
          ),
        ),
      );
      final service = ChainService(
        tron,
        httpClient: MockClient((r) async {
          final j = jsonDecode(r.body) as Map;
          Object result;
          switch (r.url.path.split('/').last) {
            case 'triggerconstantcontract':
              if (j['function_selector'] == 'transfer(address,uint256)') {
                expect(j['parameter'], data.substring(8));
              }
              result = {
                'result': {'result': true},
                'energy_used': 10000,
                'constant_result': [
                  word(
                    j['function_selector'] == 'decimals()'
                        ? BigInt.from(6)
                        : j['function_selector'] == 'balanceOf(address)'
                        ? BigInt.from(9999999)
                        : BigInt.one,
                  ),
                ],
              };
            case 'getchainparameters':
              result = {
                'chainParameter': [
                  {'key': 'getEnergyFee', 'value': 100},
                  {'key': 'getTransactionFee', 'value': 1000},
                  {'key': 'getMaxFeeLimit', 'value': 15000000000},
                ],
              };
            case 'getnowblock':
              result = block.toJson();
            case 'getaccountresource':
              result = <String, dynamic>{};
            case 'getaccount':
              result = {'balance': 100000000};
            case 'broadcasttransaction':
              broadcasts++;
              final signed = oc.TronTransaction.fromJson(
                j.cast<String, dynamic>(),
              );
              expect(signed.signature.single.length, 65);
              final call =
                  signed.rawData.contract.single.parameter
                      as oc.TronTriggerSmartContract;
              expect(call.contractAddress!.address, token.address);
              expect(call.callValue ?? BigInt.zero, BigInt.zero);
              expect(call.data, TokenTransferService.hexBytes(data));
              result = {'result': true};
            default:
              throw StateError('Unexpected ${r.url}');
          }
          return http.Response(jsonEncode(result), 200);
        }),
      );
      final transfers = TokenTransferService(service);
      final q = await transfers.quote(token, from, to, units);
      final raw = q.payload as oc.TronTransactionraw;
      expect(raw.feeLimit, BigInt.from(1300000));
      expect(q.fee > raw.feeLimit!, true);
      expect(broadcasts, 0);
      expect(await transfers.send(q, key(1)), raw.txID);
      expect(broadcasts, 1);
      service.dispose();
    },
  );
  test(
    'SPL preview includes ATA rent and checked amount, mint, recipient and signature',
    () async {
      final token = presetTokens(sol).first;
      final from = addressForKey(key(1), Family.solana),
          to = addressForKey(key(2), Family.solana);
      final source = addressForKey(key(3), Family.solana);
      final ata = oc.AssociatedTokenAccountProgramUtils.associatedTokenAccount(
        mint: oc.SolAddress.uncheckCurve(token.address),
        owner: oc.SolAddress(to),
      ).address;
      final units = BigInt.from(1234567);
      var broadcasts = 0;
      final service = ChainService(
        sol,
        httpClient: MockClient((r) async {
          final j = jsonDecode(r.body) as Map;
          Object? result;
          switch (j['method']) {
            case 'getAccountInfo':
              result = {
                'value': j['params'][0] == token.address
                    ? {
                        'owner': TokenService.tokenPrograms.first,
                        'data': {
                          'parsed': {
                            'type': 'mint',
                            'info': {'decimals': 6},
                          },
                        },
                      }
                    : null,
              };
            case 'getTokenAccountsByOwner':
              result = {
                'value': [
                  {
                    'pubkey': source,
                    'account': {
                      'owner': TokenService.tokenPrograms.first,
                      'data': {
                        'parsed': {
                          'info': {
                            'owner': from,
                            'mint': token.address,
                            'state': 'initialized',
                            'tokenAmount': {'amount': '9999999', 'decimals': 6},
                          },
                        },
                      },
                    },
                  },
                ],
              };
            case 'getMinimumBalanceForRentExemption':
              result = 2039280;
            case 'getLatestBlockhash':
              result = {
                'value': {'blockhash': '11111111111111111111111111111111'},
              };
            case 'getFeeForMessage':
              result = {'value': 5000};
            case 'getBalance':
              result = {'value': 1000000000};
            case 'simulateTransaction':
              expect(j['params'][1]['sigVerify'], false);
              result = {
                'value': {'err': null},
              };
            case 'sendTransaction':
              broadcasts++;
              final signed = oc.SolanaTransaction.deserialize(
                base64Decode(j['params'][0] as String),
              );
              expect(signed.areSignaturesReady(), true);
              expect(j['params'][1]['skipPreflight'], false);
              result = 'signature';
            default:
              throw StateError('Unexpected ${j['method']}');
          }
          return reply(j, result);
        }),
      );
      final transfers = TokenTransferService(service);
      final q = await transfers.quote(token, from, to, units);
      expect(q.fee, BigInt.from(2044280));
      final tx = q.payload as oc.SolanaTransaction;
      expect(tx.message.compiledInstructions.length, 2);
      final transfer = tx.message.compiledInstructions.last;
      final decoded = oc.SPLTokenTransferCheckedLayout.fromBuffer(
        transfer.data,
      );
      expect(decoded.amount, units);
      expect(decoded.decimals, 6);
      expect(tx.message.accountKeys[transfer.accounts[2]], ata);
      expect(broadcasts, 0);
      expect(await transfers.send(q, key(1)), 'signature');
      expect(broadcasts, 1);
      service.dispose();
    },
  );
  test(
    'Insufficient native gas balance blocks ERC20 preview independently of token balance',
    () async {
      final token = presetTokens(eth).first;
      final from = addressForKey(key(1), Family.evm),
          to = addressForKey(key(2), Family.evm);
      final service = ChainService(
        eth,
        httpClient: MockClient((r) async {
          final j = jsonDecode(r.body) as Map;
          final result = switch (j['method']) {
            'eth_call' =>
              '0x${word(j['params'][0]['data'] == '0x313ce567'
                  ? BigInt.from(6)
                  : (j['params'][0]['data'] as String).startsWith('0x70a08231')
                  ? BigInt.from(99999)
                  : BigInt.one)}',
            'eth_chainId' => '0x1',
            'eth_estimateGas' => '0xc350',
            'eth_gasPrice' => '0x3b9aca00',
            'eth_getBalance' => '0x0',
            _ => throw StateError('Unexpected RPC; must not broadcast'),
          };
          return reply(j, result);
        }),
      );
      await expectLater(
        TokenTransferService(service).quote(token, from, to, BigInt.one),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'native fee error',
            contains('ETH'),
          ),
        ),
      );
      service.dispose();
    },
  );
  test(
    'Token-2022 extensions fail before creating any transfer payload',
    () async {
      final service = ChainService(
        sol,
        httpClient: MockClient((r) async {
          final j = jsonDecode(r.body) as Map;
          expect(j['method'], 'getAccountInfo');
          return reply(j, {
            'value': {'owner': 'TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb'},
          });
        }),
      );
      await expectLater(
        TokenTransferService(service).quote(
          presetTokens(sol).first,
          addressForKey(key(1), Family.solana),
          addressForKey(key(2), Family.solana),
          BigInt.one,
        ),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'unsupported token program',
            contains('Token-2022'),
          ),
        ),
      );
      service.dispose();
    },
  );
  test(
    'Native SOL preview also constructs the recent blockhash using the current SDK type',
    () async {
      final service = ChainService(
        sol,
        httpClient: MockClient((r) async {
          final j = jsonDecode(r.body) as Map;
          return reply(j, switch (j['method']) {
            'getLatestBlockhash' => {
              'value': {'blockhash': '11111111111111111111111111111111'},
            },
            'getFeeForMessage' => {'value': 5000},
            'getBalance' => {'value': 1000000000},
            _ => throw StateError('Unexpected RPC'),
          });
        }),
      );
      final q = await service.quote(
        addressForKey(key(1), Family.solana),
        addressForKey(key(2), Family.solana),
        BigInt.one,
      );
      expect((q.payload as oc.SolanaTransaction).serialize(), isNotEmpty);
      expect(q.fee, BigInt.from(5000));
      service.dispose();
    },
  );
}
