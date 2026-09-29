import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/dmc_theme.dart';

const Color _nextTryInk = Color(0xFF6B4A15);
const Color _nextTryLine = Color(0xFFEBD9BC);
const Color _noteInk = Color(0xFF5C3F11);

/// Warm parent note on next-try rows and Mark Done. Eyebrow is never PARENT SAID.
class KidNextTryNote extends StatelessWidget {
  const KidNextTryNote({super.key, required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Dmc.marigoldSoft,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _nextTryLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.format_quote_outlined,
              size: 18, color: Dmc.marigoldDeep),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('A note from your parent',
                    style: Dmc.micro.copyWith(color: Dmc.marigoldDeep)),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: _noteInk,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class KidNextTryBadge extends StatelessWidget {
  const KidNextTryBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Dmc.marigoldSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _nextTryLine),
      ),
      child: const Text(
        'NEXT TRY',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: _nextTryInk,
        ),
      ),
    );
  }
}

class KidSentChip extends StatelessWidget {
  const KidSentChip({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Icon(Icons.send_outlined, size: 13, color: Dmc.pine),
        SizedBox(width: 5),
        Text(
          'Sent - waiting for your parent',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: Dmc.pine,
          ),
        ),
      ],
    );
  }
}

class KidDayDoneCard extends StatelessWidget {
  const KidDayDoneCard({super.key, required this.movedPct});

  final double movedPct;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 22, 18, 18),
      decoration: BoxDecoration(
        color: Dmc.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Dmc.line),
      ),
      child: Stack(
        alignment: Alignment.topCenter,
        children: [
          if (!reduce)
            const Positioned.fill(
              child: IgnorePointer(
                child: _SoftConfetti(key: Key('dmc-confetti')),
              ),
            ),
          Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: const BoxDecoration(
                  color: Dmc.marigoldSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, size: 24, color: Dmc.marigoldDeep),
              ),
              const SizedBox(height: 10),
              Text("That's today done.",
                  style: Dmc.displayStyle(size: 21, weight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Dmc.cream,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Dmc.line),
                ),
                child: Text.rich(
                  TextSpan(
                    text: '+${movedPct.toStringAsFixed(1)}%',
                    style: Dmc.displayStyle(
                        size: 16,
                        weight: FontWeight.w700,
                        color: Dmc.marigoldDeep),
                    children: const [
                      TextSpan(
                        text: ' moved the bar today',
                        style: TextStyle(
                          fontFamily: Dmc.text,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: Dmc.muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Parent checks the photos, then it counts. New chores land tomorrow.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.45, color: Dmc.muted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SoftConfetti extends StatelessWidget {
  const _SoftConfetti({super.key});

  @override
  Widget build(BuildContext context) {
    const colors = [
      Dmc.marigold,
      Color(0xFF2F8F83),
      Color(0xFFE8A33D),
      Dmc.pine,
      Dmc.clay,
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final rng = math.Random(7);
        return Stack(
          children: [
            for (var i = 0; i < 14; i++)
              Positioned(
                left: constraints.maxWidth * (0.06 + rng.nextDouble() * 0.88),
                top: 4 + rng.nextDouble() * 28,
                child: Container(
                  width: 7,
                  height: 11,
                  decoration: BoxDecoration(
                    color: colors[i % colors.length].withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class KidPaceCard extends StatelessWidget {
  const KidPaceCard({super.key, required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Dmc.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Dmc.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Dmc.surface,
              shape: BoxShape.circle,
              border: Border.all(color: Dmc.lineStrong),
            ),
            child: const Icon(Icons.wb_sunny_outlined,
                size: 17, color: Dmc.marigoldDeep),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Dmc.ink)),
                const SizedBox(height: 1),
                Text(body,
                    style: const TextStyle(
                        fontSize: 12.5, height: 1.45, color: Dmc.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class KidSentConfirmation extends StatelessWidget {
  const KidSentConfirmation({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 34, 18, 20),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: Dmc.pineSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.send_outlined, size: 26, color: Dmc.pine),
          ),
          const SizedBox(height: 12),
          Text('Sent to your parent.',
              style: Dmc.displayStyle(size: 21, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          const Text(
            'The bar moves the moment they take a look.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.5, color: Dmc.muted),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onBack,
              child: const Text('Back to today'),
            ),
          ),
        ],
      ),
    );
  }
}

class KidGoalEarnedFinale extends StatelessWidget {
  const KidGoalEarnedFinale({
    super.key,
    required this.goalTitle,
    required this.handOff,
  });

  final String goalTitle;
  final String handOff;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 560,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/photos/castle.jpg',
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const ColoredBox(color: Dmc.pineDeep),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x261F2621), Color(0xD11F2621)],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 26),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('100%',
                      style: Dmc.displayStyle(
                          size: 64,
                          weight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 6),
                  Text('You earned it.',
                      style: Dmc.displayStyle(
                          size: 27,
                          weight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(
                    handOff,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Color(0xFFE9E4D8),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      '$goalTitle, unlocked together',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
