import { CORS } from "./cors.ts";
import {
  centsToDollars,
  dollarsToCents,
  type Milestone,
  planCapture,
  planDecline,
  planWithdraw,
  ScheduleError,
  type Transfer,
  type Wallet,
  type WalletWrite,
  type Withdrawal,
} from "./funding_schedule.ts";
import {
  applyFundingDecision,
  createPaypalClient,
  PaypalConfigError,
  redactText,
  resolvePaypalHost,
} from "./paypal_orders.ts";

const UUID =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const WALLET_COLS =
  "id,family_id,goal_id,goal_amount,currency,cadence,goal_date,status";
const MILESTONE_COLS = "id,wallet_id,family_id,due_date,proposed_amount,status";
const TRANSFER_COLS =
  "id,wallet_id,milestone_id,family_id,order_id,capture_id,amount,status";
const WITHDRAWAL_COLS = "id,wallet_id,family_id,amount";

export interface HandlerDeps {
  env: Record<string, string | undefined>;
  fetch: typeof fetch;
  now: () => Date;
  log?: (line: string) => void;
}

class RestError extends Error {
  constructor(readonly status: number, message: string) {
    super(message);
    this.name = "RestError";
  }
}

interface Parent {
  userId: string;
  familyId: string;
  auth: string;
}

interface Ctx {
  deps: HandlerDeps;
  origin: string;
  anon: string;
  parent: Parent;
  secrets: string[];
}

