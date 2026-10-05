// OpenAI-compatible chat/completions helper for Token Factory + OpenAI.
// Selection order (must not require Nebius for Basics):
//   1. NEBIUS_API_KEY → Token Factory + Nemotron
//   2. OPENAI_API_KEY → https://api.openai.com/v1/ + gpt-4o-mini
//   3. no key → caller uses deterministic / abstain
//
// Nebius overrides (all optional): NEBIUS_BASE_URL, NEBIUS_VISION_BASE_URL,
// NEBIUS_TEXT_MODEL, NEBIUS_VISION_MODEL. Defaults below.
// Vision calls use NEBIUS_VISION_BASE_URL, else NEBIUS_BASE_URL, else the default.
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
  visionBaseUrl: string;
  textModel: string;
  visionModel: string;
}

function nonempty(v: string | undefined): string | null {
  const t = v?.trim();
  return t ? t : null;
}

function withTrailingSlash(base: string): string {
  return base.endsWith("/") ? base : `${base}/`;
}

export function resolveLlmProvider(
  env: Record<string, string | undefined> = Deno.env.toObject(),
): ResolvedLlm | null {
  const nebius = nonempty(env.NEBIUS_API_KEY);
  if (nebius) {
    const textBase = withTrailingSlash(nonempty(env.NEBIUS_BASE_URL) ?? NEBIUS_BASE_URL);
    const visionBase = withTrailingSlash(
      nonempty(env.NEBIUS_VISION_BASE_URL) ?? nonempty(env.NEBIUS_BASE_URL) ?? NEBIUS_BASE_URL,
    );
    return {
      provider: "nebius",
      apiKey: nebius,
      baseUrl: textBase,
      visionBaseUrl: visionBase,
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
      visionBaseUrl: OPENAI_BASE_URL,
      textModel: OPENAI_TEXT_MODEL,
      visionModel: OPENAI_TEXT_MODEL,
    };
  }
  return null;
}

const THINK_TAG = "think|thinking|redacted_thinking|reasoning";

/** Strip Nemotron / reasoning traces so JSON parse sees the payload. */
export function stripThink(text: string): string {
  const closed = text.replace(
    new RegExp(`<(${THINK_TAG})\\b[^>]*>[\\s\\S]*?<\\/\\1>`, "gi"),
    "",
  );
  // Some hosts return the reasoning with the opening tag already removed.
  return closed.replace(new RegExp(`^[\\s\\S]*?<\\/(${THINK_TAG})>`, "i"), "").trim();
}

export interface PhotoAssistPayload {
  suggest: "approve" | "reject" | "abstain";
  reason: string;
  provider: LlmProvider | null;
  model: string | null;
}

/** Abstain leaves provider and model null. A vision hit copies both from the call. */
export function photoAssistPayload(input: {
  suggest: PhotoAssistPayload["suggest"];
  reason: string;
  provider?: LlmProvider | null;
  model?: string | null;
}): PhotoAssistPayload {
  return {
    suggest: input.suggest,
    reason: input.reason,
    provider: input.provider ?? null,
    model: input.model ?? null,
  };
}

function tryJsonObject(slice: string): Record<string, unknown> | null {
  const repaired = slice.replace(/,\s*([}\]])/g, "$1");
  for (const candidate of repaired === slice ? [slice] : [slice, repaired]) {
    try {
      const parsed = JSON.parse(candidate);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) {
        return parsed as Record<string, unknown>;
      }
    } catch {
      // Next candidate or the next brace span.
    }
  }
  return null;
}

function balancedObjectAt(body: string, start: number): string | null {
  let depth = 0;
  let inString = false;
  let escape = false;
  for (let i = start; i < body.length; i++) {
    const ch = body[i];
    if (inString) {
      if (escape) escape = false;
      else if (ch === "\\") escape = true;
      else if (ch === "\"") inString = false;
      continue;
    }
    if (ch === "\"") {
      inString = true;
      continue;
    }
    if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) return body.slice(start, i + 1);
    }
  }
  return null;
}

function objectFromBody(body: string): Record<string, unknown> | null {
  const directStart = body.indexOf("{");
  const directEnd = body.lastIndexOf("}");
  if (directStart >= 0 && directEnd > directStart) {
    const direct = tryJsonObject(body.slice(directStart, directEnd + 1));
    if (direct) return direct;
  }
  let last: Record<string, unknown> | null = null;
  for (let i = 0; i < body.length; i++) {
    if (body[i] !== "{") continue;
    const slice = balancedObjectAt(body, i);
    if (!slice) continue;
    const obj = tryJsonObject(slice);
    if (!obj) continue;
    last = obj;
    i += slice.length - 1;
  }
  return last;
}

