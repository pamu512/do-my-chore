// Rev 3 Suggest Plan edge function: kid habit weights (>= 100%) + parent
// weekly save for the real cost. With OPENAI_API_KEY set, an LLM drafts the
// plan (parent-language "why"). Without a key, the deterministic builder
// below answers - same JSON shape.

import "https://deno.land/std@0.224.0/http/server.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ChoreSpec {
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

const CATALOG: ChoreSpec[] = [
  { title: "Make your bed", cadence: "daily", weight_pct: 40, requires_photo: true, is_makeup: false },
  { title: "Wash the dishes", cadence: "daily", weight_pct: 30, requires_photo: true, is_makeup: false },
  { title: "Fold the laundry", cadence: "weekly", weight_pct: 20, requires_photo: true, is_makeup: false },
  { title: "Plan the park itinerary", cadence: "once", weight_pct: 10, requires_photo: false, is_makeup: false },
];

const LITTLE_CATALOG: ChoreSpec[] = [
  { title: "Tidy your room", cadence: "daily", weight_pct: 40, requires_photo: true, is_makeup: false },
  { title: "Set and clear the table", cadence: "daily", weight_pct: 30, requires_photo: true, is_makeup: false },
  { title: "Fold the laundry", cadence: "weekly", weight_pct: 20, requires_photo: true, is_makeup: false },
  { title: "Plan the week together", cadence: "once", weight_pct: 10, requires_photo: false, is_makeup: false },
];

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
  const key = Deno.env.get("OPENAI_API_KEY");
  if (!key) return fallback;

  const prompt = `You help a parent plan how a kid earns a goal through habits, while the parent funds the real cost.
Goal: "${title}", cost $${targetAmount}, deadline in ${weeks} weeks, kid age ${kidAge}.
Return ONLY JSON: {"weekly_parent_save": number, "chores": [{"title": string, "cadence": "once"|"daily"|"weekly", "weight_pct": number, "requires_photo": boolean, "is_makeup": false}], "why": string}
Rules:
- 4-8 chores; each weight_pct > 0; all weights together sum to at least 100 (a little over is good slack).
- daily weights around 30-45, weekly around 15-25, at most one once chore.
- requires_photo ONLY for chores a parent can verify by looking (never for reading/practice/trust chores).
- weekly_parent_save = about targetAmount / weeks.
- is_makeup is always false in the initial plan; makeup chores are added by the parent later.
- "why" is 2-3 sentences in plain parent language. No ML jargon.`;

  try {
    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [{ role: "user", content: prompt }],
        response_format: { type: "json_object" },
        temperature: 0.4,
      }),
    });
    if (!res.ok) return fallback;
    const data = await res.json();
    const parsed = JSON.parse(data.choices[0].message.content) as Plan;
    if (!parsed?.chores?.length || !parsed.why) return fallback;
    const weightSum = parsed.chores.reduce((s, c) => s + (Number(c.weight_pct) || 0), 0);
    if (weightSum + 1e-9 < 100) return fallback;
    return {
      weekly_parent_save: Number(parsed.weekly_parent_save) || fallback.weekly_parent_save,
      chores: parsed.chores.slice(0, 8).map((c) => ({ ...c, is_makeup: false })),
      why: parsed.why,
    };
  } catch {
    return fallback;
  }
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
