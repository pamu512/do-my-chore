-- Do My Chore, rev 3 demo seed (LOCAL DEMO ONLY)
-- Kid earns 100% of the goal through weighted chores; parent plans the money.
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

-- goal: Disneyland family trip, $3500, ~14 weeks out, makeup off by default
insert into public.goals (id, family_id, kid_id, title, target_amount, target_date, status, goal_mode, allow_makeup) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a2',
   'Disneyland', 3500.00, current_date + 98, 'active', 'family_trip', false);

-- chores: spec worked example. Weights sum to exactly 100%
-- bed 40 daily, dishes 30 daily, laundry 20 weekly, itinerary 10 once
insert into public.chores (id, goal_id, kid_id, title, cadence, weight_pct, requires_photo, is_makeup, is_bonus, library_chore_id) values
  ('00000000-0000-0000-0000-0000000000c1', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000a2', 'Make your bed', 'daily', 40.00, true, false, false, 'make-your-bed'),
  ('00000000-0000-0000-0000-0000000000c2', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000a2', 'Wash the dishes', 'daily', 30.00, true, false, false, 'wash-the-dishes'),
  ('00000000-0000-0000-0000-0000000000c3', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000a2', 'Fold the laundry', 'weekly', 20.00, true, false, false, 'fold-the-laundry'),
  ('00000000-0000-0000-0000-0000000000c4', '00000000-0000-0000-0000-0000000000b1',
   '00000000-0000-0000-0000-0000000000a2', 'Plan the park itinerary', 'once', 10.00, false, false, false, 'plan-the-park-itinerary');

-- accepted AI plan: parent save cadence + kid weights (no dollar rewards)
insert into public.ai_plans (goal_id, family_id, suggestion, accepted, source) values
  ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001',
   '{"weekly_parent_save": 250, "weeks_estimate": 14, "why": "Disneyland costs about $3,500 for the trip. Putting aside $250 a week for 14 weeks covers it before you go. Meanwhile Arjun earns the trip by keeping the habits going: bed and dishes most days, laundry each week, and the park plan once. The weight list adds up to 100 percent, so a perfect streak lands exactly at 100 percent.", "chores": [{"title": "Make your bed", "cadence": "daily", "weight_pct": 40, "requires_photo": true}, {"title": "Wash the dishes", "cadence": "daily", "weight_pct": 30, "requires_photo": true}, {"title": "Fold the laundry", "cadence": "weekly", "weight_pct": 20, "requires_photo": true}, {"title": "Plan the park itinerary", "cadence": "once", "weight_pct": 10, "requires_photo": false}]}',
   true, 'deterministic');
