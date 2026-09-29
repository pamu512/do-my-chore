import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/chore_service.dart';
import 'package:do_my_chore/services/chore_progress_math.dart';
import 'package:do_my_chore/services/encouragement.dart';

/// Rev 3 approval semantics: approve flips the submission status only.
/// Progress lives in approved submissions x instance credits, never in
/// dollar ledger entries. The old goal/pocket split is retired.
void main() {
  group('approval credit preview (pure math)', () {
    test('daily chore credits weight / (7*N) per approval', () {
      // Bed 40% daily over 14 weeks: each approval adds 40/98.
      final credit =
          instanceCreditPct(weightPct: 40, expectedInstances: 7 * 14);
      expect(credit, closeTo(40 / 98, 1e-9));
    });

    test('weekly chore credits weight / N per approval', () {
      final credit = instanceCreditPct(weightPct: 20, expectedInstances: 14);
      expect(credit, closeTo(20 / 14, 1e-9));
    });

    test('once chore credits the full weight on the single approval', () {
      expect(instanceCreditPct(weightPct: 10, expectedInstances: 1), 10);
    });
  });

  group('submission state machine', () {
    test('photo chore cannot submit without photo', () {
      expect(
        () => assertSubmittable(requiresPhoto: true, hasPhoto: false),
        throwsArgumentError,
      );
    });

    test('photo chore submits with photo; trust chore never needs one', () {
      expect(
        () => assertSubmittable(requiresPhoto: true, hasPhoto: true),
        returnsNormally,
      );
      expect(
        () => assertSubmittable(requiresPhoto: false, hasPhoto: false),
        returnsNormally,
      );
    });

    test('reject builds a nudge and returns chore to Today', () {
      final nudge = rejectNudge(choreTitle: 'Wash the dishes');
      expect(nudge, isNotEmpty);
      expect(nudge.toLowerCase(), isNot(contains('try again')));
      expect(nudge, contains('bright light'));
      expect(nudge, contains('Wash the dishes'));
      expect(kidCopyAllowed(nudge), isTrue);
    });

    test('reject prefers a non-empty parent note', () {
      expect(
        rejectNudge(choreTitle: 'Bed', parentNote: '  Whole sheet, please.  '),
        'Whole sheet, please.',
      );
      expect(
        rejectNudge(choreTitle: 'Bed', parentNote: '   '),
        rejectNudge(choreTitle: 'Bed'),
      );
    });

    test('resubmission creates a new row, never mutates the old one', () {
      // The service always inserts; the rejected row is never updated back to
      // pending. Status transitions stay pending -> approved | rejected only.
      expect(
          kAllowedTransitions, containsPair('pending', ['approved', 'rejected']));
      expect(kAllowedTransitions.containsKey('rejected'), isFalse);
    });
  });
}
