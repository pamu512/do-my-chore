-- Rev 3 money model: kid earns 100% via weighted chores (once|daily|weekly);
-- parent is the financial planner (goal_mode, cost, parent_save_entries).
-- Approvals stop minting ledger credits from chore rewards.

-- ============ goals ============

alter table public.goals
  add column if not exists goal_mode text not null default 'kid_item'
    check (goal_mode in ('family_trip', 'kid_item')),
  add column if not exists allow_makeup boolean not null default false,
  add column if not exists kid_id uuid references public.profiles(id) on delete set null;

-- ============ chores ============

-- Backfill reward_amount into weight_pct before dropping it, so existing rows
-- keep a sensible weight.
alter table public.chores
  add column if not exists cadence text not null default 'once'
    check (cadence in ('once', 'daily', 'weekly')),
  add column if not exists weight_pct numeric(6,2) not null default 1
    check (weight_pct > 0),
  add column if not exists is_makeup boolean not null default false,
  add column if not exists is_bonus boolean not null default false,
  add column if not exists kid_id uuid references public.profiles(id) on delete set null;

update public.chores set weight_pct = 10 where weight_pct = 1;

alter table public.chores
  drop column if exists reward_amount,
  drop column if exists default_split_goal_pct;

-- ============ parent_save_entries ============

create table public.parent_save_entries (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  goal_id uuid not null references public.goals(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  note text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index idx_parent_save_family on public.parent_save_entries(family_id);
create index idx_parent_save_goal on public.parent_save_entries(goal_id);

alter table public.parent_save_entries enable row level security;

create policy "parent_save_read" on public.parent_save_entries for select to authenticated
  using (family_id = public.current_family_id());
create policy "parent_save_insert" on public.parent_save_entries for insert to authenticated
  with check (family_id = public.current_family_id() and public.is_parent());

-- ============ approve RPC: status flip only ============
-- Progress is derived from approved submissions x instance credits; the RPC
-- no longer writes ledger entries from chore rewards.

create or replace function public.approve_chore_submission(p_submission_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_family_id uuid;
  v_kid_id uuid;
  v_chore_id uuid;
begin
  if not exists (
    select 1 from profiles
    where id = auth.uid() and role = 'parent'
      and family_id = (select family_id from chore_submissions where id = p_submission_id)
  ) then
    raise exception 'only a parent of this family can approve';
  end if;

  select s.family_id, s.kid_id, s.chore_id
    into v_family_id, v_kid_id, v_chore_id
  from chore_submissions s
  where s.id = p_submission_id and s.status = 'pending'
  for update;

  if v_chore_id is null then
    raise exception 'submission not found or already decided';
  end if;

  update chore_submissions
     set status = 'approved', decided_at = now()
   where id = p_submission_id;
end;
$$;

-- ============ goals RLS additions: kid scoped rows stay family-visible ============
-- kid_id is informational in the POC (one kid per goal, no cross-family
-- exposure risk: goals are already family-scoped). No new policies needed.
