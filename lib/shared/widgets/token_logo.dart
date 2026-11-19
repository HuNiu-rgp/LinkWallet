import 'package:flutter/material.dart';
import '../../core/token.dart';
import '../theme_context.dart';

/// Locally bundled token artwork; unknown assets use a neutral token icon.
class TokenLogo extends StatelessWidget {
  final TokenDefinition token;
  final double size;
  const TokenLogo({super.key, required this.token, this.size = 42});
  @override
  Widget build(BuildContext context) {
    final symbol = token.symbol.toUpperCase();
    final asset = switch (symbol) {
      'USDT' || 'USDT0' => 'USDT',
      'USDC' => 'USDC',
      'UNI' => 'UNI',
      'BTC' || 'WBTC' => 'BTC',
      _ => null,
    };
    final background = asset == 'USDT'
        ? const Color(0xff009393)
        : context.palette.muted;
    return Semantics(
      image: true,
      label: '${token.symbol} Logo',
      child: ClipOval(
        child: SizedBox.square(
          dimension: size,
          child: ColoredBox(
            color: background,
            child: asset == null
                ? Icon(
                    Icons.token_outlined,
                    size: size * .55,
                    color: context.palette.mutedForeground,
                  )
                : Image.asset(
                    'assets/chains/$asset.png',
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
          ),
        ),
      ),
    );
  }
}
