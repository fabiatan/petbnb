// Supabase Edge Function — iPay88 payment webhook.
//
// iPay88 POSTs here (form-urlencoded) after a payment attempt. We verify the
// signature, then call the `confirm_payment(ref, amount)` RPC (defined in
// Phase 0's 010_state_transitions.sql) using the service-role key so RLS
// doesn't block the status transition.
//
// iPay88 expects the response body to be "RECEIVEOK" on success. On any
// verification failure we still return 200 (iPay88 treats non-200 as a
// retry trigger, which we don't want) with a body explaining the refusal —
// the ref_no is already logged server-side via the booking's existing
// cancellation_reason field if we decide to write it.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.1";
import { MockVerifier, Verifier } from "./verifier.ts";

function buildVerifier(): Verifier {
  // Until iPay88 sandbox creds arrive, ship the mock verifier.
  // Flip to Ipay88Verifier(MERCHANT_KEY) when wired in.
  return new MockVerifier();
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const contentType = req.headers.get("content-type") ?? "";
  if (!contentType.includes("application/x-www-form-urlencoded")) {
    return new Response("Expected form-urlencoded body", { status: 400 });
  }

  const raw = await req.text();
  const params = new URLSearchParams(raw);

  const verifier = buildVerifier();
  let payload;
  try {
    payload = await verifier.verify(params);
  } catch (err) {
    console.error("iPay88 webhook signature/parse failure:", err);
    return new Response(`INVALID: ${(err as Error).message}`, { status: 200 });
  }

  // Only status "1" = success per iPay88 docs. Anything else = declined/abandoned.
  if (payload.status !== "1") {
    console.warn("iPay88 non-success status, ignoring:", payload.status, "ref=", payload.refNo);
    return new Response("NON_SUCCESS_STATUS", { status: 200 });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    console.error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY");
    return new Response("SERVER_NOT_CONFIGURED", { status: 200 });
  }

  const client = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  const { error } = await client.rpc("confirm_payment", {
    p_ref: payload.refNo,
    p_amount: payload.amount,
  });
  if (error) {
    console.error("confirm_payment RPC failed:", error);
    return new Response(`RPC_FAILED: ${error.message}`, { status: 200 });
  }

  console.log("iPay88 webhook confirmed:", payload.refNo, payload.amount);
  return new Response("RECEIVEOK", { status: 200 });
});
