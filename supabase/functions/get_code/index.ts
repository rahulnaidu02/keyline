// KeyLine: get_code edge function
// Called by Vapi as a function tool. Vapi posts a tool-call event;
// we authenticate the caller, look up the active code, log the access,
// and respond in Vapi's expected tool-call-result format.
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

Deno.serve(async (req) => {
  // ─── auth: shared-secret header from Vapi ───────────────────────────────
  const secret = req.headers.get("x-vapi-secret");
  if (!SHARED_SECRET || secret !== SHARED_SECRET) {
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
    phone_e164?: string;
    user_pin?: string;
    unit_label?: string;
  };

  if (!args.phone_e164 || !args.user_pin || !args.unit_label) {
    return reply(toolCall.id, {
      ok: false,
      error: "missing_args",
      message: "I need your phone number, PIN, and the unit name.",
    });
  }

  // ─── 1. verify caller ───────────────────────────────────────────────────
  const { data: vData, error: vErr } = await supa.rpc("verify_caller", {
    p_phone: args.phone_e164,
    p_pin: args.user_pin,
  });

  if (vErr) {
    console.error("verify_caller error", vErr);
    return reply(toolCall.id, { ok: false, error: "internal", message: "Something went wrong on my end. Let me transfer you." });
  }

  const row = Array.isArray(vData) ? vData[0] : vData;
  if (!row?.end_user_id) {
    await supa.rpc("log_access", {
      p_org_id: row?.org_id ?? null,
      p_unit_id: null,
      p_end_user_id: null,
      p_call_id: callId,
      p_result: row?.locked ? "locked" : "denied",
      p_reason: row?.locked ? "too_many_failed_pins" : "bad_phone_or_pin",
    });
    return reply(toolCall.id, {
      ok: false,
      error: row?.locked ? "locked" : "auth_failed",
      message: row?.locked
        ? "This phone number is temporarily locked due to too many failed attempts. Please try again in fifteen minutes or stay on the line to talk to a person."
        : "I couldn't verify that phone number and PIN combination.",
    });
  }

  // ─── 2. fetch active code ───────────────────────────────────────────────
  const { data: cData, error: cErr } = await supa.rpc("get_active_code", {
    p_end_user_id: row.end_user_id,
    p_unit_label: args.unit_label,
  });

  if (cErr) {
    console.error("get_active_code error", cErr);
    return reply(toolCall.id, { ok: false, error: "internal", message: "Let me transfer you to a person." });
  }

  const code = Array.isArray(cData) ? cData[0] : cData;
  if (!code?.code_value) {
    await supa.rpc("log_access", {
      p_org_id: row.org_id,
      p_unit_id: null,
      p_end_user_id: row.end_user_id,
      p_call_id: callId,
      p_result: "not_found",
      p_reason: `no active code or not authorized for ${args.unit_label}`,
    });
    return reply(toolCall.id, {
      ok: false,
      error: "not_authorized_or_no_code",
      message: `I don't have an active code for ${args.unit_label} on your account.`,
    });
  }

  // ─── 3. log + return ────────────────────────────────────────────────────
  await supa.rpc("log_access", {
    p_org_id: row.org_id,
    p_unit_id: code.unit_id,
    p_end_user_id: row.end_user_id,
    p_call_id: callId,
    p_result: "success",
    p_reason: null,
  });

  return reply(toolCall.id, {
    ok: true,
    unit_label: code.unit_label,
    code: code.code_value,
    valid_until: code.valid_until,
    message: `Code for ${code.unit_label} is ${code.code_value.split("").join(" ")}.`,
  });
});
