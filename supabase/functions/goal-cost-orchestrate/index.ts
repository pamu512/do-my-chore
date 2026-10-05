// Parent cost/deal orchestrator (refresh / re-estimate).
// Goal-first: targetAmount is optional. Missing amount uses the static
// goal_mode prior (or an LLM estimate from goal text). Never 500 on no key.
//
// Keys (all optional — Basics still works with none):
//   NEBIUS_API_KEY  → Token Factory + Nemotron
//   OPENAI_API_KEY  → gpt-4o-mini
//   TAVILY_API_KEY  → deal search; skip search if unset
//
// TODO: require parent JWT (gateway / function verify)
// TODO: per-family rate limit on LLM + Tavily

import "https://deno.land/std@0.224.0/http/server.ts";
import { CORS } from "../_shared/cors.ts";
import { searchDeals } from "../_shared/deals.ts";
import {
  allowedPromptFields,
  finishLlmEstimate,
  inferGoalMode,
  inferSlots,
  readGoalText,
  readTargetAmount,
  resolveEstimate,
  resolveWeeks,
  type Estimate,
} from "../_shared/goal_estimate.ts";
import { chatCompletions, chatOk, llmErrorForFallback, type PublicLlmError } from "../_shared/llm.ts";
import {
  buildSafeDealQuery,
  sanitizeGoalText,
  skipLlmForGoal,
  systemGuardrailsMessage,
  wrapUserGoalPayload,
} from "../_shared/prompt_guard.ts";

async function llmOrDeterministicEstimate(input: {
  title: string;
  enteredCost?: number;
  weeks: number;
  goalMode: string;
  kidAge: number;
}): Promise<{ estimate: Estimate; model: string | null; llmError: PublicLlmError | null }> {
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
  if (!chatOk(result)) {
    return {
      estimate: resolveEstimate({
        title: input.title,
        enteredCost: input.enteredCost,
        weeks: input.weeks,
        goalMode: input.goalMode,
      }),
      model: null,
      llmError: llmErrorForFallback(result),
    };
  }
  return finishLlmEstimate({
    title: input.title,
    enteredCost: input.enteredCost,
    weeks: input.weeks,
    goalMode: input.goalMode,
    llmText: result.text,
    llmProvider: result.provider,
    llmModel: result.model,
    baseHost: result.baseHost,
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
    const goalMode = inferGoalMode(title, body.goalMode);
    const kidAge = Number(body.kidAge) > 0 ? Number(body.kidAge) : 9; // matches app kPrimaryKidAge
    const slots = inferSlots(title, body.goalMode);
    const skipLlm = skipLlmForGoal(title);
    const estimated = skipLlm
      ? {
        estimate: resolveEstimate({ title, enteredCost, weeks, goalMode }),
        model: null,
        llmError: null,
      }
      : await llmOrDeterministicEstimate({
        title,
        enteredCost,
        weeks,
        goalMode,
        kidAge,
      });
    const weekly = estimated.estimate.likely / weeks;
    const searched = await searchDeals(
      buildSafeDealQuery(slots, goalMode, estimated.estimate.likely),
      estimated.estimate.likely,
    );
    const payload = {
      estimate: estimated.estimate,
      model: estimated.model,
      weekly_save_suggestion: weekly,
      deals: searched.deals,
      deal_search: searched.dealSearch,
      weeks,
    };
    return Response.json(
      estimated.llmError ? { ...payload, llm_error: estimated.llmError } : payload,
      { headers: { ...CORS, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 400, headers: CORS });
  }
});
