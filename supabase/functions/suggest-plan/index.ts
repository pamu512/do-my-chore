// Rev 3 Suggest Plan edge function: kid habit weights (>= 100%) + parent
// weekly save for the real cost.
//
// Provider order (Basics must run with zero keys):
//   1. NEBIUS_API_KEY → Token Factory + Nemotron
//   2. OPENAI_API_KEY → gpt-4o-mini
//   3. else deterministic builder (same JSON shape)

import "https://deno.land/std@0.224.0/http/server.ts";
import { CORS } from "../_shared/cors.ts";
import { chatCompletions, parseJsonObject } from "../_shared/llm.ts";

interface ChoreSpec {
  library_chore_id: string;
  title: string;
  cadence: "once" | "daily" | "weekly";
  weight_pct: number;
  requires_photo: boolean;
  is_makeup: boolean;
}

interface Plan {
  weekly_parent_save: number;
  chores: ChoreSpec[];
  why: string;
}

const VISUAL = new Set([
  "Make your bed",
  "Wash the dishes",
  "Fold the laundry",
  "Clean the play table",
  "Vacuum the living room",
  "Tidy your room",
  "Set and clear the table",
  "Take out the recycling",
]);

const LIBRARY: Array<{
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

const CATALOG: ChoreSpec[] = [
  { library_chore_id: "make-your-bed", title: "Make your bed", cadence: "daily", weight_pct: 40, requires_photo: true, is_makeup: false },
  { library_chore_id: "wash-the-dishes", title: "Wash the dishes", cadence: "daily", weight_pct: 30, requires_photo: true, is_makeup: false },
  { library_chore_id: "fold-the-laundry", title: "Fold the laundry", cadence: "weekly", weight_pct: 20, requires_photo: true, is_makeup: false },
  { library_chore_id: "plan-the-park-itinerary", title: "Plan the park itinerary", cadence: "once", weight_pct: 10, requires_photo: false, is_makeup: false },
];

const LITTLE_CATALOG: ChoreSpec[] = [
  { library_chore_id: "tidy-your-room", title: "Tidy your room", cadence: "daily", weight_pct: 40, requires_photo: true, is_makeup: false },
  { library_chore_id: "set-and-clear-the-table", title: "Set and clear the table", cadence: "daily", weight_pct: 30, requires_photo: true, is_makeup: false },
  { library_chore_id: "fold-the-laundry", title: "Fold the laundry", cadence: "weekly", weight_pct: 20, requires_photo: true, is_makeup: false },
  { library_chore_id: "plan-the-week-together", title: "Plan the week together", cadence: "once", weight_pct: 10, requires_photo: false, is_makeup: false },
];

function libraryForAge(age: number) {
  return LIBRARY.filter((h) => age >= h.min_age && age <= h.max_age);
}

function resolveLibraryChore(raw: Partial<ChoreSpec>): ChoreSpec | null {
  const byId = LIBRARY.find((h) => h.id === raw.library_chore_id);
  const byTitle = LIBRARY.find((h) => h.title === raw.title);
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

function round25(v: number): number {
  return Math.round(v * 4) / 4;
}

export function buildDeterministicPlan(
  title: string,
  targetAmount: number,
  weeks: number,
  kidAge: number,
): Plan {
  const w = Math.max(1, weeks);
  const weeklySave = round25(targetAmount / w);
  const catalog = kidAge <= 7 ? LITTLE_CATALOG : CATALOG;
  const who = kidAge <= 7 ? "your little one" : "your kid";
  const weightSum = catalog.reduce((s, c) => s + c.weight_pct, 0);
  const why =
    `"${title}" costs about $${targetAmount}. Setting aside $${weeklySave} a week for ${w} weeks covers the full cost before the date. ` +
    `Meanwhile ${who} earns the goal by keeping the habits going: the weight list adds up to ${weightSum} percent, so a steady streak lands exactly at 100 percent by the deadline.`;

  return { weekly_parent_save: weeklySave, chores: catalog, why };
}

async function buildLlmPlan(
  title: string,
  targetAmount: number,
  weeks: number,
  kidAge: number,
): Promise<Plan> {
  const fallback = buildDeterministicPlan(title, targetAmount, weeks, kidAge);
  const allowed = libraryForAge(kidAge);
  const catalogLines = allowed
    .map((h) => `- ${h.id}: "${h.title}" (${h.cadence}, photo=${h.requires_photo})`)
    .join("\n");
  const result = await chatCompletions({
    json: true,
    temperature: 0.4,
    capability: "text",
    messages: [{
      role: "user",
      content:
        `You help a parent plan how a kid earns a goal through habits, while the parent funds the real cost.
Goal: "${title}", cost $${targetAmount}, deadline in ${weeks} weeks, kid age ${kidAge}.
Return ONLY JSON: {"weekly_parent_save": number, "chores": [{"library_chore_id": string, "title": string, "cadence": "once"|"daily"|"weekly", "weight_pct": number, "requires_photo": boolean, "is_makeup": false}], "why": string}
Rules:
- Pick 4-8 chores ONLY from this library. Use the given library_chore_id exactly. Same habit always uses the same id.
${catalogLines}
- Do not invent titles or ids. Do not fuzzy-match.
- each weight_pct > 0; all weights together sum to at least 100 (a little over is good slack).
- daily weights around 30-45, weekly around 15-25, at most one once chore.
- requires_photo ONLY when the library says photo=true.
- weekly_parent_save = about targetAmount / weeks.
- is_makeup is always false in the initial plan; makeup chores are added by the parent later.
- "why" is 2-3 sentences in plain parent language. No ML jargon.`,
    }],
  });
  if (!result) return fallback;
  const parsed = parseJsonObject(result.text) as Plan | null;
  if (!parsed?.chores?.length || !parsed.why) return fallback;
  const resolved = parsed.chores.slice(0, 8).map(resolveLibraryChore);
  if (resolved.some((c) => c == null)) return fallback;
  const chores = resolved as ChoreSpec[];
  const weightSum = chores.reduce((s, c) => s + (Number(c.weight_pct) || 0), 0);
  if (weightSum + 1e-9 < 100) return fallback;
  return {
    weekly_parent_save: Number(parsed.weekly_parent_save) || fallback.weekly_parent_save,
    chores,
    why: parsed.why,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const { title, targetAmount, targetDate, kidAge } = await req.json();
    const weeks = targetDate
      ? Math.max(1, Math.ceil((new Date(targetDate).getTime() - Date.now()) / 604800000))
      : 12;
    const plan = await buildLlmPlan(String(title), Number(targetAmount), weeks, Number(kidAge) || 8);
    return Response.json(plan, { headers: { ...CORS, "Content-Type": "application/json" } });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 400, headers: CORS });
  }
});
