import 'dart:async';
import 'wallet_controller.dart';

/// Refresh the active wallet while the app (including its menu bar) is running.
class AssetRefreshScheduler {
  static const interval = Duration(minutes: 3);
  final WalletController controller;
  Timer? _timer;
  bool _running = false, _disposed = false;
  AssetRefreshScheduler(this.controller);

  void start() {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(_refresh()));
  }

  Future<void> _refresh() async {
    if (_disposed ||
        _running ||
        controller.booting ||
        controller.selected == null ||
        controller.assetsLoading ||
        controller.tokens.loading) {
      return;
    }
    _running = true;
    try {
      await controller.refreshAssets();
    } catch (_) {
      // Asset queries expose their own errors. One failure must not stop the timer.
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
