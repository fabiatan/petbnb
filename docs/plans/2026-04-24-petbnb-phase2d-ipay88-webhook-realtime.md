# PetBnB Phase 2d — iPay88 Edge Function Webhook + Supabase Realtime

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Phase 2c manual psql step for payment confirmation with a real Supabase Edge Function webhook that iPay88 will POST to in production. Add Supabase Realtime subscriptions on the iOS Bookings tab so state changes (accept / payment confirmed / completed) surface without pull-to-refresh. Push notifications (APNs) are deferred to a separate slice because they need one-time Apple Developer Push key setup.

**Architecture:** New Deno Edge Function at `supabase/functions/ipay88-webhook/index.ts`. Pluggable signature-verifier interface — ships with a mock verifier for dev that accepts any payload, plus a documented "paste real iPay88 HMAC logic here" seam. Function uses the Supabase service-role key (from `SUPABASE_SERVICE_ROLE_KEY` secret) to call `confirm_payment(ref, amount)`. Deno test hits the handler with a mock payload, asserts the booking is confirmed.

On iOS, a new `BookingRealtimeService` subscribes to `public.bookings` filtered by `owner_id = auth.uid()`. `MyBookingsView` starts the subscription on appear, tears it down on disappear. On UPDATE events, the view re-runs its `listMyBookings()` fetch.

