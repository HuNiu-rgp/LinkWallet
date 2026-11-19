import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../core/wallet.dart';

class BrandLogo extends StatelessWidget {
  final double size;
  const BrandLogo({super.key, this.size = 32});
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/brand/linkwallet.svg',
    width: size,
    height: size,
    semanticsLabel: 'LinkWallet Logo',
  );
}

class ChainLogo extends StatelessWidget {
  final Chain chain;
  final double size;
  const ChainLogo({super.key, required this.chain, this.size = 24});
  @override
  Widget build(BuildContext context) {
    final asset = switch (chain.id) {
      728126428 => 'tron',
      0 => 'solana',
      137 => 'polygon',
      56 => 'bnb',
      _ => 'ethereum',
    };
    return Semantics(
      label: '${chain.name} Logo',
      image: true,
      child: ClipOval(
        child: Container(
          width: size,
          height: size,
          color: chain.family == Family.solana
              ? const Color(0xff12151b)
              : Colors.transparent,
          padding: chain.family == Family.solana
              ? EdgeInsets.all(size * .17)
              : EdgeInsets.zero,
          child: SvgPicture.asset(
            'assets/chains/$asset.svg',
            fit: BoxFit.contain,
            excludeFromSemantics: true,
          ),
        ),
      ),
    );
  }
}
