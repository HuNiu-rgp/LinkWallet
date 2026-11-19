import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Appearance preferences never share storage with wallet secrets.
abstract class ThemeStore {
  Future<Map<String, String>> read();
  Future<void> write(Map<String, String> values);
}

class PreferencesThemeStore implements ThemeStore {
  @override
  Future<Map<String, String>> read() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'mode': prefs.getString('linkwallet.theme.mode') ?? 'system',
      'palette': prefs.getString('linkwallet.theme.palette') ?? 'green',
    };
  }

  @override
  Future<void> write(Map<String, String> values) async {
    final prefs = await SharedPreferences.getInstance();
    final results = await Future.wait([
      prefs.setString('linkwallet.theme.mode', values['mode']!),
      prefs.setString('linkwallet.theme.palette', values['palette']!),
    ]);
    if (results.any((saved) => !saved)) throw StateError('Theme save failed');
  }
}

class ThemeController extends ChangeNotifier {
  static const palettes = {
    'green': '森林绿',
    'zinc': '经典灰',
    'blue': '海洋蓝',
    'violet': '鸢尾紫',
    'orange': '暖橙色',
  };
  final ThemeStore store;
  ThemeController({ThemeStore? store})
    : store = store ?? PreferencesThemeStore();
  ThemeMode mode = ThemeMode.system;
  String palette = 'green';
  String? persistenceError;
  int _revision = 0;
  bool _disposed = false;
  Future<void> _pending = Future.value();

  Future<void> load() async {
    final revision = _revision;
    try {
      final values = await store.read();
      if (_disposed || revision != _revision) return;
      mode =
          ThemeMode.values.where((m) => m.name == values['mode']).firstOrNull ??
          ThemeMode.system;
      palette = palettes.containsKey(values['palette'])
          ? values['palette']!
          : 'green';
      notifyListeners();
    } catch (_) {
      /* Defaults remain usable when preferences cannot be read. */
    }
  }

  Future<void> setMode(ThemeMode value) {
    mode = value;
    return _save();
  }

  Future<void> setPalette(String value) {
    if (!palettes.containsKey(value)) {
      throw ArgumentError.value(value, 'palette');
    }
    palette = value;
    return _save();
  }

  Future<void> _save() {
    final revision = ++_revision;
    final snapshot = {'mode': mode.name, 'palette': palette};
    persistenceError = null;
    notifyListeners();
    // Serialize rapid changes so the final selection also wins on disk.
    _pending = _pending.then((_) async {
      try {
        await store.write(snapshot);
      } catch (_) {
        if (!_disposed && revision == _revision) {
          persistenceError = '主题已切换，但未能保存；下次启动可能恢复默认。';
          notifyListeners();
        }
      }
    });
    return _pending;
  }

  ShadThemeData data(Brightness brightness) {
    var colors = ShadColorScheme.fromName(palette, brightness: brightness);
    if (palette == 'green') {
      colors = colors.copyWith(
        primary: brightness == Brightness.light
            ? const Color(0xff207c57)
            : const Color(0xff79d4a8),
        primaryForeground: brightness == Brightness.light
            ? Colors.white
            : const Color(0xff103d30),
      );
    }
    return ShadThemeData(brightness: brightness, colorScheme: colors);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
