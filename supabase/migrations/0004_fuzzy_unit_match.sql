-- KeyLine: forgiving unit-label matching.
-- ASR transcribes spoken labels inconsistently: "PR-204" can come through as
-- "P R 204", "pr two oh four", "P-R 204", "PR204". We strip every non-
-- alphanumeric character on both sides so any of those match the canonical
-- label. The LLM still does word-number → digit conversion in the prompt.

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
  where regexp_replace(lower(u.label), '[^a-z0-9]', '', 'g')
      = regexp_replace(lower(p_unit_label), '[^a-z0-9]', '', 'g')
  order by c.created_at desc nulls last
  limit 1;
$$;
