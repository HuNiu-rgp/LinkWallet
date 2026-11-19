import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

extension ThemeContext on BuildContext {
  ShadColorScheme get palette => ShadTheme.of(this).colorScheme;
}
