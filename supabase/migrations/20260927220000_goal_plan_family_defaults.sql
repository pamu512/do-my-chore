-- Parent-created goals and accepted plans come from client inserts that rely
-- on JWT-derived family identity, same as the other family tables.

alter table public.goals
  alter column family_id set default public.current_family_id();

alter table public.ai_plans
  alter column family_id set default public.current_family_id();
