import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  chatCompletions,
  llmErrorForFallback,
  llmErrorForRejectedOutput,
  NEBIUS_BASE_URL,
  NEBIUS_TEXT_MODEL,
  NEBIUS_VISION_MODEL,
  OPENAI_BASE_URL,
  parseJsonObject,
  photoAssistPayload,
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

Deno.test("default vision model is Nemotron Nano Omni", () => {
  const resolved = resolveLlmProvider({ NEBIUS_API_KEY: "neb-key" });
  assertEquals(resolved?.visionModel, NEBIUS_VISION_MODEL);
  assertEquals(resolved?.textModel, NEBIUS_TEXT_MODEL);
});

Deno.test("honors NEBIUS_VISION_MODEL override for account-specific ids", () => {
  const resolved = resolveLlmProvider({
    NEBIUS_API_KEY: "neb-key",
    NEBIUS_VISION_MODEL: "nvidia/custom-vision",
  });
  assertEquals(resolved?.visionModel, "nvidia/custom-vision");
});

Deno.test("honors NEBIUS_BASE_URL and NEBIUS_TEXT_MODEL overrides", () => {
  const resolved = resolveLlmProvider({
    NEBIUS_API_KEY: "neb-key",
    NEBIUS_BASE_URL: "https://llm.example.test/v1",
    NEBIUS_TEXT_MODEL: "text-override",
  });
  assertEquals(resolved?.baseUrl, "https://llm.example.test/v1/");
  assertEquals(resolved?.textModel, "text-override");
  assertEquals(resolved?.visionModel, NEBIUS_VISION_MODEL);
});

Deno.test("photo assist payload names provider and model, null on abstain", () => {
  assertEquals(photoAssistPayload({
    suggest: "abstain",
    reason: "Photo check is not configured.",
  }), {
    suggest: "abstain",
    reason: "Photo check is not configured.",
    provider: null,
    model: null,
  });
  const live = photoAssistPayload({
    suggest: "approve",
    reason: "The dishes look washed.",
    provider: "nebius",
    model: NEBIUS_VISION_MODEL,
  });
  assertEquals(live.provider, "nebius");
  assertEquals(live.model, NEBIUS_VISION_MODEL);
  assertEquals(live.suggest, "approve");
});

Deno.test("parseJsonObject strips fences and leftover prose", () => {
  const parsed = parseJsonObject('Sure.\n```json\n{"low": 1, "likely": 2}\n```\n');
  assertEquals(parsed, { low: 1, likely: 2 });
});

Deno.test("parseJsonObject ignores Nemotron think blocks", () => {
  const parsed = parseJsonObject(
    '<think>braces { like this } are noise</think>\n{"low": 10, "likely": 20}',
  );
  assertEquals(parsed, { low: 10, likely: 20 });
});

function captureFetch(
  handler: (input: RequestInfo | URL, init?: RequestInit) => Promise<Response> | Response,
): { logs: string[]; restore: () => void } {
  const logs: string[] = [];
  const origErr = console.error;
  const origFetch = globalThis.fetch;
  console.error = (...args: unknown[]) => {
    logs.push(args.map((a) => String(a)).join(" "));
  };
  globalThis.fetch = handler as typeof fetch;
  return {
    logs,
    restore() {
      console.error = origErr;
      globalThis.fetch = origFetch;
    },
  };
}

Deno.test("chatCompletions records a 401 without logging the key", async () => {
  const key = "neb-secret-key-401";
  let auth = "";
  const cap = captureFetch((_input, init) => {
    auth = new Headers(init?.headers).get("Authorization") ?? "";
    return new Response(`denied ${key}\nmore`, { status: 401 });
  });
  try {
    const result = await chatCompletions({
      env: { NEBIUS_API_KEY: key },
      messages: [{ role: "user", content: "hi" }],
    });
    assertEquals(result, {
      error: {
        provider: "nebius",
        model: NEBIUS_TEXT_MODEL,
        base_host: "api.tokenfactory.nebius.com",
        status: 401,
        message: "denied [redacted] more",
      },
    });
    assertEquals(llmErrorForFallback(result), {
      provider: "nebius",
      model: NEBIUS_TEXT_MODEL,
      base_host: "api.tokenfactory.nebius.com",
      status: 401,
      message: "denied [redacted] more",
    });
    assertEquals(auth, `Bearer ${key}`);
    const line = cap.logs.join("\n");
    assertEquals(line.includes(key), false);
    assertEquals(line.includes("Authorization"), false);
    assertEquals(line.includes("Bearer"), false);
    assertEquals(line.includes("provider=nebius"), true);
    assertEquals(line.includes(`model=${NEBIUS_TEXT_MODEL}`), true);
    assertEquals(line.includes("host=api.tokenfactory.nebius.com"), true);
    assertEquals(line.includes("status=401"), true);
    assertEquals(line.includes("denied [redacted] more"), true);
  } finally {
    cap.restore();
  }
});

