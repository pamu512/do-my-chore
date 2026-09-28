// Parent cost/deal orchestrator (refresh / re-estimate).
// Goal-first: targetAmount is optional. Missing amount uses the static
// goal_mode prior (or an LLM estimate from goal text). Never 500 on no key.
//
// Keys (all optional — Basics still works with none):
//   NEBIUS_API_KEY  → Token Factory + Nemotron
//   OPENAI_API_KEY  → gpt-4o-mini
//   TAVILY_API_KEY  → deal search; skip search if unset

import "https://deno.land/std@0.224.0/http/server.ts";
import { CORS } from "../_shared/cors.ts";
import { searchDeals } from "../_shared/deals.ts";
import {
  allowedPromptFields,
  buildEstimatePrompt,
  inferGoalMode,
  readGoalText,
  readTargetAmount,
  resolveEstimate,
  resolveWeeks,
} from "../_shared/goal_estimate.ts";
import { chatCompletions } from "../_shared/llm.ts";

async function llmOrDeterministicEstimate(input: {
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
    messages: [{
      role: "user",
      content: buildEstimatePrompt(fields, input.enteredCost),
    }],
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
    const title = readGoalText(body);
    const enteredCost = readTargetAmount(body);
    const weeks = resolveWeeks({ targetDate: body.targetDate, goalText: title });
    const goalMode = inferGoalMode(title, body.goalMode);
    const kidAge = Number(body.kidAge) > 0 ? Number(body.kidAge) : 8;
    const estimate = await llmOrDeterministicEstimate({
      title,
      enteredCost,
      weeks,
      goalMode,
      kidAge,
    });
    const weekly = estimate.likely / weeks;
    const searched = await searchDeals(
      `best current price for ${title} ${goalMode === "family_trip" ? "family trip tickets hotel" : "to buy"} under $${estimate.likely}`,
      estimate.likely,
    );
    return Response.json({
      estimate,
      weekly_save_suggestion: weekly,
      deals: searched.deals,
      deal_search: searched.dealSearch,
      weeks,
    }, { headers: { ...CORS, "Content-Type": "application/json" } });
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 400, headers: CORS });
  }
});
