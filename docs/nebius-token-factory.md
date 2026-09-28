# Nebius Token Factory (optional)

This branch adds a **Nebius × NVIDIA** eligibility path for Best Apps / Agents. It is **not required** for [Build With AI: Basics](https://learn-ai-basics.devpost.com/). The demo, deterministic Suggest Plan, and Photo Assist abstain all run with **zero API keys**.

Do not put keys in git. Set them as Supabase function secrets (hosted) or `supabase secrets set` for local.

## Provider order

Every LLM call (`suggest-plan`, `photo-assist`, `goal-cost-orchestrate`) uses the same helper (`supabase/functions/_shared/llm.ts`):

1. If `NEBIUS_API_KEY` is set → [Token Factory](https://api.tokenfactory.nebius.com/v1/) + Nemotron
2. Else if `OPENAI_API_KEY` is set → existing OpenAI `gpt-4o-mini` path
3. Else → deterministic plan / photo-assist abstain / deterministic cost bands

## Secrets

| Secret | Required? | Used by |
|---|---|---|
| `NEBIUS_API_KEY` | No | Token Factory chat/completions |
| `OPENAI_API_KEY` | No | Fallback LLM / vision |
| `TAVILY_API_KEY` | No | Deal search after Accept. If unset, cost estimate still returns; `deal_search` is `skipped`. |
| `NEBIUS_TEXT_MODEL` | No | Override text model id |
| `NEBIUS_VISION_MODEL` | No | Override vision model id |

```bash
supabase secrets set NEBIUS_API_KEY=...
# optional
supabase secrets set OPENAI_API_KEY=...
supabase secrets set TAVILY_API_KEY=...
```

## Models

Text (default, listed on the [public Token Factory catalog](https://tokenfactory.nebius.com/model-catalog.md) as of 2026-09):

- `nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B`
- Super (not the default): `nvidia/nemotron-3-super-120b-a12b`

Vision: the public catalog lists Nano as **text2text**. Account / third-party listings use `nvidia/Nemotron-3-Nano-Omni`. That string is the default constant in `_shared/llm.ts`. If your project shows a different id, set `NEBIUS_VISION_MODEL` (or edit the constant). Photo Assist still abstains when no key is set or the vision call fails.

## New parent flow

After **Accept plan**, a sheet calls `POST /functions/v1/goal-cost-orchestrate`:

- Always returns `estimate.{low,likely,high}` + a weekly save suggestion
- Optionally returns `deals[]` under the likely budget when Tavily is configured
- Parent can lock `goals.target_amount` + `ai_plans.suggestion.weekly_parent_save` and store `deal_snapshot` / `cost_estimate` JSON

Kid chore progress stays **percent-based** (rev 3). This path does not write chore rewards.

The Basics demo walkthrough (`DEMO_WALK=true`) skips the cost sheet and uses the local Suggest Plan builder so the existing video script still applies.

Photo Assist is invoked from the parent Approvals card when a photo path exists. The parent is still the final approve/reject. Without a key (or if vision fails) the card abstains.
