-- Shared library habits: stable catalog ids on chores so the same habit
-- across active goals is one kid check-in and one parent decision.
-- Sharing is library-id only. Custom chores (null id) stay goal-private.

create table public.chore_library (
  id text primary key,
  title text not null,
  cadence text not null check (cadence in ('once', 'daily', 'weekly')),
  requires_photo boolean not null default false,
  min_age int not null default 0,
  max_age int not null default 17
);

insert into public.chore_library (id, title, cadence, requires_photo, min_age, max_age) values
  ('make-your-bed', 'Make your bed', 'daily', true, 8, 17),
  ('wash-the-dishes', 'Wash the dishes', 'daily', true, 8, 17),
  ('fold-the-laundry', 'Fold the laundry', 'weekly', true, 0, 17),
  ('plan-the-park-itinerary', 'Plan the park itinerary', 'once', false, 8, 17),
  ('tidy-your-room', 'Tidy your room', 'daily', true, 0, 7),
  ('set-and-clear-the-table', 'Set and clear the table', 'daily', true, 0, 7),
  ('plan-the-week-together', 'Plan the week together', 'once', false, 0, 7),
  ('clean-the-play-table', 'Clean the play table', 'daily', true, 0, 7),
  ('vacuum-the-living-room', 'Vacuum the living room', 'weekly', true, 8, 17),
  ('take-out-the-recycling', 'Take out the recycling', 'weekly', true, 8, 17);

alter table public.chores
  add column if not exists library_chore_id text references public.chore_library(id);

create index if not exists idx_chores_library on public.chores(library_chore_id);

-- One-time import: exact title only. Not used at runtime for sharing.
update public.chores c
   set library_chore_id = l.id
  from public.chore_library l
 where c.library_chore_id is null
   and c.title = l.title;

alter table public.chore_library enable row level security;

create policy "library_read" on public.chore_library for select to authenticated
  using (true);

-- Approve fans out to every pending submission on active chores that share
-- the same non-null library id in this family. Custom (null) never fans out.
create or replace function public.approve_chore_submission(p_submission_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_family_id uuid;
  v_chore_id uuid;
  v_library_id text;
begin
  if not exists (
    select 1 from profiles
    where id = auth.uid() and role = 'parent'
      and family_id = (select family_id from chore_submissions where id = p_submission_id)
  ) then
    raise exception 'only a parent of this family can approve';
  end if;

  select s.family_id, s.chore_id
    into v_family_id, v_chore_id
  from chore_submissions s
  where s.id = p_submission_id and s.status = 'pending'
  for update;

  if v_chore_id is null then
    raise exception 'submission not found or already decided';
  end if;

  select c.library_chore_id into v_library_id
  from chores c
  where c.id = v_chore_id;

  update chore_submissions
     set status = 'approved', decided_at = now()
   where id = p_submission_id;

  if v_library_id is not null then
    update chore_submissions s
       set status = 'approved', decided_at = now()
      from chores c
      join goals g on g.id = c.goal_id
     where s.chore_id = c.id
       and s.status = 'pending'
       and s.family_id = v_family_id
       and c.library_chore_id = v_library_id
       and c.archived = false
       and g.status = 'active';
  end if;
end;
$$;
