import { centsToDollars, dollarsToCents } from "./funding_schedule.ts";

export const PAYPAL_SANDBOX_ORIGIN = "https://api-m.sandbox.paypal.com";

export class PaypalConfigError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "PaypalConfigError";
  }
}

export function redactText(raw: string, secrets: readonly string[]): string {
  let out = raw;
  const sorted = [...secrets].filter((s) => s.length >= 4).sort((a, b) => b.length - a.length);
  for (const secret of sorted) out = out.split(secret).join("[redacted]");
  out = out.replace(/\bAuthorization\b/gi, "[redacted]");
  out = out.replace(/\bBearer\b/gi, "[redacted]");
  out = out.replace(/\bBasic\b/gi, "[redacted]");
  out = out.replace(/[\r\n]+/g, " ").trim();
  return out.length <= 300 ? out : out.slice(0, 300);
}

export function assertSandboxHost(host: string): void {
  let url: URL;
  try {
    url = new URL(host);
  } catch {
    throw new PaypalConfigError("paypal host must be sandbox");
  }
  if (
    url.origin !== PAYPAL_SANDBOX_ORIGIN ||
    url.username ||
    url.password ||
    url.search ||
    url.hash ||
    (url.pathname !== "/" && url.pathname !== "")
  ) {
    throw new PaypalConfigError("paypal host must be sandbox");
  }
}

export function resolvePaypalHost(env: Record<string, string | undefined>): string {
  assertSandboxHost(env.PAYPAL_API_BASE ?? env.PAYPAL_HOST ?? PAYPAL_SANDBOX_ORIGIN);
  return PAYPAL_SANDBOX_ORIGIN;
}

export interface PaypalOrderClient {
  createOrder(input: {
    amount: string;
    currency: string;
    referenceId: string;
  }): Promise<{ orderId: string; approveUrl: string | null }>;
  captureOrder(orderId: string): Promise<{ captureId: string; amount: string; currency: string }>;
}

export interface StoredPaypalIds {
  orderId: string | null;
  captureId: string | null;
}

export function storeCreatedOrder(orderId: string): StoredPaypalIds {
  if (!/^[A-Za-z0-9]+$/.test(orderId)) throw new PaypalConfigError("missing order id");
  return { orderId, captureId: null };
}

export function storeCapture(row: StoredPaypalIds, captureId: string): StoredPaypalIds {
  if (!row.orderId) throw new PaypalConfigError("missing order id");
  if (!/^[A-Za-z0-9]+$/.test(captureId)) throw new PaypalConfigError("missing capture id");
  return { orderId: row.orderId, captureId };
}

export interface DeclineTransfer {
  orderId: null;
  captureId: null;
  amount: "0.00";
  status: "declined" | "skipped";
}

/** Decline and skip never call the client. Capture is the only branch that does. */
export async function applyFundingDecision(
  decision: "declined" | "skipped" | "capture",
  client: PaypalOrderClient,
  orderId: string,
): Promise<DeclineTransfer | { orderId: string; captureId: string; amount: string; status: "captured" }> {
  if (decision === "declined" || decision === "skipped") {
    return { orderId: null, captureId: null, amount: "0.00", status: decision };
  }
  const cap = await client.captureOrder(orderId);
  return { orderId, captureId: cap.captureId, amount: cap.amount, status: "captured" };
}

function sandboxUrl(pathname: string): string {
  const url = new URL(pathname, PAYPAL_SANDBOX_ORIGIN);
  if (url.origin !== PAYPAL_SANDBOX_ORIGIN) throw new PaypalConfigError("paypal host must be sandbox");
  return url.toString();
}

function basicToken(clientId: string, clientSecret: string): string {
  const raw = `${clientId}:${clientSecret}`;
  for (let i = 0; i < raw.length; i++) {
    if (raw.charCodeAt(i) > 255) throw new PaypalConfigError("paypal credentials are not usable");
  }
  return btoa(raw);
}

function payeeEmail(email: string | undefined, secrets: readonly string[]): string | undefined {
  if (!email) return undefined;
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new PaypalConfigError("paypal payee email is not usable");
  }
  if (secrets.some((s) => s.length >= 4 && email.includes(s))) {
    throw new PaypalConfigError("paypal payee email is not usable");
  }
  return email;
}

async function readBody(res: Response): Promise<string> {
  try {
    return await res.text();
  } catch {
    return "";
  }
}

