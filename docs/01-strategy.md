# 01 — Strategy

## Problem

Operators of physical assets that use combination locks (portable restrooms, short-term rentals, storage units, equipment lockers, event trailers) currently distribute codes by SMS, sticky notes, or phone calls to the dispatcher. This is:

- **Leaky.** Codes get shared on group chats and never rotate.
- **High-friction.** Dispatchers field "what's the code?" calls 24/7.
- **Unauditable.** No log of who got which code when.

## Solution

A voice-first access service: operators register units and rotating codes in a dashboard; their end users call one number, authenticate, and the voice agent reads back the active code. Every call is logged, codes rotate on a schedule the operator controls, and unrecoverable calls escalate to a human.

## Why voice (not SMS / app / web)

- **Universal device support.** Works on flip phones, rental phones, devices with no signal for data. PSTN is the most reliable digital channel that exists.
- **Lowest friction.** No install, no login. Scan QR → call → speak.
- **Hands-busy users.** Cleaners, contractors, event workers — gloves on, dirty hands, holding tools.
- **Audit trail.** Recorded, transcribed, structured.

## Why Vapi

We need (a) PSTN, (b) ASR, (c) TTS, (d) LLM orchestration with function calling, (e) recording + transcripts + analysis, (f) observability for latency / WER / interruption rate. Building this from Twilio + Deepgram + OpenAI + ElevenLabs is 3–4 weeks of integration. Vapi gives it to us in a day and exposes the right primitives: function tools, transfer, server webhooks, end-of-call analysis hooks.

## Target customer (initial wedge)

Portable-restroom operators. Fragmented industry (1000s of regional operators), currently using combo locks + sticky notes. Pain is acute and the contract value is recurring. Property managers (short-term rentals) are the second wedge.

## Non-goals (v1)

- We do **not** sell hardware. Existing combo locks stay in the field.
- We do **not** integrate with smart locks (Latch, Yale, August) in v1 — that's a fast-follow.
- We do **not** support multi-language in v1; Spanish is v1.1.
- We do **not** build a mobile app for end users; the phone is the app.

## Success metrics (90 days post-launch)

- 1 paying pilot operator with ≥10 units onboarded.
- ≥85% call resolution rate (caller got their code without escalating).
- ≥4.3 / 5 CSAT.
- Zero code hallucinations (hard gate).
