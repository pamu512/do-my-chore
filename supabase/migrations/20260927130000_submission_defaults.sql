-- Client inserts stay minimal and spoof-proof: family/kid identity comes
-- from the JWT defaults, and RLS still validates any explicit value.

alter table public.chore_submissions
  alter column family_id set default public.current_family_id(),
  alter column kid_id set default auth.uid();
