import 'package:flutter/material.dart';

import '../core/dmc_theme.dart';

/// Paths for Anoop's official lockup. The JPEG is the in-app source of truth;
/// launcher icons are a square crop of the pill (see scripts/gen_brand_icons.py).
abstract final class BrandAssets {
  static const logo = 'assets/branding/do_my_chore_logo.jpg';
}

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.height = 220});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Do My Chore',
      image: true,
      child: Image.asset(
        BrandAssets.logo,
        key: const Key('dmc-brand-logo'),
        height: height,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        errorBuilder: (context, error, stack) {
          return Text(
            'Do My Chore',
            textAlign: TextAlign.center,
            style: Dmc.displayStyle(size: 28, weight: FontWeight.w700),
          );
        },
      ),
    );
  }
}

/// Auth-entry / loading / backend-error surface. Cream field matches the mark.
class BrandSplash extends StatelessWidget {
  const BrandSplash({
    super.key,
    this.message,
    this.showProgress = true,
  });

  final String? message;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF9F2),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const BrandLogo(height: 240),
                if (showProgress) ...[
                  const SizedBox(height: 28),
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ],
                if (message != null) ...[
                  const SizedBox(height: 28),
                  Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: Dmc.text,
                      fontSize: 14.5,
                      height: 1.45,
                      color: Dmc.ink2,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
