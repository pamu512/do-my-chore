import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/ledger_math.dart';

void main() {
  group('suggestedSavePerWeek', () {
    test('Disneyland worked example: 3500 over 14 weeks is 250', () {
      expect(suggestedSavePerWeek(cost: 3500, weeksN: 14), 250);
    });

    test('skateboard: 180 over 6 weeks is 30', () {
      expect(suggestedSavePerWeek(cost: 180, weeksN: 6), 30);
    });

    test('zero or negative weeks clamp to one week', () {
      expect(suggestedSavePerWeek(cost: 100, weeksN: 0), 100);
    });
  });

  group('suggestedSavePerDay / Month', () {
    test('day is week / 7', () {
      expect(suggestedSavePerDay(cost: 3500, weeksN: 14), closeTo(250 / 7, 1e-9));
    });

    test('month uses ceil(weeks / 4.345) months', () {
      // 14 weeks -> 4 months -> 875
      expect(suggestedSavePerMonth(cost: 3500, weeksN: 14), 875);
    });
  });

  group('parentSaveProgress', () {
    test('fraction under cost', () {
      expect(parentSaveProgress(saved: 500, cost: 3500), closeTo(500 / 3500, 1e-9));
    });

    test('caps at 1 past the cost', () {
      expect(parentSaveProgress(saved: 4000, cost: 3500), 1);
    });

    test('zero cost never divides by zero', () {
      expect(parentSaveProgress(saved: 100, cost: 0), 0);
    });
  });
}
