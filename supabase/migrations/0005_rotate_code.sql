-- KeyLine: rentor can rotate a unit's code by voice.
--
-- A "rentor" is the party who owns/leases the unit. They're the only one
-- allowed to change the active code. For v1, we store one rentor phone per
-- unit directly on the units table — simplest possible model. Later this can
-- become a many-to-many table (multiple rentors per unit, or per-org rentors).

alter table units add column if not exists rentor_phone text;

-- rotate_code: verifies caller is the rentor for the unit, deactivates the
-- current active code, inserts a new one with the requested expiration.
-- Returns one row with ok + reason.
create or replace function rotate_code(
  p_caller_phone text,
  p_unit_label   text,
  p_new_value    text,
  p_valid_hours  integer
) returns table (
  ok          boolean,
  reason      text,
  unit_label  text,
  new_value   text,
  valid_until timestamptz
)
language plpgsql
security definer
as $$
declare
  v_unit         units%rowtype;
  v_valid_until  timestamptz;
begin
  -- 1. find unit (fuzzy match, same rule as lookup_unit)
  select * into v_unit from units u
   where regexp_replace(lower(u.label), '[^a-z0-9]', '', 'g')
       = regexp_replace(lower(p_unit_label), '[^a-z0-9]', '', 'g')
   limit 1;

  if not found then
    return query select false, 'unit_not_found'::text, null::text, null::text, null::timestamptz;
    return;
  end if;

  -- 2. caller must be the rentor
  if v_unit.rentor_phone is null or v_unit.rentor_phone <> p_caller_phone then
    return query select false, 'not_rentor'::text, v_unit.label, null::text, null::timestamptz;
    return;
  end if;

  -- 3. validate new code: 4-8 digits
  if p_new_value !~ '^[0-9]{4,8}$' then
    return query select false, 'invalid_code_format'::text, v_unit.label, null::text, null::timestamptz;
    return;
  end if;

  -- 4. clamp validity window: 1 hour to 90 days
  if p_valid_hours is null or p_valid_hours < 1 then
    v_valid_until := now() + interval '24 hours';
  elsif p_valid_hours > 2160 then
    v_valid_until := now() + interval '2160 hours';
  else
    v_valid_until := now() + (p_valid_hours::text || ' hours')::interval;
  end if;

  -- 5. deactivate current active code(s)
  update codes set active = false where unit_id = v_unit.id and active;

  -- 6. insert new active code
  insert into codes (unit_id, value, active, valid_until)
  values (v_unit.id, p_new_value, true, v_valid_until);

  return query select true, null::text, v_unit.label, p_new_value, v_valid_until;
end;
$$;
