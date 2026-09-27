// Photo Assist edge function — suggests approve/reject for visually
// verifiable chores only. Without OPENAI_API_KEY it abstains with a clear
// reason. The parent is always final: this is a suggestion on the approval
// card, never an action.

import "https://deno.land/std@0.224.0/http/server.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface AssistResult {
  suggest: "approve" | "reject" | "abstain";
  reason: string;
}

function abstain(reason: string): AssistResult {
  return { suggest: "abstain", reason };
}

function isVisuallyVerifiable(choreTitle: string): boolean {
  const t = choreTitle.toLowerCase();
  // Explicit trust-based verbs never make sense with photo proof.
  const trustBased = ["read", "practice", "homework", "brush", "pray", "write", "study"];
  if (trustBased.some((w) => t.includes(w))) return false;
  // Otherwise accept an explicit "done state" cue a photo could show.
  const visualCues = ["clean", "tidy", "wash", "dishes", "fold", "vacuum", "made", "set", "take out", "empty"];
  return visualCues.some((w) => t.includes(w));
}

async function assistWithVision(choreTitle: string, imageBase64: string): Promise<AssistResult | null> {
  const key = Deno.env.get("OPENAI_API_KEY");
  if (!key) return null;
  try {
    const res = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key}` },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
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
        response_format: { type: "json_object" },
        temperature: 0.2,
      }),
    });
    if (!res.ok) return null;
    const data = await res.json();
    const parsed = JSON.parse(data.choices[0].message.content) as AssistResult;
    if (parsed?.suggest !== "approve" && parsed?.suggest !== "reject") return null;
    return parsed;
  } catch {
    return null;
  }
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
