// Goal-first cost estimate + minimized prompts.
// Zero keys and bad model JSON always fall back to a static prior by
// goal_mode (not live market prices). Parent must confirm before lock.

import { parseJsonObject } from "./llm.ts";

export type EstimateProvider = "nebius" | "openai" | "deterministic";

export interface Estimate {
  low: number;
  likely: number;
  high: number;
  currency: string;
  rationale: string;
  provider: EstimateProvider;
}

export interface AllowedPromptFields {
  goalText: string;
  kidAge: number;
  weeks: number;
  goal_mode: string;
}

export interface GoalSlots {
  goal_mode: string;
  place?: string;
  duration_days?: number;
  party_size_default: number;
}

export interface ChoreSpec {
  library_chore_id: string;
  title: string;
  cadence: "once" | "daily" | "weekly";
  weight_pct: number;
  requires_photo: boolean;
  is_makeup: boolean;
}

/** Stable chore catalog (mirrors app/lib/services/chore_library.dart). */
export const CHORE_LIBRARY: Array<{
  id: string;
  title: string;
  cadence: "once" | "daily" | "weekly";
  requires_photo: boolean;
  min_age: number;
  max_age: number;
}> = [
  { id: "make-your-bed", title: "Make your bed", cadence: "daily", requires_photo: true, min_age: 8, max_age: 17 },
  { id: "wash-the-dishes", title: "Wash the dishes", cadence: "daily", requires_photo: true, min_age: 8, max_age: 17 },
  { id: "fold-the-laundry", title: "Fold the laundry", cadence: "weekly", requires_photo: true, min_age: 0, max_age: 17 },
  { id: "plan-the-park-itinerary", title: "Plan the park itinerary", cadence: "once", requires_photo: false, min_age: 8, max_age: 17 },
  { id: "tidy-your-room", title: "Tidy your room", cadence: "daily", requires_photo: true, min_age: 0, max_age: 7 },
  { id: "set-and-clear-the-table", title: "Set and clear the table", cadence: "daily", requires_photo: true, min_age: 0, max_age: 7 },
  { id: "plan-the-week-together", title: "Plan the week together", cadence: "once", requires_photo: false, min_age: 0, max_age: 7 },
  { id: "clean-the-play-table", title: "Clean the play table", cadence: "daily", requires_photo: true, min_age: 0, max_age: 7 },
  { id: "vacuum-the-living-room", title: "Vacuum the living room", cadence: "weekly", requires_photo: true, min_age: 8, max_age: 17 },
  { id: "take-out-the-recycling", title: "Take out the recycling", cadence: "weekly", requires_photo: true, min_age: 8, max_age: 17 },
];

export function libraryForAge(age: number) {
  return CHORE_LIBRARY.filter((h) => age >= h.min_age && age <= h.max_age);
}

/** Resolve an LLM row to a library chore by id, falling back to exact title. */
export function resolveLibraryChore(raw: Partial<ChoreSpec>): ChoreSpec | null {
  const byId = CHORE_LIBRARY.find((h) => h.id === raw.library_chore_id);
  const byTitle = CHORE_LIBRARY.find((h) => h.title === raw.title);
  const hit = byId ?? byTitle;
  if (!hit) return null;
  return {
    library_chore_id: hit.id,
    title: hit.title,
    cadence: (raw.cadence as ChoreSpec["cadence"]) || hit.cadence,
    weight_pct: Number(raw.weight_pct) || 0,
    requires_photo: raw.requires_photo === true,
    is_makeup: false,
  };
}

/** Static USD priors when the parent has not entered an amount. Not live prices. */
export const COST_PRIORS: Record<string, { low: number; likely: number; high: number }> = {
  family_trip: { low: 800, likely: 1200, high: 1800 },
  kid_item: { low: 40, likely: 80, high: 150 },
  other: { low: 80, likely: 150, high: 250 },
};

export function round25(v: number): number {
  return Math.round(v * 4) / 4;
}

export function readGoalText(body: Record<string, unknown>): string {
  const text = String(body.goalText ?? body.title ?? "").trim();
  return text || "Goal";
}

export function readTargetAmount(body: Record<string, unknown>): number | undefined {
  const n = Number(body.targetAmount);
  return n > 0 ? n : undefined;
}

