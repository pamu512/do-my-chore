/// Age-keyed chore catalog with stable ids. Suggest plan picks from here.
/// Sharing on Kid Today / approvals is library-id only — never title match.
library;

import 'chore_progress_math.dart';

class LibraryHabit {
  final String id;
  final String title;
  final String cadence;
  final bool requiresPhoto;
  final int minAge;
  final int maxAge;

  const LibraryHabit({
    required this.id,
    required this.title,
    required this.cadence,
    required this.requiresPhoto,
    required this.minAge,
    required this.maxAge,
  });
}

/// Extends the catalogs already used by `buildDeterministicPlan` / suggest-plan.
const List<LibraryHabit> kChoreLibrary = [
  LibraryHabit(
      id: 'make-your-bed',
      title: 'Make your bed',
      cadence: 'daily',
      requiresPhoto: true,
      minAge: 8,
      maxAge: 17),
  LibraryHabit(
      id: 'wash-the-dishes',
      title: 'Wash the dishes',
      cadence: 'daily',
      requiresPhoto: true,
      minAge: 8,
      maxAge: 17),
  LibraryHabit(
      id: 'fold-the-laundry',
      title: 'Fold the laundry',
      cadence: 'weekly',
      requiresPhoto: true,
      minAge: 0,
      maxAge: 17),
  LibraryHabit(
      id: 'plan-the-park-itinerary',
      title: 'Plan the park itinerary',
      cadence: 'once',
      requiresPhoto: false,
      minAge: 8,
      maxAge: 17),
  LibraryHabit(
      id: 'tidy-your-room',
      title: 'Tidy your room',
      cadence: 'daily',
      requiresPhoto: true,
      minAge: 0,
      maxAge: 7),
  LibraryHabit(
      id: 'set-and-clear-the-table',
      title: 'Set and clear the table',
      cadence: 'daily',
      requiresPhoto: true,
      minAge: 0,
      maxAge: 7),
  LibraryHabit(
      id: 'plan-the-week-together',
      title: 'Plan the week together',
      cadence: 'once',
      requiresPhoto: false,
      minAge: 0,
      maxAge: 7),
  LibraryHabit(
      id: 'clean-the-play-table',
      title: 'Clean the play table',
      cadence: 'daily',
      requiresPhoto: true,
      minAge: 0,
      maxAge: 7),
  LibraryHabit(
      id: 'vacuum-the-living-room',
      title: 'Vacuum the living room',
      cadence: 'weekly',
      requiresPhoto: true,
      minAge: 8,
      maxAge: 17),
  LibraryHabit(
      id: 'take-out-the-recycling',
      title: 'Take out the recycling',
      cadence: 'weekly',
      requiresPhoto: true,
      minAge: 8,
      maxAge: 17),
];

LibraryHabit? libraryHabitById(String id) {
  for (final h in kChoreLibrary) {
    if (h.id == id) return h;
  }
  return null;
}

LibraryHabit? libraryHabitByExactTitle(String title) {
  for (final h in kChoreLibrary) {
    if (h.title == title) return h;
  }
  return null;
}

List<LibraryHabit> libraryForAge(int age) =>
    [for (final h in kChoreLibrary) if (age >= h.minAge && age <= h.maxAge) h];

List<double> clusterCreditPreviews(
  List<({double weightPct, String cadence, int weeksN})> members,
) {
  return [
    for (final m in members)
      instanceCreditPct(
        weightPct: m.weightPct,
        expectedInstances:
            expectedInstances(cadence: m.cadence, weeksN: m.weeksN),
      )
  ];
}
