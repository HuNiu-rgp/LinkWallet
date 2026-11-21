import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/core/token.dart';
import 'package:chainvault/platform/wallet_menu_bar.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MenuController extends WalletController {
  MenuController() : super(WalletStore());
  int refreshes = 0;
  @override
  Future<void> showWallet() async {}
  @override
  Future<void> refreshAssets() async {
    refreshes++;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const first = Account('日常钱包', 'TronFirstAddress', true, Family.tron);
  const second = Account('观察钱包', 'TronSecondAddress', false, Family.tron);
  const other = Account(
    'ETH',
    '0x1111111111111111111111111111111111111111',
    false,
    Family.evm,
  );

  test(
    'Menu snapshot includes complete address and portfolio balances and respects hiding',
    () {
      final c = MenuController()
        ..selected = first
        ..accounts = [first, second, other]
        ..balance = BigInt.from(128500000);
      c.tokens.balances = [
        TokenBalance(
          presetTokens(c.chain).first,
          amount: BigInt.from(1248000000),
        ),
      ];
      final menu = WalletMenuBar(c);
      addTearDown(() {
        menu.dispose();
        c.dispose();
      });
      final data = menu.snapshot();
      expect(data['address'], first.address);
      expect(data['assets'], [
        {'symbol': 'TRX', 'balance': '128.500'},
        {'symbol': 'USDT', 'balance': '1248.000'},
      ]);
      expect((data['wallets'] as List).length, 2);
      expect(data.keys.toSet(), {
        'network',
        'loading',
        'error',
        'selectedId',
        'name',
        'address',
        'refreshing',
        'assets',
        'wallets',
      });
      c.hidden = true;
      expect(
        (menu.snapshot()['assets'] as List).map((e) => e['balance']),
        everyElement('••••'),
      );
    },
  );

  test(
    'Native channel updates data, selects permitted wallets and refreshes only assets',
    () async {
      const channel = MethodChannel('test.wallet.menu');
      final updates = <Map>[];
      binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        updates.add(call.arguments as Map);
        return null;
      });
      final c = MenuController()
        ..selected = first
        ..accounts = [first, second, other];
      final menu = WalletMenuBar(c, channel: channel)..start(enabled: true);
      addTearDown(() {
        menu.dispose();
        c.dispose();
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
      });
      await Future<void>.delayed(Duration.zero);
      expect(updates.last['address'], first.address);
      Future<void> native(String method, [Object? arguments]) async {
        await binding.defaultBinaryMessenger.handlePlatformMessage(
          channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall(method, arguments),
          ),
          null,
        );
      }

      await native('selectWallet', 'evm:null:${other.address}');
      expect(c.selected, same(first));
      await native('selectWallet', 'tron:null:${second.address}');
      expect(c.selected, same(second));
      await Future<void>.delayed(Duration.zero);
      expect(updates.last['address'], second.address);
      await native('refreshAssets');
      expect(c.refreshes, 1);
      c.update(() => c.assetsLoading = true);
      await native('refreshAssets');
      expect(c.refreshes, 1);
    },
  );
}
