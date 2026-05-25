-- KeyLine: drop PIN-based auth in favor of phone-only.
-- Rationale: portable-restroom contractors and field workers won't remember
-- PINs issued days ago. Caller-ID alone is acceptable for v1 — operator
-- pre-authorizes by phone number; abuse is auditable. PIN can return as an
-- opt-in per-unit setting later.

alter table end_users drop column if exists pin_hash;
alter table end_users drop column if exists failed_attempts;
alter table end_users drop column if exists locked_until;

drop function if exists verify_caller(text, text);

create or replace function verify_caller(p_phone text)
returns table (end_user_id uuid, org_id uuid)
language sql
security definer
as $$
  select id, org_id
  from end_users
  where phone_e164 = p_phone
    and status = 'active'
  limit 1;
$$;

-- access_logs.result CHECK already allows 'denied' / 'not_found' — no change needed.
