import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/wallet.dart';
import '../../core/token.dart';
import '../../core/token_repository.dart';
import '../../core/token_service.dart';
import '../../platform/transfer_notifications.dart';
import '../wallets/wallet_controller.dart';

/// Independent reads: monitoring never changes the selected wallet or its cache.
class WalletTransferMonitor extends ChangeNotifier {
  static const preferenceKey = 'linkwallet.transfer-monitor.enabled';
  final WalletController controller;
  final TransferNotifier notifier;
  final TokenRepository repository;
  final ChainService Function(Chain) serviceFactory;
  final Duration interval;
  Timer? _timer;
  bool enabled = false, permissionGranted = false, checking = false;
  bool _disposed = false;
  int _generation = 0;
  String? error;
  DateTime? lastChecked;
  final Map<String, Set<String>> _seen = {};
  final Map<String, int> _baselineTime = {};
  final Map<String, BigInt> _balances = {};
  WalletTransferMonitor(
    this.controller, {
    TransferNotifier? notifier,
    TokenRepository? repository,
    ChainService Function(Chain)? serviceFactory,
    this.interval = const Duration(seconds: 60),
  }) : notifier = notifier ?? SystemTransferNotifier(),
       repository = repository ?? controller.tokens.repository,
       serviceFactory = serviceFactory ?? ChainService.new;

