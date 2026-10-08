-- Atomic parent top-up: applies the overshoot rule to top-ups too (design
-- rev 2: "credit only enough to reach the target ... in the same
-- approval/top-up transaction"). Goal part lands as parent_topup (capped at
-- target), remainder overflows to pocket_credit, in one transaction.

create or replace function public.add_parent_topup(p_goal_id uuid, p_amount numeric)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_family_id uuid;
  v_target numeric(12,2);
  v_bank numeric(12,2);
  v_room numeric(12,2);
  v_goal_part numeric(12,2);
begin
  if p_amount is null or p_amount <= 0 then
    raise exception 'top-up must be positive';
  end if;

  select g.family_id, g.target_amount into v_family_id, v_target
  from goals g where g.id = p_goal_id;

  if v_family_id is null then
    raise exception 'goal not found';
  end if;

  if not exists (
    select 1 from profiles
    where id = auth.uid() and role = 'parent' and family_id = v_family_id
  ) then
    raise exception 'only a parent of this family can top up';
  end if;

  select coalesce(sum(amount), 0) into v_bank
  from ledger_entries
  where goal_id = p_goal_id and kind in ('goal_credit', 'parent_topup');

  v_room := greatest(v_target - v_bank, 0);
  v_goal_part := least(p_amount, v_room);

  if v_goal_part > 0 then
    insert into ledger_entries (family_id, goal_id, kind, amount, created_by)
    values (v_family_id, p_goal_id, 'parent_topup', v_goal_part, auth.uid());
  end if;

  if p_amount - v_goal_part > 0 then
    insert into ledger_entries (family_id, goal_id, kind, amount, created_by)
    values (v_family_id, p_goal_id, 'pocket_credit', p_amount - v_goal_part, auth.uid());
  end if;
end;
$$;
