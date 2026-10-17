import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  capturedCents,
  dollarsToCents,
  goalFundingPercent,
  periodsLeft,
  planCapture,
  planDecline,
  recomputeSchedule,
  splitShortfallCents,
  type Milestone,
  type Transfer,
  type Wallet,
} from "./funding_schedule.ts";

const wallet = (over: Partial<Wallet> = {}): Wallet => ({
  id: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
  goalId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
  goalAmount: "10.00",
  goalDate: "2026-11-07",
  cadence: "weekly",
  status: "active",
  currency: "USD",
  ...over,
});

Deno.test("split puts the remainder on the last period", () => {
  assertEquals(splitShortfallCents(100, 3), [33, 33, 34]);
  assertEquals(splitShortfallCents(100, 3).reduce((a, b) => a + b, 0), 100);
});

Deno.test("recompute splits 100 cents across 3 Mondays as 33, 33, 34", () => {
  const result = recomputeSchedule({
    wallet: wallet({ goalAmount: "1.00", goalDate: "2026-11-02" }),
    milestones: [],
    transfers: [],
    asOf: "2026-10-17",
  });
  assertEquals(periodsLeft("2026-11-02", "2026-10-17"), [
    "2026-10-19",
    "2026-10-26",
    "2026-11-02",
  ]);
  assertEquals(result.insertRows.map((r) => r.proposedAmount), ["0.33", "0.33", "0.34"]);
  assertEquals(
    result.insertRows.reduce((sum, r) => sum + dollarsToCents(r.proposedAmount), 0),
    100,
  );
  assertEquals(result.status, "active");
});

Deno.test("empty weekly grid is one period on goal_date while the goal is ahead", () => {
  assertEquals(periodsLeft("2026-10-21", "2026-10-20"), ["2026-10-21"]);
  const result = recomputeSchedule({
    wallet: wallet({ goalAmount: "5.00", goalDate: "2026-10-21" }),
    milestones: [],
    transfers: [],
    asOf: "2026-10-20",
  });
  assertEquals(result.insertRows, [{ dueDate: "2026-10-21", proposedAmount: "5.00" }]);
});

Deno.test("no periods left marks the wallet short and adds no date after the goal", () => {
  const result = recomputeSchedule({
    wallet: wallet({ goalAmount: "5.00", goalDate: "2026-10-21" }),
    milestones: [],
    transfers: [],
    asOf: "2026-10-22",
  });
  assertEquals(periodsLeft("2026-10-21", "2026-10-22"), []);
  assertEquals(result.status, "short");
  assertEquals(result.insertRows, []);
  assertEquals(result.milestones.some((m) => m.dueDate > "2026-10-21"), false);
});

Deno.test("decline keeps the capture, writes a zero transfer, and resplits the shortfall", () => {
  const w = wallet();
  const milestones: Milestone[] = [
    { id: "cap", dueDate: "2026-10-12", proposedAmount: "4.00", status: "captured" },
    { id: "skip", dueDate: "2026-10-05", proposedAmount: "1.00", status: "skipped" },
    { id: "dec", dueDate: "2026-10-19", proposedAmount: "2.00", status: "proposed" },
    { id: "old", dueDate: "2026-10-26", proposedAmount: "2.00", status: "proposed" },
    { id: "apr", dueDate: "2026-11-02", proposedAmount: "2.00", status: "approved" },
  ];
  const transfers: Transfer[] = [
    {
      id: "t-cap",
      milestoneId: "cap",
      orderId: "ORDER1",
      captureId: "CAP1",
      amount: "4.00",
      status: "captured",
    },
  ];
  const before = goalFundingPercent(w.goalAmount, transfers);
  const result = planDecline({
    wallet: w,
    milestones,
    transfers,
    milestoneId: "dec",
    decision: "declined",
    asOf: "2026-10-17",
  });
  assertEquals(result.milestones.find((m) => m.id === "cap"), milestones[0]);
  assertEquals(result.milestones.find((m) => m.id === "skip")?.status, "skipped");
  assertEquals(result.milestones.find((m) => m.id === "dec")?.status, "declined");
  assertEquals(result.milestones.some((m) => m.id === "old" || m.id === "apr"), false);
  const declined = result.transfers.find((t) => t.milestoneId === "dec");
  assertEquals(declined?.amount, "0.00");
  assertEquals(declined?.captureId, null);
  assertEquals(declined?.status, "declined");
  assertEquals(result.fundingPercent, before);
  assertEquals(goalFundingPercent(w.goalAmount, result.transfers), before);
  assertEquals(capturedCents(result.transfers), 400);
  const proposed = result.milestones.filter((m) => m.status === "proposed");
  const proposedCents = proposed.reduce((sum, m) => sum + dollarsToCents(m.proposedAmount), 0);
  const shortfall = dollarsToCents(w.goalAmount) - capturedCents(result.transfers);
  assertEquals(proposedCents, shortfall);
  assertEquals(proposed.map((m) => m.proposedAmount), ["3.00", "3.00"]);
  assertEquals(result.milestones.some((m) => m.dueDate > w.goalDate), false);
  const save = result.writes.find((w) => w.kind === "insert_parent_save");
  assertEquals(save, undefined);
  const transferWrite = result.writes.find((w) => w.kind === "insert_transfer");
  assertEquals(transferWrite?.kind === "insert_transfer" ? transferWrite.amount : "", "0.00");
  assertEquals(transferWrite?.kind === "insert_transfer" ? transferWrite.captureId : "x", null);
});

