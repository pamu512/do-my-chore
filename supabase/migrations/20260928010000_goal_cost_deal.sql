-- Parent-only cost/deal snapshot written after Accept when the parent
-- locks a real-world estimate (or a found deal). Kid chore progress is
-- unchanged: still percent-based from weighted approvals.

alter table public.goals
  add column if not exists cost_estimate jsonb,
  add column if not exists deal_snapshot jsonb;