export function createPaypalClient(deps: {
  clientId: string;
  clientSecret: string;
  host?: string;
  intent?: string;
  payeeEmail?: string;
  fetch?: typeof fetch;
  log?: (line: string) => void;
}): PaypalOrderClient {
  assertSandboxHost(deps.host ?? PAYPAL_SANDBOX_ORIGIN);
  if ((deps.intent ?? "CAPTURE") !== "CAPTURE") {
    throw new PaypalConfigError("paypal intent must be CAPTURE");
  }
  const fetchImpl = deps.fetch ?? fetch;
  const log = deps.log ?? ((line: string) => console.error(line));
  const secrets = [deps.clientId, deps.clientSecret, basicToken(deps.clientId, deps.clientSecret)];
  const payee = payeeEmail(deps.payeeEmail, secrets);
  let accessToken: string | null = null;

  function fail(action: string, status: number | null, raw: string): Error {
    const message = redactText(raw || "upstream error", secrets);
    const line = redactText(
      `paypal ${action} host=api-m.sandbox.paypal.com status=${status ?? "null"} body=${message}`,
      secrets,
    );
    log(line);
    return new Error(line);
  }

  async function token(): Promise<string> {
    if (accessToken) return accessToken;
    const res = await fetchImpl(sandboxUrl("/v1/oauth2/token"), {
      method: "POST",
      headers: {
        Authorization: `Basic ${secrets[2]}`,
        "Content-Type": "application/x-www-form-urlencoded",
        Accept: "application/json",
      },
      body: "grant_type=client_credentials",
    });
    const raw = await readBody(res);
    if (!res.ok) throw fail("oauth", res.status, raw);
    let parsed: { access_token?: unknown };
    try {
      parsed = JSON.parse(raw);
    } catch {
      throw fail("oauth", res.status, "unreadable token");
    }
    if (typeof parsed.access_token !== "string" || parsed.access_token.length < 4) {
      throw fail("oauth", res.status, "missing token");
    }
    accessToken = parsed.access_token;
    secrets.push(accessToken);
    return accessToken;
  }

  return {
    async createOrder(input) {
      if (input.currency !== "USD") throw new PaypalConfigError("paypal currency must be USD");
      if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(input.referenceId)) {
        throw new PaypalConfigError("invalid reference");
      }
      const amount = centsToDollars(dollarsToCents(input.amount));
      if (dollarsToCents(amount) <= 0) throw new PaypalConfigError("paypal amount must be positive");
      const bearer = await token();
      const body: Record<string, unknown> = {
        intent: "CAPTURE",
        purchase_units: [{
          reference_id: input.referenceId,
          amount: { currency_code: "USD", value: amount },
          ...(payee ? { payee: { email_address: payee } } : {}),
        }],
      };
      const res = await fetchImpl(sandboxUrl("/v2/checkout/orders"), {
        method: "POST",
        headers: {
          Authorization: `Bearer ${bearer}`,
          "Content-Type": "application/json",
          Accept: "application/json",
          "PayPal-Request-Id": input.referenceId,
        },
        body: JSON.stringify(body),
      });
      const raw = await readBody(res);
      if (!res.ok) throw fail("createOrder", res.status, raw);
      let parsed: { id?: unknown; links?: { rel?: string; href?: string }[] };
      try {
        parsed = JSON.parse(raw);
      } catch {
        throw fail("createOrder", res.status, "unreadable order");
      }
      if (typeof parsed.id !== "string") throw fail("createOrder", res.status, "missing order id");
      const orderId = parsed.id;
      if (!/^[A-Za-z0-9]+$/.test(orderId)) throw new PaypalConfigError("missing order id");
      const approve = parsed.links?.find((l) => l.rel === "payer-action" || l.rel === "approve");
      const approveUrl = typeof approve?.href === "string" ? approve.href : null;
      return { orderId, approveUrl };
    },

    async captureOrder(orderId: string) {
      if (!/^[A-Za-z0-9]+$/.test(orderId)) throw new PaypalConfigError("invalid order id");
      const bearer = await token();
      const res = await fetchImpl(sandboxUrl(`/v2/checkout/orders/${orderId}/capture`), {
        method: "POST",
        headers: {
          Authorization: `Bearer ${bearer}`,
          "Content-Type": "application/json",
          Accept: "application/json",
          "PayPal-Request-Id": `capture-${orderId}`,
        },
        body: "{}",
      });
      const raw = await readBody(res);
      if (!res.ok) throw fail("captureOrder", res.status, raw);
      let parsed: {
        purchase_units?: {
          payments?: {
            captures?: { id?: string; status?: string; amount?: { currency_code?: string; value?: string } }[];
          };
        }[];
      };
      try {
        parsed = JSON.parse(raw);
      } catch {
        throw fail("captureOrder", res.status, "unreadable capture");
      }
      const capture = parsed.purchase_units?.[0]?.payments?.captures?.[0];
      if (!capture || capture.status !== "COMPLETED" || typeof capture.id !== "string") {
        throw new PaypalConfigError("paypal capture was not usable");
      }
      if (capture.amount?.currency_code !== "USD" || typeof capture.amount.value !== "string") {
        throw new PaypalConfigError("paypal capture was not usable");
      }
      let amount: string;
      try {
        amount = centsToDollars(dollarsToCents(capture.amount.value));
      } catch {
        throw new PaypalConfigError("paypal capture was not usable");
      }
      if (dollarsToCents(amount) <= 0) throw new PaypalConfigError("paypal capture was not usable");
      const stored = storeCapture({ orderId, captureId: null }, capture.id);
      return { captureId: stored.captureId!, amount, currency: "USD" };
    },
  };
}
