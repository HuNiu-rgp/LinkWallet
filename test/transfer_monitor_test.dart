import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:chainvault/core/wallet.dart';
import 'package:chainvault/core/token.dart';
import 'package:chainvault/core/token_repository.dart';
import 'package:chainvault/features/monitoring/wallet_transfer_monitor.dart';
import 'package:chainvault/features/wallets/wallet_controller.dart';
import 'package:chainvault/platform/transfer_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

class EmptyTokens extends TokenRepository {
  @override
  Future<List<TokenDefinition>> load() async => [];
}

class Notifications extends TransferNotifier {
  final events = <Map<String, String>>[];
  bool fail = false, allowed = true;
  @override
  Future<bool> requestPermission() async => allowed;
  @override
  Future<void> show({
    required String id,
    required String title,
    required String body,
  }) async {
    if (fail) throw StateError('delivery failed');
    events.add({'id': id, 'title': title, 'body': body});
  }
}

class Probe {
  List<Map<String, dynamic>> rows = [];
  bool fail = false;
  int calls = 0;
  BigInt balance = BigInt.from(1000000);
  Completer<List<Map<String, dynamic>>>? pending;
}

class MonitorService extends ChainService {
  final Probe probe;
  MonitorService(super.chain, this.probe);
  @override
  Future<List<Map<String, dynamic>>> history(String address) async {
    probe.calls++;
    if (probe.fail) throw StateError('limited');
    return probe.pending?.future ?? probe.rows;
  }

  @override
  Future<BigInt> balance(String address) async {
    if (probe.fail) throw StateError('limited');
    return probe.balance;
  }

  @override
  Future<dynamic> rpc(String method, List<dynamic> params) async =>
      '0x${'0'.padLeft(64, '0')}';
}

Map<String, dynamic> tx(String hash, {bool incoming = true, String? token}) => {
  'hash': hash,
  'timestampMs': 200,
  'incoming': incoming,
  'amount': '5',
  'symbol': token == null ? 'TRX' : 'USDT',
  'detail': 'TransferContract',
  'status': 'SUCCESS',
  'tokenAddress': token,
};
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  WalletController controller() => WalletController(WalletStore())
    ..booting = false
    ..accounts = [const Account('Wallet', 'address', false, Family.tron)];
  WalletTransferMonitor monitor(WalletController c, Probe p, Notifications n) =>
      WalletTransferMonitor(
          c,
          repository: EmptyTokens(),
          notifier: n,
          serviceFactory: (chain) => MonitorService(chain, p),
        )
        ..enabled = true
        ..permissionGranted = true;
  test(
    'Denied permission does not start queries and disabled preference survives restart',
    () async {
      final c = controller();
      final p = Probe();
      final n = Notifications()..allowed = false;
      final m = WalletTransferMonitor(
        c,
        repository: EmptyTokens(),
        notifier: n,
        serviceFactory: (chain) => MonitorService(chain, p),
      );
      addTearDown(() {
        m.dispose();
        c.dispose();
      });
      await m.start();
      expect(m.enabled, true);
      expect(m.permissionGranted, false);
      await m.poll();
      expect(p.calls, 0);
      await m.setEnabled(false);
      final fresh = WalletTransferMonitor(
        c,
        repository: EmptyTokens(),
        notifier: n,
      );
      addTearDown(fresh.dispose);
      await fresh.start();
      expect(fresh.enabled, false);
    },
  );
  test(
    'Baseline is silent; only new portfolio transfers notify once in both directions',
    () async {
      final c = controller()..balance = BigInt.from(99);
      final p = Probe()..rows = [tx('old')];
      final n = Notifications();
      final m = monitor(c, p, n);
      addTearDown(() {
        m.dispose();
        c.dispose();
      });
      await m.poll();
      expect(n.events, isEmpty);
      p.rows = [
        tx('sent', incoming: false),
        tx('received'),
        tx('old'),
        tx('spam', token: 'fake'),
        {
          'hash': 'stake',
          'status': 'SUCCESS',
          'detail': 'DelegateResourceContract',
        },
      ];
      await m.poll();
      await m.poll();
      expect(n.events.length, 2);
      expect(n.events.any((e) => e['title']!.contains('收到转账')), true);
      expect(n.events.any((e) => e['title']!.contains('转账已确认')), true);
      expect(c.balance, BigInt.from(99));
      expect(c.transactions, isEmpty);
    },
  );
  test('Network and notification errors preserve baseline for retry', () async {
    final c = controller();
    final p = Probe()..rows = [tx('old')];
    final n = Notifications();
    final m = monitor(c, p, n);
    addTearDown(() {
      m.dispose();
      c.dispose();
    });
    await m.poll();
    p.fail = true;
    await m.poll();
    expect(m.error, isNotNull);
    p.fail = false;
    p.rows = [tx('new'), tx('old')];
    n.fail = true;
    await m.poll();
    n.fail = false;
    await m.poll();
    expect(n.events.length, 1);
    expect(m.error, isNull);
  });
  test(
    'Polls never overlap and deletion prevents pending notifications',
    () async {
      final c = controller();
      final p = Probe()..rows = [tx('old')];
      final n = Notifications();
      final m = monitor(c, p, n);
      addTearDown(() {
        m.dispose();
        c.dispose();
      });
      await m.poll();
      p.pending = Completer<List<Map<String, dynamic>>>();
      final pending = m.poll();
      await Future<void>.delayed(Duration.zero);
      await m.poll();
      expect(p.calls, 2);
      c.accounts = [];
      p.pending!.complete([tx('new'), tx('old')]);
      await pending;
      expect(n.events, isEmpty);
    },
  );
  test(
    'Disabled monitoring sends nothing; other chains report balance changes honestly',
    () async {
      final c = controller()
        ..accounts = [
          const Account(
            'POL Wallet',
            'address',
            false,
            Family.evm,
            chainId: 137,
          ),
        ];
      final p = Probe();
      final n = Notifications();
      final m = monitor(c, p, n);
      addTearDown(() {
        m.dispose();
        c.dispose();
      });
      await m.poll();
      p.balance = BigInt.from(2000000);
      await m.poll();
      expect(n.events.single['title'], contains('余额变动'));
      m.enabled = false;
      p.balance = BigInt.from(3000000);
      await m.poll();
      expect(n.events.length, 1);
    },
  );
}
