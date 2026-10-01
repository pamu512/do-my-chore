// Photo Assist edge function — suggests approve/reject for visually
// verifiable chores only. Without an LLM key it abstains with a clear
// reason. The parent is always final: this is a suggestion on the approval
// card, never an action.
//
// Provider order (Basics must run with zero keys):
//   1. NEBIUS_API_KEY → Token Factory vision model (see _shared/llm.ts)
//   2. OPENAI_API_KEY → gpt-4o-mini
//   3. else abstain

import "https://deno.land/std@0.224.0/http/server.ts";
import { CORS } from "../_shared/cors.ts";
import { chatCompletions, parseJsonObject } from "../_shared/llm.ts";
import { photoAssistSystemMessage } from "../_shared/prompt_guard.ts";

interface AssistResult {
  suggest: "approve" | "reject" | "abstain";
  reason: string;
}

function abstain(reason: string): AssistResult {
  return { suggest: "abstain", reason };
}

function isVisuallyVerifiable(choreTitle: string): boolean {
  const t = choreTitle.toLowerCase();
  const trustBased = ["read", "practice", "homework", "brush", "pray", "write", "study"];
  if (trustBased.some((w) => t.includes(w))) return false;
  const visualCues = ["clean", "tidy", "wash", "dishes", "fold", "vacuum", "made", "set", "take out", "empty"];
  return visualCues.some((w) => t.includes(w));
}

async function assistWithVision(choreTitle: string, imageBase64: string): Promise<AssistResult | null> {
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
  if (!result) return null;
  const parsed = parseJsonObject(result.text);
  const suggest = parsed?.suggest;
  if (suggest !== "approve" && suggest !== "reject") return null;
  return { suggest, reason: String(parsed?.reason ?? "Have a look and decide.") };
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
      assisted ?? abstain("Photo check is not configured — your call, parent."),
      { headers: { ...CORS, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 400, headers: CORS });
  }
});
