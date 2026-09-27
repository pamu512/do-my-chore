-- Do My Chore — initial schema (design rev 2)
-- Money truth lives in ledger_entries; goals carry NO balance column.
-- chore_submissions carries a denormalized family_id so RLS policies stay join-free.

create extension if not exists pgcrypto with schema extensions;

-- ============ tables ============

create table public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_at timestamptz not null default now()
);

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  family_id uuid not null references public.families(id) on delete cascade,
  role text not null check (role in ('parent', 'kid')),
  display_name text not null,
  created_at timestamptz not null default now()
);

create table public.goals (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  title text not null,
  target_amount numeric(12,2) not null check (target_amount > 0),
  target_date date,
  status text not null default 'active' check (status in ('active', 'achieved', 'archived')),
  created_at timestamptz not null default now()
);
-- NOTE: intentionally no balance column — balances are summed from ledger_entries on read.

create table public.chores (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null references public.goals(id) on delete cascade,
  title text not null,
  reward_amount numeric(12,2) not null check (reward_amount > 0),
  default_split_goal_pct int not null default 100 check (default_split_goal_pct between 0 and 100),
  requires_photo boolean not null default false,
  archived boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.chore_submissions (
  id uuid primary key default gen_random_uuid(),
  chore_id uuid not null references public.chores(id) on delete cascade,
  family_id uuid not null references public.families(id) on delete cascade,
  kid_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  photo_url text,
  ai_photo_result jsonb,
  reject_nudge text,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.ledger_entries (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  goal_id uuid references public.goals(id) on delete set null,
  kind text not null check (kind in ('goal_credit', 'pocket_credit', 'parent_topup')),
  amount numeric(12,2) not null check (amount > 0),
  submission_id uuid references public.chore_submissions(id) on delete set null,
  note text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create table public.ai_plans (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null references public.goals(id) on delete cascade,
  family_id uuid not null references public.families(id) on delete cascade,
  suggestion jsonb not null,
  accepted boolean not null default false,
  source text not null default 'deterministic' check (source in ('llm', 'deterministic')),
  created_at timestamptz not null default now()
);

create table public.album_items (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null references public.goals(id) on delete cascade,
  family_id uuid not null references public.families(id) on delete cascade,
  photo_url text not null,
  chore_submission_id uuid references public.chore_submissions(id) on delete set null,
  caption text,
  added_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index idx_profiles_family on public.profiles(family_id);
create index idx_goals_family on public.goals(family_id);
create index idx_chores_goal on public.chores(goal_id);
create index idx_submissions_family on public.chore_submissions(family_id, status);
create index idx_submissions_chore on public.chore_submissions(chore_id);
create index idx_ledger_family on public.ledger_entries(family_id, kind);
create index idx_ledger_goal on public.ledger_entries(goal_id);
create index idx_album_family on public.album_items(family_id);
create index idx_album_goal on public.album_items(goal_id);

-- ============ RLS helpers ============
-- SECURITY DEFINER avoids recursive policy evaluation on profiles.

create or replace function public.current_family_id() returns uuid
language sql stable security definer set search_path = public as $$
  select family_id from public.profiles where id = auth.uid();
$$;

create or replace function public.is_parent() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'parent'
  );
$$;

-- ============ RLS: enable + policies ============

alter table public.families enable row level security;
alter table public.profiles enable row level security;
alter table public.goals enable row level security;
alter table public.chores enable row level security;
alter table public.chore_submissions enable row level security;
alter table public.ledger_entries enable row level security;
alter table public.ai_plans enable row level security;
alter table public.album_items enable row level security;

-- families: read own only
create policy "family_read" on public.families for select to authenticated
  using (id = public.current_family_id());

-- profiles: family reads itself; writes stay with service role (seed/demo toggle is client-side state)
create policy "profiles_read" on public.profiles for select to authenticated
  using (family_id = public.current_family_id());

-- goals: family reads; parent writes
create policy "goals_read" on public.goals for select to authenticated
  using (family_id = public.current_family_id());
create policy "goals_parent_write" on public.goals for all to authenticated
  using (family_id = public.current_family_id() and public.is_parent())
  with check (family_id = public.current_family_id() and public.is_parent());

-- chores: family reads; parent writes
create policy "chores_read" on public.chores for select to authenticated
  using (exists (
    select 1 from public.goals g
    where g.id = chores.goal_id and g.family_id = public.current_family_id()
  ));
create policy "chores_parent_write" on public.chores for all to authenticated
  using (exists (
    select 1 from public.goals g
    where g.id = chores.goal_id and g.family_id = public.current_family_id()
  ) and public.is_parent())
  with check (exists (
    select 1 from public.goals g
    where g.id = chores.goal_id and g.family_id = public.current_family_id()
  ) and public.is_parent());

-- chore_submissions: family reads; kid inserts own; parent decides (update)
create policy "submissions_read" on public.chore_submissions for select to authenticated
  using (family_id = public.current_family_id());
create policy "submissions_kid_insert" on public.chore_submissions for insert to authenticated
  with check (family_id = public.current_family_id() and kid_id = auth.uid());
create policy "submissions_parent_update" on public.chore_submissions for update to authenticated
  using (family_id = public.current_family_id() and public.is_parent())
  with check (family_id = public.current_family_id());

-- ledger_entries: family reads; parent appends; nobody updates/deletes (immutable ledger)
create policy "ledger_read" on public.ledger_entries for select to authenticated
  using (family_id = public.current_family_id());
create policy "ledger_parent_insert" on public.ledger_entries for insert to authenticated
  with check (family_id = public.current_family_id() and public.is_parent());

-- ai_plans: family reads; parent writes
create policy "ai_plans_read" on public.ai_plans for select to authenticated
  using (family_id = public.current_family_id());
create policy "ai_plans_parent_write" on public.ai_plans for all to authenticated
  using (family_id = public.current_family_id() and public.is_parent())
  with check (family_id = public.current_family_id() and public.is_parent());

-- album_items: family reads; parent adds and deletes
create policy "album_read" on public.album_items for select to authenticated
  using (family_id = public.current_family_id());
create policy "album_parent_insert" on public.album_items for insert to authenticated
  with check (family_id = public.current_family_id() and public.is_parent());
create policy "album_parent_delete" on public.album_items for delete to authenticated
  using (family_id = public.current_family_id() and public.is_parent());

-- ============ storage ============

insert into storage.buckets (id, name, public)
values ('chore-photos', 'chore-photos', false)
on conflict (id) do nothing;

-- object paths are prefixed by family_id: <family_id>/<submission_id>.jpg
create policy "photos_family_read" on storage.objects for select to authenticated
  using (bucket_id = 'chore-photos' and (storage.foldername(name))[1] = public.current_family_id()::text);
create policy "photos_family_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'chore-photos' and (storage.foldername(name))[1] = public.current_family_id()::text);
create policy "photos_parent_delete" on storage.objects for delete to authenticated
  using (bucket_id = 'chore-photos' and (storage.foldername(name))[1] = public.current_family_id()::text and public.is_parent());
