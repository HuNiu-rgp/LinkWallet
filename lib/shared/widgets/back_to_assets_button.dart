import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class BackToAssetsButton extends StatelessWidget {
  const BackToAssetsButton({super.key});
  @override
  Widget build(BuildContext context) => ShadButton.outline(
    height: 34,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    leading: const Icon(Icons.arrow_back_rounded, size: 16),
    onPressed: () => Navigator.of(context).pop(),
    child: const Text('返回资产', style: TextStyle(fontSize: 12)),
  );
}
