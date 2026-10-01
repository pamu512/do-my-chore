/// Demo family context for goal-first Suggest.
///
/// Profiles have no age column in v1, and multi-kid plans are out of scope.
/// The seeded family has one kid; Suggest attaches this primary age.
const int kPrimaryKidAge = 8;

/// Shown next to the first AI call. No sale / no ads. No em dashes.
const String kAiPrivacyOneLiner =
    'Suggest uses your goal text and the primary kid age only. '
    'Photos leave the device only if you open Photo Assist. '
    'We do not sell this data or use it for ads.';