export function parseJsonObject(text: string): Record<string, unknown> | null {
  const trimmed = stripThink(text);
  const fence = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i);
  if (fence?.[1]) {
    const fromFence = objectFromBody(fence[1]);
    if (fromFence) return fromFence;
  }
  return objectFromBody(trimmed);
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

export interface ChatSuccess {
  text: string;
  provider: LlmProvider;
  model: string;
  baseHost: string;
}

/** Upstream failure. message is already clipped and key-redacted. */
export interface ChatFailure {
  error: {
    provider: LlmProvider;
    model: string;
    base_host: string;
    status: number | null;
    message: string;
    available_models?: string[];
  };
}

/** null means no key. Callers must not treat ChatFailure as "not configured". */
export type ChatCompletionResult = ChatSuccess | ChatFailure | null;

export type LlmOutputRejectReason = "unparseable_output" | "invalid_plan" | "invalid_estimate";

export type PublicLlmError =
  | { reason: "no_key" }
  | {
    provider: LlmProvider;
    model: string;
    base_host: string;
    status: number | null;
    message: string;
    available_models?: string[];
  }
  | {
    provider: LlmProvider;
    model: string;
    base_host: string;
    status: 200;
    reason: LlmOutputRejectReason;
    sample: string;
  };

const LLM_ERROR_LIMIT = 300;
const SAMPLE_LIMIT = 400;
const AVAILABLE_MODELS_LIMIT = 25;
const MODEL_ID_PREFER = /omni|vl|vision|nemotron/i;

function baseHost(baseUrl: string): string {
  try {
    return new URL(baseUrl).hostname;
  } catch {
    return "unknown";
  }
}

function isModelNotFound(status: number, body: string): boolean {
  if (status !== 404) return false;
  return /model/i.test(body) &&
    /model[_\s-]?not[_\s-]?found|does not exist|do not exist|unknown model|no such model/i.test(body);
}

function modelIdsFromList(data: unknown): string[] | undefined {
  const raw = Array.isArray(data)
    ? data
    : (data && typeof data === "object"
      ? ((data as { data?: unknown }).data ?? (data as { models?: unknown }).models)
      : undefined);
  if (!Array.isArray(raw)) return undefined;
  const ids: string[] = [];
  for (const item of raw) {
    if (typeof item === "string") ids.push(item);
    else if (item && typeof item === "object" && typeof (item as { id?: unknown }).id === "string") {
      ids.push((item as { id: string }).id);
    }
  }
  return ids;
}

/** Up to 25 ids. Matches of /omni|vl|vision|nemotron/i stay in front. Ids are not secrets. */
function pickAvailableModels(ids: string[], apiKey: string): string[] {
  const seen = new Set<string>();
  const unique: string[] = [];
  for (const id of ids) {
    const cleaned = (apiKey ? id.split(apiKey).join("[redacted]") : id).trim();
    if (!cleaned || seen.has(cleaned)) continue;
    seen.add(cleaned);
    unique.push(cleaned);
  }
  const preferred = unique.filter((id) => MODEL_ID_PREFER.test(id));
  const rest = unique.filter((id) => !MODEL_ID_PREFER.test(id));
  return [...preferred, ...rest].slice(0, AVAILABLE_MODELS_LIMIT);
}

async function listAvailableModels(baseUrl: string, apiKey: string): Promise<string[] | undefined> {
  try {
    const res = await fetch(new URL("models", baseUrl), {
      method: "GET",
      headers: { Authorization: `Bearer ${apiKey}` },
    });
    if (!res.ok) return undefined;
    const data = await res.json();
    const ids = modelIdsFromList(data);
    if (!ids) return undefined;
    return pickAvailableModels(ids, apiKey);
  } catch {
    return undefined;
  }
}

function redactAndClip(raw: string, apiKey: string): string {
  const redacted = apiKey ? raw.split(apiKey).join("[redacted]") : raw;
  const flat = redacted.replace(/[\r\n]+/g, " ").trim();
  return flat.length <= LLM_ERROR_LIMIT ? flat : flat.slice(0, LLM_ERROR_LIMIT);
}

