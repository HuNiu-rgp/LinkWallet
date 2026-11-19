import 'package:flutter/material.dart';
import '../theme_context.dart';

Widget walletCard(
  BuildContext context,
  Widget child, {
  EdgeInsets padding = const EdgeInsets.all(24),
}) => Container(
  width: double.infinity,
  padding: padding,
  decoration: BoxDecoration(
    color: context.palette.card,
    border: Border.all(color: context.palette.border),
    borderRadius: BorderRadius.circular(14),
  ),
  child: child,
);
