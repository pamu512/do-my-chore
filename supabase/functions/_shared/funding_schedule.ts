// Shortfall is goal cents minus effective captured (captured cents minus withdrawn cents), floored at 0.
// Withdrawals are rows in paypal_withdrawals; paypal_transfers is never touched.
// Weekly dues are Monday UTC.
// ponytail: no family timezone. A goal before the next Monday is one payment on goal_date.

export type MilestoneStatus =
  | "proposed"
  | "approved"
  | "captured"
  | "skipped"
  | "declined";
export type TransferStatus = "created" | "captured" | "declined" | "skipped";
export type WalletStatus = "active" | "short" | "funded";

export class ScheduleError extends Error {
  constructor(message: string, readonly status: number) {
    super(message);
    this.name = "ScheduleError";
  }
}

export interface Milestone {
  id: string;
  dueDate: string;
  proposedAmount: string;
  status: MilestoneStatus;
}

export interface Transfer {
  id: string;
  milestoneId: string;
  orderId: string | null;
  captureId: string | null;
  amount: string;
  status: TransferStatus;
}

export interface Withdrawal {
  id: string;
  walletId: string;
  amount: string;
}

export interface Wallet {
  id: string;
  goalId: string;
  goalAmount: string;
  goalDate: string;
  cadence: "weekly";
  status: WalletStatus;
  currency: string;
}

export type WalletWrite =
  | { kind: "update_milestone"; id: string; status: MilestoneStatus }
  | {
    kind: "insert_transfer";
    milestoneId: string;
    walletId: string;
    orderId: string | null;
    captureId: string | null;
    amount: string;
    status: TransferStatus;
  }
  | { kind: "delete_milestones"; ids: string[] }
  | {
    kind: "insert_milestones";
    walletId: string;
    rows: { dueDate: string; proposedAmount: string }[];
  }
  | { kind: "update_wallet"; id: string; status: WalletStatus }
  | { kind: "capture_transfer"; id: string; captureId: string; amount: string }
  | { kind: "insert_parent_save"; goalId: string; amount: string; note: string }
  | {
    kind: "insert_withdrawal";
    walletId: string;
    amount: string;
    note: string;
  };

const DAY_MS = 86_400_000;
const MONDAY = 1;

export function dollarsToCents(amount: string): number {
  const m = /^(\d+)(?:\.(\d{1,4}))?$/.exec(amount.trim());
  if (!m) throw new ScheduleError("invalid amount", 400);
  const extra = m[2] ?? "";
  if (extra.length > 2 && /[1-9]/.test(extra.slice(2))) {
    throw new ScheduleError("invalid amount", 400);
  }
  const whole = Number(m[1]);
  const frac = extra.slice(0, 2).padEnd(2, "0");
  return whole * 100 + Number(frac);
}

export function centsToDollars(cents: number): string {
  if (!Number.isInteger(cents) || cents < 0) {
    throw new ScheduleError("invalid amount", 400);
  }
  const whole = Math.floor(cents / 100);
  const frac = String(cents % 100).padStart(2, "0");
  return `${whole}.${frac}`;
}

export function capturedCents(
  transfers: readonly { status: string; amount: string }[],
): number {
  let sum = 0;
  for (const t of transfers) {
    if (t.status === "captured") sum += dollarsToCents(t.amount);
  }
  return sum;
}

export function withdrawnCents(
  withdrawals: readonly { amount: string }[],
): number {
  let sum = 0;
  for (const w of withdrawals) {
    sum += dollarsToCents(w.amount);
  }
  return sum;
}

export function goalFundingPercent(
  goalAmount: string,
  transfers: readonly { status: string; amount: string }[],
  withdrawnCents = 0,
): number {
  const goal = dollarsToCents(goalAmount);
  if (goal === 0) return 0;
  return Math.max(0, capturedCents(transfers) - withdrawnCents) / goal;
}

export function splitShortfallCents(cents: number, periods: number): number[] {
  if (!Number.isInteger(cents) || cents < 0) {
    throw new ScheduleError("invalid amount", 400);
  }
  if (!Number.isInteger(periods) || periods < 0) {
    throw new ScheduleError("invalid periods", 400);
  }
  if (periods === 0) return [];
  const base = Math.floor(cents / periods);
  const rem = cents - base * periods;
  const out = Array.from({ length: periods }, () => base);
  out[periods - 1] = base + rem;
  return out;
}

