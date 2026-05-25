# 03 — Design

## System diagram

```
                  ┌──────────────────────────────────┐
                  │   End user phone (PSTN / mobile) │
                  │   or Vapi web call widget        │
                  └──────────────┬───────────────────┘
                                 ▼
                       ┌─────────────────────┐
                       │        Vapi         │
                       │ telephony · ASR · LLM · TTS │
                       └──────────┬──────────┘
                                  │ HTTPS function-call
                                  │ (x-vapi-secret header)
                                  ▼
                ┌─────────────────────────────────────┐
                │  Supabase Edge Function: get_code   │
                │  (Deno, service-role client)        │
                └──────────┬──────────────────────────┘
                           │ RPC
                           ▼
                ┌────────────────────────┐
                │   Supabase Postgres    │
                │  verify_caller()       │
                │  get_active_code()     │
                │  log_access()          │
                └────────────────────────┘
```

## Data model

See `supabase/migrations/0001_init.sql` for the source of truth. Key tables:

- `orgs` — one row per operator company (multi-tenant boundary).
- `units` — physical lock units. `(org_id, label)` is unique.
- `codes` — code values per unit. Multiple rows allowed; only one row per unit has `active = true`. Time-bounded by `valid_from / valid_until`.
- `end_users` — callers. Identified by `phone_e164`, authenticated by bcrypt'd `pin_hash`. Has rate-limit fields (`failed_attempts`, `locked_until`).
- `authorizations` — which end users can access which units, time-bounded.
- `access_logs` — append-only audit log keyed by Vapi `call_id`.

## Auth design

Two-factor by construction: **caller phone + PIN**. Phone alone is too spoofable; PIN alone has no identity. Together, the false-accept rate is negligible for our threat model (opportunistic attacker, not a nation-state).

Failure handling:
- ≤4 failed attempts: PIN re-entry allowed, counter incremented.
- 5th failed attempt: phone locked for 15 minutes (`locked_until`).
- All failures logged to `access_logs` with reason.

## Voice agent design

**One tool, one happy path.** The LLM does not branch over multiple tools; it gathers `phone + pin + unit_label`, calls `get_code` once, and reads the result. This keeps the prompt simple and the eval surface small.

Future tools (post-MVP):
- `escalate_to_human(reason, summary)` — currently we'll just use Vapi's built-in `transferCall`.
- `rotate_code(unit_id, new_value, expires_at)` — operator-only, voice-based code rotation. Out of scope for v1.

See `vapi/system-prompt.md` for the full agent contract and `vapi/tools.json` for the function schema.

## Code-hallucination guardrail

The single most dangerous failure mode is the LLM inventing a 4-digit code. Two layers of defense:

1. **Prompt-level.** System prompt instructs the model that the only valid source of a digit string is the `code` field of a successful tool result, with a self-check before speaking.
2. **Output filter (future).** Post-process every assistant turn: regex out any 4-digit sequence not present in the latest tool result. If found, replace the turn with a canned apology and escalate.

For v1 we ship layer 1 and add layer 2 the moment we see a regression in evals.

## NFR targets (recap)

| | Target |
|---|---|
| End-to-end turn latency | P50 < 1.2s, P95 < 2.0s |
| Tool round-trip | P95 < 300ms |
| Reliability | 99.5% monthly |
| Code-hallucination rate | 0% (hard gate) |
| Resolution rate | ≥ 85% |
| WER (clean / noisy) | ≤ 8% / ≤ 15% |

## Why this architecture (and not alternatives)

| Alternative | Why we didn't | 
|---|---|
| Stuff all logic into the Vapi system prompt (no DB) | No audit trail, no rotation, no per-user authz. Demo only. |
| Run our own Next.js API instead of Supabase Edge Functions | Same DB anyway; Supabase functions are zero-ops and co-located with Postgres. |
| Use Twilio + custom STT/TTS/LLM | 3–4 weeks of integration work. Vapi is the boring choice. |
| Smart-lock integration (Yale, Latch) | Customer doesn't want to replace hardware. Different business. |
