# 02 — Discovery

## Personas

### Operator (Owner)

- **Who:** Dispatcher / owner of a portable-restroom company, or a property manager running 10–500 STR units.
- **Day looks like:** Fields 5–30 access-code calls/day, manages combo locks across a region, struggles with rotation hygiene.
- **What they want:** Stop being the human help desk. Trust that the codes are right. See who accessed what.
- **What they don't want:** Another app to learn. A long onboarding. A flaky system that locks out their customers.

### End user (Caller)

- **Who:** Tenant, cleaner, contractor, event attendee, field worker.
- **Day looks like:** Shows up to a unit, needs the code now, possibly in poor signal, often hands-busy or gloved.
- **What they want:** 15 seconds, code, done.
- **What they don't want:** Install anything. Remember a username. Press 12 IVR menus.

### Vendor admin (us)

- **Who:** KeyLine founder.
- **Day looks like:** Watches the call dashboard, handles escalations, reviews flagged calls, ships eval improvements.
- **What they want:** Operators to never call them. Calls that resolve themselves.

## Top user journeys

1. **Field worker arriving at unit** — scans QR → call auto-dials with unit context → speaks PIN → hears code. <30s total.
2. **Cleaner without QR** — calls toll-free → speaks phone + PIN + unit name → hears code.
3. **Operator rotates a code** — logs into dashboard → unit detail page → "rotate" → enters new value + expiration → save. Next caller gets the new code.
4. **Failed auth → escalation** — caller mistypes PIN twice → agent says "let me get you a person" → Vapi transfers to vendor or operator.
5. **Operator audits a complaint** — opens unit log → filters by date → reads transcripts → exports.

## Constraints we discovered

- **Caller ID** is unreliable in commercial mobile and VOIP scenarios. Cannot be the sole auth factor.
- **PIN entry** by voice is harder than by keypad in noisy environments. Plan for DTMF fallback ("press 1-2-3-4 on your keypad").
- **Unit labels** in the wild are inconsistent: stickers may say "PR204," "PR-204," "PR 204," or "Park Row 204." Match case-insensitively and accept common variants.
- **Background noise** at portable-restroom sites includes generators and traffic. Use a noise-tolerant transcriber (Deepgram Nova-3) and add a custom-vocabulary boost for the unit-label pattern (`PR-###`, `BLUE-#`).
- **Network conditions:** Many field workers are on 1-bar LTE. Voice (PSTN) tolerates this; an app-based solution would not.

## Out-of-scope for v1 (capture so we don't drift)

- Smart-lock hardware integration.
- Multi-language.
- End-user self-service (PIN reset, etc.) by voice.
- Operator-side analytics beyond a simple log + summary.
- SMS fallback channel.
