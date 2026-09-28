import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  NEBIUS_BASE_URL,
  NEBIUS_TEXT_MODEL,
  OPENAI_BASE_URL,
  parseJsonObject,
  resolveLlmProvider,
} from "./llm.ts";

Deno.test("prefers NEBIUS_API_KEY over OPENAI_API_KEY", () => {
  const resolved = resolveLlmProvider({
    NEBIUS_API_KEY: "neb-key",
    OPENAI_API_KEY: "oai-key",
  });
  assertEquals(resolved?.provider, "nebius");
  assertEquals(resolved?.apiKey, "neb-key");
  assertEquals(resolved?.baseUrl, NEBIUS_BASE_URL);
  assertEquals(resolved?.textModel, NEBIUS_TEXT_MODEL);
});

Deno.test("falls back to OpenAI when Nebius is unset", () => {
  const resolved = resolveLlmProvider({ OPENAI_API_KEY: "oai-key" });
  assertEquals(resolved?.provider, "openai");
  assertEquals(resolved?.baseUrl, OPENAI_BASE_URL);
  assertEquals(resolved?.textModel, "gpt-4o-mini");
});

Deno.test("returns null when no keys are set (Basics path)", () => {
  assertEquals(resolveLlmProvider({}), null);
  assertEquals(resolveLlmProvider({ NEBIUS_API_KEY: "", OPENAI_API_KEY: "  " }), null);
});

Deno.test("honors NEBIUS_VISION_MODEL override for account-specific ids", () => {
  const resolved = resolveLlmProvider({
    NEBIUS_API_KEY: "neb-key",
    NEBIUS_VISION_MODEL: "nvidia/custom-vision",
  });
  assertEquals(resolved?.visionModel, "nvidia/custom-vision");
});

Deno.test("parseJsonObject strips fences and leftover prose", () => {
  const parsed = parseJsonObject('Sure.\n```json\n{"low": 1, "likely": 2}\n```\n');
  assertEquals(parsed, { low: 1, likely: 2 });
});
