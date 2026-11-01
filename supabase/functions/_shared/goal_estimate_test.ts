import { assertEquals, assert } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  NEBIUS_BASE_URL,
  parseJsonObject,
  resolveLlmProvider,
} from "./llm.ts";
import {
  allowedPromptFields,
  buildEstimatePrompt,
  buildPlanPrompt,
  deterministicEstimate,
  finishLlmEstimate,
  goalFirstResponse,
  readGoalText,
  resolveEstimate,
  resolveWeeks,
} from "./goal_estimate.ts";

Deno.test("provider order is unchanged: Nebius over OpenAI over none", () => {
  const both = resolveLlmProvider({
    NEBIUS_API_KEY: "neb-key",
    OPENAI_API_KEY: "oai-key",
  });
  assertEquals(both?.provider, "nebius");
  assertEquals(both?.baseUrl, NEBIUS_BASE_URL);
  assertEquals(resolveLlmProvider({ OPENAI_API_KEY: "oai-key" })?.provider, "openai");
  assertEquals(resolveLlmProvider({}), null);
});

Deno.test("parseJsonObject still strips Nemotron think blocks", () => {
  const parsed = parseJsonObject(
    '<think>ignore { this }</think>\n{"low": 10, "likely": 20, "high": 30, "rationale": "ok"}',
  );
  assertEquals(parsed?.low, 10);
  assertEquals(parsed?.likely, 20);
});

Deno.test("readGoalText prefers goalText and accepts legacy title", () => {
  assertEquals(readGoalText({ goalText: "Miami Christmas", title: "old" }), "Miami Christmas");
  assertEquals(readGoalText({ title: "Skateboard" }), "Skateboard");
  assertEquals(readGoalText({}), "Goal");
});

Deno.test("missing targetAmount + zero-key uses goal_mode prior, not 400", () => {
  const trip = deterministicEstimate({
    title: "Miami for Christmas",
    weeks: 12,
    goalMode: "family_trip",
  });
  assertEquals(trip.provider, "deterministic");
  assertEquals(trip.currency, "USD");
  assert(trip.low > 0 && trip.likely > 0 && trip.high > 0);
  assert(trip.low <= trip.likely && trip.likely <= trip.high);
  assertEquals(trip.likely, 1200);
  assertEquals(trip.low, 800);
  assertEquals(trip.high, 1800);

  const item = deterministicEstimate({
    title: "Skateboard",
    weeks: 8,
    goalMode: "kid_item",
  });
  assertEquals(item.likely, 80);
  assertEquals(item.low, 40);
  assertEquals(item.high, 150);
});

Deno.test("entered amount still bands 80/100/125 around the parent prior", () => {
  const estimate = deterministicEstimate({
    title: "Disneyland",
    enteredCost: 3500,
    weeks: 14,
    goalMode: "family_trip",
  });
  assertEquals(estimate.likely, 3500);
  assertEquals(estimate.low, 2800);
  assertEquals(estimate.high, 4375);
  assertEquals(estimate.provider, "deterministic");
});

Deno.test("zero-key resolveEstimate never requires an LLM result", () => {
  const estimate = resolveEstimate({
    title: "Miami Christmas",
    weeks: 12,
    goalMode: "family_trip",
  });
  assertEquals(estimate.provider, "deterministic");
  assertEquals(estimate.likely, 1200);
});

Deno.test("bad JSON and invalid bands fall back to the deterministic prior", () => {
  const fallback = deterministicEstimate({
    title: "Miami",
    weeks: 12,
    goalMode: "family_trip",
  });
  const fromGarbage = resolveEstimate({
    title: "Miami",
    weeks: 12,
    goalMode: "family_trip",
    llmText: "not-json",
    llmProvider: "nebius",
  });
  assertEquals(fromGarbage, fallback);

  const fromBadBands = resolveEstimate({
    title: "Miami",
    weeks: 12,
    goalMode: "family_trip",
    llmText: '{"low": 900, "likely": 100, "high": 50, "rationale": "backwards"}',
    llmProvider: "openai",
  });
  assertEquals(fromBadBands, fallback);
});

