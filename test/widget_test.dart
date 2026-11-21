import 'package:chainvault/app/link_wallet_app.dart';
import 'package:chainvault/core/wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class EmptyStore extends WalletStore {
  @override
  Future<List<Account>> load() async => [];
}

void main() {
  testWidgets('Empty desktop shows five networks and wallet onboarding', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // ShadApp supplies actual shadcn theme and routing.
    await tester.pumpWidget(LinkWalletApp(store: EmptyStore()));
    await tester.pumpAndSettle();
    expect(find.text('添加你的第一个 TRON 钱包'), findsOneWidget);
    expect(find.text('TRON 主网'), findsOneWidget);
    expect(find.text('区块链网络'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('创建钱包'));
    await tester.pumpAndSettle();
    expect(find.text('钱包名称'), findsOneWidget);
    expect(find.byType(ShadDialog), findsOneWidget);
    expect(find.byType(ShadInput), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('network-selector')));
    await tester.pumpAndSettle();
    for (final name in ['Solana', 'Polygon', 'BNB Chain', 'Ethereum']) {
      expect(find.text('$name 主网'), findsOneWidget);
    }
    await tester.tap(find.text('Solana 主网'));
    await tester.pumpAndSettle();
    expect(find.text('添加你的第一个 Solana 钱包'), findsOneWidget);
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.byType(ShadDialog), findsOneWidget);
    expect(find.byType(ShadInput), findsNWidgets(2));
    await tester.tap(find.text('公开地址 · 仅观察'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('私钥 / Solana seed · 十六进制'));
    await tester.pumpAndSettle();
    expect(find.text('64 位十六进制私钥 / seed'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