function json(status: number, body: unknown): Response {
  return Response.json(body, {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function logLine(deps: HandlerDeps, secrets: readonly string[], line: string) {
  (deps.log ?? ((s: string) => console.error(s)))(redactText(line, secrets));
}

function uuid(value: unknown, label: string): string {
  if (typeof value !== "string" || !UUID.test(value)) {
    throw new ScheduleError(`invalid ${label}`, 400);
  }
  return value;
}

function money(value: unknown): string {
  if (typeof value === "number" && Number.isFinite(value)) {
    return centsToDollars(dollarsToCents(value.toFixed(2)));
  }
  if (typeof value === "string") return centsToDollars(dollarsToCents(value));
  throw new ScheduleError("invalid amount", 500);
}

function asRows(data: unknown): Record<string, unknown>[] {
  if (data == null) return [];
  if (!Array.isArray(data)) throw new ScheduleError("unreadable response", 502);
  return data.filter((row): row is Record<string, unknown> =>
    !!row && typeof row === "object"
  );
}

function supabaseOrigin(raw: string): string {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    throw new ScheduleError("server is not configured", 500);
  }
  if (
    (url.protocol !== "http:" && url.protocol !== "https:") || url.username ||
    url.password
  ) {
    throw new ScheduleError("server is not configured", 500);
  }
  return url.origin;
}

async function readJson(req: Request): Promise<Record<string, unknown>> {
  let body: unknown;
  try {
    body = await req.json();
  } catch {
    throw new ScheduleError("invalid json", 400);
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new ScheduleError("invalid json", 400);
  }
  return body as Record<string, unknown>;
}

function asOf(now: Date): string {
  return now.toISOString().slice(0, 10);
}

function withdrawNote(value: unknown): string {
  if (value == null) return "";
  if (typeof value !== "string" || value.length > 500) {
    throw new ScheduleError("invalid note", 400);
  }
  return value;
}

async function rest(
  ctx: Ctx,
  method: string,
  path: string,
  body?: unknown,
  prefer?: string,
): Promise<unknown> {
  if (path.startsWith("/") || path.includes("://")) {
    throw new ScheduleError("bad rest path", 500);
  }
  const res = await ctx.deps.fetch(`${ctx.origin}/rest/v1/${path}`, {
    method,
    headers: {
      apikey: ctx.anon,
      Authorization: ctx.parent.auth,
      Accept: "application/json",
      ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
      ...(prefer ? { Prefer: prefer } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  if (!res.ok) {
    throw new RestError(
      res.status,
      redactText(text || res.statusText, ctx.secrets),
    );
  }
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    throw new ScheduleError("unreadable response", 502);
  }
}

async function openCtx(req: Request, deps: HandlerDeps): Promise<Ctx> {
  const missing = ["SUPABASE_URL", "SUPABASE_ANON_KEY"].filter((key) =>
    !deps.env[key]
  );
  if (missing.length > 0) {
    logLine(deps, [], `missing env ${missing.join(",")}`);
    throw new ScheduleError("server is not configured", 500);
  }
  const origin = supabaseOrigin(deps.env.SUPABASE_URL ?? "");
  const anon = deps.env.SUPABASE_ANON_KEY ?? "";
  const secrets = [
    anon,
    deps.env.PAYPAL_CLIENT_ID ?? "",
    deps.env.PAYPAL_CLIENT_SECRET ?? "",
  ].filter((s) => s.length >= 4);
  const header = (req.headers.get("Authorization") ?? "").trim();
  const match = /^Bearer\s+(\S+)$/i.exec(header);
  if (!match) throw new ScheduleError("not allowed", 401);
  const auth = `Bearer ${match[1]}`;
  secrets.push(match[1], auth);
  const userRes = await deps.fetch(`${origin}/auth/v1/user`, {
    headers: { apikey: anon, Authorization: auth, Accept: "application/json" },
  });
  const userText = await userRes.text();
  if (!userRes.ok) {
    logLine(deps, secrets, `auth status=${userRes.status} body=${userText}`);
    throw new ScheduleError("not allowed", 401);
  }
  let user: { id?: unknown };
  try {
    user = JSON.parse(userText);
  } catch {
    throw new ScheduleError("not allowed", 401);
  }
  const userId = uuid(user.id, "user");
  const ctx: Ctx = {
    deps,
    origin,
    anon,
    parent: { userId, familyId: "", auth },
    secrets,
  };
  const profiles = asRows(
    await rest(
      ctx,
      "GET",
      `profiles?id=eq.${userId}&select=role,family_id`,
    ),
  );
  const profile = profiles[0];
  if (!profile || profile.role !== "parent") {
    throw new ScheduleError("not allowed", 403);
  }
  ctx.parent.familyId = uuid(profile.family_id, "family");
  return ctx;
}

function mapMilestone(row: Record<string, unknown>): Milestone {
  const status = row.status;
  if (
    status !== "proposed" && status !== "approved" && status !== "captured" &&
    status !== "skipped" && status !== "declined"
  ) {
    throw new ScheduleError("unreadable response", 502);
  }
  if (typeof row.id !== "string" || typeof row.due_date !== "string") {
    throw new ScheduleError("unreadable response", 502);
  }
  return {
    id: row.id,
    dueDate: row.due_date,
    proposedAmount: money(row.proposed_amount),
    status,
  };
}

function mapTransfer(row: Record<string, unknown>): Transfer {
  const status = row.status;
  if (
    status !== "created" && status !== "captured" && status !== "declined" &&
    status !== "skipped"
  ) {
    throw new ScheduleError("unreadable response", 502);
  }
  if (typeof row.id !== "string" || typeof row.milestone_id !== "string") {
    throw new ScheduleError("unreadable response", 502);
  }
  return {
    id: row.id,
    milestoneId: row.milestone_id,
    orderId: typeof row.order_id === "string" ? row.order_id : null,
    captureId: typeof row.capture_id === "string" ? row.capture_id : null,
    amount: money(row.amount),
    status,
  };
}

function mapWithdrawal(row: Record<string, unknown>): Withdrawal {
  if (typeof row.id !== "string" || typeof row.wallet_id !== "string") {
    throw new ScheduleError("unreadable response", 502);
  }
  return { id: row.id, walletId: row.wallet_id, amount: money(row.amount) };
}

function mapWallet(row: Record<string, unknown>, familyId: string): Wallet {
  if (row.family_id !== familyId) {
    throw new ScheduleError("milestone not found", 404);
  }
  if (row.cadence !== "weekly") {
    throw new ScheduleError("wallet cadence is not weekly", 409);
  }
  const status = row.status;
  if (status !== "active" && status !== "short" && status !== "funded") {
    throw new ScheduleError("unreadable response", 502);
  }
  if (
    typeof row.id !== "string" || typeof row.goal_id !== "string" ||
    typeof row.goal_date !== "string"
  ) {
    throw new ScheduleError("unreadable response", 502);
  }
  return {
    id: row.id,
    goalId: row.goal_id,
    goalAmount: money(row.goal_amount),
    goalDate: row.goal_date,
    cadence: "weekly",
    status,
    currency: typeof row.currency === "string" ? row.currency : "USD",
  };
}

async function loadBundle(ctx: Ctx, walletId: string): Promise<{
  wallet: Wallet;
  milestones: Milestone[];
  transfers: Transfer[];
  withdrawals: Withdrawal[];
}> {
  const familyId = ctx.parent.familyId;
  const wallets = asRows(
    await rest(
      ctx,
      "GET",
      `goal_wallets?id=eq.${walletId}&family_id=eq.${familyId}&select=${WALLET_COLS}`,
    ),
  );
  if (wallets.length !== 1) throw new ScheduleError("wallet not found", 404);
  const milestones = asRows(
    await rest(
      ctx,
      "GET",
      `funding_milestones?wallet_id=eq.${walletId}&family_id=eq.${familyId}&select=${MILESTONE_COLS}`,
    ),
  ).map(mapMilestone);
  const transfers = asRows(
    await rest(
      ctx,
      "GET",
      `paypal_transfers?wallet_id=eq.${walletId}&family_id=eq.${familyId}&select=${TRANSFER_COLS}`,
    ),
  ).map(mapTransfer);
  const withdrawals = asRows(
    await rest(
      ctx,
      "GET",
      `paypal_withdrawals?wallet_id=eq.${walletId}&family_id=eq.${familyId}&select=${WITHDRAWAL_COLS}`,
    ),
  ).map(mapWithdrawal);
  return {
    wallet: mapWallet(wallets[0], familyId),
    milestones,
    transfers,
    withdrawals,
  };
}

async function loadMilestone(
  ctx: Ctx,
  milestoneId: string,
): Promise<Record<string, unknown>> {
  const rows = asRows(
    await rest(
      ctx,
      "GET",
      `funding_milestones?id=eq.${milestoneId}&family_id=eq.${ctx.parent.familyId}&select=${MILESTONE_COLS}`,
    ),
  );
  if (rows.length !== 1 || typeof rows[0].wallet_id !== "string") {
    throw new ScheduleError("milestone not found", 404);
  }
  return rows[0];
}

function paypalFor(ctx: Ctx) {
  const clientId = ctx.deps.env.PAYPAL_CLIENT_ID ?? "";
  const clientSecret = ctx.deps.env.PAYPAL_CLIENT_SECRET ?? "";
  if (!clientId || !clientSecret) {
    logLine(
      ctx.deps,
      ctx.secrets,
      "missing env PAYPAL_CLIENT_ID,PAYPAL_CLIENT_SECRET",
    );
    throw new ScheduleError("paypal is not configured", 500);
  }
  ctx.secrets.push(clientId, clientSecret);
  return createPaypalClient({
    clientId,
    clientSecret,
    host: resolvePaypalHost(ctx.deps.env),
    intent: "CAPTURE",
    payeeEmail: ctx.deps.env.PAYPAL_BUSINESS_EMAIL,
    fetch: ctx.deps.fetch,
    log: (line) => logLine(ctx.deps, ctx.secrets, line),
  });
}

async function executeWrites(
  ctx: Ctx,
  writes: readonly WalletWrite[],
): Promise<void> {
  const familyId = ctx.parent.familyId;
  for (const w of writes) {
    if (w.kind === "update_milestone") {
      uuid(w.id, "milestone id");
      await rest(
        ctx,
        "PATCH",
        `funding_milestones?id=eq.${w.id}&family_id=eq.${familyId}`,
        { status: w.status },
        "return=minimal",
      );
    } else if (w.kind === "insert_transfer") {
      uuid(w.milestoneId, "milestone id");
      uuid(w.walletId, "wallet id");
      await rest(ctx, "POST", "paypal_transfers", {
        wallet_id: w.walletId,
        milestone_id: w.milestoneId,
        family_id: familyId,
        order_id: w.orderId,
        capture_id: w.captureId,
        amount: w.amount,
        status: w.status,
      }, "return=minimal");
    } else if (w.kind === "delete_milestones") {
      if (w.ids.length === 0) continue;
      for (const id of w.ids) uuid(id, "milestone id");
      await rest(
        ctx,
        "DELETE",
        `funding_milestones?id=in.(${
          w.ids.join(",")
        })&family_id=eq.${familyId}`,
        undefined,
        "return=minimal",
      );
    } else if (w.kind === "insert_milestones") {
      if (w.rows.length === 0) continue;
      uuid(w.walletId, "wallet id");
      await rest(
        ctx,
        "POST",
        "funding_milestones",
        w.rows.map((row) => ({
          wallet_id: w.walletId,
          family_id: familyId,
          due_date: row.dueDate,
          proposed_amount: row.proposedAmount,
          status: "proposed",
        })),
        "return=minimal",
      );
    } else if (w.kind === "update_wallet") {
      uuid(w.id, "wallet id");
      await rest(
        ctx,
        "PATCH",
        `goal_wallets?id=eq.${w.id}&family_id=eq.${familyId}`,
        { status: w.status },
        "return=minimal",
      );
    } else if (w.kind === "capture_transfer") {
      uuid(w.id, "transfer id");
      const rows = asRows(
        await rest(
          ctx,
          "PATCH",
          `paypal_transfers?id=eq.${w.id}&family_id=eq.${familyId}&status=eq.created`,
          { status: "captured", capture_id: w.captureId, amount: w.amount },
          "return=representation",
        ),
      );
      if (rows.length !== 1) {
        throw new ScheduleError("capture was not recorded", 409);
      }
    } else if (w.kind === "insert_withdrawal") {
      uuid(w.walletId, "wallet id");
      if (dollarsToCents(w.amount) <= 0) {
        throw new ScheduleError("withdraw amount must be positive", 409);
      }
      await rest(ctx, "POST", "paypal_withdrawals", {
        wallet_id: w.walletId,
        family_id: familyId,
        amount: w.amount,
        note: w.note,
      }, "return=minimal");
    } else if (w.kind === "insert_parent_save") {
      uuid(w.goalId, "goal id");
      if (dollarsToCents(w.amount) <= 0) {
        throw new ScheduleError("capture amount must be positive", 409);
      }
      try {
        await rest(ctx, "POST", "parent_save_entries", {
          family_id: familyId,
          goal_id: w.goalId,
          amount: w.amount,
          note: w.note,
          created_by: ctx.parent.userId,
        }, "return=minimal");
      } catch (e) {
        if (!(e instanceof RestError) || e.status !== 409) throw e;
        const existing = asRows(
          await rest(
            ctx,
            "GET",
            `parent_save_entries?goal_id=eq.${w.goalId}&note=eq.${
              encodeURIComponent(w.note)
            }&select=id`,
          ),
        );
        if (existing.length < 1) throw e;
      }
    }
  }
}

function fail(
  deps: HandlerDeps,
  secrets: readonly string[],
  e: unknown,
): Response {
  const message = e instanceof Error ? e.message : "request failed";
  logLine(deps, secrets, message);
  if (e instanceof ScheduleError) return json(e.status, { error: e.message });
  if (e instanceof PaypalConfigError) {
    return json(500, { error: "paypal is not configured" });
  }
  if (message.startsWith("paypal ")) {
    return json(502, { error: "paypal failed" });
  }
  return json(500, { error: "request failed" });
}

export async function handleFundingDecline(
  req: Request,
  deps?: HandlerDeps,
): Promise<Response> {
  const used = deps ??
    {
      env: Deno.env.toObject(),
      fetch: globalThis.fetch,
      now: () => new Date(),
    };
  const secrets: string[] = [];
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") {
      return json(405, { error: "method not allowed" });
    }
    const body = await readJson(req);
    const milestoneId = uuid(body.milestone_id, "milestone id");
    if (body.decision !== "skipped" && body.decision !== "declined") {
      throw new ScheduleError("decision must be skipped or declined", 400);
    }
    const ctx = await openCtx(req, used);
    secrets.push(...ctx.secrets);
    const row = await loadMilestone(ctx, milestoneId);
    const bundle = await loadBundle(ctx, uuid(row.wallet_id, "wallet id"));
    const plan = planDecline({
      wallet: bundle.wallet,
      milestones: bundle.milestones,
      transfers: bundle.transfers,
      withdrawals: bundle.withdrawals,
      milestoneId,
      decision: body.decision,
      asOf: asOf(used.now()),
    });
    if (
      plan.writes.some((w) =>
        w.kind === "insert_parent_save" || w.kind === "capture_transfer"
      )
    ) {
      throw new ScheduleError("decline must not capture or save", 500);
    }
    await executeWrites(ctx, plan.writes);
    return json(200, {
      milestone_id: milestoneId,
      decision: body.decision,
      wallet_status: plan.walletStatus,
      funding_percent: plan.fundingPercent,
    });
  } catch (e) {
    return fail(used, secrets, e);
  }
}

export async function handleWalletWithdraw(
  req: Request,
  deps?: HandlerDeps,
): Promise<Response> {
  const used = deps ??
    {
      env: Deno.env.toObject(),
      fetch: globalThis.fetch,
      now: () => new Date(),
    };
  const secrets: string[] = [];
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") {
      return json(405, { error: "method not allowed" });
    }
    const body = await readJson(req);
    const walletId = uuid(body.wallet_id, "wallet id");
    // Client money is a decimal string. Numbers round through toFixed and would
    // change the amount before the captured-balance check.
    if (typeof body.amount !== "string") {
      throw new ScheduleError("invalid amount", 400);
    }
    const amount = money(body.amount);
    const note = withdrawNote(body.note);
    const ctx = await openCtx(req, used);
    secrets.push(...ctx.secrets);
    const bundle = await loadBundle(ctx, walletId);
    const plan = planWithdraw({
      wallet: bundle.wallet,
      milestones: bundle.milestones,
      transfers: bundle.transfers,
      withdrawals: bundle.withdrawals,
      amount,
      note,
      asOf: asOf(used.now()),
    });
    if (
      plan.writes.some((w) =>
        w.kind === "insert_transfer" || w.kind === "capture_transfer" ||
        w.kind === "insert_parent_save" || w.kind === "update_milestone"
      )
    ) {
      throw new ScheduleError(
        "withdraw must not touch transfers or saves",
        500,
      );
    }
    await executeWrites(ctx, plan.writes);
    return json(200, {
      wallet_id: walletId,
      amount: plan.amount,
      wallet_status: plan.walletStatus,
      funding_percent: plan.fundingPercent,
    });
  } catch (e) {
    return fail(used, secrets, e);
  }
}

export async function handlePaypalOrder(
  req: Request,
  deps?: HandlerDeps,
): Promise<Response> {
  const used = deps ??
    {
      env: Deno.env.toObject(),
      fetch: globalThis.fetch,
      now: () => new Date(),
    };
  const secrets: string[] = [];
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") {
      return json(405, { error: "method not allowed" });
    }
    const body = await readJson(req);
    const milestoneId = uuid(body.milestone_id, "milestone id");
    const ctx = await openCtx(req, used);
    secrets.push(...ctx.secrets);
    const row = await loadMilestone(ctx, milestoneId);
    const bundle = await loadBundle(ctx, uuid(row.wallet_id, "wallet id"));
    const milestone = bundle.milestones.find((m) => m.id === milestoneId);
    if (!milestone) throw new ScheduleError("milestone not found", 404);
    if (milestone.status !== "proposed" && milestone.status !== "approved") {
      throw new ScheduleError("milestone already settled", 409);
    }
    if (bundle.wallet.currency !== "USD") {
      throw new ScheduleError("wallet currency must be USD", 409);
    }
    if (dollarsToCents(milestone.proposedAmount) <= 0) {
      throw new ScheduleError("milestone amount must be positive", 409);
    }
    const open = bundle.transfers.find((t) =>
      t.milestoneId === milestoneId && t.status === "created" && t.orderId
    );
    if (open?.orderId) {
      return json(200, { order_id: open.orderId, reused: true });
    }
    const created = await paypalFor(ctx).createOrder({
      amount: milestone.proposedAmount,
      currency: "USD",
      referenceId: milestone.id,
    });
    const write: WalletWrite = {
      kind: "insert_transfer",
      milestoneId: milestone.id,
      walletId: bundle.wallet.id,
      orderId: created.orderId,
      captureId: null,
      amount: "0.00",
      status: "created",
    };
    await executeWrites(ctx, [write]);
    return json(200, {
      order_id: created.orderId,
      approve_url: created.approveUrl,
    });
  } catch (e) {
    return fail(used, secrets, e);
  }
}