Deno.test("think-block JSON still becomes a live estimate", () => {
  const estimate = resolveEstimate({
    title: "Miami",
    weeks: 12,
    goalMode: "family_trip",
    llmText:
      '<think>noise { }</think>```json\n{"low": 900, "likely": 1400, "high": 2000, "rationale": "A 4-day Miami trip is usually this band."}\n```',
    llmProvider: "nebius",
  });
  assertEquals(estimate.provider, "nebius");
  assertEquals(estimate.likely, 1400);
  assertEquals(estimate.low, 900);
  assertEquals(estimate.high, 2000);
});

Deno.test("allowed prompt fields are only goal text, kidAge, weeks, goal_mode", () => {
  const fields = allowedPromptFields({
    goalText: "Miami Christmas 4 days",
    kidAge: 9,
    weeks: 12,
    goalMode: "family_trip",
    parentName: "Arjun",
    email: "parent@demo",
    uid: "00000000-0000-0000-0000-0000000000a1",
    familyId: "fam-1",
    ledger: [{ amount: 20 }],
  } as Record<string, unknown>);
  assertEquals(Object.keys(fields).sort(), ["goalText", "goal_mode", "kidAge", "weeks"]);
  assertEquals(fields.goalText, "Miami Christmas 4 days");
  assertEquals(fields.kidAge, 9);
  assertEquals(fields.weeks, 12);
  assertEquals(fields.goal_mode, "family_trip");

  const prompt = buildEstimatePrompt(fields);
  const lower = prompt.toLowerCase();
  for (const banned of ["arjun", "parent@demo", "00000000-0000-0000-0000-0000000000a1", "fam-1", "ledger"]) {
    assert(!lower.includes(banned), `prompt leaked "${banned}"`);
  }

  const planPrompt = buildPlanPrompt(fields, 1200);
  const planLower = planPrompt.toLowerCase();
  for (const banned of ["arjun", "parent@demo", "ledger", "fam-1"]) {
    assert(!planLower.includes(banned), `plan prompt leaked "${banned}"`);
  }
});

Deno.test("goal-first response is estimate + weekly_save + chores + why; deals stay on this payload", () => {
  const estimate = deterministicEstimate({
    title: "Miami Christmas",
    weeks: 12,
    goalMode: "family_trip",
  });
  const combined = goalFirstResponse({
    estimate,
    weeklyParentSave: 100,
    chores: [
      { library_chore_id: "make-your-bed", title: "Make your bed", cadence: "daily", weight_pct: 40, requires_photo: true, is_makeup: false },
      { library_chore_id: "wash-the-dishes", title: "Wash the dishes", cadence: "daily", weight_pct: 30, requires_photo: true, is_makeup: false },
      { library_chore_id: "fold-the-laundry", title: "Fold the laundry", cadence: "weekly", weight_pct: 20, requires_photo: true, is_makeup: false },
      { library_chore_id: "plan-the-week-together", title: "Plan the week together", cadence: "once", weight_pct: 10, requires_photo: false, is_makeup: false },
    ],
    why: "Parent funds the trip; the kid earns it with habits.",
    weeks: 12,
    slots: { goal_mode: "family_trip", party_size_default: 4 },
    deals: [],
    dealSearch: "skipped",
  });
  assertEquals(combined.estimate.likely, 1200);
  assertEquals(combined.weekly_save_suggestion, 100);
  assertEquals(combined.weekly_parent_save, 100);
  assertEquals(combined.chores.length, 4);
  assert(combined.why.length > 0);
  assertEquals(combined.deals, []);
  assertEquals(combined.deal_search, "skipped");
  assertEquals(combined.weeks, 12);
  assertEquals(combined.model, null);
  assertEquals(combined.plan_provider, null);
});

Deno.test("goalFirstResponse threads model and plan_provider", () => {
  const estimate = deterministicEstimate({
    title: "Lego castle set",
    weeks: 14,
    goalMode: "kid_item",
  });
  const live = goalFirstResponse({
    estimate: { ...estimate, provider: "nebius" },
    weeklyParentSave: 6,
    chores: [],
    why: "live",
    weeks: 14,
    slots: { goal_mode: "kid_item", party_size_default: 1 },
    model: "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B",
    planProvider: "nebius",
  });
  assertEquals(live.estimate.provider, "nebius");
  assertEquals(live.model, "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B");
  assertEquals(live.plan_provider, "nebius");
});

