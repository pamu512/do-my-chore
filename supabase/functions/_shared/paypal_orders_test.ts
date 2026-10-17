import { assertEquals, assertRejects, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  applyFundingDecision,
  createPaypalClient,
  PAYPAL_SANDBOX_ORIGIN,
  PaypalConfigError,
  resolvePaypalHost,
  storeCapture,
  storeCreatedOrder,
} from "./paypal_orders.ts";

const REF = "11111111-1111-4111-8111-111111111111";
const CLIENT_ID = "cid-test-value-xyz";
const SECRET = "sec-test-value-xyz";

Deno.test("create then capture stores both ids", async () => {
  const calls: string[] = [];
  let intent = "";
  const client = createPaypalClient({
    clientId: CLIENT_ID,
    clientSecret: SECRET,
    fetch: (input, init) => {
      const url = String(input);
      calls.push(url);
      if (url === `${PAYPAL_SANDBOX_ORIGIN}/v1/oauth2/token`) {
        return Promise.resolve(new Response(JSON.stringify({ access_token: "tok-test-value" }), { status: 200 }));
      }
      if (url === `${PAYPAL_SANDBOX_ORIGIN}/v2/checkout/orders`) {
        const body = JSON.parse(String(init?.body));
        intent = body.intent;
        const headers = new Headers(init?.headers);
        assertEquals(headers.get("PayPal-Request-Id"), REF);
        return Promise.resolve(new Response(JSON.stringify({
          id: "ORDER123",
          links: [{ rel: "payer-action", href: "https://www.sandbox.paypal.com/checkoutnow?token=ORDER123" }],
        }), { status: 201 }));
      }
      if (url === `${PAYPAL_SANDBOX_ORIGIN}/v2/checkout/orders/ORDER123/capture`) {
        return Promise.resolve(new Response(JSON.stringify({
          purchase_units: [{
            payments: {
              captures: [{
                id: "CAP123",
                status: "COMPLETED",
                amount: { currency_code: "USD", value: "10.00" },
              }],
            },
          }],
        }), { status: 201 }));
      }
      return Promise.resolve(new Response(`unexpected ${url}`, { status: 500 }));
    },
  });
  const created = await client.createOrder({ amount: "10.00", currency: "USD", referenceId: REF });
  let row = storeCreatedOrder(created.orderId);
  const captured = await client.captureOrder(created.orderId);
  row = storeCapture(row, captured.captureId);
  assertEquals(intent, "CAPTURE");
  assertEquals(row, { orderId: "ORDER123", captureId: "CAP123" });
  assertEquals(captured.amount, "10.00");
  assertEquals(calls.every((url) => url.startsWith(PAYPAL_SANDBOX_ORIGIN)), true);
});

Deno.test("decline path never calls capture", async () => {
  let calls = 0;
  const client = createPaypalClient({
    clientId: CLIENT_ID,
    clientSecret: SECRET,
    fetch: () => {
      calls += 1;
      return Promise.resolve(new Response("no", { status: 500 }));
    },
  });
  const row = await applyFundingDecision("declined", client, "ORDER123");
  assertEquals(calls, 0);
  assertEquals(row, { orderId: null, captureId: null, amount: "0.00", status: "declined" });
});

Deno.test("live host or AUTHORIZE intent throws before fetch", () => {
  let calls = 0;
  const fetchImpl = () => {
    calls += 1;
    return Promise.resolve(new Response("no"));
  };
  assertThrows(
    () => createPaypalClient({ clientId: CLIENT_ID, clientSecret: SECRET, host: "https://api-m.paypal.com", fetch: fetchImpl }),
    PaypalConfigError,
    "sandbox",
  );
  assertThrows(
    () => createPaypalClient({ clientId: CLIENT_ID, clientSecret: SECRET, intent: "AUTHORIZE", fetch: fetchImpl }),
    PaypalConfigError,
    "CAPTURE",
  );
  assertThrows(
    () => resolvePaypalHost({ PAYPAL_API_BASE: "https://api-m.paypal.com" }),
    PaypalConfigError,
    "sandbox",
  );
  assertEquals(resolvePaypalHost({}), PAYPAL_SANDBOX_ORIGIN);
  assertEquals(calls, 0);
});

Deno.test("paypal logs and errors omit the secret and Authorization", async () => {
  const logs: string[] = [];
  const orig = console.error;
  console.error = (...args: unknown[]) => logs.push(args.map((a) => String(a)).join(" "));
  try {
    const client = createPaypalClient({
      clientId: CLIENT_ID,
      clientSecret: SECRET,
      log: (line) => logs.push(line),
      fetch: () => Promise.resolve(new Response(`nope ${SECRET}\nAuthorization: Bearer ${SECRET}`, { status: 401 })),
    });
    const err = await assertRejects(() =>
      client.createOrder({ amount: "10.00", currency: "USD", referenceId: REF })
    );
    const basic = btoa(`${CLIENT_ID}:${SECRET}`);
    const blob = `${err instanceof Error ? err.message : String(err)}\n${logs.join("\n")}`;
    assertEquals(blob.includes(SECRET), false);
    assertEquals(blob.includes(CLIENT_ID), false);
    assertEquals(blob.includes(basic), false);
    assertEquals(blob.includes("Authorization"), false);
    assertEquals(blob.includes("Bearer"), false);
    assertEquals(logs.some((line) => line.includes("status=401")), true);
    assertEquals(logs.some((line) => line.includes("[redacted]")), true);
  } finally {
    console.error = orig;
  }
});