export async function handlePaypalCapture(
  req: Request,
  deps?: HandlerDeps,
): Promise<Response> {
  const used = deps ??
    {
      env: Deno.env.toObject(),
      fetch: globalThis.fetch,
      now: () => new Date(),
    };
  const secrets: string[] = [];
  try {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") {
      return json(405, { error: "method not allowed" });
    }
    const body = await readJson(req);
    if (
      typeof body.order_id !== "string" || !/^[A-Za-z0-9]+$/.test(body.order_id)
    ) {
      throw new ScheduleError("invalid order id", 400);
    }
    const orderId = body.order_id;
    const ctx = await openCtx(req, used);
    secrets.push(...ctx.secrets);
    const found = asRows(
      await rest(
        ctx,
        "GET",
        `paypal_transfers?order_id=eq.${orderId}&family_id=eq.${ctx.parent.familyId}&select=${TRANSFER_COLS}`,
      ),
    );
    if (found.length !== 1) throw new ScheduleError("transfer not found", 404);
    const transfer = mapTransfer(found[0]);
    const bundle = await loadBundle(ctx, uuid(found[0].wallet_id, "wallet id"));
    let captureId = transfer.captureId;
    let amount = transfer.amount;
    const alreadyRecorded = transfer.status === "captured" && !!captureId;
    if (!alreadyRecorded) {
      if (transfer.status !== "created" || !transfer.orderId) {
        throw new ScheduleError("milestone already settled", 409);
      }
      const recorded = await applyFundingDecision(
        "capture",
        paypalFor(ctx),
        transfer.orderId,
      );
      if (recorded.status !== "captured" || recorded.captureId == null) {
        throw new ScheduleError("paypal capture was not usable", 502);
      }
      captureId = recorded.captureId;
      amount = recorded.amount;
    }
    if (!captureId) {
      throw new ScheduleError("paypal capture was not usable", 502);
    }
    const plan = planCapture({
      wallet: bundle.wallet,
      milestones: bundle.milestones,
      transfers: bundle.transfers,
      withdrawals: bundle.withdrawals,
      milestoneId: transfer.milestoneId,
      transferId: transfer.id,
      captureId,
      amount,
      asOf: asOf(used.now()),
      alreadyRecorded,
    });
    const saves = plan.writes.filter((w) => w.kind === "insert_parent_save");
    if (saves.length !== 1) {
      throw new ScheduleError("capture must record one parent save", 500);
    }
    await executeWrites(ctx, plan.writes);
    return json(200, {
      order_id: orderId,
      capture_id: captureId,
      amount: plan.amount,
      wallet_status: plan.walletStatus,
    });
  } catch (e) {
    return fail(used, secrets, e);
  }
}