export function normalizeGoalMode(raw: unknown): string {
  const v = String(raw ?? "").trim();
  if (v === "family_trip" || v === "kid_item" || v === "other") return v;
  return "";
}

export function inferGoalMode(goalText: string, hint?: unknown): string {
  const normalized = normalizeGoalMode(hint);
  if (normalized) return normalized;
  const t = goalText.toLowerCase();
  if (/\b(trip|travel|vacation|flight|hotel|miami|disney|christmas|xmas)\b/.test(t)) {
    return "family_trip";
  }
  return "kid_item";
}

export function inferSlots(goalText: string, hint?: unknown): GoalSlots {
  const goal_mode = inferGoalMode(goalText, hint);
  const t = goalText.toLowerCase();
  const days = t.match(/(\d+)\s*-?\s*days?\b/);
  let place: string | undefined;
  const toPlace = goalText.match(
    /\bto\s+([A-Za-z][A-Za-z ]{1,32}?)(?:\s+with|\s+for|\s+over|,|\.|$)/i,
  );
  if (toPlace) place = toPlace[1].trim();
  else if (t.includes("miami")) place = "Miami";
  return {
    goal_mode,
    ...(place ? { place } : {}),
    ...(days ? { duration_days: Number(days[1]) } : {}),
    party_size_default: goal_mode === "family_trip" ? 4 : 1,
  };
}

function nextChristmas(now: Date): Date {
  const year = now.getUTCFullYear();
  let ms = Date.UTC(year, 11, 25);
  if (ms <= now.getTime()) ms = Date.UTC(year + 1, 11, 25);
  return new Date(ms);
}

export function weeksBetween(target: Date, now: Date): number {
  const ms = target.getTime() - now.getTime();
  return Math.max(1, Math.ceil(ms / 604800000));
}

export function resolveWeeks(
  input: { targetDate?: unknown; goalText?: string },
  now: Date = new Date(),
): number {
  const raw = String(input.targetDate ?? "").trim();
  if (raw) {
    const parsed = new Date(raw);
    if (!Number.isNaN(parsed.getTime())) return weeksBetween(parsed, now);
  }
  const text = (input.goalText ?? "").toLowerCase();
  if (text.includes("christmas") || text.includes("xmas")) {
    return weeksBetween(nextChristmas(now), now);
  }
  return 12;
}

export function allowedPromptFields(input: Record<string, unknown>): AllowedPromptFields {
  const goalText = readGoalText(input);
  const kidAge = Number(input.kidAge);
  const weeks = Number(input.weeks);
  return {
    goalText,
    kidAge: kidAge > 0 ? Math.round(kidAge) : 8,
    weeks: weeks > 0 ? Math.round(weeks) : 12,
    goal_mode: inferGoalMode(goalText, input.goalMode ?? input.goal_mode),
  };
}

export function buildEstimatePrompt(fields: AllowedPromptFields, parentPriorUsd?: number): string {
  const prior = parentPriorUsd != null && parentPriorUsd > 0
    ? `Parent prior amount: $${parentPriorUsd}. Use it as a prior, not the only possible answer.\n`
    : "";
  return (
    `Estimate a realistic present-day USD cost for this family goal.\n` +
    `Goal: "${fields.goalText}"\n` +
    `Type: ${fields.goal_mode}\n` +
    `Kid age: ${fields.kidAge}\n` +
    `Deadline in ${fields.weeks} weeks.\n` +
    prior +
    `Return ONLY JSON: {"low": number, "likely": number, "high": number, "rationale": string}\n` +
    `Rules: all numbers > 0; low <= likely <= high; USD; rationale is 2-3 sentences in plain parent language (no ML jargon).`
  );
}