export function chatOk(result: ChatCompletionResult): result is ChatSuccess {
  return !!result && "text" in result;
}

/** Success → null. No key → {reason:'no_key'}. HTTP/exception failure → public fields. */
export function llmErrorForFallback(result: ChatCompletionResult): PublicLlmError | null {
  if (result == null) return { reason: "no_key" };
  if (!chatOk(result)) {
    return {
      provider: result.error.provider,
      model: result.error.model,
      base_host: result.error.base_host,
      status: result.error.status,
      message: result.error.message.slice(0, LLM_ERROR_LIMIT),
      ...(result.error.available_models ? { available_models: result.error.available_models } : {}),
    };
  }
  return null;
}

/** HTTP 200 whose text we will not use. sample is stripped model text, clipped. */
export function llmErrorForRejectedOutput(input: {
  provider: LlmProvider;
  model: string;
  baseHost: string;
  text: string;
  reason: LlmOutputRejectReason;
}): PublicLlmError {
  const sample = stripThink(input.text).slice(0, SAMPLE_LIMIT);
  const err: PublicLlmError = {
    provider: input.provider,
    model: input.model,
    base_host: input.baseHost,
    status: 200,
    reason: input.reason,
    sample,
  };
  console.error(
    `llm rejected output provider=${input.provider} model=${input.model} base_host=${input.baseHost} status=200 reason=${input.reason} sample=${sample.replace(/[\r\n]+/g, " ")}`,
  );
  return err;
}

export function preferLlmError(
  a: PublicLlmError | null,
  b: PublicLlmError | null,
): PublicLlmError | null {
  if (a && !("reason" in a)) return a;
  if (b && !("reason" in b)) return b;
  return a ?? b;
}

export async function chatCompletions(opts: {
  messages: ChatMessage[];
  temperature?: number;
  json?: boolean;
  capability?: "text" | "vision";
  env?: Record<string, string | undefined>;
}): Promise<ChatCompletionResult> {
  const resolved = resolveLlmProvider(opts.env ?? Deno.env.toObject());
  if (!resolved) return null;

  const model = opts.capability === "vision" ? resolved.visionModel : resolved.textModel;
  const baseUrl = opts.capability === "vision" ? resolved.visionBaseUrl : resolved.baseUrl;
  const body: Record<string, unknown> = {
    model,
    messages: opts.messages,
    temperature: opts.temperature ?? 0.3,
    max_tokens: 2048,
  };
  // Token Factory / Nemotron may ignore response_format; OpenAI uses it.
  if (opts.json && resolved.provider === "openai") {
    body.response_format = { type: "json_object" };
  }
  // Nano defaults to enable_thinking; think-blocks break JSON parse.
  if (resolved.provider === "nebius") {
    body.chat_template_kwargs = { enable_thinking: false };
  }

  const host = baseHost(baseUrl);
  const fail = (
    status: number | null,
    raw: string,
    kind: "body" | "error",
    available?: string[],
  ): ChatFailure => {
    const message = redactAndClip(raw || "upstream error", resolved.apiKey);
    const detail = kind === "body" ? `status=${status ?? "null"} body=${message}` : `error=${message}`;
    const listed = available && available.length > 0 ? ` available_models=${available.join(",")}` : "";
    console.error(
      `llm chatCompletions provider=${resolved.provider} model=${model} host=${host} ${detail}${listed}`,
    );
    return {
      error: {
        provider: resolved.provider,
        model,
        base_host: host,
        status,
        message,
        ...(available ? { available_models: available } : {}),
      },
    };
  };

  try {
    const res = await fetch(new URL("chat/completions", baseUrl), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${resolved.apiKey}`,
      },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      let raw = "";
      try {
        raw = await res.text();
      } catch {
        raw = "";
      }
      let available: string[] | undefined;
      if (isModelNotFound(res.status, raw)) {
        available = await listAvailableModels(baseUrl, resolved.apiKey);
      }
      return fail(res.status, raw || res.statusText || "upstream error", "body", available);
    }
    const data = await res.json();
    const text = messageText(data?.choices?.[0]?.message?.content);
    if (!text) return fail(res.status, "empty completion", "body");
    const safe = resolved.apiKey ? text.split(resolved.apiKey).join("[redacted]") : text;
    return { text: safe, provider: resolved.provider, model, baseHost: host };
  } catch (e) {
    const raw = e instanceof Error ? e.message : String(e);
    return fail(null, raw, "error");
  }
}