Deno.test("repeating a decline does not insert a second zero transfer", () => {
  const w = wallet();
  const first = planDecline({
    wallet: w,
    milestones: [
      { id: "cap", dueDate: "2026-10-12", proposedAmount: "4.00", status: "captured" },
      { id: "dec", dueDate: "2026-10-19", proposedAmount: "2.00", status: "proposed" },
    ],
    transfers: [
      { id: "t-cap", milestoneId: "cap", orderId: "ORDER1", captureId: "CAP1", amount: "4.00", status: "captured" },
    ],
    milestoneId: "dec",
    decision: "declined",
    asOf: "2026-10-17",
  });
  const again = planDecline({
    wallet: { ...w, status: first.walletStatus },
    milestones: first.milestones.map((m, i) => ({ ...m, id: m.id || `new-${i}` })),
    transfers: first.transfers.map((t, i) => ({ ...t, id: t.id || `new-t-${i}` })),
    milestoneId: "dec",
    decision: "declined",
    asOf: "2026-10-17",
  });
  assertEquals(again.writes.some((w) => w.kind === "insert_transfer"), false);
  assertEquals(again.transfers.filter((t) => t.milestoneId === "dec").length, 1);
  assertEquals(again.fundingPercent, first.fundingPercent);
});

Deno.test("captured money is only status captured, and a funded wallet adds no tail", () => {
  const transfers: Transfer[] = [
    { id: "1", milestoneId: "m", orderId: "O", captureId: "C", amount: "10.00", status: "captured" },
    { id: "2", milestoneId: "n", orderId: null, captureId: null, amount: "0.00", status: "declined" },
    { id: "3", milestoneId: "p", orderId: "OPEN", captureId: null, amount: "0.00", status: "created" },
  ];
  assertEquals(goalFundingPercent("10.00", transfers), 1);
  assertEquals(goalFundingPercent("0.00", transfers), 0);
  const result = recomputeSchedule({
    wallet: wallet(),
    milestones: [{ id: "m", dueDate: "2026-10-12", proposedAmount: "10.00", status: "captured" }],
    transfers: [transfers[0]],
    asOf: "2026-10-17",
  });
  assertEquals(result.status, "funded");
  assertEquals(result.insertRows, []);
  assertEquals(result.milestones.map((m) => m.id), ["m"]);
});

Deno.test("an open order stays put and is not scheduled twice", () => {
  const milestones: Milestone[] = [
    { id: "pin", dueDate: "2026-10-19", proposedAmount: "4.00", status: "approved" },
    { id: "old", dueDate: "2026-10-26", proposedAmount: "6.00", status: "proposed" },
  ];
  const transfers: Transfer[] = [
    { id: "open", milestoneId: "pin", orderId: "ORDEROPEN", captureId: null, amount: "0.00", status: "created" },
  ];
  const result = recomputeSchedule({
    wallet: wallet(),
    milestones,
    transfers,
    asOf: "2026-10-17",
  });
  assertEquals(result.deleteIds, ["old"]);
  assertEquals(result.milestones.find((m) => m.id === "pin")?.proposedAmount, "4.00");
  const proposed = result.insertRows.reduce((sum, r) => sum + dollarsToCents(r.proposedAmount), 0);
  assertEquals(proposed, 600);
  assertEquals(proposed + dollarsToCents("4.00"), 1000);
  assertThrows(() =>
    planDecline({
      wallet: wallet(),
      milestones,
      transfers,
      milestoneId: "pin",
      decision: "declined",
      asOf: "2026-10-17",
    })
  );
});

