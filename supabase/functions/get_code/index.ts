// KeyLine: get_code edge function
// Called by Vapi as a function tool.
//
// Flow:
//   1. Look up the unit by label (case-insensitive).
//   2. If unit not found → not_found.
//   3. If unit policy = 'open' → return active code (no auth).
//   4. If unit policy = 'restricted':
//        - If phone missing       → needs_phone (agent asks caller)
//        - If phone not authorized → denied
//        - Else                   → return code.
//
// Deploy:  supabase functions deploy get_code --no-verify-jwt
// Secrets: supabase secrets set VAPI_SHARED_SECRET=<long-random>

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SHARED_SECRET = Deno.env.get("VAPI_SHARED_SECRET")!;

const supa = createClient(SUPABASE_URL, SERVICE_ROLE, {
  auth: { persistSession: false },
});

type ToolCall = {
  id: string;
  function: { name: string; arguments: Record<string, unknown> | string };
};

type VapiRequest = {
  message: {
    type: "tool-calls";
    toolCalls: ToolCall[];
    call?: { id?: string };
  };
};

function parseArgs(args: ToolCall["function"]["arguments"]) {
  return typeof args === "string" ? JSON.parse(args) : args;
}

function reply(toolCallId: string, result: unknown) {
  return new Response(
    JSON.stringify({ results: [{ toolCallId, result: JSON.stringify(result) }] }),
    { headers: { "content-type": "application/json" } },
  );
}

async function logAccess(opts: {
  org_id: string | null;
  unit_id: string | null;
  end_user_id: string | null;
  call_id: string | null;
  result: string;
  reason: string | null;
}) {
  await supa.rpc("log_access", {
    p_org_id: opts.org_id,
    p_unit_id: opts.unit_id,
    p_end_user_id: opts.end_user_id,
    p_call_id: opts.call_id,
    p_result: opts.result,
    p_reason: opts.reason,
  });
}

Deno.serve(async (req) => {
  // ─── auth: shared-secret header from Vapi ───────────────────────────────
  if (!SHARED_SECRET || req.headers.get("x-vapi-secret") !== SHARED_SECRET) {
    return new Response("unauthorized", { status: 401 });
  }

  let body: VapiRequest;
  try {
    body = await req.json();
  } catch {
    return new Response("bad request", { status: 400 });
  }

  const toolCall = body.message?.toolCalls?.[0];
  if (!toolCall || toolCall.function.name !== "get_code") {
    return new Response("unsupported tool", { status: 400 });
  }

  const callId = body.message.call?.id ?? null;
  const args = parseArgs(toolCall.function.arguments) as {
    unit_label?: string;
    phone_e164?: string;
  };

  if (!args.unit_label) {
    return reply(toolCall.id, {
      ok: false,
      error: "missing_unit",
      message: "I need the unit name from the sticker.",
    });
  }

  // ─── 1. look up the unit + active code + policy ─────────────────────────
  const { data: uData, error: uErr } = await supa.rpc("lookup_unit", {
    p_unit_label: args.unit_label,
  });
  if (uErr) {
    console.error("lookup_unit error", uErr);
    return reply(toolCall.id, {
      ok: false,
      error: "internal",
      message: "Something went wrong on my end. Let me transfer you.",
    });
  }
  const unit = Array.isArray(uData) ? uData[0] : uData;

  if (!unit) {
    await logAccess({ org_id: null, unit_id: null, end_user_id: null, call_id: callId, result: "not_found", reason: `unit ${args.unit_label} does not exist` });
    return reply(toolCall.id, {
      ok: false,
      error: "not_found",
      message: `I don't have a unit named ${args.unit_label}. Can you check the sticker on the unit and try again?`,
    });
  }

  if (!unit.code_value) {
    await logAccess({ org_id: unit.org_id, unit_id: unit.unit_id, end_user_id: null, call_id: callId, result: "not_found", reason: "no active code" });
    return reply(toolCall.id, {
      ok: false,
      error: "no_active_code",
      message: `There's no active code for ${unit.unit_label} right now. Let me transfer you to a person.`,
    });
  }

  // ─── 2. open units: deliver the code, no auth required ──────────────────
  if (unit.access_policy === "open") {
    await logAccess({ org_id: unit.org_id, unit_id: unit.unit_id, end_user_id: null, call_id: callId, result: "success", reason: "open_policy" });
    return reply(toolCall.id, {
      ok: true,
      policy: "open",
      unit_label: unit.unit_label,
      code: unit.code_value,
      valid_until: unit.valid_until,
      message: `Code for ${unit.unit_label} is ${unit.code_value.split("").join(" ")}.`,
    });
  }

  // ─── 3. restricted units: require phone + allowlist check ───────────────
  if (!args.phone_e164) {
    return reply(toolCall.id, {
      ok: false,
      error: "needs_phone",
      policy: "restricted",
      message: `${unit.unit_label} is a restricted unit. What number are you calling from?`,
    });
  }

  const { data: aData, error: aErr } = await supa.rpc("is_authorized", {
    p_phone: args.phone_e164,
    p_unit_id: unit.unit_id,
  });
  if (aErr) {
    console.error("is_authorized error", aErr);
    return reply(toolCall.id, { ok: false, error: "internal", message: "Let me transfer you to a person." });
  }
  const authz = Array.isArray(aData) ? aData[0] : aData;

  if (!authz?.authorized) {
    await logAccess({ org_id: unit.org_id, unit_id: unit.unit_id, end_user_id: authz?.end_user_id ?? null, call_id: callId, result: "denied", reason: "not_on_allowlist" });
    return reply(toolCall.id, {
      ok: false,
      error: "not_authorized",
      policy: "restricted",
      message: `That phone number isn't on the allowlist for ${unit.unit_label}. Want me to connect you to the operator?`,
    });
  }

  await logAccess({ org_id: unit.org_id, unit_id: unit.unit_id, end_user_id: authz.end_user_id, call_id: callId, result: "success", reason: "restricted_policy_authorized" });
  return reply(toolCall.id, {
    ok: true,
    policy: "restricted",
    unit_label: unit.unit_label,
    code: unit.code_value,
    valid_until: unit.valid_until,
    message: `Code for ${unit.unit_label} is ${unit.code_value.split("").join(" ")}.`,
  });
});