Deno.test("resolveWeeks uses targetDate, else inferred Christmas, else 12", () => {
  assertEquals(resolveWeeks({ targetDate: "2099-01-01" }, new Date("2026-09-28")), Math.ceil(
    (new Date("2099-01-01").getTime() - new Date("2026-09-28").getTime()) / 604800000,
  ));
  const fromChristmas = resolveWeeks(
    { goalText: "Miami with the family for Christmas" },
    new Date("2026-09-28T12:00:00Z"),
  );
  assert(fromChristmas >= 12 && fromChristmas <= 14);
  assertEquals(resolveWeeks({ goalText: "a skateboard sometime" }, new Date("2026-09-28")), 12);
});

const NEMOTRON_ESTIMATE = `<think>
The braces { "low": 0 } in here are not the answer.
</think>
\`\`\`json
{
  "low": "800",
  "likely": "1,200",
  "high": "$1,800",
  "currency": "USD",
  "confidence": "medium",
  "rationale": "A family trip in this range usually costs about this much today. The low figure is a tighter budget and the high figure leaves room for hotels. You confirm the likely number before it is locked.",
}
\`\`\``;

Deno.test("realistic Nemotron estimate with a think block and fenced JSON is accepted", () => {
  const estimate = resolveEstimate({
    title: "Miami",
    weeks: 12,
    goalMode: "family_trip",
    llmText: NEMOTRON_ESTIMATE,
    llmProvider: "nebius",
  });
  assertEquals(estimate.provider, "nebius");
  assertEquals(estimate.low, 800);
  assertEquals(estimate.likely, 1200);
  assertEquals(estimate.high, 1800);
  assertEquals(estimate.currency, "USD");
  assert(estimate.rationale.startsWith("A family trip"));

  const live = finishLlmEstimate({
    title: "Miami",
    weeks: 12,
    goalMode: "family_trip",
    llmText: NEMOTRON_ESTIMATE,
    llmProvider: "nebius",
    llmModel: "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B",
    baseHost: "api.tokenfactory.nebius.com",
  });
  assertEquals(live.llmError, null);
  assertEquals(live.model, "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B");
  assertEquals(live.estimate.likely, 1200);
});

Deno.test("unparseable and invalid estimates set llm_error instead of failing silently", () => {
  const logs: string[] = [];
  const orig = console.error;
  console.error = (...args: unknown[]) => {
    logs.push(args.map((a) => String(a)).join(" "));
  };
  try {
    const garbage = finishLlmEstimate({
      title: "Miami",
      weeks: 12,
      goalMode: "family_trip",
      llmText: "not-json " + "x".repeat(500),
      llmProvider: "nebius",
      llmModel: "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B",
      baseHost: "api.tokenfactory.nebius.com",
    });
    assertEquals(garbage.estimate.provider, "deterministic");
    assertEquals(garbage.model, null);
    const garbageErr = garbage.llmError;
    if (!garbageErr || !("sample" in garbageErr)) throw new Error("expected unparseable sample");
    assertEquals(garbageErr.reason, "unparseable_output");
    assertEquals(garbageErr.status, 200);
    assertEquals(garbageErr.base_host, "api.tokenfactory.nebius.com");
    assertEquals(garbageErr.sample.length, 400);
    assertEquals(garbageErr.sample.startsWith("not-json "), true);

    const badBands = finishLlmEstimate({
      title: "Miami",
      weeks: 12,
      goalMode: "family_trip",
      llmText: '{"low": 900, "likely": 100, "high": 50, "rationale": "backwards", "extra": true}',
      llmProvider: "nebius",
      llmModel: "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B",
      baseHost: "llm.example.test",
    });
    const bandErr = badBands.llmError;
    if (!bandErr || !("sample" in bandErr)) throw new Error("expected invalid_estimate sample");
    assertEquals(bandErr.reason, "invalid_estimate");
    assertEquals(bandErr.base_host, "llm.example.test");
    assertEquals(bandErr.status, 200);
    assert(bandErr.sample.includes("backwards"));
  } finally {
    console.error = orig;
  }
  const line = logs.join("\n");
  assert(line.includes("reason=unparseable_output"));
  assert(line.includes("reason=invalid_estimate"));
  assert(line.includes("base_host=api.tokenfactory.nebius.com"));
  assert(line.includes("base_host=llm.example.test"));
});