function parseUtcDate(iso: string): number {
  const m = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
  if (!m) throw new ScheduleError("invalid date", 400);
  const y = Number(m[1]);
  const mo = Number(m[2]);
  const d = Number(m[3]);
  const t = Date.UTC(y, mo - 1, d);
  const check = new Date(t);
  if (
    check.getUTCFullYear() !== y || check.getUTCMonth() !== mo - 1 ||
    check.getUTCDate() !== d
  ) {
    throw new ScheduleError("invalid date", 400);
  }
  return t;
}

function isoDate(t: number): string {
  const dt = new Date(t);
  const y = dt.getUTCFullYear();
  const mo = String(dt.getUTCMonth() + 1).padStart(2, "0");
  const d = String(dt.getUTCDate()).padStart(2, "0");
  return `${y}-${mo}-${d}`;
}

/** Weekly due dates from the next Monday on or after asOf through goalDate.
 *  Empty, with goalDate still on or after asOf, means one period due on goalDate.
 */
export function periodsLeft(goalDate: string, asOf: string): string[] {
  const goal = parseUtcDate(goalDate);
  const start = parseUtcDate(asOf);
  const startDow = new Date(start).getUTCDay();
  const delta = (MONDAY - startDow + 7) % 7;
  const dates: string[] = [];
  for (
    let cursor = start + delta * DAY_MS;
    cursor <= goal;
    cursor += 7 * DAY_MS
  ) {
    dates.push(isoDate(cursor));
  }
  if (dates.length === 0 && goal >= start) return [goalDate];
  return dates;
}

function pinnedIds(
  milestones: readonly Milestone[],
  transfers: readonly Transfer[],
): Set<string> {
  const open = new Set(
    transfers.filter((t) => t.status === "created").map((t) => t.milestoneId),
  );
  const ids = new Set<string>();
  for (const m of milestones) {
    if (
      (m.status === "proposed" || m.status === "approved") && open.has(m.id)
    ) ids.add(m.id);
  }
  return ids;
}

export interface RecomputeResult {
  status: WalletStatus;
  milestones: Milestone[];
  deleteIds: string[];
  insertRows: { dueDate: string; proposedAmount: string }[];
}

export function recomputeSchedule(input: {
  wallet: Wallet;
  milestones: readonly Milestone[];
  transfers: readonly Transfer[];
  asOf: string;
  withdrawnCents?: number;
}): RecomputeResult {
  if (input.wallet.cadence !== "weekly") {
    throw new ScheduleError("wallet cadence is not weekly", 409);
  }
  const goal = parseUtcDate(input.wallet.goalDate);
  const effective = Math.max(
    0,
    capturedCents(input.transfers) - (input.withdrawnCents ?? 0),
  );
  const shortfall = Math.max(
    0,
    dollarsToCents(input.wallet.goalAmount) - effective,
  );
  const pinned = pinnedIds(input.milestones, input.transfers);
  const kept = input.milestones.filter((m) =>
    m.status === "captured" || m.status === "skipped" ||
    m.status === "declined" || pinned.has(m.id)
  );
  const deleteIds = input.milestones.filter((m) =>
    !kept.some((k) => k.id === m.id)
  ).map((m) => m.id);
  const lockedDates = new Set(kept.map((m) => m.dueDate));
  let dates = periodsLeft(input.wallet.goalDate, input.asOf).filter((d) =>
    !lockedDates.has(d)
  );
  const reserved = kept
    .filter((m) => pinned.has(m.id))
    .reduce((sum, m) => sum + dollarsToCents(m.proposedAmount), 0);
  const schedulable = Math.max(0, shortfall - reserved);
  if (schedulable === 0) dates = [];
  for (const d of dates) {
    if (parseUtcDate(d) > goal) {
      throw new ScheduleError("due date is after the goal", 500);
    }
  }
  const parts = splitShortfallCents(schedulable, dates.length);
  const insertRows = dates.map((dueDate, i) => ({
    dueDate,
    proposedAmount: centsToDollars(parts[i]),
  }));
  const proposed: Milestone[] = insertRows.map((row) => ({
    id: "",
    dueDate: row.dueDate,
    proposedAmount: row.proposedAmount,
    status: "proposed",
  }));
  let status: WalletStatus;
  if (shortfall === 0) status = "funded";
  else if (dates.length === 0 && reserved < shortfall) status = "short";
  else status = "active";
  const milestones = [...kept, ...proposed].sort((a, b) =>
    a.dueDate.localeCompare(b.dueDate)
  );
  return { status, milestones, deleteIds, insertRows };
}

