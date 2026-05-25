-- KeyLine: per-unit access policy.
-- Rentors decide whether a unit is 'open' (anyone with the unit name gets the
-- code) or 'restricted' (caller phone must be on the allowlist). Default is
-- 'restricted' — safer by default.

alter table units add column if not exists access_policy text not null default 'restricted'
  check (access_policy in ('open','restricted'));

create index if not exists units_policy_idx on units (access_policy);

-- lookup_unit: returns unit metadata + active code if one exists.
-- Used by the edge function to decide whether to require caller auth.
create or replace function lookup_unit(p_unit_label text)
returns table (
  unit_id uuid,
  org_id uuid,
  unit_label text,
  access_policy text,
  code_value text,
  valid_until timestamptz
)
language sql
security definer
as $$
  select
    u.id,
    u.org_id,
    u.label,
    u.access_policy,
    c.value,
    c.valid_until
  from units u
  left join codes c
    on c.unit_id = u.id
   and c.active
   and (c.valid_until is null or c.valid_until > now())
  where lower(u.label) = lower(p_unit_label)
  order by c.created_at desc nulls last
  limit 1;
$$;

-- is_authorized: phone is on the allowlist for the given unit and not expired/revoked.
create or replace function is_authorized(p_phone text, p_unit_id uuid)
returns table (authorized boolean, end_user_id uuid)
language sql
security definer
as $$
  with caller as (
    select id from end_users
    where phone_e164 = p_phone and status = 'active'
    limit 1
  )
  select
    exists (
      select 1
      from authorizations a
      where a.end_user_id = (select id from caller)
        and a.unit_id     = p_unit_id
        and a.revoked_at is null
        and (a.valid_until is null or a.valid_until > now())
    ) as authorized,
    (select id from caller) as end_user_id;
$$;
