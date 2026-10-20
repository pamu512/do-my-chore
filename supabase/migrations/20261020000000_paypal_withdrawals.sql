-- Mid-goal parent withdrawals, wallet-level and append-only. paypal_transfers
-- stays the capture ledger and is not altered here; captured rows are immutable.
-- Kids get no policies on this table; they keep calling goal_funding_percent.

create table public.paypal_withdrawals (
  id uuid primary key default gen_random_uuid(),
  wallet_id uuid not null,
  family_id uuid not null default public.current_family_id() references public.families(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  note text not null default '',
  created_at timestamptz not null default now(),
  constraint paypal_withdrawals_wallet_family_fk foreign key (wallet_id, family_id)
    references public.goal_wallets (id, family_id) on delete cascade
);

create index idx_paypal_withdrawals_family on public.paypal_withdrawals (family_id);
create index idx_paypal_withdrawals_wallet on public.paypal_withdrawals (wallet_id);

alter table public.paypal_withdrawals enable row level security;

-- No update or delete policy: rows can only be inserted and read.
create policy "paypal_withdrawals_parent_select" on public.paypal_withdrawals
  for select to authenticated
  using (family_id = public.current_family_id() and public.is_parent());
create policy "paypal_withdrawals_parent_insert" on public.paypal_withdrawals
  for insert to authenticated
  with check (family_id = public.current_family_id() and public.is_parent());

revoke all on table public.paypal_withdrawals from anon;

-- Kid percent follows effective money: captured minus withdrawn, clamped at 0
-- so concurrent reads can never surface a negative share.
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
  v_withdrawn numeric;
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

  select coalesce(sum(wd.amount), 0)
    into v_withdrawn
    from public.paypal_withdrawals wd
    join public.goal_wallets w on w.id = wd.wallet_id
    where w.goal_id = p_goal_id;

  return greatest(0, v_captured - v_withdrawn) / v_amount;
end;
$$;
