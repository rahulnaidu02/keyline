// KeyLine: rotate_code edge function
// Called by Vapi when the rentor wants to change the active code for a unit.
//
// Flow:
//   1. Validate Vapi shared-secret header.
//   2. Call rotate_code RPC — RPC checks rentor-phone match and updates DB.
//   3. Log the rotation as an access_log row (result='success' or 'denied').
//   4. Return Vapi-shaped tool result.
//
// Deploy:  supabase functions deploy rotate_code --no-verify-jwt

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
  if (!toolCall || toolCall.function.name !== "rotate_code") {
    return new Response("unsupported tool", { status: 400 });
  }

  const callId = body.message.call?.id ?? null;
  const args = parseArgs(toolCall.function.arguments) as {
    unit_label?: string;
    new_code?: string;
    caller_phone?: string;
    valid_hours?: number | string;
  };

  if (!args.unit_label || !args.new_code || !args.caller_phone) {
    return reply(toolCall.id, {
      ok: false,
      error: "missing_args",
      message: "I need the unit name, the new four-digit code, and the phone number you registered as the rentor.",
    });
  }

  const validHours = typeof args.valid_hours === "string"
    ? parseInt(args.valid_hours, 10)
    : (args.valid_hours ?? 24);

  const { data, error } = await supa.rpc("rotate_code", {
    p_caller_phone: args.caller_phone,
    p_unit_label: args.unit_label,
    p_new_value: args.new_code,
    p_valid_hours: Number.isFinite(validHours) ? validHours : 24,
  });

  if (error) {
    console.error("rotate_code rpc error", error);
    return reply(toolCall.id, { ok: false, error: "internal", message: "Something went wrong on my end. Let me transfer you." });
  }

  const row = Array.isArray(data) ? data[0] : data;

  if (!row?.ok) {
    const reason = row?.reason ?? "unknown";
    await supa.rpc("log_access", {
      p_org_id: null,
      p_unit_id: null,
      p_end_user_id: null,
      p_call_id: callId,
      p_result: reason === "unit_not_found" ? "not_found" : "denied",
      p_reason: `rotate_${reason}`,
    });
    const msg = reason === "unit_not_found"
      ? `I don't have a unit named ${args.unit_label}.`
      : reason === "not_rentor"
      ? `That phone number isn't registered as the rentor for ${args.unit_label}. Only the rentor can change the code.`
      : reason === "invalid_code_format"
      ? "The new code needs to be four to eight digits, no letters."
      : "I couldn't change the code right now. Let me transfer you.";
    return reply(toolCall.id, { ok: false, error: reason, message: msg });
  }

  await supa.rpc("log_access", {
    p_org_id: null,
    p_unit_id: null,
    p_end_user_id: null,
    p_call_id: callId,
    p_result: "success",
    p_reason: "rotate",
  });

  return reply(toolCall.id, {
    ok: true,
    unit_label: row.unit_label,
    new_code: row.new_value,
    valid_until: row.valid_until,
    message: `Done. New code for ${row.unit_label} is ${row.new_value.split("").join(" ")}, active until ${row.valid_until}.`,
  });
});
