-- Accountability on both sides of a goal:
--   parent_end_goal lets a parent terminate a failing goal, but refuses when
--   the kid is on pace (linear projection) or has already earned the goal.
-- Pace uses whole elapsed weeks since created_at, same math as the app.

create or replace function public.parent_end_goal(p_goal_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_family_ok boolean;
  v_target date;
  v_created timestamptz;
  v_n int;
  v_elapsed int;
  v_approved_pct numeric;
begin
  -- Only a parent of the goal's family may end it.
  select exists (
    select 1
    from goals g
    join profiles p on p.family_id = g.family_id
    where g.id = p_goal_id and p.id = auth.uid() and p.role = 'parent'
  ) into v_family_ok;
  if not v_family_ok then
    raise exception 'only a parent of this family can end a goal';
  end if;

  select target_date, created_at into v_target, v_created
  from goals where id = p_goal_id;
  if v_target is null then
    raise exception 'goal has no target date';
  end if;

  -- Plan length and elapsed weeks (whole weeks, clamped to the plan window).
  v_n := greatest(1, ceil((v_target - (v_created::date))::numeric / 7)::int);
  v_elapsed := greatest(0, least(v_n,
    floor(extract(epoch from (now() - v_created)) / 604800)::int));

  -- Kid's earned percent: same credit math as the app
  -- (per chore: min(approved, expected) * weight / expected, capped at 100).
  select least(coalesce(sum(
    least(x.cnt,
      case c.cadence when 'once' then 1 when 'weekly' then v_n else 7 * v_n end)
      * c.weight_pct /
      case c.cadence when 'once' then 1 when 'weekly' then v_n else 7 * v_n end
  ), 0), 100)
  into v_approved_pct
  from chores c
  join lateral (
    select count(*)::int as cnt
    from chore_submissions s
    where s.chore_id = c.id and s.status = 'approved'
  ) x on true
  where c.goal_id = p_goal_id and c.archived = false;

  -- Accountability: the parent may not end a goal the kid is on track for.
  if v_approved_pct + 1e-6 >= 100.0 * v_elapsed / v_n then
    raise exception 'kid is on pace (% at week % of %) - the goal cannot be ended',
      v_approved_pct, v_elapsed, v_n;
  end if;

  update goals set status = 'archived' where id = p_goal_id;
end;
$$;