Deno.test("chatCompletions records a 404, clips the body, and uses NEBIUS_BASE_URL", async () => {
  const key = "neb-secret-key-404";
  const body = `missing-model ${"x".repeat(400)}`;
  let seen = "";
  const cap = captureFetch((input) => {
    seen = typeof input === "string" ? input : input instanceof URL ? input.href : input.url;
    return new Response(body, { status: 404 });
  });
  try {
    const result = await chatCompletions({
      env: {
        NEBIUS_API_KEY: key,
        NEBIUS_BASE_URL: "https://llm.example.test/v1",
        NEBIUS_VISION_MODEL: "vision-override",
      },
      capability: "vision",
      messages: [{ role: "user", content: "hi" }],
    });
    if (!result || !("error" in result)) throw new Error("expected chat failure");
    assertEquals(result.error.status, 404);
    assertEquals(result.error.provider, "nebius");
    assertEquals(result.error.base_host, "llm.example.test");
    assertEquals(result.error.model, "vision-override");
    assertEquals("available_models" in result.error, false);
    assertEquals(result.error.message.length, 300);
    assertEquals(result.error.message.startsWith("missing-model "), true);
    assertEquals(result.error.message.includes(key), false);
    assertEquals(seen, "https://llm.example.test/v1/chat/completions");
    const line = cap.logs.join("\n");
    assertEquals(line.includes(key), false);
    assertEquals(line.includes("Authorization"), false);
    assertEquals(line.includes("host=llm.example.test"), true);
    assertEquals(line.includes("status=404"), true);
    assertEquals(line.includes("model=vision-override"), true);
    assertEquals(line.includes(result.error.message), true);
  } finally {
    cap.restore();
  }
});

Deno.test("chatCompletions records a thrown fetch error without the key", async () => {
  const key = "neb-secret-key-throw";
  const cap = captureFetch(() => {
    throw new Error(`socket down ${key}`);
  });
  try {
    const result = await chatCompletions({
      env: { NEBIUS_API_KEY: key, NEBIUS_TEXT_MODEL: "text-override" },
      messages: [{ role: "user", content: "hi" }],
    });
    assertEquals(result, {
      error: {
        provider: "nebius",
        model: "text-override",
        base_host: "api.tokenfactory.nebius.com",
        status: null,
        message: "socket down [redacted]",
      },
    });
    const line = cap.logs.join("\n");
    assertEquals(line.includes(key), false);
    assertEquals(line.includes("socket down [redacted]"), true);
    assertEquals(line.includes("host=api.tokenfactory.nebius.com"), true);
  } finally {
    cap.restore();
  }
});

Deno.test("chatCompletions returns null when no key is set and does not fetch", async () => {
  let called = false;
  const cap = captureFetch(() => {
    called = true;
    return new Response("nope", { status: 500 });
  });
  try {
    const result = await chatCompletions({
      env: {},
      messages: [{ role: "user", content: "hi" }],
    });
    assertEquals(result, null);
    assertEquals(llmErrorForFallback(result), { reason: "no_key" });
    assertEquals(called, false);
    assertEquals(cap.logs.length, 0);
  } finally {
    cap.restore();
  }
});

function requestUrl(input: RequestInfo | URL): string {
  if (typeof input === "string") return input;
  if (input instanceof URL) return input.href;
  return input.url;
}

Deno.test("vision base URL falls back to NEBIUS_BASE_URL then the default", async () => {
  const explicit = resolveLlmProvider({
    NEBIUS_API_KEY: "neb-key",
    NEBIUS_BASE_URL: "https://text.example.test/v1",
    NEBIUS_VISION_BASE_URL: "https://vision.example.test/v1",
  });
  assertEquals(explicit?.baseUrl, "https://text.example.test/v1/");
  assertEquals(explicit?.visionBaseUrl, "https://vision.example.test/v1/");

  const fromText = resolveLlmProvider({
    NEBIUS_API_KEY: "neb-key",
    NEBIUS_BASE_URL: "https://llm.example.test/v1/",
  });
  assertEquals(fromText?.baseUrl, "https://llm.example.test/v1/");
  assertEquals(fromText?.visionBaseUrl, "https://llm.example.test/v1/");

  const fallback = resolveLlmProvider({ NEBIUS_API_KEY: "neb-key" });
  assertEquals(fallback?.baseUrl, NEBIUS_BASE_URL);
  assertEquals(fallback?.visionBaseUrl, NEBIUS_BASE_URL);

  const openai = resolveLlmProvider({ OPENAI_API_KEY: "oai-key" });
  assertEquals(openai?.visionBaseUrl, OPENAI_BASE_URL);

  const urls: string[] = [];
  const cap = captureFetch((input, init) => {
    urls.push(`${init?.method ?? "GET"} ${requestUrl(input)}`);
    return new Response(
      JSON.stringify({ choices: [{ message: { content: "ok" } }] }),
      { status: 200 },
    );
  });
  try {
    const envBoth = {
      NEBIUS_API_KEY: "neb-key",
      NEBIUS_BASE_URL: "https://text.example.test/v1",
      NEBIUS_VISION_BASE_URL: "https://vision.example.test/v1/",
    };
    await chatCompletions({
      env: envBoth,
      capability: "vision",
      messages: [{ role: "user", content: "hi" }],
    });
    await chatCompletions({
      env: envBoth,
      capability: "text",
      messages: [{ role: "user", content: "hi" }],
    });
    await chatCompletions({
      env: { NEBIUS_API_KEY: "neb-key", NEBIUS_BASE_URL: "https://llm.example.test/v1" },
      capability: "vision",
      messages: [{ role: "user", content: "hi" }],
    });
    await chatCompletions({
      env: { NEBIUS_API_KEY: "neb-key" },
      capability: "vision",
      messages: [{ role: "user", content: "hi" }],
    });
  } finally {
    cap.restore();
  }
  assertEquals(urls, [
    "POST https://vision.example.test/v1/chat/completions",
    "POST https://text.example.test/v1/chat/completions",
    "POST https://llm.example.test/v1/chat/completions",
    "POST https://api.tokenfactory.nebius.com/v1/chat/completions",
  ]);
});