export function buildPlanPrompt(fields: AllowedPromptFields, targetAmount: number): string {
  const catalogLines = libraryForAge(fields.kidAge)
    .map((h) => `- ${h.id}: "${h.title}" (${h.cadence}, photo=${h.requires_photo})`)
    .join("\n");
  return (
    `You help a parent plan how a kid earns a goal through habits, while the parent funds the real cost.\n` +
    `Goal: "${fields.goalText}", cost $${targetAmount}, deadline in ${fields.weeks} weeks, kid age ${fields.kidAge}.\n` +
    `Type: ${fields.goal_mode}.\n` +
    `Return ONLY JSON: {"weekly_parent_save": number, "chores": [{"library_chore_id": string, "title": string, "cadence": "once"|"daily"|"weekly", "weight_pct": number, "requires_photo": boolean, "is_makeup": false}], "why": string}\n` +
    `Rules:\n` +
    `- Pick 4-8 chores ONLY from this library. Use the given library_chore_id exactly. Same habit always uses the same id.\n` +
    `${catalogLines}\n` +
    `- Do not invent titles or ids. Do not fuzzy-match.\n` +
    `- each weight_pct > 0; all weights together sum to at least 100 (a little over is good slack).\n` +
    `- daily weights around 30-45, weekly around 15-25, at most one once chore.\n` +
    `- requires_photo ONLY when the library says photo=true.\n` +
    `- weekly_parent_save = about cost / weeks. This is parent funding, not kid pocket money.\n` +
    `- is_makeup is always false in the initial plan; makeup chores are added by the parent later.\n` +
    `- "why" is 2-3 sentences in plain parent language. No ML jargon.`
  );
}

export function deterministicEstimate(input: {
  title: string;
  enteredCost?: number;
  weeks: number;
  goalMode: string;
}): Estimate {
  const weeks = Math.max(1, input.weeks);
  const entered = input.enteredCost != null && input.enteredCost > 0 ? input.enteredCost : undefined;
  if (entered != null) {
    return {
      low: round25(entered * 0.8),
      likely: entered,
      high: round25(entered * 1.25),
      currency: "USD",
      rationale:
        `"${input.title}" is entered at $${entered.toFixed(0)}. Without live prices we treat that as the likely cost, with a lower band around 80% and a higher band around 125% so you can lock a number that still feels honest.`,
      provider: "deterministic",
    };
  }
  const prior = COST_PRIORS[input.goalMode] ?? COST_PRIORS.other;
  return {
    low: prior.low,
    likely: prior.likely,
    high: prior.high,
    currency: "USD",
    rationale:
      `"${input.title}" has no amount yet. This offline band is a starting point for a ${input.goalMode.replace("_", " ")}, not a live price. Confirm or change the likely number before you lock it. About $${round25(prior.likely / weeks)} a week for ${weeks} weeks covers the likely figure.`,
    provider: "deterministic",
  };
}

function validEstimate(raw: Record<string, unknown> | null): Omit<Estimate, "provider"> | null {
  if (!raw) return null;
  const low = Number(raw.low);
  const likely = Number(raw.likely);
  const high = Number(raw.high);
  const rationale = String(raw.rationale ?? "").trim();
  if (!(low > 0 && likely > 0 && high > 0)) return null;
  if (low > likely || likely > high) return null;
  if (!rationale) return null;
  return { low, likely, high, currency: "USD", rationale };
}

export function resolveEstimate(input: {
  title: string;
  enteredCost?: number;
  weeks: number;
  goalMode: string;
  llmText?: string | null;
  llmProvider?: "nebius" | "openai";
}): Estimate {
  const fallback = deterministicEstimate({
    title: input.title,
    enteredCost: input.enteredCost,
    weeks: input.weeks,
    goalMode: input.goalMode,
  });
  if (!input.llmText || !input.llmProvider) return fallback;
  const parsed = validEstimate(parseJsonObject(input.llmText));
  if (!parsed) return fallback;
  return { ...parsed, provider: input.llmProvider };
}

export function goalFirstResponse(input: {
  estimate: Estimate;
  weeklyParentSave: number;
  chores: ChoreSpec[];
  why: string;
  weeks: number;
  slots: GoalSlots;
  deals?: unknown[];
  dealSearch?: "tavily" | "skipped";
}): {
  estimate: Estimate;
  weekly_save_suggestion: number;
  weeks: number;
  slots: GoalSlots;
  weekly_parent_save: number;
  chores: ChoreSpec[];
  why: string;
  deals: unknown[];
  deal_search: "tavily" | "skipped";
} {
  const weeks = Math.max(1, input.weeks);
  return {
    estimate: input.estimate,
    weekly_save_suggestion: input.estimate.likely / weeks,
    weeks,
    slots: input.slots,
    weekly_parent_save: input.weeklyParentSave,
    chores: input.chores,
    why: input.why,
    deals: input.deals ?? [],
    deal_search: input.dealSearch ?? "skipped",
  };
}
