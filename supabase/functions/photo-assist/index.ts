// Photo Assist edge function. Suggests approve/reject for visually
// verifiable chores only. No key: abstain, "not configured". A failed
// vision call: abstain, "check failed", plus llm_error. The parent is
// always final: this is a suggestion on the approval card, never an action.
//
// Provider order (Basics must run with zero keys):
//   1. NEBIUS_API_KEY → Token Factory vision model (see _shared/llm.ts)
//   2. OPENAI_API_KEY → gpt-4o-mini
//   3. else abstain

import "https://deno.land/std@0.224.0/http/server.ts";
import { CORS } from "../_shared/cors.ts";
import {
  chatCompletions,
  chatOk,
  llmErrorForFallback,
  parseJsonObject,
  photoAssistPayload,
  type PhotoAssistPayload,
  type PublicLlmError,
} from "../_shared/llm.ts";
import { photoAssistSystemMessage } from "../_shared/prompt_guard.ts";

const NOT_CONFIGURED = "Photo check is not configured. Your call, parent.";
const CHECK_FAILED = "Photo check failed. Your call, parent.";

function abstain(reason: string): PhotoAssistPayload {
  return photoAssistPayload({ suggest: "abstain", reason });
}

function isVisuallyVerifiable(choreTitle: string): boolean {
  const t = choreTitle.toLowerCase();
  const trustBased = ["read", "practice", "homework", "brush", "pray", "write", "study"];
  if (trustBased.some((w) => t.includes(w))) return false;
  const visualCues = ["clean", "tidy", "wash", "dishes", "fold", "vacuum", "made", "set", "take out", "empty"];
  return visualCues.some((w) => t.includes(w));
}

async function assistWithVision(
  choreTitle: string,
  imageBase64: string,
): Promise<{ payload: PhotoAssistPayload; llmError: PublicLlmError | null }> {
  const result = await chatCompletions({
    json: true,
    temperature: 0.2,
    capability: "vision",
    messages: [
      { role: "system", content: photoAssistSystemMessage() },
      {
        role: "user",
        content: [
          {
            type: "text",
            text:
              `A kid claims they finished the chore: "${choreTitle}". ` +
              "Look at the photo. Reply ONLY JSON: {\"suggest\": \"approve\"|\"reject\", \"reason\": string}. " +
              "The reason is one kind sentence for the parent. You are not certain — if the photo is unclear, suggest reject gently.",
          },
          { type: "image_url", image_url: { url: `data:image/jpeg;base64,${imageBase64}` } },
        ],
      },
    ],
  });
  if (!chatOk(result)) {
    return {
      payload: abstain(result == null ? NOT_CONFIGURED : CHECK_FAILED),
      llmError: llmErrorForFallback(result),
    };
  }
  const parsed = parseJsonObject(result.text);
  const suggest = parsed?.suggest === "approve" || parsed?.suggest === "reject"
    ? parsed.suggest
    : null;
  if (!suggest) {
    return {
      payload: abstain(CHECK_FAILED),
      llmError: {
        provider: result.provider,
        model: result.model,
        base_host: result.baseHost,
        status: null,
        message: "Photo check response was not usable.",
      },
    };
  }
  return {
    payload: photoAssistPayload({
      suggest,
      reason: String(parsed?.reason ?? "Have a look and decide."),
      provider: result.provider,
      model: result.model,
    }),
    llmError: null,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const { choreTitle, image } = await req.json();
    if (!isVisuallyVerifiable(String(choreTitle))) {
      return Response.json(
        abstain("This chore is not visually checkable — decide based on trust."),
        { headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }
    if (!image) {
      return Response.json(
        abstain("No photo was attached, so there is nothing to check."),
        { headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }
    const assisted = await assistWithVision(String(choreTitle), String(image));
    return Response.json(
      assisted.llmError ? { ...assisted.payload, llm_error: assisted.llmError } : assisted.payload,
      { headers: { ...CORS, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 400, headers: CORS });
  }
});
