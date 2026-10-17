import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { handleFundingDecline, handlePaypalCapture, handlePaypalOrder } from "./wallet_http.ts";

const PARENT = "11111111-1111-4111-8111-111111111111";
const FAMILY = "22222222-2222-4222-8222-222222222222";
const GOAL = "33333333-3333-4333-8333-333333333333";
const WALLET = "44444444-4444-4444-8444-444444444444";
const M_CAP = "55555555-5555-4555-8555-555555555555";
const M_DEC = "66666666-6666-4666-8666-666666666666";
const M_LATER = "77777777-7777-4777-8777-777777777777";
const T_CAP = "88888888-8888-4888-8888-888888888888";
const T_OPEN = "99999999-9999-4999-8999-999999999999";
const SECRET = "sec-test-value-xyz";
const ANON = "anon-test-key-xyz";
const ORIGIN = "http://127.0.0.1:54321";

function env(): Record<string, string> {
  return {
    SUPABASE_URL: ORIGIN,
    SUPABASE_ANON_KEY: ANON,
    PAYPAL_CLIENT_ID: "cid-test-value-xyz",
    PAYPAL_CLIENT_SECRET: SECRET,
  };
}

function req(path: string, body: unknown, token = "parent-jwt-token"): Request {
  return new Request(`${ORIGIN}${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

interface Call {
  url: string;
  method: string;
  body: string;
}

Deno.test("decline does not call paypal or insert a parent save", async () => {
  const calls: Call[] = [];
  const logs: string[] = [];
  const res = await handleFundingDecline(req("/funding-decline", {
    milestone_id: M_DEC,
    decision: "declined",
  }), {
    env: env(),
    now: () => new Date("2026-10-17T15:00:00.000Z"),
    log: (line) => logs.push(line),
    fetch: (input, init) => {
      const url = String(input);
      const method = init?.method ?? "GET";
      const body = typeof init?.body === "string" ? init.body : "";
      calls.push({ url, method, body });
      if (url.endsWith("/auth/v1/user")) return Promise.resolve(Response.json({ id: PARENT }));
      if (url.includes("/profiles?")) return Promise.resolve(Response.json([{ role: "parent", family_id: FAMILY }]));
      if (url.includes("funding_milestones?id=eq.")) {
        return Promise.resolve(Response.json([{
          id: M_DEC,
          wallet_id: WALLET,
          family_id: FAMILY,
          due_date: "2026-10-19",
          proposed_amount: "2.00",
          status: "proposed",
        }]));
      }
      if (url.includes("goal_wallets?")) {
        return Promise.resolve(Response.json([{
          id: WALLET,
          family_id: FAMILY,
          goal_id: GOAL,
          goal_amount: "10.00",
          currency: "USD",
          cadence: "weekly",
          goal_date: "2026-11-07",
          status: "active",
        }]));
      }
      if (url.includes("funding_milestones?wallet_id=eq.")) {
        return Promise.resolve(Response.json([
          { id: M_CAP, wallet_id: WALLET, family_id: FAMILY, due_date: "2026-10-12", proposed_amount: "4.00", status: "captured" },
          { id: M_DEC, wallet_id: WALLET, family_id: FAMILY, due_date: "2026-10-19", proposed_amount: "2.00", status: "proposed" },
          { id: M_LATER, wallet_id: WALLET, family_id: FAMILY, due_date: "2026-10-26", proposed_amount: "2.00", status: "proposed" },
        ]));
      }
      if (url.includes("paypal_transfers?wallet_id=eq.")) {
        return Promise.resolve(Response.json([{
          id: T_CAP,
          wallet_id: WALLET,
          milestone_id: M_CAP,
          family_id: FAMILY,
          order_id: "ORDER1",
          capture_id: "CAP1",
          amount: "4.00",
          status: "captured",
        }]));
      }
      if (url.includes("parent_save_entries") || url.includes("paypal.com")) {
        return Promise.resolve(new Response("forbidden write", { status: 500 }));
      }
      if (method === "PATCH" || method === "POST" || method === "DELETE") {
        return Promise.resolve(new Response(null, { status: 204 }));
      }
      return Promise.resolve(new Response(`unexpected ${method} ${url}`, { status: 500 }));
    },
  });
  const text = await res.text();
  assertEquals(res.status, 200, `${text}\n${JSON.stringify(calls, null, 2)}`);
  assertEquals(calls.some((c) => c.url.includes("parent_save_entries")), false);
  assertEquals(calls.some((c) => c.url.includes("paypal.com")), false);
  const transfer = calls.find((c) => c.method === "POST" && c.url.endsWith("/paypal_transfers"));
  assertEquals(JSON.parse(transfer?.body ?? "{}"), {
    wallet_id: WALLET,
    milestone_id: M_DEC,
    family_id: FAMILY,
    order_id: null,
    capture_id: null,
    amount: "0.00",
    status: "declined",
  });
  const blob = `${text}\n${logs.join("\n")}`;
  assertEquals(blob.includes(SECRET), false);
  assertEquals(blob.includes(ANON), false);
  assertEquals(blob.includes("parent-jwt-token"), false);
  assertEquals(blob.includes("Authorization"), false);
});

Deno.test("a kid cannot decline", async () => {
  const calls: Call[] = [];
  const res = await handleFundingDecline(req("/funding-decline", {
    milestone_id: M_DEC,
    decision: "declined",
  }), {
    env: env(),
    now: () => new Date("2026-10-17T15:00:00.000Z"),
    fetch: (input, init) => {
      const url = String(input);
      calls.push({ url, method: init?.method ?? "GET", body: "" });
      if (url.endsWith("/auth/v1/user")) return Promise.resolve(Response.json({ id: PARENT }));
      if (url.includes("/profiles?")) return Promise.resolve(Response.json([{ role: "kid", family_id: FAMILY }]));
      return Promise.resolve(new Response("should not be called", { status: 500 }));
    },
  });
  assertEquals(res.status, 403);
  assertEquals(calls.some((c) => c.url.includes("paypal.com") || c.url.includes("parent_save_entries")), false);
});

Deno.test("create order is reused and capture stores both ids with one parent save", async () => {
  const calls: Call[] = [];
  let transferStatus = "created";
  let parentSaves = 0;
  const fetchImpl: typeof fetch = (input, init) => {
    const url = String(input);
    const method = init?.method ?? "GET";
    const body = typeof init?.body === "string" ? init.body : "";
    calls.push({ url, method, body });
    if (url.endsWith("/auth/v1/user")) return Promise.resolve(Response.json({ id: PARENT }));
    if (url.includes("/profiles?")) return Promise.resolve(Response.json([{ role: "parent", family_id: FAMILY }]));
    if (url.includes("funding_milestones?id=eq.")) {
      return Promise.resolve(Response.json([{
        id: M_DEC,
        wallet_id: WALLET,
        family_id: FAMILY,
        due_date: "2026-10-19",
        proposed_amount: "4.00",
        status: transferStatus === "captured" ? "captured" : "approved",
      }]));
    }
    if (url.includes("goal_wallets?")) {
      return Promise.resolve(Response.json([{
        id: WALLET,
        family_id: FAMILY,
        goal_id: GOAL,
        goal_amount: "10.00",
        currency: "USD",
        cadence: "weekly",
        goal_date: "2026-11-07",
        status: "active",
      }]));
    }
    if (url.includes("funding_milestones?wallet_id=eq.")) {
      return Promise.resolve(Response.json([{
        id: M_DEC,
        wallet_id: WALLET,
        family_id: FAMILY,
        due_date: "2026-10-19",
        proposed_amount: "4.00",
        status: transferStatus === "captured" ? "captured" : "approved",
      }]));
    }
    if (url.includes("paypal_transfers?wallet_id=eq.") || url.includes("paypal_transfers?order_id=eq.")) {
      return Promise.resolve(Response.json([{
        id: T_OPEN,
        wallet_id: WALLET,
        milestone_id: M_DEC,
        family_id: FAMILY,
        order_id: "ORDER123",
        capture_id: transferStatus === "captured" ? "CAP123" : null,
        amount: transferStatus === "captured" ? "4.00" : "0.00",
        status: transferStatus,
      }]));
    }
    if (url.endsWith("/v1/oauth2/token")) {
      return Promise.resolve(Response.json({ access_token: "tok-test-value" }));
    }
    if (url.endsWith("/v2/checkout/orders") && method === "POST") {
      return Promise.resolve(Response.json({ id: "ORDER999", links: [] }, { status: 201 }));
    }
    if (url.endsWith("/v2/checkout/orders/ORDER123/capture")) {
      transferStatus = "captured";
      return Promise.resolve(Response.json({
        purchase_units: [{
          payments: {
            captures: [{ id: "CAP123", status: "COMPLETED", amount: { currency_code: "USD", value: "4.00" } }],
          },
        }],
      }, { status: 201 }));
    }
    if (url.includes("parent_save_entries") && method === "POST") {
      parentSaves += 1;
      if (parentSaves > 1) return Promise.resolve(new Response("duplicate", { status: 409 }));
      return Promise.resolve(new Response("", { status: 201 }));
    }
    if (url.includes("parent_save_entries") && method === "GET") {
      return Promise.resolve(Response.json([{ id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }]));
    }
    if (method === "PATCH" && url.includes("status=eq.created")) {
      transferStatus = "captured";
      return Promise.resolve(Response.json([{ id: T_OPEN }]));
    }
    if (method === "PATCH" || method === "POST" || method === "DELETE") {
      return Promise.resolve(new Response(null, { status: 204 }));
    }
    return Promise.resolve(new Response(`unexpected ${method} ${url}`, { status: 500 }));
  };
  const deps = { env: env(), fetch: fetchImpl, now: () => new Date("2026-10-17T15:00:00.000Z") };
  const reused = await handlePaypalOrder(req("/paypal-order", { milestone_id: M_DEC }), deps);
  const reusedBody = await reused.json();
  assertEquals(reused.status, 200, JSON.stringify(reusedBody));
  assertEquals(reusedBody.order_id, "ORDER123");
  assertEquals(reusedBody.reused, true);
  assertEquals(calls.some((c) => c.url.includes("paypal.com")), false);

  const captured = await handlePaypalCapture(req("/paypal-capture", { order_id: "ORDER123" }), deps);
  const capturedBody = await captured.json();
  assertEquals(captured.status, 200, JSON.stringify({ capturedBody, calls }));
  assertEquals(capturedBody.order_id, "ORDER123");
  assertEquals(capturedBody.capture_id, "CAP123");
  assertEquals(capturedBody.amount, "4.00");
  const saves = calls.filter((c) => c.method === "POST" && c.url.includes("parent_save_entries"));
  assertEquals(saves.length, 1);
  assertEquals(JSON.parse(saves[0].body).amount, "4.00");

  const again = await handlePaypalCapture(req("/paypal-capture", { order_id: "ORDER123" }), deps);
  const againBody = await again.json();
  assertEquals(again.status, 200, JSON.stringify(againBody));
  assertEquals(againBody.capture_id, "CAP123");
  const captureCalls = calls.filter((c) => c.url.includes("/capture"));
  assertEquals(captureCalls.length, 1);
});

Deno.test("a configured live paypal host never gets a request", async () => {
  const calls: string[] = [];
  const res = await handlePaypalOrder(req("/paypal-order", { milestone_id: M_DEC }), {
    env: { ...env(), PAYPAL_API_BASE: "https://api-m.paypal.com" },
    now: () => new Date("2026-10-17T15:00:00.000Z"),
    fetch: (input, init) => {
      const url = String(input);
      calls.push(url);
      if (url.includes("paypal.com")) return Promise.resolve(new Response("live", { status: 500 }));
      if (url.endsWith("/auth/v1/user")) return Promise.resolve(Response.json({ id: PARENT }));
      if (url.includes("/profiles?")) return Promise.resolve(Response.json([{ role: "parent", family_id: FAMILY }]));
      if (url.includes("funding_milestones?id=eq.")) {
        return Promise.resolve(Response.json([{
          id: M_DEC,
          wallet_id: WALLET,
          family_id: FAMILY,
          due_date: "2026-10-19",
          proposed_amount: "4.00",
          status: "proposed",
        }]));
      }
      if (url.includes("goal_wallets?")) {
        return Promise.resolve(Response.json([{
          id: WALLET,
          family_id: FAMILY,
          goal_id: GOAL,
          goal_amount: "10.00",
          currency: "USD",
          cadence: "weekly",
          goal_date: "2026-11-07",
          status: "active",
        }]));
      }
      if (url.includes("funding_milestones?wallet_id=eq.")) {
        return Promise.resolve(Response.json([{
          id: M_DEC,
          wallet_id: WALLET,
          family_id: FAMILY,
          due_date: "2026-10-19",
          proposed_amount: "4.00",
          status: "proposed",
        }]));
      }
      if (url.includes("paypal_transfers?wallet_id=eq.")) return Promise.resolve(Response.json([]));
      return Promise.resolve(new Response(`unexpected ${init?.method ?? "GET"} ${url}`, { status: 500 }));
    },
  });
  assertEquals(res.status, 500);
  const body = await res.json();
  assertEquals(body.error, "paypal is not configured");
  assertEquals(calls.some((url) => url.includes("api-m.paypal.com")), false);
});