Deno.test("capture records one parent save for the captured amount and leaves the capture row", () => {
  const milestones: Milestone[] = [
    { id: "m", dueDate: "2026-10-19", proposedAmount: "4.00", status: "approved" },
    { id: "later", dueDate: "2026-10-26", proposedAmount: "6.00", status: "proposed" },
  ];
  const transfers: Transfer[] = [
    { id: "t", milestoneId: "m", orderId: "ORDER1", captureId: null, amount: "0.00", status: "created" },
  ];
  const plan = planCapture({
    wallet: wallet(),
    milestones,
    transfers,
    milestoneId: "m",
    transferId: "t",
    captureId: "CAP123",
    amount: "4.00",
    asOf: "2026-10-17",
    alreadyRecorded: false,
  });
  const saves = plan.writes.filter((w) => w.kind === "insert_parent_save");
  assertEquals(saves, [{
    kind: "insert_parent_save",
    goalId: wallet().goalId,
    amount: "4.00",
    note: "paypal capture CAP123",
  }]);
  assertEquals(plan.writes.some((w) => w.kind === "capture_transfer"), true);
  const removed = plan.writes.find((w) => w.kind === "delete_milestones");
  assertEquals(removed?.kind === "delete_milestones" ? removed.ids : [], ["later"]);
  const inserted = plan.writes.find((w) => w.kind === "insert_milestones");
  const insertedCents = inserted?.kind === "insert_milestones"
    ? inserted.rows.reduce((sum, row) => sum + dollarsToCents(row.proposedAmount), 0)
    : -1;
  assertEquals(insertedCents, 600);
  const again = planCapture({
    wallet: wallet(),
    milestones: [{ id: "m", dueDate: "2026-10-19", proposedAmount: "4.00", status: "captured" }],
    transfers: [{ id: "t", milestoneId: "m", orderId: "ORDER1", captureId: "CAP123", amount: "4.00", status: "captured" }],
    milestoneId: "m",
    transferId: "t",
    captureId: "CAP123",
    amount: "4.00",
    asOf: "2026-10-17",
    alreadyRecorded: true,
  });
  assertEquals(again.writes.some((w) => w.kind === "capture_transfer"), false);
  assertEquals(again.writes.filter((w) => w.kind === "insert_parent_save").length, 1);
});

Deno.test("funding schedule does not use requiredWeeklySave", async () => {
  const src = await Deno.readTextFile(new URL("./funding_schedule.ts", import.meta.url));
  assertEquals(src.includes("requiredWeeklySave"), false);
});

Deno.test("goal wallet migration has parent-only policies and no balance column", async () => {
  const sql = await Deno.readTextFile(
    new URL("../../migrations/20261017000000_goal_wallet.sql", import.meta.url),
  );
  const code = sql.replace(/--[^\n]*/g, "");
  assertEquals(/\bbalance\b/i.test(code), false);
  assertEquals(code.includes("check (goal_amount > 0)"), true);
  assertEquals(code.includes("default 'USD'"), true);
  assertEquals(code.includes("default 'weekly'"), true);
  assertEquals(code.includes("check (status in ('active', 'short', 'funded'))"), true);
  assertEquals(code.includes("check (proposed_amount >= 0)"), true);
  assertEquals(code.includes("check (status in ('proposed', 'approved', 'captured', 'skipped', 'declined'))"), true);
  assertEquals(code.includes("check (status in ('created', 'captured', 'declined', 'skipped'))"), true);
  assertEquals(code.includes("amount numeric(12,2) not null default 0 check (amount >= 0)"), true);
  assertEquals(code.includes("status = 'captured'"), true);
  assertEquals(code.includes("security definer"), true);
  assertEquals(code.includes("goal_funding_percent"), true);
  assertEquals(code.includes("v_amount = 0"), true);
  assertEquals(code.includes("for delete"), false);
  const policies = code.match(/create policy[\s\S]*?;/g) ?? [];
  assertEquals(policies.length, 9);
  for (const policy of policies) {
    assertEquals(policy.includes("is_parent()"), true);
    assertEquals(policy.includes("current_family_id()"), true);
  }
});
