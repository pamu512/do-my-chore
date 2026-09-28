import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/services/cost_estimate.dart';

void main() {
  group('buildDeterministicCostEstimate', () {
    test('uses the parent number as likely, with an 80/125 band', () {
      final estimate = buildDeterministicCostEstimate(
        title: 'Disneyland',
        enteredCost: 3500,
        weeks: 14,
      );
      expect(estimate.low, 2800);
      expect(estimate.likely, 3500);
      expect(estimate.high, 4375);
      expect(estimate.currency, 'USD');
      expect(estimate.provider, 'deterministic');
      expect(estimate.weeklySaveSuggestion, 250);
    });

    test('weekly save follows locked likely / weeks', () {
      final estimate = buildDeterministicCostEstimate(
        title: 'Skateboard',
        enteredCost: 200,
        weeks: 8,
      );
      expect(estimate.weeklySaveSuggestion, 25);
    });

    test('missing amount uses the family_trip prior table', () {
      final estimate = buildDeterministicCostPrior(
        title: 'Miami Christmas',
        goalMode: 'family_trip',
        weeks: 12,
      );
      expect(estimate.low, 800);
      expect(estimate.likely, 1200);
      expect(estimate.high, 1800);
      expect(estimate.provider, 'deterministic');
      expect(estimate.weeklySaveSuggestion, 100);
    });

    test('missing amount uses the kid_item prior table', () {
      final estimate = buildDeterministicCostPrior(
        title: 'Skateboard',
        goalMode: 'kid_item',
        weeks: 8,
      );
      expect(estimate.likely, 80);
      expect(estimate.low, 40);
      expect(estimate.high, 150);
    });

    test('zero or negative entered cost is rejected', () {
      expect(
        () => buildDeterministicCostEstimate(
          title: 'X',
          enteredCost: 0,
          weeks: 4,
        ),
        throwsArgumentError,
      );
    });

    test('why stays in parent language (no ML jargon)', () {
      final estimate = buildDeterministicCostEstimate(
        title: 'Camping trip',
        enteredCost: 300,
        weeks: 12,
      );
      final lower = estimate.rationale.toLowerCase();
      for (final jargon in ['model', 'inference', 'token', 'llm', 'nebius']) {
        expect(lower.contains(jargon), isFalse, reason: 'found "$jargon"');
      }
    });
  });

  group('dealsUnderBudget', () {
    test('keeps priced deals at or under the budget', () {
      final kept = dealsUnderBudget(
        [
          const GoalDeal(
              title: 'Over', url: 'https://a.example', price: 4000),
          const GoalDeal(
              title: 'Fit', url: 'https://b.example', price: 2899),
        ],
        budget: 3500,
      );
      expect(kept.map((d) => d.title), ['Fit']);
    });

    test('all priced deals over budget stay empty', () {
      final kept = dealsUnderBudget(
        [
          const GoalDeal(
              title: 'Over', url: 'https://a.example', price: 4000),
          const GoalDeal(
              title: 'Also over', url: 'https://b.example', price: 5000),
        ],
        budget: 3500,
      );
      expect(kept, isEmpty);
    });

    test('when no prices parse, still returns the top links', () {
      final kept = dealsUnderBudget(
        const [
          GoalDeal(title: 'A', url: 'https://a.example'),
          GoalDeal(title: 'B', url: 'https://b.example'),
          GoalDeal(title: 'C', url: 'https://c.example'),
          GoalDeal(title: 'D', url: 'https://d.example'),
        ],
        budget: 3500,
      );
      expect(kept.map((d) => d.title), ['A', 'B', 'C']);
    });
  });

  group('parseCostOrchestrateResponse', () {
    test('reads estimate + deals from the edge payload', () {
      final result = parseCostOrchestrateResponse({
        'estimate': {
          'low': 2800,
          'likely': 3500,
          'high': 4200,
          'currency': 'USD',
          'rationale': 'Park tickets plus a hotel night.',
          'provider': 'nebius',
        },
        'weekly_save_suggestion': 250,
        'deals': [
          {
            'title': 'Ticket bundle',
            'url': 'https://tickets.example',
            'price': 2899,
            'snippet': 'Family 4-pack',
            'source': 'tavily',
          }
        ],
        'deal_search': 'tavily',
      });
      expect(result.estimate.provider, 'nebius');
      expect(result.estimate.likely, 3500);
      expect(result.weeklySaveSuggestion, 250);
      expect(result.deals.single.price, 2899);
      expect(result.dealSearch, 'tavily');
    });

    test('falls back when the payload is missing an estimate', () {
      final result = parseCostOrchestrateResponse(
        {'oops': true},
        fallbackTitle: 'Disneyland',
        fallbackCost: 3500,
        fallbackWeeks: 14,
      );
      expect(result.estimate.provider, 'deterministic');
      expect(result.estimate.likely, 3500);
      expect(result.deals, isEmpty);
    });
  });

  group('lockPayload', () {
    test('stores the chosen amount, weekly save, and optional deal JSON', () {
      final estimate = buildDeterministicCostEstimate(
        title: 'Disneyland',
        enteredCost: 3500,
        weeks: 14,
      );
      final deal = const GoalDeal(
        title: 'Bundle',
        url: 'https://tickets.example',
        price: 2899,
      );
      final payload = lockPayload(
        estimate: estimate,
        lockedAmount: 2899,
        weeks: 14,
        deal: deal,
      );
      expect(payload.targetAmount, 2899);
      expect(payload.weeklyParentSave, closeTo(2899 / 14, 0.01));
      expect(payload.deal!['url'], 'https://tickets.example');
      expect(payload.costEstimate['provider'], 'deterministic');
    });
  });

  group('extractUsdPrice', () {
    test('reads the first dollar amount from a snippet', () {
      expect(extractUsdPrice('From \$2,899 for a family of four'), 2899);
      expect(extractUsdPrice('about \$199.99 plus tax'), 199.99);
      expect(extractUsdPrice('no price here'), isNull);
    });
  });
}