function tailWrites(
  wallet: Wallet,
  recomputed: RecomputeResult,
): WalletWrite[] {
  const writes: WalletWrite[] = [];
  if (recomputed.deleteIds.length > 0) {
    writes.push({ kind: "delete_milestones", ids: recomputed.deleteIds });
  }
  if (recomputed.insertRows.length > 0) {
    writes.push({
      kind: "insert_milestones",
      walletId: wallet.id,
      rows: recomputed.insertRows,
    });
  }
  writes.push({
    kind: "update_wallet",
    id: wallet.id,
    status: recomputed.status,
  });
  return writes;
}

export function planDecline(input: {
  wallet: Wallet;
  milestones: readonly Milestone[];
  transfers: readonly Transfer[];
  milestoneId: string;
  decision: "skipped" | "declined";
  asOf: string;
  withdrawals?: readonly { amount: string }[];
}): {
  writes: WalletWrite[];
  fundingPercent: number;
  walletStatus: WalletStatus;
  milestones: Milestone[];
  transfers: Transfer[];
} {
  if (input.decision !== "skipped" && input.decision !== "declined") {
    throw new ScheduleError("decision must be skipped or declined", 400);
  }
  const target = input.milestones.find((m) => m.id === input.milestoneId);
  if (!target) throw new ScheduleError("milestone not found", 404);
  const alreadySettled = target.status === input.decision;
  if (
    target.status !== "proposed" && target.status !== "approved" &&
    !alreadySettled
  ) {
    throw new ScheduleError("milestone already settled", 409);
  }
  if (
    input.transfers.some((t) =>
      t.milestoneId === target.id &&
      (t.status === "created" || t.status === "captured")
    )
  ) {
    throw new ScheduleError("milestone has an open paypal order", 409);
  }
  const beforeCaptured = capturedCents(input.transfers);
  const milestones = input.milestones.map((m) =>
    m.id === target.id ? { ...m, status: input.decision } : m
  );
  const hasZeroTransfer = input.transfers.some((t) =>
    t.milestoneId === target.id && t.status === input.decision &&
    t.captureId == null && dollarsToCents(t.amount) === 0
  );
  const declineTransfer: Transfer = {
    id: "",
    milestoneId: target.id,
    orderId: null,
    captureId: null,
    amount: "0.00",
    status: input.decision,
  };
  const transfers: Transfer[] = hasZeroTransfer
    ? [...input.transfers]
    : [...input.transfers, declineTransfer];
  if (capturedCents(transfers) !== beforeCaptured) {
    throw new ScheduleError("decline changed captured money", 500);
  }
  const alreadyWithdrawn = withdrawnCents(input.withdrawals ?? []);
  const recomputed = recomputeSchedule({
    wallet: input.wallet,
    milestones,
    transfers,
    asOf: input.asOf,
    withdrawnCents: alreadyWithdrawn,
  });
  const after = goalFundingPercent(
    input.wallet.goalAmount,
    transfers,
    alreadyWithdrawn,
  );
  const writes: WalletWrite[] = [];
  if (!alreadySettled) {
    writes.push({
      kind: "update_milestone",
      id: target.id,
      status: input.decision,
    });
  }
  if (!hasZeroTransfer) {
    writes.push({
      kind: "insert_transfer",
      milestoneId: target.id,
      walletId: input.wallet.id,
      orderId: null,
      captureId: null,
      amount: "0.00",
      status: input.decision,
    });
  }
  writes.push(...tailWrites(input.wallet, recomputed));
  if (
    writes.some((w) =>
      w.kind === "insert_parent_save" || w.kind === "capture_transfer"
    )
  ) {
    throw new ScheduleError("decline must not capture or save", 500);
  }
  return {
    writes,
    fundingPercent: after,
    walletStatus: recomputed.status,
    milestones: recomputed.milestones,
    transfers,
  };
}

export function parentSaveNote(captureId: string): string {
  if (!/^[A-Za-z0-9]+$/.test(captureId)) {
    throw new ScheduleError("invalid capture id", 400);
  }
  return `paypal capture ${captureId}`;
}

