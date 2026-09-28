// OpenAI-compatible chat/completions helper for Token Factory + OpenAI.
// Selection order (must not require Nebius for Basics):
//   1. NEBIUS_API_KEY → https://api.tokenfactory.nebius.com/v1/ + Nemotron
//   2. OPENAI_API_KEY → https://api.openai.com/v1/ + gpt-4o-mini
//   3. no key → caller uses deterministic / abstain
//
// Text model (public Token Factory catalog, 2026-09):
//   nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B
// Super (optional, not the default): nvidia/nemotron-3-super-120b-a12b
//
// Vision: the public catalog lists Nano as text2text. Account listings and
// third-party catalogs use nvidia/Nemotron-3-Nano-Omni. Override with
// NEBIUS_VISION_MODEL if your project shows a different id.

export const NEBIUS_BASE_URL = "https://api.tokenfactory.nebius.com/v1/";
export const OPENAI_BASE_URL = "https://api.openai.com/v1/";

export const NEBIUS_TEXT_MODEL = "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B";
export const NEBIUS_VISION_MODEL = "nvidia/Nemotron-3-Nano-Omni";
export const OPENAI_TEXT_MODEL = "gpt-4o-mini";

export type LlmProvider = "nebius" | "openai";

export type ChatContent =
  | string
  | Array<Record<string, unknown>>;

export interface ChatMessage {
  role: "system" | "user" | "assistant";
  content: ChatContent;
}

export interface ResolvedLlm {
  provider: LlmProvider;
  apiKey: string;
  baseUrl: string;
  textModel: string;
  visionModel: string;
}

function nonempty(v: string | undefined): string | null {
  const t = v?.trim();
  return t ? t : null;
}

export function resolveLlmProvider(
  env: Record<string, string | undefined> = Deno.env.toObject(),
): ResolvedLlm | null {
  const nebius = nonempty(env.NEBIUS_API_KEY);
  if (nebius) {
    return {
      provider: "nebius",
      apiKey: nebius,
      baseUrl: NEBIUS_BASE_URL,
      textModel: nonempty(env.NEBIUS_TEXT_MODEL) ?? NEBIUS_TEXT_MODEL,
      visionModel: nonempty(env.NEBIUS_VISION_MODEL) ?? NEBIUS_VISION_MODEL,
    };
  }
  const openai = nonempty(env.OPENAI_API_KEY);
  if (openai) {
    return {
      provider: "openai",
      apiKey: openai,
      baseUrl: OPENAI_BASE_URL,
      textModel: OPENAI_TEXT_MODEL,
      visionModel: OPENAI_TEXT_MODEL,
    };
  }
  return null;
}

export function parseJsonObject(text: string): Record<string, unknown> | null {
  const trimmed = text.trim();
  const fence = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/);
  const body = fence?.[1] ?? trimmed;
  const start = body.indexOf("{");
  const end = body.lastIndexOf("}");
  if (start < 0 || end <= start) return null;
  try {
    const parsed = JSON.parse(body.slice(start, end + 1));
    if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
      return parsed as Record<string, unknown>;
    }
    return null;
  } catch {
    return null;
  }
}

function messageText(content: unknown): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((p) => (typeof p === "string" ? p : String((p as { text?: string })?.text ?? "")))
      .join("");
  }
  return "";
}

export async function chatCompletions(opts: {
  messages: ChatMessage[];
  temperature?: number;
  json?: boolean;
  capability?: "text" | "vision";
  env?: Record<string, string | undefined>;
}): Promise<{ text: string; provider: LlmProvider; model: string } | null> {
  const resolved = resolveLlmProvider(opts.env ?? Deno.env.toObject());
  if (!resolved) return null;

  const model = opts.capability === "vision" ? resolved.visionModel : resolved.textModel;
  const body: Record<string, unknown> = {
    model,
    messages: opts.messages,
    temperature: opts.temperature ?? 0.3,
  };
  // Token Factory / Nemotron may ignore response_format; OpenAI uses it.
  if (opts.json && resolved.provider === "openai") {
    body.response_format = { type: "json_object" };
  }

  try {
    const res = await fetch(new URL("chat/completions", resolved.baseUrl), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${resolved.apiKey}`,
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) return null;
    const data = await res.json();
    const text = messageText(data?.choices?.[0]?.message?.content);
    if (!text) return null;
    return { text, provider: resolved.provider, model };
  } catch {
    return null;
  }
}
