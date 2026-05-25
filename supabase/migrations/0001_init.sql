-- KeyLine initial schema
-- Multi-tenant access-control DB for the voice agent.

create extension if not exists pgcrypto;

-- ─── core tables ─────────────────────────────────────────────────────────

create table orgs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  vendor_contact_phone text,
  created_at timestamptz not null default now()
);

create table operators (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references orgs(id) on delete cascade,
  email text not null unique,
  role text not null default 'admin' check (role in ('admin','member')),
  created_at timestamptz not null default now()
);

create table units (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references orgs(id) on delete cascade,
  label text not null,
  notes text,
  created_at timestamptz not null default now(),
  unique (org_id, label)
);
create index units_label_lower_idx on units (org_id, lower(label));

create table codes (
  id uuid primary key default gen_random_uuid(),
  unit_id uuid not null references units(id) on delete cascade,
  value text not null check (value ~ '^[0-9]{4,8}$'),
  active boolean not null default true,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  created_at timestamptz not null default now()
);
create index codes_unit_active_idx on codes (unit_id) where active;

create table end_users (
  id uuid primary key default gen_random_uuid(),
  org_id uuid not null references orgs(id) on delete cascade,
  name text,
  phone_e164 text not null,
  pin_hash text not null,
  status text not null default 'active' check (status in ('active','suspended')),
  failed_attempts int not null default 0,
  locked_until timestamptz,
  created_at timestamptz not null default now(),
  unique (org_id, phone_e164)
);
create index end_users_phone_idx on end_users (phone_e164);

create table authorizations (
  id uuid primary key default gen_random_uuid(),
  end_user_id uuid not null references end_users(id) on delete cascade,
  unit_id uuid not null references units(id) on delete cascade,
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  revoked_at timestamptz,
  unique (end_user_id, unit_id)
);

create table access_logs (
  id uuid primary key default gen_random_uuid(),
  org_id uuid references orgs(id),
  unit_id uuid references units(id),
  end_user_id uuid references end_users(id),
  vapi_call_id text,
  channel text not null default 'voice',
  result text not null check (result in ('success','denied','not_found','expired','locked','escalated','error')),
  reason text,
  created_at timestamptz not null default now()
);
create index access_logs_unit_idx on access_logs (unit_id, created_at desc);
create index access_logs_call_idx on access_logs (vapi_call_id);

-- ─── RPCs the edge function will call ────────────────────────────────────

-- Verify a caller by phone + PIN. Returns end_user_id on success, null otherwise.
-- Bumps failed_attempts on miss; locks for 15 min after 5 failures.
create or replace function verify_caller(p_phone text, p_pin text)
returns table (end_user_id uuid, org_id uuid, locked boolean)
language plpgsql
security definer
as $$
declare
  v_user end_users%rowtype;
begin
  select * into v_user from end_users where phone_e164 = p_phone limit 1;

  if not found then
    return query select null::uuid, null::uuid, false;
    return;
  end if;

  if v_user.locked_until is not null and v_user.locked_until > now() then
    return query select null::uuid, v_user.org_id, true;
    return;
  end if;

  if v_user.status <> 'active' then
    return query select null::uuid, v_user.org_id, false;
    return;
  end if;

  if v_user.pin_hash = crypt(p_pin, v_user.pin_hash) then
    update end_users set failed_attempts = 0, locked_until = null where id = v_user.id;
    return query select v_user.id, v_user.org_id, false;
    return;
  else
    update end_users
       set failed_attempts = failed_attempts + 1,
           locked_until = case when failed_attempts + 1 >= 5
                              then now() + interval '15 minutes'
                              else null end
     where id = v_user.id;
    return query select null::uuid, v_user.org_id, (v_user.failed_attempts + 1 >= 5);
    return;
  end if;
end;
$$;

-- Get the active code for a unit (label match, case-insensitive) for a caller
-- who has a non-revoked, non-expired authorization. Returns one row or none.
create or replace function get_active_code(p_end_user_id uuid, p_unit_label text)
returns table (code_value text, valid_until timestamptz, unit_id uuid, unit_label text)
language sql
security definer
as $$
  select c.value, c.valid_until, u.id, u.label
  from end_users eu
  join authorizations a on a.end_user_id = eu.id
       and a.revoked_at is null
       and (a.valid_until is null or a.valid_until > now())
  join units u on u.id = a.unit_id
       and u.org_id = eu.org_id
       and lower(u.label) = lower(p_unit_label)
  join codes c on c.unit_id = u.id
       and c.active
       and (c.valid_until is null or c.valid_until > now())
  where eu.id = p_end_user_id
  order by c.created_at desc
  limit 1;
$$;

-- Convenience: log an access attempt.
create or replace function log_access(
  p_org_id uuid,
  p_unit_id uuid,
  p_end_user_id uuid,
  p_call_id text,
  p_result text,
  p_reason text
) returns void
language sql
security definer
as $$
  insert into access_logs (org_id, unit_id, end_user_id, vapi_call_id, result, reason)
  values (p_org_id, p_unit_id, p_end_user_id, p_call_id, p_result, p_reason);
$$;

-- ─── RLS (operator dashboard will need it; edge function uses service role) ──
alter table orgs           enable row level security;
alter table operators      enable row level security;
alter table units          enable row level security;
alter table codes          enable row level security;
alter table end_users      enable row level security;
alter table authorizations enable row level security;
alter table access_logs    enable row level security;
