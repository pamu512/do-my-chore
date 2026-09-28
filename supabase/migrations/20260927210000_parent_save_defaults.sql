-- Rev 3 fix: parent_save_entries client inserts must not need to pass family_id
-- or created_by; both come from the JWT like the other family tables.

alter table public.parent_save_entries
  alter column family_id set default public.current_family_id(),
  alter column created_by set default auth.uid();
