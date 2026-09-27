-- Do My Chore — demo seed (LOCAL DEMO ONLY)
-- Fixed UUIDs so tests and the demo video are deterministic.
-- Credentials are documented in README as demo-only; never reuse.

-- family
insert into public.families (id, name) values
  ('00000000-0000-0000-0000-000000000001', 'Demo Family');

-- auth users (email/password, confirmed)
-- GoTrue scans token columns as strings: they must be '' not NULL.
-- phone stays NULL: '' collides on users_phone_key across users.
insert into auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at,
                        confirmation_token, recovery_token, email_change,
                        email_change_token_new, email_change_token_current,
                        reauthentication_token, phone, phone_change, phone_change_token,
                        raw_app_meta_data, raw_user_meta_data)
values
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a1',
   'authenticated', 'authenticated', 'parent@demo', crypt('demo1234', gen_salt('bf')),
   now(), now(), now(), '', '', '', '', '', '', NULL, '', '',
   '{"provider":"email","providers":["email"]}', '{}'),
  ('00000000-0000-0000-0000-000000000000', '00000000-0000-0000-0000-0000000000a2',
   'authenticated', 'authenticated', 'kid@demo', crypt('demo1234', gen_salt('bf')),
   now(), now(), now(), '', '', '', '', '', '', NULL, '', '',
   '{"provider":"email","providers":["email"]}', '{}');

insert into auth.identities (user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
values
  ('00000000-0000-0000-0000-0000000000a1', 'parent@demo',
   '{"sub":"00000000-0000-0000-0000-0000000000a1","email":"parent@demo"}', 'email', now(), now(), now()),
  ('00000000-0000-0000-0000-0000000000a2', 'kid@demo',
   '{"sub":"00000000-0000-0000-0000-0000000000a2","email":"kid@demo"}', 'email', now(), now(), now());

-- profiles
insert into public.profiles (id, family_id, role, display_name) values
  ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 'parent', 'Priya'),
  ('00000000-0000-0000-0000-0000000000a2', '00000000-0000-0000-0000-000000000001', 'kid', 'Arjun');

-- goal: Disneyland $500 by Dec 15
insert into public.goals (id, family_id, title, target_amount, target_date, status) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001',
   'Disneyland', 500.00, date '2026-12-15', 'active');

-- chores: mix of visually verifiable (requires_photo) and trust-based
insert into public.chores (id, goal_id, title, reward_amount, default_split_goal_pct, requires_photo) values
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b1', 'Clean the play table', 5.00, 80, true),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000b1', 'Wash the dishes', 4.00, 80, true),
  ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000b1', 'Read for 20 minutes', 3.00, 100, false),
  ('00000000-0000-0000-0000-0000000000c4', '00000000-0000-0000-0000-0000000000b1', 'Make your bed', 2.00, 100, false),
  ('00000000-0000-0000-0000-0000000000c5', '00000000-0000-0000-0000-0000000000b1', 'Fold the laundry', 4.00, 60, false),
  ('00000000-0000-0000-0000-0000000000c6', '00000000-0000-0000-0000-0000000000b1', 'Take out the recycling', 3.00, 100, false);

-- accepted AI plan (feeds the parent weeks-to-goal card: $500 target, $25/week top-up)
insert into public.ai_plans (goal_id, family_id, suggestion, accepted, source) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001',
   '{"weekly_topup": 25, "weeks_estimate": 20, "why": "At $25 a week from you plus about $21 in chores, Arjun hits $500 before mid-December without either of you feeling the pinch.", "chores": []}',
   true, 'deterministic');