Deno.test("404 model-not-found adds available_models and never returns the key", async () => {
  const key = "neb-secret-key-models";
  const ids = [
    "other/a",
    "nvidia/nemotron-3-nano-omni",
    "other/b",
    "acme/vision-small",
    "other/c",
    "foo/vl-8b",
    key,
    ...Array.from({ length: 28 }, (_, i) => `other/extra-${i}`),
  ];
  const urls: string[] = [];
  const methods: string[] = [];
  const auths: string[] = [];
  const cap = captureFetch((input, init) => {
    const url = requestUrl(input);
    urls.push(url);
    methods.push(init?.method ?? "GET");
    auths.push(new Headers(init?.headers).get("Authorization") ?? "");
    if (url.endsWith("/models")) {
      return new Response(JSON.stringify({ data: ids.map((id) => ({ id })) }), { status: 200 });
    }
    return new Response(
      JSON.stringify({ detail: `The model nvidia/missing does not exist. ${key}` }),
      { status: 404 },
    );
  });
  try {
    const result = await chatCompletions({
      env: {
        NEBIUS_API_KEY: key,
        NEBIUS_VISION_BASE_URL: "https://vision.example.test/v1",
        NEBIUS_VISION_MODEL: "nvidia/missing",
      },
      capability: "vision",
      messages: [{ role: "user", content: "hi" }],
    });
    if (!result || !("error" in result)) throw new Error("expected chat failure");
    const listed = result.error.available_models ?? [];
    assertEquals(result.error.base_host, "vision.example.test");
    assertEquals(result.error.status, 404);
    assertEquals(listed.length, 25);
    assertEquals(listed.slice(0, 3), [
      "nvidia/nemotron-3-nano-omni",
      "acme/vision-small",
      "foo/vl-8b",
    ]);
    assertEquals(listed[3], "other/a");
    assertEquals(listed.includes("[redacted]"), true);
    assertEquals(listed.includes("other/extra-18"), false);
    assertEquals(JSON.stringify(result).includes(key), false);
    const pub = llmErrorForFallback(result);
    if (!pub || !("available_models" in pub) || !pub.available_models) {
      throw new Error("expected available_models");
    }
    assertEquals(pub.available_models.length, 25);
    assertEquals(methods, ["POST", "GET"]);
    assertEquals(urls, [
      "https://vision.example.test/v1/chat/completions",
      "https://vision.example.test/v1/models",
    ]);
    assertEquals(auths, [`Bearer ${key}`, `Bearer ${key}`]);
    const line = cap.logs.join("\n");
    assertEquals(line.includes(key), false);
    assertEquals(line.includes("Authorization"), false);
    assertEquals(line.includes("Bearer"), false);
    assertEquals(line.includes("available_models="), true);
    assertEquals(line.includes("nvidia/nemotron-3-nano-omni"), true);
  } finally {
    cap.restore();
  }
});

Deno.test("rejected output error keeps base_host, reason, and a 400 char sample", () => {
  const cap = captureFetch(() => new Response("unused", { status: 500 }));
  try {
    const err = llmErrorForRejectedOutput({
      provider: "nebius",
      model: NEBIUS_TEXT_MODEL,
      baseHost: "api.tokenfactory.us-central1.nebius.com",
      text: `<think>${"z".repeat(50)}</think>${"y".repeat(500)}`,
      reason: "unparseable_output",
    });
    if (!err || !("sample" in err)) throw new Error("expected sample");
    assertEquals(err.status, 200);
    assertEquals(err.reason, "unparseable_output");
    assertEquals(err.base_host, "api.tokenfactory.us-central1.nebius.com");
    assertEquals(err.sample, "y".repeat(400));
    assertEquals(err.sample.includes("<think>"), false);
    const line = cap.logs.join("\n");
    assertEquals(line.includes("reason=unparseable_output"), true);
    assertEquals(line.includes("base_host=api.tokenfactory.us-central1.nebius.com"), true);
    assertEquals(line.includes("y".repeat(400)), true);
  } finally {
    cap.restore();
  }
});
