// Post-Accept parent cost/deal orchestrator.
// Estimates real-world USD cost (low/likely/high) and optionally finds
// deals under that budget. Does NOT write chores or change kid %.
//
// Keys (all optional — Basics still works with none):
//   NEBIUS_API_KEY  → Token Factory + Nemotron
//   OPENAI_API_KEY  → gpt-4o-mini
//   TAVILY_API_KEY  → deal search; skip search if unset

import "https://deno.land/std@0.224.0/http/server.ts";
import { CORS } from "../_shared/cors.ts";
import { type Deal, dealsUnderBudget, extractUsdPrice } from "../_shared/deals.ts";
import { chatCompletions, parseJsonObject } from "../_shared/llm.ts";

interface Estimate {
  low: number;
  likely: number;
  high: number;
  currency: string;
  rationale: string;
  provider: "nebius" | "openai" | "deterministic";
}

function round25(v: number): number {
  return Math.round(v * 4) / 4;
}

function weeksFrom(targetDate: string | undefined): number {
  if (!targetDate) return 12;
  const ms = new Date(targetDate).getTime() - Date.now();
  return Math.max(1, Math.ceil(ms / 604800000));
}

function deterministicEstimate(title: string, enteredCost: number, weeks: number): Estimate {
  return {
    low: round25(enteredCost * 0.8),
    likely: enteredCost,
    high: round25(enteredCost * 1.25),
    currency: "USD",
    rationale:
      `"${title}" is entered at $${enteredCost.toFixed(0)}. Without live prices we treat that as the likely cost, with a lower band around 80% and a higher band around 125% so you can lock a number that still feels honest.`,
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

async function llmEstimate(input: {
  title: string;
  enteredCost: number;
  weeks: number;
  goalMode: string;
}): Promise<Estimate> {
  const fallback = deterministicEstimate(input.title, input.enteredCost, input.weeks);
  const result = await chatCompletions({
    json: true,
    temperature: 0.3,
    capability: "text",
    messages: [{
      role: "user",
      content:
        `Estimate a realistic present-day USD cost for this family goal.\n` +
        `Goal: "${input.title}"\n` +
        `Type: ${input.goalMode}\n` +
        `Parent's entered number: $${input.enteredCost}\n` +
        `Deadline in ${input.weeks} weeks.\n` +
        `Return ONLY JSON: {"low": number, "likely": number, "high": number, "rationale": string}\n` +
        `Rules: all numbers > 0; low <= likely <= high; USD; rationale is 2-3 sentences in plain parent language (no ML jargon). ` +
        `Use the entered number as a prior, not as the only possible answer.`,
    }],
  });
  if (!result) return fallback;
  const parsed = validEstimate(parseJsonObject(result.text));
  if (!parsed) return fallback;
  return { ...parsed, provider: result.provider };
}

async function searchDeals(query: string, budget: number): Promise<{ deals: Deal[]; dealSearch: "tavily" | "skipped" }> {
  const key = Deno.env.get("TAVILY_API_KEY")?.trim();
  if (!key) return { deals: [], dealSearch: "skipped" };
  try {
    const res = await fetch("https://api.tavily.com/search", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${key}`,
      },
      body: JSON.stringify({
        query,
        max_results: 5,
        search_depth: "basic",
      }),
    });
    if (!res.ok) return { deals: [], dealSearch: "skipped" };
    const data = await res.json();
    const raw = Array.isArray(data?.results) ? data.results : [];
    const mapped: Deal[] = raw.map((r: { title?: string; url?: string; content?: string }) => {
      const snippet = String(r.content ?? "");
      const price = extractUsdPrice(`${r.title ?? ""} ${snippet}`);
      return {
        title: String(r.title ?? "Deal"),
        url: String(r.url ?? ""),
        snippet: snippet.slice(0, 240) || undefined,
        source: "tavily",
        ...(price != null ? { price } : {}),
      };
    }).filter((d: Deal) => d.url);
    return { deals: dealsUnderBudget(mapped, budget), dealSearch: "tavily" };
  } catch {
    return { deals: [], dealSearch: "skipped" };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const body = await req.json();
    const title = String(body.title ?? "").trim() || "Goal";
    const enteredCost = Number(body.targetAmount);
    if (!(enteredCost > 0)) {
      return Response.json({ error: "targetAmount must be positive" }, { status: 400, headers: CORS });
    }
    const weeks = weeksFrom(body.targetDate);
    const goalMode = String(body.goalMode ?? "kid_item");
    const estimate = await llmEstimate({ title, enteredCost, weeks, goalMode });
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
