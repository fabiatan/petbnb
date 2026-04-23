// Deno test for the iPay88 webhook verifier. Doesn't cover the full HTTP
// handler (that needs a live Supabase instance); instead tests the pluggable
// verifier in isolation. Integration smoke is done via curl in Task 2.

import { assertEquals, assertRejects } from "https://deno.land/std@0.208.0/assert/mod.ts";
import { MockVerifier } from "./verifier.ts";

Deno.test("MockVerifier parses valid payload", async () => {
  const verifier = new MockVerifier();
  const params = new URLSearchParams({
    MerchantCode: "TEST",
    RefNo: "PETBNB-abcd1234-efgh5678",
    Amount: "160.00",
    Status: "1",
    TransId: "T1",
    Signature: "sig",
  });
  const result = await verifier.verify(params);
  assertEquals(result.refNo, "PETBNB-abcd1234-efgh5678");
  assertEquals(result.amount, 160);
  assertEquals(result.status, "1");
  assertEquals(result.transId, "T1");
});

Deno.test("MockVerifier rejects missing RefNo", async () => {
  const verifier = new MockVerifier();
  const params = new URLSearchParams({ Amount: "160.00", Status: "1" });
  await assertRejects(() => verifier.verify(params), Error, "Missing RefNo");
});

Deno.test("MockVerifier rejects missing Amount", async () => {
  const verifier = new MockVerifier();
  const params = new URLSearchParams({ RefNo: "x", Status: "1" });
  await assertRejects(() => verifier.verify(params), Error, "Missing Amount");
});

Deno.test("MockVerifier rejects invalid Amount", async () => {
  const verifier = new MockVerifier();
  const params = new URLSearchParams({
    RefNo: "x", Amount: "not-a-number", Status: "1",
  });
  await assertRejects(() => verifier.verify(params), Error, "Invalid Amount");
});

Deno.test("MockVerifier accepts status '0' (non-success will be filtered upstream)", async () => {
  const verifier = new MockVerifier();
  const params = new URLSearchParams({
    RefNo: "x", Amount: "100", Status: "0",
  });
  const result = await verifier.verify(params);
  assertEquals(result.status, "0");
});
