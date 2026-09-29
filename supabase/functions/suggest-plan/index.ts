// Goal-first Suggest Plan: estimate + weekly save + chores + why in one
// response. Optional deals live here too (same Tavily helper as cost
// orchestrate). targetAmount is optional.
//
// Provider order (Basics must run with zero keys):
//   1. NEBIUS_API_KEY → Token Factory + Nemotron
//   2. OPENAI_API_KEY → gpt-4o-mini
//   3. else deterministic builder (same JSON shape)
//
// TODO: require parent JWT (gateway / function verify)
// TODO: per-family rate limit on LLM + Tavily

import "https://deno.land/std@0.224.0/http/server.ts";
import { CORS } from "../_shared/cors.ts";
import { searchDeals } from "../_shared/deals.ts";
import {
  allowedPromptFields,
  goalFirstResponse,
  inferSlots,
  readGoalText,
  readTargetAmount,
  resolveEstimate,
  resolveWeeks,
  type ChoreSpec,
} from "../_shared/goal_estimate.ts";
import { chatCompletions, parseJsonObject } from "../_shared/llm.ts";
import {
  buildSafeDealQuery,
  sanitizeGoalText,
  skipLlmForGoal,
  systemGuardrailsMessage,
  validatePlanOutput,
  wrapUserGoalPayload,
} from "../_shared/prompt_guard.ts";

interface Plan {
  weekly_parent_save: number;
  chores: ChoreSpec[];
  why: string;
}

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
    `That weekly figure is parent funding for the real cost, not kid pocket money. ` +
    `Meanwhile ${who} earns the goal by keeping the habits going: the weight list adds up to ${weightSum} percent, so a steady streak lands exactly at 100 percent by the deadline.`;

  return { weekly_parent_save: weeklySave, chores: catalog, why };
}

async function buildLlmPlan(
  fields: ReturnType<typeof allowedPromptFields>,
  targetAmount: number,
): Promise<Plan> {
  const fallback = buildDeterministicPlan(fields.goalText, targetAmount, fields.weeks, fields.kidAge);
  const result = await chatCompletions({
    json: true,
    temperature: 0.4,
    capability: "text",
    messages: [
      { role: "system", content: systemGuardrailsMessage() },
      {
        role: "user",
        content: wrapUserGoalPayload(fields, { task: "plan", costUsd: targetAmount }),
      },
    ],
  });
  if (!result) return fallback;
  return validatePlanOutput(parseJsonObject(result.text), fallback) ?? fallback;
}

async function buildLlmEstimate(input: {
  title: string;
  enteredCost?: number;
  weeks: number;
  goalMode: string;
  kidAge: number;
}) {
  const fields = allowedPromptFields({
    goalText: input.title,
    kidAge: input.kidAge,
    weeks: input.weeks,
    goalMode: input.goalMode,
  });
  const result = await chatCompletions({
    json: true,
    temperature: 0.3,
    capability: "text",
    messages: [
      { role: "system", content: systemGuardrailsMessage() },
      {
        role: "user",
        content: wrapUserGoalPayload(fields, {
          task: "estimate",
          parentPriorUsd: input.enteredCost,
        }),
      },
    ],
  });
  return resolveEstimate({
    title: input.title,
    enteredCost: input.enteredCost,
    weeks: input.weeks,
    goalMode: input.goalMode,
    llmText: result?.text,
    llmProvider: result?.provider,
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const body = await req.json() as Record<string, unknown>;
    const sanitized = sanitizeGoalText(readGoalText(body));
    const title = sanitized.empty ? "Goal" : sanitized.text;
    const enteredCost = readTargetAmount(body);
    const weeks = resolveWeeks({ targetDate: body.targetDate, goalText: title });
    const kidAge = Number(body.kidAge) > 0 ? Number(body.kidAge) : 8;
    const slots = inferSlots(title, body.goalMode);
    const skipLlm = skipLlmForGoal(title);
    const estimate = skipLlm
      ? resolveEstimate({
        title,
        enteredCost,
        weeks,
        goalMode: slots.goal_mode,
      })
      : await buildLlmEstimate({
        title,
        enteredCost,
        weeks,
        goalMode: slots.goal_mode,
        kidAge,
      });
    const planAmount = enteredCost ?? estimate.likely;
    const fields = allowedPromptFields({
      goalText: title,
      kidAge,
      weeks,
      goalMode: slots.goal_mode,
    });
    const plan = skipLlm
      ? buildDeterministicPlan(title, planAmount, weeks, kidAge)
      : await buildLlmPlan(fields, planAmount);
    const searched = await searchDeals(
      buildSafeDealQuery(slots, slots.goal_mode, estimate.likely),
      estimate.likely,
    );
    return Response.json(
      goalFirstResponse({
        estimate,
        weeklyParentSave: plan.weekly_parent_save,
        chores: plan.chores,
        why: plan.why,
        weeks,
        slots,
        deals: searched.deals,
        dealSearch: searched.dealSearch,
      }),
      { headers: { ...CORS, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 400, headers: CORS });
  }
});