  Future<void> start() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_disposed) {
        await setEnabled(prefs.getBool(preferenceKey) ?? true, persist: false);
      }
    } catch (_) {
      if (!_disposed) {
        error = '监控初始化失败，请重新开启';
        notifyListeners();
      }
    }
  }

  Future<void> setEnabled(bool value, {bool persist = true}) async {
    final generation = ++_generation;
    _timer?.cancel();
    _timer = null;
    enabled = value;
    error = null;
    _seen.clear();
    _baselineTime.clear();
    _balances.clear();
    if (!_disposed) notifyListeners();
    try {
      if (persist) {
        final prefs = await SharedPreferences.getInstance();
        if (_disposed || generation != _generation) return;
        if (!await prefs.setBool(preferenceKey, value)) {
          throw StateError('无法保存监控设置');
        }
      }
      if (!_active(generation) || !value) return;
      permissionGranted = await notifier.requestPermission();
      if (!_active(generation)) return;
      if (permissionGranted) {
        _timer = Timer.periodic(interval, (_) => unawaited(poll()));
        unawaited(poll());
      }
    } catch (_) {
      if (_active(generation)) {
        permissionGranted = false;
        error = '通知服务不可用，请重新启动应用后重试';
      }
    }
    if (!_disposed) notifyListeners();
  }

  bool _active(int generation) =>
      !_disposed && enabled && generation == _generation;
  bool _exists(Account account) => controller.accounts.any(
    (a) =>
        a.address == account.address &&
        a.family == account.family &&
        a.chainId == account.chainId,
  );

  String _eventId(Map<String, dynamic> t) =>
      '${t['hash']}:${t['tokenAddress'] ?? 'native'}:${t['from']}:${t['to']}:${t['incoming']}:${t['amount']}';

  Future<void> poll() async {
    if (_disposed ||
        !enabled ||
        !permissionGranted ||
        checking ||
        controller.booting) {
      return;
    }
    checking = true;
    notifyListeners();
    final generation = _generation;
    var failures = 0;
    try {
      final custom = await repository.load();
      if (!_active(generation)) return;
      final visited = <String>{};
      for (final account in List<Account>.of(controller.accounts)) {
        for (final chain in Chain.all.where(account.supportsChain)) {
          if (!_active(generation)) return;
          if (!_exists(account)) continue;
          final key = '${chain.id}:${account.address}';
          if (!visited.add(key)) continue;
          final tokens = <String, TokenDefinition>{
            for (final t in [...presetTokens(chain), ...custom])
              if (t.chainId == chain.id) t.id: t,
          }.values.toList();
          final service = serviceFactory(chain);
          try {
            if (chain.family == Family.tron) {
              service.historyTokenContracts = tokens
                  .map((t) => t.address)
                  .toSet();
              final rows = await service.history(account.address);
              if (!_active(generation) || !_exists(account)) continue;
              final contracts = tokens.map((t) => t.address).toSet();
              final transfers = rows.where((t) {
                if (t['incoming'] is! bool ||
                    t['amount'] == null ||
                    (t['status'] != 'SUCCESS' && t['status'] != '已确认')) {
                  return false;
                }
                final contract = t['tokenAddress'];
                return contract == null
                    ? t['detail'] == 'TransferContract' &&
                          t['symbol'] == chain.symbol
                    : contracts.contains(contract);
              }).toList();
              final scope =
                  '$key:${(tokens.map((t) => t.address).toList()..sort()).join(',')}';
              final ids = transfers.map(_eventId).toSet();
              final seen = _seen[scope];
              if (seen == null) {
                _seen[scope] = ids;
                final timestamps = transfers.map(
                  (t) => t['timestampMs'] as int? ?? 0,
                );
                _baselineTime[scope] = timestamps.isEmpty
                    ? DateTime.now().millisecondsSinceEpoch
                    : timestamps.reduce((a, b) => a > b ? a : b);
              } else {
                for (final t in transfers.reversed) {
                  if (!_active(generation) || !_exists(account)) break;
                  final id = _eventId(t);
                  if (seen.contains(id) ||
                      (t['timestampMs'] as int? ?? 0) < _baselineTime[scope]!) {
                    continue;
                  }
                  await notifier.show(
                    id: '$key:$id',
                    title:
                        '${account.name} · ${t['incoming'] == true ? '收到转账' : '转账已确认'}',
                    body:
                        '${t['incoming'] == true ? '+' : '-'}${t['amount']} ${t['symbol']} · ${chain.name}\n${t['hash']}',
                  );
                  if (!_active(generation)) break;
                  seen.add(id);
                }
                if (seen.length > 1000) {
                  seen.removeAll(seen.take(seen.length - 1000).toList());
                }
              }
            } else {
              // Standard RPC cannot enumerate full address history on every chain.
              // Notify balance changes honestly instead of inventing a transaction.
              Future<void> check(
                String asset,
                String symbol,
                int decimals,
                Future<BigInt> Function() read,
              ) async {
                try {
                  final value = await read();
                  if (!_active(generation) || !_exists(account)) return;
                  final id = '$key:$asset';
                  final before = _balances[id];
                  if (before != null && value != before) {
                    final delta = value - before;
                    await notifier.show(
                      id: '$id:${DateTime.now().microsecondsSinceEpoch}',
                      title: '${account.name} · 余额变动',
                      body:
                          '$symbol ${delta.isNegative ? '-' : '+'}${formatEther(delta.abs(), decimals)} · ${chain.name}\n当前余额：${formatEther(value, decimals)} $symbol',
                    );
                  }
                  if (_active(generation)) _balances[id] = value;
                } catch (_) {
                  failures++;
                }
              }

              await check(
                'native',
                chain.symbol,
                chain.decimals,
                () => service.balance(account.address),
              );
              for (final token in tokens) {
                if (!_active(generation) || !_exists(account)) break;
                await check(
                  token.address,
                  token.symbol,
                  token.decimals,
                  () => TokenService(service).balance(token, account.address),
                );
              }
            }
          } catch (_) {
            failures++;
          } finally {
            service.dispose();
          }
        }
      }
      if (_active(generation)) {
        lastChecked = DateTime.now();
        error = failures == 0 ? null : '$failures 项查询或通知失败，将在下一轮重试';
      }
    } catch (_) {
      if (_active(generation)) error = '读取监控配置失败，将在下一轮重试';
    } finally {
      checking = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> testNotification() async {
    try {
      await notifier.show(
        id: 'linkwallet-test',
        title: 'LinkWallet 转账监控',
        body: '系统通知已开启，窗口隐藏后也会继续监控。',
      );
    } catch (_) {
      if (!_disposed) {
        error = '测试通知发送失败，请检查 macOS 通知权限';
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _timer?.cancel();
    super.dispose();
  }
}
