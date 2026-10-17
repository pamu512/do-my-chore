-- Goal funding wallet. Captured money is the sum of paypal_transfers.amount
-- where status = 'captured'. goal_wallets has no balance column.
-- Kids have no policies on these tables; they call goal_funding_percent.

create unique index goals_id_family_key on public.goals (id, family_id);

create table public.goal_wallets (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null default public.current_family_id() references public.families(id) on delete cascade,
  goal_id uuid not null,
  goal_amount numeric(12,2) not null check (goal_amount > 0),
  currency text not null default 'USD' check (currency ~ '^[A-Z]{3}$'),
  cadence text not null default 'weekly' check (cadence = 'weekly'),
  goal_date date not null,
  status text not null default 'active' check (status in ('active', 'short', 'funded')),
  created_at timestamptz not null default now(),
  constraint goal_wallets_goal_id_key unique (goal_id),
  constraint goal_wallets_id_family_key unique (id, family_id),
  constraint goal_wallets_goal_family_fk foreign key (goal_id, family_id)
    references public.goals (id, family_id) on delete cascade
);

create table public.funding_milestones (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null,
  family_id uuid not null default public.current_family_id() references public.families(id) on delete cascade,
  due_date date not null,
  proposed_amount numeric(12,2) not null check (proposed_amount >= 0),
  status text not null default 'proposed'
    check (status in ('proposed', 'approved', 'captured', 'skipped', 'declined')),
  created_at timestamptz not null default now(),
  constraint funding_milestones_id_wallet_key unique (id, wallet_id),
  constraint funding_milestones_wallet_due_key unique (wallet_id, due_date),
  constraint funding_milestones_wallet_family_fk foreign key (wallet_id, family_id)
    references public.goal_wallets (id, family_id) on delete cascade
);

create table public.paypal_transfers (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null,
  milestone_id uuid not null,
  family_id uuid not null default public.current_family_id() references public.families(id) on delete cascade,
  order_id text,
  capture_id text,
  amount numeric(12,2) not null default 0 check (amount >= 0),
  status text not null check (status in ('created', 'captured', 'declined', 'skipped')),
  created_at timestamptz not null default now(),
  constraint paypal_transfers_wallet_family_fk foreign key (wallet_id, family_id)
    references public.goal_wallets (id, family_id) on delete cascade,
  constraint paypal_transfers_milestone_wallet_fk foreign key (milestone_id, wallet_id)
    references public.funding_milestones (id, wallet_id) on delete cascade,
  constraint paypal_transfers_status_amount_chk check (
    (status = 'captured' and capture_id is not null and amount > 0)
    or (status in ('declined', 'skipped') and capture_id is null and amount = 0)
    or (status = 'created' and order_id is not null and capture_id is null and amount = 0)
  )
);

create index idx_goal_wallets_family on public.goal_wallets (family_id);
create index idx_funding_milestones_family on public.funding_milestones (family_id);
create index idx_funding_milestones_wallet on public.funding_milestones (wallet_id, due_date);
create index idx_paypal_transfers_family on public.paypal_transfers (family_id);
create index idx_paypal_transfers_wallet_status on public.paypal_transfers (wallet_id, status);

create unique index paypal_transfers_order_uidx
  on public.paypal_transfers (order_id)
  where order_id is not null;

create unique index paypal_transfers_capture_uidx
  on public.paypal_transfers (capture_id)
  where capture_id is not null;

create unique index paypal_transfers_one_captured
  on public.paypal_transfers (milestone_id)
  where status = 'captured';

create unique index paypal_transfers_one_open_order
  on public.paypal_transfers (milestone_id)
  where status = 'created';

-- One ledger row per PayPal capture. parent_save_entries.amount must stay > 0,
-- so declines never insert there.
create unique index parent_save_one_paypal_capture
  on public.parent_save_entries (goal_id, note)
  where note like 'paypal capture %';

alter table public.goal_wallets enable row level security;
alter table public.funding_milestones enable row level security;
alter table public.paypal_transfers enable row level security;

create policy "goal_wallets_parent_select" on public.goal_wallets
  for select to authenticated
  using (family_id = public.current_family_id() and public.is_parent());
create policy "goal_wallets_parent_insert" on public.goal_wallets
  for insert to authenticated
  with check (family_id = public.current_family_id() and public.is_parent());
create policy "goal_wallets_parent_update" on public.goal_wallets
  for update to authenticated
  using (family_id = public.current_family_id() and public.is_parent())
  with check (family_id = public.current_family_id() and public.is_parent());

create policy "funding_milestones_parent_select" on public.funding_milestones
  for select to authenticated
  using (family_id = public.current_family_id() and public.is_parent());
create policy "funding_milestones_parent_insert" on public.funding_milestones
  for insert to authenticated
  with check (family_id = public.current_family_id() and public.is_parent());
create policy "funding_milestones_parent_update" on public.funding_milestones
  for update to authenticated
  using (family_id = public.current_family_id() and public.is_parent())
  with check (family_id = public.current_family_id() and public.is_parent());

create policy "paypal_transfers_parent_select" on public.paypal_transfers
  for select to authenticated
  using (family_id = public.current_family_id() and public.is_parent());
create policy "paypal_transfers_parent_insert" on public.paypal_transfers
  for insert to authenticated
  with check (family_id = public.current_family_id() and public.is_parent());
create policy "paypal_transfers_parent_update" on public.paypal_transfers
  for update to authenticated
  using (family_id = public.current_family_id() and public.is_parent())
  with check (family_id = public.current_family_id() and public.is_parent());

revoke all on table public.goal_wallets from anon;
revoke all on table public.funding_milestones from anon;
revoke all on table public.paypal_transfers from anon;

-- Family members only, including kids. security definer reads transfers the
-- kid cannot select. Returns 0 when the wallet is missing or the goal amount is 0.
create or replace function public.goal_funding_percent(p_goal_id uuid)
returns numeric
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_amount numeric;
  v_captured numeric;
begin
  if auth.uid() is null or not exists (
    select 1
    from public.goals g
    join public.profiles p on p.family_id = g.family_id
    where g.id = p_goal_id
      and p.id = auth.uid()
  ) then
    raise exception 'family members only';
  end if;

  select w.goal_amount
    into v_amount
  from public.goal_wallets w
  where w.goal_id = p_goal_id;

  if v_amount is null or v_amount = 0 then
    return 0;
  end if;

  select coalesce(sum(t.amount), 0)
    into v_captured
  from public.paypal_transfers t
  join public.goal_wallets w on w.id = t.wallet_id
  where w.goal_id = p_goal_id
    and t.status = 'captured';

  return v_captured / v_amount;
end;
$$;

revoke all on function public.goal_funding_percent(uuid) from public;
grant execute on function public.goal_funding_percent(uuid) to authenticated, service_role;
