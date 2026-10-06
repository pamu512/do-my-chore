import 'package:flutter_test/flutter_test.dart';
import 'package:do_my_chore/core/family_context.dart';
import 'package:do_my_chore/features/kid/mark_done_screen.dart';
import 'package:do_my_chore/services/edge_ai_client.dart';
import 'package:do_my_chore/services/goal_service.dart';

void main() {
  final combined = <String, dynamic>{
    'estimate': {
      'low': 900,
      'likely': 1400,
      'high': 2000,
      'currency': 'USD',
      'rationale': 'A 4-day Miami trip is usually this band.',
      'provider': 'nebius',
    },
    'weekly_save_suggestion': 100,
    'weeks': 14,
    'weekly_parent_save': 100,
    'chores': [
      {
        'title': 'Make your bed',
        'cadence': 'daily',
        'weight_pct': 40,
        'requires_photo': true,
        'is_makeup': false,
      },
      {
        'title': 'Wash the dishes',
        'cadence': 'daily',
        'weight_pct': 30,
        'requires_photo': true,
        'is_makeup': false,
      },
      {
        'title': 'Fold the laundry',
        'cadence': 'weekly',
        'weight_pct': 20,
        'requires_photo': true,
        'is_makeup': false,
      },
      {
        'title': 'Plan the park itinerary',
        'cadence': 'once',
        'weight_pct': 10,
        'requires_photo': false,
        'is_makeup': false,
      },
    ],
    'why': 'Parent funds the trip; the kid earns it with habits.',
    'deals': [
      {
        'title': 'Ticket bundle',
        'url': 'https://tickets.example',
        'price': 899,
        'source': 'tavily',
      }
    ],
    'deal_search': 'tavily',
    'model': 'nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B',
    'plan_provider': 'nebius',
  };

  test('parses combined estimate + chores + deals', () {
    final result = parseSuggestPlanPayload(
      combined,
      fallbackTitle: 'Miami Christmas',
      fallbackWeeks: 12,
      kidAge: kPrimaryKidAge,
      goalMode: 'family_trip',
    );
    expect(result.estimate.provider, 'nebius');
    expect(result.estimate.likely, 1400);
    expect(result.source, 'llm');
    expect(result.plan.weeklyParentSave, 100);
    expect(result.plan.chores.length, 4);
    expect(validatePlan(result.plan), isNull);
    expect(result.deals.single.price, 899);
    expect(result.dealSearch, 'tavily');
    expect(result.weeks, 14);
    expect(result.model, 'nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B');
    expect(result.planProvider, 'nebius');
  });

  test('live payload is used; null or unparseable payload stays local', () {
    final live = resolveSuggestPlan(
      edgePayload: combined,
      title: 'Miami Christmas',
      weeks: 12,
      kidAge: kPrimaryKidAge,
      goalMode: 'family_trip',
    );
    expect(live.source, 'llm');
    expect(live.estimate.provider, 'nebius');
    expect(live.model, 'nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B');
    expect(live.deals, isNotEmpty);

    final missing = resolveSuggestPlan(
      edgePayload: null,
      title: 'Miami Christmas',
      weeks: 12,
      kidAge: kPrimaryKidAge,
      goalMode: 'family_trip',
    );
    expect(missing.source, 'deterministic');
    expect(missing.estimate.provider, 'deterministic');
    expect(missing.estimate.likely, 1200);
    expect(missing.model, isNull);
    expect(missing.deals, isEmpty);

    final bad = resolveSuggestPlan(
      edgePayload: {'oops': true},
      title: 'Miami Christmas',
      weeks: 12,
      kidAge: kPrimaryKidAge,
      goalMode: 'family_trip',
    );
    expect(bad.source, 'deterministic');
    expect(bad.estimate.likely, 1200);
  });

  test('missing amount local path uses the goal_mode prior', () {
    final result = localGoalFirstSuggest(
      title: 'Miami Christmas',
      weeks: 12,
      kidAge: kPrimaryKidAge,
      goalMode: 'family_trip',
    );
    expect(result.estimate.likely, 1200);
    expect(result.plan.weeklyParentSave, 100);
    expect(result.source, 'deterministic');
  });

  test('bad combined JSON falls back to local deterministic', () {
    final result = parseSuggestPlanPayload(
      {'oops': true},
      fallbackTitle: 'Miami Christmas',
      fallbackWeeks: 12,
      kidAge: kPrimaryKidAge,
      goalMode: 'family_trip',
    );
    expect(result.source, 'deterministic');
    expect(result.estimate.likely, 1200);
    expect(validatePlan(result.plan), isNull);
  });

  test('privacy one-liner forbids sale/ads and has no em dash', () {
    expect(kAiPrivacyOneLiner.toLowerCase(), contains('do not sell'));
    expect(kAiPrivacyOneLiner.toLowerCase(), contains('ads'));
    expect(kAiPrivacyOneLiner.contains('—'), isFalse);
    expect(kAiPrivacyOneLiner.toLowerCase(), contains('goal text'));
    expect(kAiPrivacyOneLiner.toLowerCase(), contains('kid age'));
  });

  test('primary kid age is the demo family default', () {
    expect(kPrimaryKidAge, 8);
  });

  test('PhotoAssistResult.fromJson reads provider and model', () {
    final live = PhotoAssistResult.fromJson({
      'suggest': 'approve',
      'reason': 'The dishes look washed.',
      'provider': 'nebius',
      'model': 'Qwen/Qwen3.8-27B',
    });
    expect(live.suggest, 'approve');
    expect(live.provider, 'nebius');
    expect(live.model, 'Qwen/Qwen3.8-27B');
    expect(live.shownReason, 'The dishes look washed. (Qwen/Qwen3.8-27B)');

    final abstain = PhotoAssistResult.fromJson({
      'suggest': 'abstain',
      'reason': 'Photo check is not configured.',
      'provider': null,
      'model': null,
    });
    expect(abstain.provider, isNull);
    expect(abstain.model, isNull);
    expect(abstain.shownReason, 'Photo check is not configured.');
  });

  test('DEMO_WALK photo asset matches the chore title', () {
    expect(demoWalkPhotoAsset('Wash the dishes'), 'assets/photos/dishes.jpg');
    expect(demoWalkPhotoAsset('Fold the laundry'), 'assets/photos/laundry.jpg');
    expect(demoWalkPhotoAsset('Tidy your room'), 'assets/photos/bed.jpg');
    expect(demoWalkPhotoAsset('Make your bed'), 'assets/photos/bed.jpg');
    expect(demoWalkPhotoAsset('Homework'), 'assets/photos/dishes.jpg');
  });
}
