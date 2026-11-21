import 'dart:async';
import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:chainvault/features/wallets/asset_refresh_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

class ScheduledController extends WalletController {
  ScheduledController() : super(WalletStore());
  final refreshed = <String>[];
  Completer<void>? pending;
  bool fail = false;
  @override
  Future<void> refreshAssets() async {
    refreshed.add(selected!.address);
    if (fail) throw StateError('offline');
    if (pending != null) await pending!.future;
  }
}

void main() {
  const a = Account('A', 'address-A', false, Family.tron);
  const b = Account('B', 'address-B', false, Family.tron);

  testWidgets(
    'Refreshes every three minutes, follows selection and stops on dispose',
    (tester) async {
      final c = ScheduledController()
        ..booting = false
        ..selected = a
        ..historyPage = 2;
      final scheduler = AssetRefreshScheduler(c)
        ..start()
        ..start();
      addTearDown(() {
        scheduler.dispose();
        c.dispose();
      });
      await tester.pump(const Duration(minutes: 2, seconds: 59));
      expect(c.refreshed, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(c.refreshed, [a.address]);
      c.selected = b;
      await tester.pump(const Duration(minutes: 3));
      expect(c.refreshed, [a.address, b.address]);
      expect(c.historyPage, 2);
      scheduler.dispose();
      await tester.pump(const Duration(minutes: 6));
      expect(c.refreshed.length, 2);
    },
  );

  testWidgets(
    'Skips initial/manual queries and overlapping ticks; retries after errors',
    (tester) async {
      final c = ScheduledController()..selected = a;
      final scheduler = AssetRefreshScheduler(c)..start();
      addTearDown(() {
        scheduler.dispose();
        c.dispose();
      });
      await tester.pump(const Duration(minutes: 3));
      expect(c.refreshed, isEmpty);
      c.booting = false;
      c.assetsLoading = true;
      await tester.pump(const Duration(minutes: 3));
      expect(c.refreshed, isEmpty);
      c.assetsLoading = false;
      c.tokens.loading = true;
      await tester.pump(const Duration(minutes: 3));
      expect(c.refreshed, isEmpty);
      c.tokens.loading = false;
      c.pending = Completer<void>();
      await tester.pump(const Duration(minutes: 3));
      expect(c.refreshed.length, 1);
      await tester.pump(const Duration(minutes: 3));
      expect(c.refreshed.length, 1);
      c.pending!.complete();
      await tester.pump();
      c.pending = null;
      c.fail = true;
      await tester.pump(const Duration(minutes: 3));
      expect(c.refreshed.length, 2);
      c.fail = false;
      await tester.pump(const Duration(minutes: 3));
      expect(c.refreshed.length, 3);
      c.selected = null;
      await tester.pump(const Duration(minutes: 3));
      expect(c.refreshed.length, 3);
      scheduler.dispose();
    },
  );
}
