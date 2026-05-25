# 06 — Launch

## Launch readiness checklist

### Functional
- [ ] All 12 eval scenarios pass with hard gates met.
- [ ] Audit log writes on every call (success and failure).
- [ ] Rate limit verified: 5 wrong PINs → 15-min lock.
- [ ] Escalation path tested: 2 failed auths → transfer.
- [ ] Codes rotate on schedule (cron job verified).

### Non-functional
- [ ] P95 turn latency < 2.0s observed over 50 test calls.
- [ ] Tool round-trip P95 < 300ms (Supabase function metrics).
- [ ] Recording + transcript captured for every call.
- [ ] Status page live (UptimeRobot or Supabase status page).
- [ ] Fallback: if Vapi unreachable, Twilio forwards toll-free → vendor cell phone.

### Compliance / safety
- [ ] Call-recording disclosure in first message ("This call is recorded...") **OR** explicit opt-in workflow.
- [ ] Privacy policy live on the operator dashboard.
- [ ] PIN hash uses bcrypt (`crypt` + `gen_salt('bf')`), verified.
- [ ] Shared secret rotated; old value invalidated.
- [ ] All Vapi → edge function traffic uses HTTPS + secret header.

### Pilot
- [ ] One operator onboarded (Acme Sanitation or equivalent).
- [ ] At least 10 units registered.
- [ ] At least 5 end users authorized.
- [ ] Operator can see logs and rotate codes in some surface (SQL editor is acceptable for v0; dashboard for v1).

## Day-1 ops

- Watch every call in real-time for the first week.
- Daily review meeting: scan all transcripts, flag anything weird, file as a new eval scenario.
- Slack alert on: any `result = 'error'`, any `escalated`, any latency P95 > 2.5s.

## Communications

- **Operators:** weekly digest email with call count, resolution rate, top 3 failures, code rotations made.
- **Internal:** weekly review of the eval set + production metrics.

## Rollback plan

If a regression slips into production:

1. **Prompt regression:** revert the system prompt in Vapi UI (Vapi versions assistants).
2. **Tool regression:** redeploy previous edge function via `supabase functions deploy get_code --no-verify-jwt` from a previous commit.
3. **Schema regression:** Supabase migrations are forward-only; have a `down.sql` ready for any destructive change. For data: PITR is on by default on Supabase Pro.
4. **Full outage:** Twilio number forwards to vendor cell.
