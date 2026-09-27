// Build With AI: Basics — Suggest Plan edge function.
// With OPENAI_API_KEY set, an LLM drafts the plan (parent-language "why").
// Without a key, the deterministic builder below answers — same JSON shape.

import "https://deno.land/std@0.224.0/http/server.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ChoreSpec {
  title: string;
  reward: number;
  requires_photo: boolean;
  split_goal_pct: number;
}

interface Plan {
  weekly_topup: number;
  chores: ChoreSpec[];
  why: string;
}

const VISUAL = new Set([
  "Clean the play table",
  "Wash the dishes",
  "Vacuum the living room",
  "Tidy your room",
  "Set and clear the table",
  "Take out the recycling",
]);

const CATALOG: ChoreSpec[] = [
  { title: "Clean the play table", reward: 5, requires_photo: true, split_goal_pct: 80 },
  { title: "Read for 20 minutes", reward: 3, requires_photo: false, split_goal_pct: 100 },
  { title: "Wash the dishes", reward: 4, requires_photo: true, split_goal_pct: 80 },
  { title: "Make your bed", reward: 2, requires_photo: false, split_goal_pct: 100 },
  { title: "Vacuum the living room", reward: 5, requires_photo: true, split_goal_pct: 60 },
  { title: "Take out the recycling", reward: 3, requires_photo: false, split_goal_pct: 100 },
];

function round25(v: number): number {
  return Math.round(v * 4) / 4;
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, v));
}

export function buildDeterministicPlan(
  title: string,
  targetAmount: number,
  weeks: number,
  kidAge: number,
): Plan {
  const w = Math.max(1, weeks);
  const weeklyTotal = targetAmount / w;
  const weeklyTopup = round25(weeklyTotal * 0.3);
  const choreWeeklyNeeded = weeklyTotal - weeklyTopup;
  const baseSum = CATALOG.reduce((s, c) => s + c.reward, 0);
  const scale = choreWeeklyNeeded / baseSum;

  const chores: ChoreSpec[] = CATALOG.map((c) => ({
    title: c.title,
    reward: clamp(round25(c.reward * scale), 0.5, 50),
    requires_photo: c.requires_photo && VISUAL.has(c.title),
    split_goal_pct: c.split_goal_pct,
  }));

  const choreWeekly = chores.reduce((s, c) => s + c.reward, 0);
  const who = kidAge <= 7 ? "your little one" : "your kid";
  const why =
    `Over ${w} weeks, "${title}" needs $${targetAmount}. ` +
    `Putting in $${weeklyTopup.toFixed(0)} a week from your own money, plus about $${choreWeekly.toFixed(0)} a week that ${who} earns from these chores, gets there right on time — no end-of-plan scramble. Chores with a camera icon just need a quick photo so you can see the result yourself.`;

  return { weekly_topup: weeklyTopup, chores, why };
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

  const prompt = `You help a parent plan how a kid saves for a goal.
Goal: "${title}", cost $${targetAmount}, deadline in ${weeks} weeks, kid age ${kidAge}.
Return ONLY JSON: {"weekly_topup": number, "chores": [{"title": string, "reward": number, "requires_photo": boolean, "split_goal_pct": number}], "why": string}
Rules: 4-8 chores; parent top-up covers roughly 30% weekly; rewards age-appropriate (max $10);
requires_photo ONLY for chores a parent can verify by looking (never for reading/practice/trust chores);
"why" is 2-3 sentences in plain parent language — explain the plan like a friend, no ML jargon.`;

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
    return {
      weekly_topup: Number(parsed.weekly_topup) || fallback.weekly_topup,
      chores: parsed.chores.slice(0, 8),
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
