-- Atomic approve: flips the submission to approved and writes BOTH ledger
-- entries (goal credit + pocket overshoot) in one transaction, so the money
-- rule "fill goal to target, remainder to pocket" cannot tear.

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
  v_reward numeric(12,2);
  v_split_pct int;
  v_goal_id uuid;
  v_target numeric(12,2);
  v_goal_bank numeric(12,2);
  v_goal_share numeric(12,2);
  v_pocket_share numeric(12,2);
  v_goal_credit numeric(12,2);
  v_pocket_credit numeric(12,2);
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

  select c.reward_amount, c.default_split_goal_pct, g.id, g.target_amount
    into v_reward, v_split_pct, v_goal_id, v_target
  from chores c join goals g on g.id = c.goal_id
  where c.id = v_chore_id;

  -- balances are computed on read, always
  select coalesce(sum(amount), 0) into v_goal_bank
  from ledger_entries
  where goal_id = v_goal_id and kind in ('goal_credit', 'parent_topup');

  -- reward split by chore percentage, goal share capped at target
  v_goal_share := round(v_reward * v_split_pct / 100.0, 2);
  v_pocket_share := round(v_reward - v_goal_share, 2);

  v_goal_credit := least(v_goal_share, greatest(v_target - v_goal_bank, 0));
  v_pocket_credit := v_pocket_share + (v_goal_share - v_goal_credit);

  update chore_submissions
     set status = 'approved', decided_at = now()
   where id = p_submission_id;

  if v_goal_credit > 0 then
    insert into ledger_entries (family_id, goal_id, kind, amount, submission_id, created_by)
    values (v_family_id, v_goal_id, 'goal_credit', v_goal_credit, p_submission_id, auth.uid());
  end if;

  if v_pocket_credit > 0 then
    insert into ledger_entries (family_id, goal_id, kind, amount, submission_id, created_by)
    values (v_family_id, v_goal_id, 'pocket_credit', v_pocket_credit, p_submission_id, auth.uid());
  end if;
end;
$$;
