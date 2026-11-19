import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../app/theme_controller.dart';
import '../../shared/theme_context.dart';
import '../../shared/widgets/form_fields.dart';
import '../../shared/widgets/wallet_card.dart';

class AppearanceSettings extends StatelessWidget {
  final ThemeController controller;
  const AppearanceSettings({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => walletCard(
    context,
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('外观主题', style: ShadTheme.of(context).textTheme.large),
        const SizedBox(height: 8),
        Text(
          '即时应用到所有页面和弹窗，并在下次启动时恢复。',
          style: TextStyle(color: context.palette.mutedForeground),
        ),
        const SizedBox(height: 24),
        LinkSelect<ThemeMode>(
          label: '显示模式',
          value: controller.mode,
          options: const {
            ThemeMode.system: '跟随系统',
            ThemeMode.light: '浅色模式',
            ThemeMode.dark: '深色模式',
          },
          onChanged: controller.setMode,
        ),
        const SizedBox(height: 20),
        LinkSelect<String>(
          label: '主题配色',
          value: controller.palette,
          options: ThemeController.palettes,
          onChanged: controller.setPalette,
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ThemeController.palettes.entries.map((entry) {
            final color = ShadColorScheme.fromName(entry.key).primary;
            return Semantics(
              selected: controller.palette == entry.key,
              child: ShadButton.outline(
                key: ValueKey('palette-${entry.key}'),
                onPressed: () => controller.setPalette(entry.key),
                leading: Icon(
                  controller.palette == entry.key
                      ? Icons.check_circle
                      : Icons.circle,
                  size: 16,
                  color: color,
                ),
                child: Text(entry.value),
              ),
            );
          }).toList(),
        ),
        if (controller.persistenceError != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              controller.persistenceError!,
              style: TextStyle(color: context.palette.destructive),
            ),
          ),
      ],
    ),
  );
}
