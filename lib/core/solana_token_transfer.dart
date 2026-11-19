import 'dart:convert';
import 'package:on_chain/on_chain.dart' as oc;
import 'amount.dart';
import 'chain_service.dart';
import 'token.dart';
import 'token_service.dart';
import 'token_transfer_quote.dart';

class SolanaTokenTransfer {
  final ChainService service;
  SolanaTokenTransfer(this.service);
  Future<dynamic> account(String address) async =>
      (await service.rpc('getAccountInfo', [
        address,
        {'encoding': 'jsonParsed', 'commitment': 'confirmed'},
      ]))['value'];
  Future<TokenTransferQuote> quote(
    TokenDefinition token,
    String from,
    String recipient,
    BigInt amount,
  ) async {
    if (amount <= BigInt.zero || amount.bitLength > 64) {
      throw const FormatException('SPL 金额超出范围');
    }
    final mint = await account(token.address);
    if (mint == null ||
        mint['owner'] != 'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA') {
      throw const FormatException('当前仅支持标准 SPL 代币转账；Token-2022 扩展代币暂仅可查看余额');
    }
    if (mint['data']['parsed']['type'] != 'mint' ||
        mint['data']['parsed']['info']['decimals'] != token.decimals) {
      throw const FormatException('Mint 或代币精度不匹配');
    }
    final recipientInfo = await account(recipient);
    if (recipientInfo != null &&
        TokenService.tokenPrograms.contains(recipientInfo['owner'])) {
      throw const FormatException('请输入收款人的钱包地址，不是代币账户地址');
    }
    final response = await service.rpc('getTokenAccountsByOwner', [
      from,
      {'mint': token.address},
      {'encoding': 'jsonParsed', 'commitment': 'confirmed'},
    ]);
    TokenService.sumSolanaAccounts(response as Map, token, from);
    final owner = oc.SolAddress(from),
        destinationOwner = oc.SolAddress.uncheckCurve(recipient),
        mintAddress = oc.SolAddress.uncheckCurve(token.address);
    final destination =
        oc.AssociatedTokenAccountProgramUtils.associatedTokenAccount(
          mint: mintAddress,
          owner: destinationOwner,
          allowOwnerOffCurve: true,
        ).address;
    final destinationInfo = await account(destination.address);
    final instructions = <oc.TransactionInstruction>[];
    var rent = BigInt.zero;
    if (destinationInfo == null) {
      rent = BigInt.parse(
        (await service.rpc('getMinimumBalanceForRentExemption', [
          165,
          {'commitment': 'confirmed'},
        ])).toString(),
      );
      instructions.add(
        oc.AssociatedTokenAccountProgram.associatedTokenAccountIdempotent(
          payer: owner,
          associatedToken: destination,
          owner: destinationOwner,
          mint: mintAddress,
        ),
      );
    } else {
      final info = destinationInfo['data']['parsed']['info'];
      if (destinationInfo['owner'] != mint['owner'] ||
          info['mint'] != token.address ||
          info['owner'] != recipient ||
          info['state'] != 'initialized') {
        throw const FormatException('收款代币账户无效或已冻结');
      }
    }
    var remaining = amount, sources = 0;
    for (final row in response['value'] as List) {
      if (row['account']['owner'] != mint['owner']) {
        throw const FormatException('来源账户的 Token Program 不匹配');
      }
      final info = row['account']['data']['parsed']['info'] as Map;
      if (info['state'] != 'initialized') continue;
      final available = BigInt.parse(info['tokenAmount']['amount'] as String);
      if (available == BigInt.zero) continue;
      final part = available < remaining ? available : remaining;
      instructions.add(
        oc.SPLTokenProgram.transferChecked(
          source: oc.SolAddress.uncheckCurve(row['pubkey'] as String),
          mint: mintAddress,
          destination: destination,
          owner: owner,
          layout: oc.SPLTokenTransferCheckedLayout(
            amount: part,
            decimals: token.decimals,
          ),
        ),
      );
      remaining -= part;
      sources++;
      if (remaining == BigInt.zero) break;
      if (sources >= 4) throw const FormatException('代币分散在较多账户，请先归集后转账');
    }
    if (remaining > BigInt.zero) {
      throw const FormatException('可转出的代币余额不足（不包含冻结账户）');
    }
    final block = await service.rpc('getLatestBlockhash', [
      {'commitment': 'confirmed'},
    ]);
    final tx = oc.SolanaTransaction(
      instructions: instructions,
      recentBlockhash: oc.SolAddress.uncheckCurve(
        block['value']['blockhash'] as String,
      ),
      payerKey: owner,
    );
    final bytes = tx.serialize();
    if (bytes.length > 1232) throw const FormatException('交易过大，请减少来源账户');
    final feeValue = (await service.rpc('getFeeForMessage', [
      base64Encode(tx.serializeMessage()),
      {'commitment': 'confirmed'},
    ]))['value'];
    if (feeValue == null) throw const FormatException('无法估算 SOL 手续费');
    final fee = BigInt.parse(feeValue.toString()) + rent;
    final balance = await service.balance(from);
    if (balance < fee) {
      throw FormatException(
        'SOL 不足以支付手续费${rent > BigInt.zero ? '与收款账户租金' : ''}，需预留 ${formatEther(fee, 9)} SOL',
      );
    }
    final simulation = await service.rpc('simulateTransaction', [
      base64Encode(bytes),
      {'encoding': 'base64', 'sigVerify': false, 'commitment': 'confirmed'},
    ]);
    if (simulation['value']['err'] != null) {
      throw const FormatException('SPL 转账模拟失败，未发送交易');
    }
    return TokenTransferQuote(
      token: token,
      from: from,
      recipient: recipient,
      amount: amount,
      gas: BigInt.one,
      price: fee,
      balance: balance,
      transaction: tx,
      feeNote: rent > BigInt.zero
          ? '含创建收款代币账户的租金 ${formatEther(rent, 9)} SOL。'
          : '收款代币账户已存在，无需额外创建租金。',
    );
  }
}
