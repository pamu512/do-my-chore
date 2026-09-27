-- Same spoof-proof defaults for the remaining client-writable tables:
-- family identity from JWT, added_by from the caller.

alter table public.ledger_entries
  alter column family_id set default public.current_family_id();

alter table public.album_items
  alter column family_id set default public.current_family_id(),
  alter column added_by set default auth.uid();
