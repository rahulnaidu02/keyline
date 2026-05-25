# KeyLine

Voice-first access-control service. Operators register units and rotate PIN codes; end users call a number, authenticate, and the voice agent reads back the active code.

**Stack:** Vapi (telephony + voice) → Supabase Edge Function (Deno) → Supabase Postgres.

## Repo layout

```
keyline/
├── docs/                 # Playbook-style docs (strategy → launch)
├── supabase/
│   ├── migrations/       # SQL schema
│   ├── seed.sql          # Demo data so you can call and get a code
│   └── functions/get_code/   # The single tool Vapi calls
├── vapi/
│   ├── assistant.json    # Import into Vapi
│   ├── system-prompt.md  # The agent's brain
│   └── tools.json        # Function-call schema
├── evals/                # Pre-prod test scenarios
└── .env.example
```

## Quickstart

```bash
# 1. Supabase
supabase login
supabase link --project-ref <YOUR_PROJECT_REF>
supabase db push                              # applies migrations
supabase db query < supabase/seed.sql         # loads demo users + units + codes
supabase functions deploy get_code --no-verify-jwt
supabase secrets set VAPI_SHARED_SECRET=<long_random_string>

# 2. Vapi
#   - Create new assistant in Vapi UI
#   - Paste vapi/system-prompt.md into System Prompt
#   - Add tool from vapi/tools.json (point URL at your edge function)
#   - Set server secret header to match VAPI_SHARED_SECRET
#   - Pick voice/transcriber/model of your choice

# 3. Demo call
#   - Click "Talk" button in Vapi UI (web widget)
#   - Auth with seeded credentials (see supabase/seed.sql header)
#   - Ask for "PR-204"
```

See [docs/04-build.md](docs/04-build.md) for step-by-step setup.
