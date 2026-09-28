import 'package:flutter/material.dart';
import 'dart:math' as math;

/// C-Ledger design tokens: calm porcelain surfaces, pine for the parent,
/// marigold for the kid. Display serif (Fraunces) for headings and numbers,
/// Public Sans for text. Mirror of the approved HTML mock (Direction C).
abstract final class Dmc {
  Dmc._();

  // ---- palette ----
  static const bg = Color(0xFFFBFAF8);
  static const surface = Color(0xFFFFFFFF);
  static const ink = Color(0xFF1F2621);
  static const ink2 = Color(0xFF4A544D);
  static const muted = Color(0xFF5D675F);
  static const faint = Color(0xFF7A837C);
  static const pine = Color(0xFF1E4D3B);
  static const pineDeep = Color(0xFF143528);
  static const pineSoft = Color(0xFFEDF2EF);
  static const marigold = Color(0xFFD98E2B);
  static const marigoldDeep = Color(0xFF8F5A12);
  static const marigoldSoft = Color(0xFFF9EEDD);
  static const clay = Color(0xFFB45540);
  static const clayText = Color(0xFFA34936);
  static const claySoft = Color(0xFFF7E9E5);
  static const line = Color(0xFFE6E2D9);
  static const lineStrong = Color(0xFFDCD6C8);
  static const cream = Color(0xFFF7F5EF);
  static const snack = Color(0xFF243029);
  static const onSnack = Color(0xFFF4F2EC);

  // ---- type families (bundled, see pubspec) ----
  static const display = 'DmcDisplay';
  static const text = 'DmcText';

  // ---- role accents (the mock's kid-mode swap) ----
  static Color accent(bool isKid) => isKid ? marigold : pine;
  static Color accentInk(bool isKid) => isKid ? ink : Colors.white;
  static Color accentText(bool isKid) => isKid ? marigoldDeep : pine;
  static Color accentSoft(bool isKid) => isKid ? marigoldSoft : pineSoft;

  static TextStyle displayStyle({
    double size = 21,
    FontWeight weight = FontWeight.w600,
    Color color = ink,
  }) =>
      TextStyle(
        fontFamily: display,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: -0.2,
        height: 1.15,
      );

  /// Small uppercase eyebrow label, as in the mock's `.micro`.
  static const micro = TextStyle(
    fontFamily: text,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.9,
    color: muted,
  );

  static ThemeData theme(bool isKid) {
    final accentColor = accent(isKid);
    final scheme = ColorScheme.fromSeed(
      seedColor: accentColor,
      primary: accentColor,
      onPrimary: accentInk(isKid),
      secondary: isKid ? pine : marigold,
      onSecondary: isKid ? Colors.white : ink,
      surface: surface,
      onSurface: ink,
      error: clay,
      onError: Colors.white,
    );
    return ThemeData(
      useMaterial3: true,
      fontFamily: text,
      scaffoldBackgroundColor: bg,
      colorScheme: scheme,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: display,
          fontSize: 17.5,
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: line),
        ),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1, space: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        titleTextStyle: displayStyle(size: 18, weight: FontWeight.w700),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accentColor,
          foregroundColor: accentInk(isKid),
          disabledBackgroundColor: accentColor.withValues(alpha: 0.42),
          disabledForegroundColor: accentInk(isKid),
          minimumSize: const Size(0, 47),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontFamily: text,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          backgroundColor: surface,
          side: const BorderSide(color: lineStrong),
          minimumSize: const Size(0, 47),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(
            fontFamily: text,
            fontSize: 15.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accentText(isKid),
          textStyle: const TextStyle(
            fontFamily: text,
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: const TextStyle(color: faint),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: lineStrong),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: lineStrong),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accentColor, width: 1.5),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: pine,
        linearTrackColor: line,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: snack,
        contentTextStyle: const TextStyle(
          fontFamily: text,
          fontSize: 13.5,
          color: onSnack,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// The goal rail from the mock: progress fill, milestone dots at
/// 20/40/60/80 that light up as they pass, and the castle at the finish.
class DmcProgressRail extends StatelessWidget {
  const DmcProgressRail({
    super.key,
    required this.pct,
    required this.isKid,
    this.leftCap = '0%',
    this.rightCap,
  });

  /// Progress in percent, 0..100 (values above 100 clamp: the bar caps).
  final double pct;
  final bool isKid;
  final String leftCap;
  final String? rightCap;

  static const _railHeight = 30.0;

  @override
  Widget build(BuildContext context) {
    final accent = Dmc.accent(isKid);
    final clamped = pct.clamp(0.0, 100.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _railHeight,
          width: double.infinity,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              Widget dot(double fraction) {
                final passed = clamped / 100 >= fraction - 1e-9;
                return Positioned(
                  left: w * fraction - 6,
                  top: _railHeight / 2 - 6,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: passed ? accent : Dmc.bg,
                      border: Border.all(
                        color: passed ? accent : Dmc.lineStrong,
                        width: 1.5,
                      ),
                    ),
                  ),
                );
              }

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: _railHeight / 2 - 2,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: Dmc.line,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: _railHeight / 2 - 2,
                    child: Container(
                      height: 4,
                      width: w * clamped / 100,
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  dot(0.2),
                  dot(0.4),
                  dot(0.6),
                  dot(0.8),
                  Positioned(
                    right: -2,
                    top: _railHeight / 2 - 15,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: const BoxDecoration(
                        color: Dmc.surface,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.castle_outlined,
                        size: 21,
                        color: clamped >= 100 ? accent : Dmc.faint,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (rightCap != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(leftCap, style: _capStyle),
                Text(rightCap!, style: _capStyle),
              ],
            ),
          ),
      ],
    );
  }

  static const _capStyle = TextStyle(
    fontFamily: Dmc.text,
    fontSize: 11.5,
    color: Dmc.faint,
  );
}

/// Shimmer-free skeleton block used by the loading states. A soft pulse on
/// cream keeps the calm of the design while matching final layout shapes.
class DmcSkeleton extends StatefulWidget {
  const DmcSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
    this.margin,
  });

  final double? width;
  final double height;
  final double radius;
  final EdgeInsetsGeometry? margin;

  @override
  State<DmcSkeleton> createState() => _DmcSkeletonState();
}

class _DmcSkeletonState extends State<DmcSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(
          (math.sin(_c.value * 2 * math.pi) + 1) / 2,
        );
        final color = Color.lerp(
          const Color(0xFFEFEBE1),
          const Color(0xFFF7F4EC),
          t,
        )!;
        return Container(
          width: widget.width,
          height: widget.height,
          margin: widget.margin,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        );
      },
    );
  }
}

/// A goal-card-shaped skeleton: header line, big balance line, rail, rows.
class DmcGoalCardSkeleton extends StatelessWidget {
  const DmcGoalCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const DmcSkeleton(width: 110, height: 11),
                const Spacer(),
                Container(
                  width: 44,
                  height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFEBE1),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Dmc.line),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const DmcSkeleton(width: 180, height: 26),
            const SizedBox(height: 14),
            const DmcSkeleton(height: 6, radius: 3),
            const SizedBox(height: 14),
            const DmcSkeleton(height: 30, radius: 15),
            const SizedBox(height: 16),
            ...List.generate(3, (i) => const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Row(children: [
                    DmcSkeleton(width: 20),
                    SizedBox(width: 12),
                    Expanded(child: DmcSkeleton(height: 14)),
                  ]),
                )),
          ],
        ),
      ),
    );
  }
}
