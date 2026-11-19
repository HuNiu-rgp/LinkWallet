import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class LinkInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? placeholder;
  final bool enabled, obscureText, autocorrect, enableSuggestions;
  final TextInputType? keyboardType;
  const LinkInput({
    super.key,
    required this.controller,
    required this.label,
    this.placeholder,
    this.enabled = true,
    this.obscureText = false,
    this.autocorrect = false,
    this.enableSuggestions = false,
    this.keyboardType,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: ShadTheme.of(context).textTheme.small),
      const SizedBox(height: 8),
      ShadInput(
        controller: controller,
        enabled: enabled,
        obscureText: obscureText,
        autocorrect: autocorrect,
        enableSuggestions: enableSuggestions,
        keyboardType: keyboardType,
        placeholder: placeholder == null ? null : Text(placeholder!),
      ),
    ],
  );
}

class LinkSelect<T> extends StatelessWidget {
  final String label;
  final T value;
  final bool enabled;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  const LinkSelect({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(label, style: ShadTheme.of(context).textTheme.small),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) => ShadSelect<T>(
          initialValue: value,
          enabled: enabled,
          minWidth: constraints.maxWidth,
          maxWidth: constraints.maxWidth,
          options: options.entries.map(
            (e) => ShadOption<T>(value: e.key, child: Text(e.value)),
          ),
          selectedOptionBuilder: (context, selected) =>
              Text(options[selected]!),
          onChanged: (selected) {
            if (selected != null) onChanged(selected);
          },
        ),
      ),
    ],
  );
}
