import 'dart:async';
import 'package:chainvault/app/theme_controller.dart';
import 'package:chainvault/app/link_wallet_app.dart';
import 'package:chainvault/core/wallet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MemoryThemeStore implements ThemeStore {
  Map<String, String> values = {'mode': 'light', 'palette': 'green'};
  bool fail = false;
  @override
  Future<Map<String, String>> read() async => Map.of(values);
  @override
  Future<void> write(Map<String, String> next) async {
    if (fail) throw StateError('disk unavailable');
    values = Map.of(next);
  }
}

class CountingWalletStore extends WalletStore {
  int loads = 0;
  @override
  Future<List<Account>> load() async {
    loads++;
    return [];
  }
}

void main() {
  test(
    'Theme preferences survive a fresh controller and rapid changes',
    () async {
      SharedPreferences.setMockInitialValues({});
      final first = ThemeController();
      await first.setMode(ThemeMode.dark);
      final writes = [
        first.setPalette('blue'),
        first.setPalette('violet'),
        first.setPalette('orange'),
      ];
      await Future.wait(writes);
      final restored = ThemeController();
      await restored.load();
      expect(restored.mode, ThemeMode.dark);
      expect(restored.palette, 'orange');
      expect(restored.data(Brightness.dark).brightness, Brightness.dark);
      first.dispose();
      restored.dispose();
    },
  );
  test('Invalid saved preferences fall back to safe defaults', () async {
    final store = MemoryThemeStore()
      ..values = {'mode': 'invalid', 'palette': 'invalid'};
    final theme = ThemeController(store: store);
    await theme.load();
    expect(theme.mode, ThemeMode.system);
    expect(theme.palette, 'green');
    theme.dispose();
  });
  test('Late startup load cannot overwrite user selection', () async {
    final ready = Completer<Map<String, String>>();
    final theme = ThemeController(store: DelayedStore(ready.future));
    final loading = theme.load();
    await theme.setMode(ThemeMode.dark);
    ready.complete({'mode': 'light', 'palette': 'blue'});
    await loading;
    expect(theme.mode, ThemeMode.dark);
    expect(theme.palette, 'green');
    theme.dispose();
  });
  test(
    'Write failure keeps selected theme and exposes retryable error',
    () async {
      final store = MemoryThemeStore()..fail = true;
      final theme = ThemeController(store: store);
      await theme.setPalette('blue');
      expect(theme.palette, 'blue');
      expect(theme.persistenceError, isNotNull);
      store.fail = false;
      await theme.setPalette('violet');
      expect(theme.persistenceError, isNull);
      theme.dispose();
    },
  );
  testWidgets(
    'Settings switch mode and palette without reloading wallets; dialog follows theme',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = CountingWalletStore();
      final theme = ThemeController(store: MemoryThemeStore());
      await tester.pumpWidget(LinkWalletApp(store: store, theme: theme));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('nav-3')));
      await tester.pumpAndSettle();
      expect(find.text('外观主题'), findsOneWidget);
      await tester.tap(find.text('浅色模式'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色模式'));
      await tester.pumpAndSettle();
      expect(theme.mode, ThemeMode.dark);
      await tester.tap(find.byKey(const ValueKey('palette-violet')));
      await tester.pumpAndSettle();
      expect(theme.palette, 'violet');
      expect(store.loads, 1);
      await tester.tap(find.byKey(const ValueKey('nav-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      final colors = ShadTheme.of(
        tester.element(find.byType(ShadDialog)),
      ).colorScheme;
      expect(
        ShadTheme.of(tester.element(find.byType(ShadDialog))).brightness,
        Brightness.dark,
      );
      expect(colors.primary, theme.data(Brightness.dark).colorScheme.primary);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      theme.dispose();
    },
  );
  testWidgets('System mode responds to platform brightness changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    final store = MemoryThemeStore()..values['mode'] = 'system';
    final theme = ThemeController(store: store);
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
    await tester.pumpWidget(
      LinkWalletApp(store: CountingWalletStore(), theme: theme),
    );
    await tester.pumpAndSettle();
    expect(
      ShadTheme.of(tester.element(find.text('我的钱包'))).brightness,
      Brightness.light,
    );
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    await tester.pumpAndSettle();
    expect(
      ShadTheme.of(tester.element(find.text('我的钱包'))).brightness,
      Brightness.dark,
    );
    await tester.pumpWidget(const SizedBox());
    theme.dispose();
  });
}

class DelayedStore implements ThemeStore {
  final Future<Map<String, String>> value;
  DelayedStore(this.value);
  @override
  Future<Map<String, String>> read() => value;
  @override
  Future<void> write(Map<String, String> values) async {}
}
