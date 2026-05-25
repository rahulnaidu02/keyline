-- KeyLine demo seed data.
-- Run after migrations: `supabase db query < supabase/seed.sql`
--
-- Demo credentials (use these when calling the agent):
--   Caller A:  phone +15555550111  PIN 1234   →  authorized for PR-204, PR-301
--   Caller B:  phone +15555550222  PIN 4242   →  authorized for BLUE-7 only
--
-- Active codes:
--   PR-204  → 7391  (valid 30 days)
--   PR-301  → 8124  (valid 7 days)
--   BLUE-7  → 5566  (valid 24 hours)
--   GHOST-1 → 9999  (active but no caller is authorized — use for "denied" testing)
--
-- Re-run safe: truncates everything first.

truncate table access_logs, authorizations, codes, end_users, units, operators, orgs restart identity cascade;

with new_org as (
  insert into orgs (id, name, vendor_contact_phone)
  values ('11111111-1111-1111-1111-111111111111', 'Acme Sanitation', '+15555550000')
  returning id
)
insert into operators (org_id, email, role)
select id, 'ops@acme-sanitation.test', 'admin' from new_org;

insert into units (id, org_id, label, notes) values
  ('22222222-2222-2222-2222-222222222204', '11111111-1111-1111-1111-111111111111', 'PR-204',  'Park-row 204, downtown'),
  ('22222222-2222-2222-2222-222222222301', '11111111-1111-1111-1111-111111111111', 'PR-301',  'Park-row 301, riverfront'),
  ('22222222-2222-2222-2222-2222222207b7', '11111111-1111-1111-1111-111111111111', 'BLUE-7',  'Blue trailer #7, event circuit'),
  ('22222222-2222-2222-2222-2222222dead1', '11111111-1111-1111-1111-111111111111', 'GHOST-1', 'Test unit no one is authorized for');

insert into codes (unit_id, value, valid_until) values
  ('22222222-2222-2222-2222-222222222204', '7391', now() + interval '30 days'),
  ('22222222-2222-2222-2222-222222222301', '8124', now() + interval '7 days'),
  ('22222222-2222-2222-2222-2222222207b7', '5566', now() + interval '24 hours'),
  ('22222222-2222-2222-2222-2222222dead1', '9999', now() + interval '7 days');

-- PIN hashes use pgcrypto bcrypt (gen_salt('bf')). Stored as crypt(pin, salt).
insert into end_users (id, org_id, name, phone_e164, pin_hash) values
  ('33333333-3333-3333-3333-333333333aaa',
   '11111111-1111-1111-1111-111111111111',
   'Alex (Caller A)',
   '+15555550111',
   crypt('1234', gen_salt('bf'))),
  ('33333333-3333-3333-3333-333333333bbb',
   '11111111-1111-1111-1111-111111111111',
   'Bree (Caller B)',
   '+15555550222',
   crypt('4242', gen_salt('bf')));

insert into authorizations (end_user_id, unit_id) values
  ('33333333-3333-3333-3333-333333333aaa', '22222222-2222-2222-2222-222222222204'),
  ('33333333-3333-3333-3333-333333333aaa', '22222222-2222-2222-2222-222222222301'),
  ('33333333-3333-3333-3333-333333333bbb', '22222222-2222-2222-2222-2222222207b7');