export function planCapture(input: {
  wallet: Wallet;
  milestones: readonly Milestone[];
  transfers: readonly Transfer[];
  milestoneId: string;
  transferId: string;
  captureId: string;
  amount: string;
  asOf: string;
  alreadyRecorded: boolean;
  withdrawals?: readonly { amount: string }[];
}): { writes: WalletWrite[]; walletStatus: WalletStatus; amount: string } {
  const amount = centsToDollars(dollarsToCents(input.amount));
  const cents = dollarsToCents(amount);
  if (cents <= 0) {
    throw new ScheduleError("capture amount must be positive", 409);
  }
  const target = input.milestones.find((m) => m.id === input.milestoneId);
  if (!target) throw new ScheduleError("milestone not found", 404);
  if (target.status === "skipped" || target.status === "declined") {
    throw new ScheduleError("milestone already settled", 409);
  }
  const transfer = input.transfers.find((t) => t.id === input.transferId);
  if (!transfer || transfer.milestoneId !== target.id) {
    throw new ScheduleError("transfer not found", 404);
  }
  const note = parentSaveNote(input.captureId);
  const transfers = input.transfers.map((t) =>
    t.id === transfer.id
      ? {
        ...t,
        status: "captured" as const,
        amount,
        captureId: input.captureId,
      }
      : t
  );
  const milestones = input.milestones.map((m) =>
    m.id === target.id ? { ...m, status: "captured" as const } : m
  );
  const recomputed = recomputeSchedule({
    wallet: input.wallet,
    milestones,
    transfers,
    asOf: input.asOf,
    withdrawnCents: withdrawnCents(input.withdrawals ?? []),
  });
  const writes: WalletWrite[] = [];
  if (!input.alreadyRecorded) {
    writes.push({
      kind: "capture_transfer",
      id: transfer.id,
      captureId: input.captureId,
      amount,
    });
  }
  if (target.status !== "captured") {
    writes.push({
      kind: "update_milestone",
      id: target.id,
      status: "captured",
    });
  }
  writes.push(...tailWrites(input.wallet, recomputed));
  writes.push({
    kind: "insert_parent_save",
    goalId: input.wallet.goalId,
    amount,
    note,
  });
  const saves = writes.filter((w) => w.kind === "insert_parent_save");
  if (
    saves.length !== 1 || saves[0].kind !== "insert_parent_save" ||
    saves[0].amount !== amount
  ) {
    throw new ScheduleError("capture must record one parent save", 500);
  }
  return { writes, walletStatus: recomputed.status, amount };
}

export function planWithdraw(input: {
  wallet: Wallet;
  milestones: readonly Milestone[];
  transfers: readonly Transfer[];
  withdrawals: readonly { amount: string }[];
  amount: string;
  note: string;
  asOf: string;
}): {
  writes: WalletWrite[];
  fundingPercent: number;
  walletStatus: WalletStatus;
  amount: string;
  withdrawnCents: number;
  milestones: Milestone[];
} {
  const cents = dollarsToCents(input.amount);
  if (cents <= 0) {
    throw new ScheduleError("withdraw amount must be positive", 409);
  }
  const captured = capturedCents(input.transfers);
  const already = withdrawnCents(input.withdrawals);
  if (cents > captured - already) {
    throw new ScheduleError("withdraw exceeds captured balance", 409);
  }
  const totalWithdrawn = already + cents;
  const recomputed = recomputeSchedule({
    wallet: input.wallet,
    milestones: input.milestones,
    transfers: input.transfers,
    asOf: input.asOf,
    withdrawnCents: totalWithdrawn,
  });
  const writes: WalletWrite[] = [{
    kind: "insert_withdrawal",
    walletId: input.wallet.id,
    amount: centsToDollars(cents),
    note: input.note,
  }];
  writes.push(...tailWrites(input.wallet, recomputed));
  const forbidden = writes.some((w) =>
    w.kind === "capture_transfer" || w.kind === "insert_transfer" ||
    w.kind === "insert_parent_save" || w.kind === "update_milestone"
  );
  if (forbidden) {
    throw new ScheduleError("withdraw must not touch transfers or saves", 500);
  }
  return {
    writes,
    fundingPercent: goalFundingPercent(
      input.wallet.goalAmount,
      input.transfers,
      totalWithdrawn,
    ),
    walletStatus: recomputed.status,
    amount: centsToDollars(cents),
    withdrawnCents: totalWithdrawn,
    milestones: recomputed.milestones,
  };
}