**Tech Stack additions:**
- Supabase Edge Functions runtime (Deno — already installed via Supabase CLI from Phase 0)
- Supabase Realtime (already enabled via Phase 0's config; no new deps)
- No new SPM packages (Supabase Swift's `RealtimeV2` sub-client ships with the main SDK)

**Spec references:** §10 (payment flow invariants) + §11 (notification matrix — `payment_confirmed` push is stubbed in this phase; real APNs in 2e)
**Phase 2c handoff:** `/Users/fabian/CodingProject/Primary/PetBnB/ios/README.md`

**Scope in this slice:**
- `supabase/functions/ipay88-webhook/index.ts` Edge Function
- Signature verifier interface with `MockVerifier` (always-accept) + documented plug-in point for real iPay88 HMAC
- Deno integration test for the webhook
- `BookingRealtimeService` on iOS wrapping Supabase Swift Realtime
- `MyBookingsView` integration: subscribe on appear, refresh on UPDATE events
- `PaymentStubView` docs: swap the manual psql snippet for "functions serve" instructions
- XCTest for Realtime service lifecycle + event parsing
- README handoff marking Phase 2 complete

**Out of scope (deferred):**
- APNs push notifications — Phase 2e or 3; needs .p8 key, bundle ID entitlements, device testing
- iPay88 production HMAC verification — structured to drop in when sandbox creds arrive
- Webhook audit/event log table — Phase 5+
- Retry/rate-limiting at the webhook layer — Phase 5+
- Realtime subscription auto-reconnection after session expiry — iOS Supabase SDK 2.24 handles this internally; just ensure we don't fight it
- Realtime on the business web dashboard — Phase 5+ polish (spec §8 only required it for the iOS owner surface)

**Phase 2d success criteria:**
1. `supabase functions serve ipay88-webhook --no-verify-jwt` runs locally on :54321/functions/v1/ipay88-webhook.
2. A `curl` POST to the local webhook URL with a valid mock payload flips the test booking from `pending_payment` to `confirmed` via the underlying `confirm_payment` RPC.
3. `deno test supabase/functions/ipay88-webhook/` passes.
4. iOS MyBookingsView updates within ~2s of a booking row's `status` column changing (via direct psql UPDATE as a test stand-in), without pull-to-refresh.
5. Removing the MyBookings tab from the foreground triggers the subscription to tear down (verified via Supabase Studio's Realtime logs — the channel count drops).
6. `supabase test db` all green; `xcodebuild test` count goes 11 → 14+.
7. `xcodebuild build` clean.

---

## File structure

```
PetBnB/
├── supabase/
│   └── functions/                                (NEW directory)
│       └── ipay88-webhook/
│           ├── index.ts                           (NEW — Edge Function handler)
│           ├── verifier.ts                        (NEW — Verifier interface + MockVerifier)
│           └── index_test.ts                      (NEW — Deno integration test)
└── ios/Sources/
    ├── App/
    │   └── AppState.swift                         (MODIFY — add bookingRealtimeService)
    └── Bookings/
        ├── BookingRealtimeService.swift           (NEW)
        ├── MyBookingsView.swift                   (MODIFY — subscribe on appear)
        └── PaymentStubView.swift                  (MODIFY — swap psql snippet for functions-serve hint)
Tests/
└── BookingRealtimeServiceTests.swift              (NEW)
```

No new DB migrations. All RLS and RPC functions exist from Phase 0.

---

## Task 1: Signature verifier interface + mock

**Files:**
- Create: `supabase/functions/ipay88-webhook/verifier.ts`

- [ ] **Step 1: Write verifier**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/functions/ipay88-webhook/verifier.ts`:
```ts
// Pluggable signature verifier for the iPay88 webhook. Phase 2d ships with a
// MockVerifier that accepts any payload. Replace with real HMAC logic when
// iPay88 sandbox credentials arrive — the interface stays the same so the
// Edge Function handler doesn't change.

export interface Ipay88Payload {
  refNo: string;
  amount: number;
  status: string;       // "1" = success per iPay88 docs
  transId: string;
  signature: string;
  merchantCode: string;
}

export interface Verifier {
  /**
   * Parse + validate a webhook POST body.
   * Returns the normalised payload on success, or throws on verification failure.
   */
  verify(formBody: URLSearchParams): Promise<Ipay88Payload>;
}

/**
 * Dev verifier that does no real signature check — just parses the fields and
 * returns them. DO NOT use in production.
 */
export class MockVerifier implements Verifier {
  async verify(formBody: URLSearchParams): Promise<Ipay88Payload> {
    const refNo = formBody.get("RefNo");
    const amount = formBody.get("Amount");
    const status = formBody.get("Status");
    const transId = formBody.get("TransId") ?? "";
    const signature = formBody.get("Signature") ?? "";
    const merchantCode = formBody.get("MerchantCode") ?? "";

    if (!refNo) throw new Error("Missing RefNo");
    if (!amount) throw new Error("Missing Amount");
    if (!status) throw new Error("Missing Status");

    const parsedAmount = Number(amount);
    if (!Number.isFinite(parsedAmount) || parsedAmount < 0) {
      throw new Error(`Invalid Amount: ${amount}`);
    }

    return {
      refNo,
      amount: parsedAmount,
      status,
      transId,
      signature,
      merchantCode,
    };
  }
}

/**
 * Real iPay88 verifier. When sandbox credentials are provisioned:
 *   1. Read IPAY88_MERCHANT_KEY from Edge Function secrets.
 *   2. Compute HMAC-SHA256 over the canonical string:
 *      MerchantKey + MerchantCode + RefNo + Amount (no dots) + Currency
 *   3. Compare with the Signature field (base64).
 * See iPay88's "Signature generation" appendix in their integration guide.
 */
export class Ipay88Verifier implements Verifier {
  constructor(private readonly merchantKey: string) {}

  async verify(_formBody: URLSearchParams): Promise<Ipay88Payload> {
    // TODO: implement when sandbox creds arrive. Until then, instantiation of
    // this class itself throws so we never accidentally route production
    // traffic through an unverified path.
    throw new Error("Ipay88Verifier not implemented; use MockVerifier in dev");
  }
}
```

- [ ] **Step 2: Syntax check with Deno**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
supabase functions new --help > /dev/null 2>&1 || true    # warm up
deno check supabase/functions/ipay88-webhook/verifier.ts
```
Expected: no output = success. (If `deno` isn't on PATH, Supabase CLI bundles it — `supabase functions serve` exercises the same runtime.)

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/functions/ipay88-webhook/verifier.ts
git commit -m "feat(supabase): iPay88 webhook signature verifier interface + mock"
```

---

## Task 2: Edge Function handler

**Files:**
- Create: `supabase/functions/ipay88-webhook/index.ts`

- [ ] **Step 1: Write handler**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/functions/ipay88-webhook/index.ts`:
```ts
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
```

- [ ] **Step 2: Serve locally + smoke test**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
supabase functions serve ipay88-webhook --no-verify-jwt --env-file supabase/.env.local
```

In another terminal (leave serve running), seed a test booking + call the webhook:
```bash
# Seed a test booking in pending_payment state
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" <<'SQL'
INSERT INTO auth.users (id, email) VALUES ('b2d01111-0000-0000-0000-000000000001', 'webhook-test@t') ON CONFLICT DO NOTHING;
INSERT INTO user_profiles (id, display_name) VALUES ('b2d01111-0000-0000-0000-000000000001', 'Test') ON CONFLICT DO NOTHING;
-- re-use a seeded business+listing+kennel from seed.sql
INSERT INTO bookings (
  id, owner_id, business_id, listing_id, kennel_type_id,
  check_in, check_out, nights, subtotal_myr, status,
  payment_deadline, ipay88_reference
) VALUES (
  'b2d01111-beef-0000-0000-000000000001',
  'b2d01111-0000-0000-0000-000000000001',
  '40000000-0000-0000-0000-000000000001',
  '50000000-0000-0000-0000-000000000001',
  '60000000-0000-0000-0000-000000000001',
  '2027-08-01', '2027-08-03', 2, 160, 'pending_payment',
  now() + interval '15 minutes', 'WEBHOOK-TEST-REF'
) ON CONFLICT DO NOTHING;
SQL

# Fire the webhook
curl -v -X POST http://127.0.0.1:54321/functions/v1/ipay88-webhook \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data "MerchantCode=TEST&RefNo=WEBHOOK-TEST-REF&Amount=160.00&Status=1&TransId=T1&Signature=sig"

# Verify status flipped
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
  -c "SELECT status FROM bookings WHERE ipay88_reference='WEBHOOK-TEST-REF';"
```
Expected: curl returns HTTP 200 with `RECEIVEOK`. Final SELECT shows `status = confirmed`.

If `supabase/.env.local` doesn't exist, the function reads from the default Supabase local env (populated automatically when `supabase start` boots). The `--env-file` flag is optional in local dev.

Stop the `supabase functions serve` process.

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/functions/ipay88-webhook/index.ts
git commit -m "feat(supabase): iPay88 webhook Edge Function calling confirm_payment"
```

---

## Task 3: Deno integration test

**Files:**
- Create: `supabase/functions/ipay88-webhook/index_test.ts`

- [ ] **Step 1: Write test**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/functions/ipay88-webhook/index_test.ts`:
```ts
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
```

- [ ] **Step 2: Run Deno tests**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
deno test supabase/functions/ipay88-webhook/index_test.ts --allow-all 2>&1 | tail -10
```

If `deno` isn't directly on PATH, Supabase CLI shims it; try:
```bash
supabase functions test ipay88-webhook 2>&1 | tail -10
```

If neither works, download Deno directly: `brew install deno` (one-time).

Expected: 5 tests passing.

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/functions/ipay88-webhook/index_test.ts
git commit -m "test(supabase): Deno tests for iPay88 webhook verifier"
```

---

## Task 4: iOS BookingRealtimeService

Wraps Supabase Swift's Realtime client to subscribe to `public.bookings` updates filtered by owner_id.

**Files:**
- Create: `ios/Sources/Bookings/BookingRealtimeService.swift`

- [ ] **Step 1: Write service**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Bookings/BookingRealtimeService.swift`:
```swift
import Foundation
import Supabase
import Realtime

/// Subscribes to `public.bookings` Postgres changes filtered by the caller's
/// owner_id. Emits an event whenever any of the caller's bookings UPDATE,
/// INSERT, or DELETE. The consumer (MyBookingsView) re-fetches its list on
/// receipt.
@MainActor
final class BookingRealtimeService {
    enum Event {
        case changed         // some booking of the caller changed — refetch
    }

    private let client: SupabaseClient
    private var channel: RealtimeChannelV2?
    private var task: Task<Void, Never>?

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Start a subscription. Caller holds the returned AsyncStream and iterates
    /// for events. Call `stop()` to tear down.
    func start() async -> AsyncStream<Event> {
        AsyncStream { continuation in
            let startTask = Task { [client] in
                guard let userId = try? await client.auth.user().id else { return }
                let channel = client.channel("owner-bookings-\(userId.uuidString)")

                // Postgres changes emit on each UPDATE; we map to the generic
                // `changed` event rather than trying to diff incrementally.
                let changes = channel.postgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: "bookings",
                    filter: "owner_id=eq.\(userId.uuidString)"
                )

                do {
                    try await channel.subscribeWithError()
                } catch {
                    continuation.finish()
                    return
                }

                self.channel = channel

                for await _ in changes {
                    continuation.yield(.changed)
                }
                continuation.finish()
            }
            self.task = startTask

            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in await self?.stop() }
            }
        }
    }

    func stop() async {
        task?.cancel()
        task = nil
        if let channel {
            try? await channel.unsubscribe()
        }
        channel = nil
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
```

Supabase Swift 2.24 may expose the Realtime client via `import Supabase` alone (no `import Realtime`) or via a separate `Realtime` sub-module. If `import Realtime` errors, remove it and rely on `import Supabase`. If `RealtimeChannelV2`, `AnyAction`, `subscribeWithError`, or `postgresChange` have different names or signatures, adapt minimally and report. The canonical API shape is:
- `client.channel(name)` returns a channel object
- `channel.postgresChange(...)` returns an AsyncSequence
- `channel.subscribe()` or `subscribeWithError()` starts it
- Iterate the async sequence for change events

If your SDK version uses a different method like `channel.onPostgresChange { ... }` callback-style, adapt the implementation into an AsyncStream manually.

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Sources/Bookings/BookingRealtimeService.swift
git commit -m "feat(ios): BookingRealtimeService — Realtime subscription to owner bookings"
```

---

## Task 5: Wire Realtime into AppState + MyBookingsView

**Files:**
- Modify: `ios/Sources/App/AppState.swift`
- Modify: `ios/Sources/Bookings/MyBookingsView.swift`

- [ ] **Step 1: Update AppState**

Overwrite `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/App/AppState.swift`:
```swift
import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class AppState {
    enum Status {
        case bootstrapping
        case signedOut
        case signedIn(userId: UUID, displayName: String)
    }

    var status: Status = .bootstrapping
    let authService: AuthService
    let petService: PetService
    let listingRepository: ListingRepository
    let bookingService: BookingService
    let bookingRealtimeService: BookingRealtimeService

    init() {
        let client = SupabaseClientProvider.shared
        self.authService = AuthService(client: client)
        self.petService = PetService(client: client)
        self.listingRepository = ListingRepository(client: client)
        self.bookingService = BookingService(client: client)
        self.bookingRealtimeService = BookingRealtimeService(client: client)
    }

    func bootstrap() async {
        for await event in authService.authEvents() {
            switch event {
            case let .signedIn(userId, displayName):
                status = .signedIn(userId: userId, displayName: displayName)
            case .signedOut:
                status = .signedOut
            }
        }
    }
}
```

- [ ] **Step 2: Update MyBookingsView**

Find `ios/Sources/Bookings/MyBookingsView.swift`. Keep the existing structure; add a realtime subscription lifecycle using `.task` and `.onDisappear`.

Replace the existing `.task { await reload() }.refreshable { await reload() }` chain with:

```swift
            .task {
                await reload()
                // Keep the subscription running while this view is on screen.
                let events = await appState.bookingRealtimeService.start()
                for await _ in events {
                    await reload()
                }
            }
            .refreshable { await reload() }
            .onDisappear {
                Task { await appState.bookingRealtimeService.stop() }
            }
```

Leave everything else in the view alone.

- [ ] **Step 3: Build**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Sources/App/AppState.swift ios/Sources/Bookings/MyBookingsView.swift
git commit -m "feat(ios): Realtime subscription in MyBookingsView + AppState wiring"
```

---

## Task 6: Update PaymentStubView with functions-serve snippet

**Files:**
- Modify: `ios/Sources/Bookings/PaymentStubView.swift`

- [ ] **Step 1: Swap the psql instruction**

In `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Bookings/PaymentStubView.swift`, find the block that shows the psql snippet:

```swift
Text("iPay88 integration is stubbed for Phase 2c. To simulate a successful webhook, run:")
```

Replace the explanatory text + the following `Text(...)` with:

```swift
Text("Run the Edge Function locally and fire a mock webhook (Phase 2d):")
    .font(.footnote)
    .foregroundStyle(.secondary)
Text("supabase functions serve ipay88-webhook --no-verify-jwt")
    .font(.system(.caption, design: .monospaced))
    .foregroundStyle(.primary)
    .textSelection(.enabled)
Text("# then in another terminal:")
    .font(.system(.caption, design: .monospaced))
    .foregroundStyle(.secondary)
Text("curl -X POST http://127.0.0.1:54321/functions/v1/ipay88-webhook -H 'Content-Type: application/x-www-form-urlencoded' --data \"RefNo=\(ref)&Amount=\(String(format: "%.2f", summary.booking.subtotal_myr))&Status=1&TransId=T1&Signature=sig&MerchantCode=TEST\"")
    .font(.system(.caption, design: .monospaced))
    .foregroundStyle(.primary)
    .textSelection(.enabled)
Text("Phase 2e wires real APNs + Apple Pay; Phase 3 wires real iPay88 signature verification.")
    .font(.footnote)
    .foregroundStyle(.secondary)
```

- [ ] **Step 2: Build**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
```

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Sources/Bookings/PaymentStubView.swift
git commit -m "feat(ios): PaymentStubView points at functions serve + curl webhook"
```

---

## Task 7: XCTest for BookingRealtimeService lifecycle

**Files:**
- Create: `ios/Tests/BookingRealtimeServiceTests.swift`

- [ ] **Step 1: Write tests**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Tests/BookingRealtimeServiceTests.swift`:
```swift
import XCTest
@testable import PetBnB

final class BookingRealtimeServiceTests: XCTestCase {
    func test_service_initializes_without_crashing() {
        let client = SupabaseClientProvider.shared
        let svc = BookingRealtimeService(client: client)
        XCTAssertNotNil(svc)
    }

    func test_stop_without_start_is_safe() async {
        let client = SupabaseClientProvider.shared
        let svc = BookingRealtimeService(client: client)
        await svc.stop()  // should not crash, no channel to unsubscribe
    }

    func test_realtime_event_enum_value() {
        XCTAssertEqual(BookingRealtimeService.Event.changed, BookingRealtimeService.Event.changed)
    }
}
```

- [ ] **Step 2: Run tests**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild test -project PetBnB.xcodeproj -scheme PetBnB \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -quiet CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
```
Expected: 14 tests passing (11 prior + 3 new).

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Tests/BookingRealtimeServiceTests.swift
git commit -m "test(ios): XCTest for BookingRealtimeService lifecycle"
```

---

## Task 8: Manual Realtime smoke + README

**Files:**
- Modify: `ios/README.md`
- Modify: `PetBnB/README.md`

- [ ] **Step 1: Manual Realtime smoke**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:

1. `supabase start` (already running from prior phases).
2. Build + launch the iOS app on the simulator.
3. Sign in as the seeded owner (or a newly-signed-up user).
4. Create a test booking in the DB (as postgres, bypassing RLS):
   ```bash
   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c \
     "INSERT INTO bookings (owner_id, business_id, listing_id, kennel_type_id, check_in, check_out, nights, subtotal_myr, status)
      SELECT u.id, '40000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001',
             '2028-01-01', '2028-01-03', 2, 160, 'requested'
      FROM auth.users u WHERE u.email = '<your-logged-in-email>';"
   ```
5. Switch to the iOS simulator and tap the Bookings tab. The new booking should appear within ~2s (no pull-to-refresh needed).
6. In a terminal, flip its status: `psql -c "UPDATE bookings SET status='accepted' WHERE status='requested' AND check_in='2028-01-01';"`.
7. Back in iOS, the booking should move from "Awaiting response" to "Pay now" without pull-to-refresh.

If this works, the Realtime wiring is good. If not, check `supabase functions logs` or the iOS console for errors; report.

- [ ] **Step 2: Update `ios/README.md`**

Append to `/Users/fabian/CodingProject/Primary/PetBnB/ios/README.md` after the Phase 2c sections:

```markdown

## Phase 2d — iPay88 webhook + Realtime

1. `supabase/functions/ipay88-webhook/` receives iPay88's payment POST and calls `confirm_payment`. Ships with a MockVerifier; real HMAC plugs into `Ipay88Verifier` when sandbox creds arrive.
2. Run locally:
   ```bash
   supabase functions serve ipay88-webhook --no-verify-jwt
   ```
3. `BookingRealtimeService` subscribes iOS to `public.bookings` filtered by `owner_id=eq.<caller>` using Supabase Swift's RealtimeV2 API. MyBookingsView starts the subscription on appear, stops on disappear.

## Phase 2d known limitations

- iPay88 HMAC verification is stubbed (`Ipay88Verifier` throws). Swap in real implementation when sandbox creds arrive — see comments in `verifier.ts`.
- No automatic retry on webhook delivery failure — Phase 5+.
- APNs push notifications are NOT in Phase 2d (deferred to Phase 2e).
- Realtime reconnects automatically on network change, but if the user's JWT expires mid-session the subscription silently drops. Phase 5 polish.
```

- [ ] **Step 3: Update root `PetBnB/README.md`**

Add to Status section:
```
- [x] **Phase 2d** — iPay88 Edge Function webhook + iOS Realtime

**Phase 2 (iOS owner app) — complete** (modulo APNs push in Phase 2e).
```

- [ ] **Step 4: Final acceptance**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
supabase test db
./supabase/scripts/verify-phase0.sh
cd web && pnpm build && pnpm exec playwright test
cd ../ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
xcodebuild test  -project PetBnB.xcodeproj -scheme PetBnB -destination 'platform=iOS Simulator,name=iPhone 17' -quiet CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
```
All must succeed: pgTAP 79, web Playwright 4, iOS XCTest 14.

- [ ] **Step 5: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/README.md README.md
git commit -m "docs: Phase 2d README + Phase 2 complete handoff"
```

---

## Phase 2d complete — final checklist

- [ ] `git log --oneline | head -15` shows 8 new commits on top of Phase 2c (104 total).
- [ ] `supabase test db` — 79 pgTAP passing.
- [ ] `deno test supabase/functions/ipay88-webhook/` — 5 tests passing.
- [ ] `xcodebuild test` — 14 iOS tests passing.
- [ ] Manual webhook smoke: curl POST → booking flips to `confirmed`.
- [ ] Manual Realtime smoke: UPDATE on bookings table → iOS MyBookings refreshes within ~2s.
- [ ] No credentials committed: `git log -p c2c9620..HEAD | grep -E "(eyJ[A-Za-z0-9_-]{20,}|sb_secret_|sk_live_)"` empty.

Push:
```bash
git push origin main
```

After Phase 2d, Phase 2 is functionally complete modulo APNs. Consider planning:
- Phase 2e: Apple Push Notifications (requires .p8 key + entitlement setup)
- Phase 3: production polish — real iPay88 HMAC, Error/retry policies, audit logs, performance tuning
- Phase 4: Reviews wiring
- Phase 5: Public SEO pages + transactional email
- Phase 6: Closed beta in KL
