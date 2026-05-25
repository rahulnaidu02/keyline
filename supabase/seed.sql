-- KeyLine demo seed data.
-- Run after migrations: `supabase db query --linked -f supabase/seed.sql`
--
-- Demo units & policies:
--   PR-204    restricted   →  Caller A (+15555550111) on allowlist   →  code 7391
--   PR-301    restricted   →  Caller A (+15555550111) on allowlist   →  code 8124
--   BLUE-7    open         →  anyone with the unit name              →  code 5566
--   GHOST-1   restricted   →  nobody on allowlist (for denial demo)  →  code 9999
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

insert into units (id, org_id, label, notes, access_policy) values
  ('22222222-2222-2222-2222-222222222204', '11111111-1111-1111-1111-111111111111', 'PR-204',  'Park-row 204, downtown',          'restricted'),
  ('22222222-2222-2222-2222-222222222301', '11111111-1111-1111-1111-111111111111', 'PR-301',  'Park-row 301, riverfront',        'restricted'),
  ('22222222-2222-2222-2222-2222222207b7', '11111111-1111-1111-1111-111111111111', 'BLUE-7',  'Blue trailer #7, public event',   'open'),
  ('22222222-2222-2222-2222-2222222dead1', '11111111-1111-1111-1111-111111111111', 'GHOST-1', 'Test unit no one is authorized for','restricted');

insert into codes (unit_id, value, valid_until) values
  ('22222222-2222-2222-2222-222222222204', '7391', now() + interval '30 days'),
  ('22222222-2222-2222-2222-222222222301', '8124', now() + interval '7 days'),
  ('22222222-2222-2222-2222-2222222207b7', '5566', now() + interval '24 hours'),
  ('22222222-2222-2222-2222-2222222dead1', '9999', now() + interval '7 days');

insert into end_users (id, org_id, name, phone_e164) values
  ('33333333-3333-3333-3333-333333333aaa',
   '11111111-1111-1111-1111-111111111111',
   'Alex (Caller A)',
   '+15555550111');

insert into authorizations (end_user_id, unit_id) values
  ('33333333-3333-3333-3333-333333333aaa', '22222222-2222-2222-2222-222222222204'),
  ('33333333-3333-3333-3333-333333333aaa', '22222222-2222-2222-2222-222222222301');
