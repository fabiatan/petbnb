# PetBnB Phase 2c — iOS Booking Creation + Payment-Intent Stub + My Bookings

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Phase 2b's `BookingPlaceholderView` with a real booking flow. A pet owner can review a booking, submit it (request-to-book or instant-book based on the kennel's `instant_book` flag, calling Phase 0's existing state-machine RPCs), create a payment intent, and see their bookings in a new **Bookings** tab with live status. iPay88 payment completion is still stubbed for Phase 2d; the app surfaces the `ipay88_reference` plus dev-instructions for manually simulating the webhook via psql.

**Architecture:** New `BookingService` on `AppState` calls four Phase 0 RPCs: `create_booking_request`, `create_instant_booking`, `create_payment_intent`, plus the Phase 1d `accept_booking` / `decline_booking` that already work on the server (iOS never calls those — only the business dashboard does). Bookings are read via the existing `bookings_owner_read` RLS policy from Phase 0. Kennel + business names are joined client-side using the public-read policies on `businesses`, `listings`, `kennel_types`. TabView gains a third tab — **Bookings** — alongside Discover + Pets.

**Tech Stack (unchanged from 2a/2b):**
- SwiftUI + Observable, iOS 17+
- Supabase Swift 2.24 (no new SPM deps)
- XCTest

**Spec references:** §8 (owner iOS — screens 4 Request, 5 Status) + §7 (booking state machine) + §10 (payment flow)
**Phase 2b handoff:** `/Users/fabian/CodingProject/Primary/PetBnB/ios/README.md`

**Scope in this slice:**
- `Booking`, `BookingStatus`, `BookingSummary` Swift models
- `BookingService` — create_request / create_instant / create_payment_intent / listBookings / getBooking
- `SearchCriteria` now threaded from Discover → Results → ListingDetail → Booking (replaces synthetic defaults in ListingDetail)
- **BookingReviewView** — review screen: business, kennel, dates, pet, cert presence, price breakdown, Send-request / Book-now button
- **PaymentStubView** — after booking is payable: show `ipay88_reference`, price, and a DEV psql snippet; a Refresh button polls the booking status
- **MyBookingsView** — list of the user's bookings grouped by status section (awaiting-response, pay-now, confirmed, completed, other)
- **BookingDetailView** — drill-down for a single booking with cancel action (via `cancel_booking_by_owner` RPC)
- TabView 3rd tab: **Bookings**
- Cert-presence precondition: if the chosen pet has no cert valid through check_out, the Send-request button is disabled with a clear message
- XCTest for Booking model decoding, status ordering, service-error messages
- README updates

**Out of scope (deferred):**
- Real iPay88 payment UI — Phase 2d + Phase 3 Edge Function webhook; for 2c, the app just shows the ref and a copy-paste psql snippet
- Push notifications — Phase 2d
- Realtime subscriptions — Phase 2d (use pull-to-refresh for now)
- Cancellation refund computation UI — the Phase 0 RPC just flips state; refund amounts are a later layer
- Booking cancellation by business from iOS — business-side only
- Chat with business — out of Phase 2 entirely
- Reviewing completed stays — Phase 4
- Photo-gallery zoom, map, distance — still deferred
- Advanced booking filters / search in My Bookings — linear list is fine at MVP scale

**Phase 2c success criteria:**
1. Manual simulator flow: sign up → add pet (from Phase 2a) + upload cert → Discover → Search → ListingDetail → pick kennel → Continue.
2. BookingReviewView shows the right summary (pet name, dates, nights, total price, business + kennel).
3. Tap Send-request on a non-instant kennel → booking created with `status='requested'`; user redirected to MyBookings.
4. Tap Book-now on an instant-book kennel → `status='pending_payment'` → redirected to PaymentStubView with `ipay88_reference`.
5. MyBookings shows the booking under the right section and refreshes on pull-down.
6. BookingDetailView shows the full booking + a Cancel action (when status is `confirmed`, calls `cancel_booking_by_owner`).
7. Running `psql -c "SELECT confirm_payment('<ref>', <amount>);"` from the project root flips the booking to `confirmed`; refreshing MyBookings reflects it.
8. `supabase test db` still green, `xcodebuild test` count goes 8 → 11+.

---

## File structure

```
PetBnB/ios/Sources/
├── App/
│   └── AppState.swift                     (MODIFY — add bookingService)
│   └── RootView.swift                     (MODIFY — TabView gains Bookings tab)
├── Bookings/                              (NEW)
│   ├── Booking.swift                       (NEW — BookingStatus enum, Booking + BookingSummary models)
│   ├── BookingService.swift                (NEW)
│   ├── BookingReviewView.swift             (NEW — replaces Phase 2b placeholder)
│   ├── PaymentStubView.swift               (NEW)
│   ├── MyBookingsView.swift                (NEW)
│   └── BookingDetailView.swift             (NEW)
├── Listings/
│   ├── ListingDetailView.swift             (MODIFY — Continue pushes BookingReviewView with SearchCriteria threaded through)
│   └── SearchResultsView.swift             (MODIFY — nav value becomes struct holding business + criteria)
│   └── BookingPlaceholderView.swift        (DELETE — replaced by BookingReviewView)
Tests/
└── BookingServiceTests.swift               (NEW)
```

No Supabase migrations; all server-side functions used by this phase already exist from Phase 0 / 1d.

---

## Task 1: Booking models

**Files:**
- Create: `ios/Sources/Bookings/Booking.swift`

- [ ] **Step 1: Write models**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Bookings/Booking.swift`:
```swift
import Foundation

/// Mirrors the Postgres enum from Phase 0 `001_enums.sql`.
enum BookingStatus: String, Codable, Equatable, CaseIterable {
    case requested
    case accepted
    case declined
    case pending_payment
    case expired
    case confirmed
    case completed
    case cancelled_by_owner
    case cancelled_by_business
}

extension BookingStatus {
    /// High-level grouping for the MyBookings list sections.
    enum Group: String, CaseIterable {
        case awaitingResponse
        case payNow
        case confirmed
        case completed
        case other
    }

    var group: Group {
        switch self {
        case .requested: .awaitingResponse
        case .accepted, .pending_payment: .payNow
        case .confirmed: .confirmed
        case .completed: .completed
        case .declined, .expired, .cancelled_by_owner, .cancelled_by_business: .other
        }
    }

    /// Short label for list rows and status pills.
    var label: String {
        switch self {
        case .requested: "Awaiting response"
        case .accepted: "Pay now"
        case .declined: "Declined"
        case .pending_payment: "Pay now"
        case .expired: "Expired"
        case .confirmed: "Confirmed"
        case .completed: "Completed"
        case .cancelled_by_owner: "Cancelled"
        case .cancelled_by_business: "Cancelled by sitter"
        }
    }
}

/// Full booking row as returned by the Phase 0 `bookings` table.
struct Booking: Identifiable, Codable, Equatable {
    let id: UUID
    let owner_id: UUID
    let business_id: UUID
    let listing_id: UUID
    let kennel_type_id: UUID
    let check_in: Date
    let check_out: Date
    let nights: Int
    let subtotal_myr: Double
    let platform_fee_myr: Double
    let business_payout_myr: Double
    let status: BookingStatus
    let requested_at: Date
    let acted_at: Date?
    let payment_deadline: Date?
    let special_instructions: String?
    let cancellation_reason: String?
    let ipay88_reference: String?
    let is_instant_book: Bool
    let created_at: Date?
    let updated_at: Date?
}

/// A flattened booking row with business + kennel names joined in for display.
struct BookingSummary: Identifiable, Equatable {
    let booking: Booking
    let businessName: String
    let kennelName: String

    var id: UUID { booking.id }
}
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
git add ios/Sources/Bookings/Booking.swift
git commit -m "feat(ios): Booking + BookingStatus + BookingSummary models"
```

---

## Task 2: BookingService

Wraps the four Phase 0 RPCs plus list/get queries.

**Files:**
- Create: `ios/Sources/Bookings/BookingService.swift`

- [ ] **Step 1: Write service**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Bookings/BookingService.swift`:
```swift
import Foundation
import Supabase

enum BookingServiceError: LocalizedError {
    case notAuthenticated
    case invalidInput(String)
    case rpcFailed(String)
    case fetchFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Not signed in."
        case .invalidInput(let m): "Invalid input: \(m)"
        case .rpcFailed(let m): "Server error: \(m)"
        case .fetchFailed(let m): "Couldn't load: \(m)"
        }
    }
}

@MainActor
final class BookingService {
    let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    struct CreateBookingInput {
        let kennelTypeID: UUID
        let petIDs: [UUID]
        let checkIn: Date
        let checkOut: Date
        let specialInstructions: String?
        let isInstantBook: Bool
    }

    /// Route to the right Phase 0 RPC based on the kennel's `instant_book` flag.
    /// Returns the new booking id.
    func createBooking(_ input: CreateBookingInput) async throws -> UUID {
        guard !input.petIDs.isEmpty else {
            throw BookingServiceError.invalidInput("Pick at least one pet")
        }
        guard input.checkOut > input.checkIn else {
            throw BookingServiceError.invalidInput("Check-out must be after check-in")
        }

        let fn = input.isInstantBook ? "create_instant_booking" : "create_booking_request"
        let dateFmt = DateFormatter()
        dateFmt.dateFormat = "yyyy-MM-dd"
        dateFmt.timeZone = TimeZone(identifier: "UTC")
        let params: [String: AnyJSON] = [
            "p_kennel_type_id": .string(input.kennelTypeID.uuidString),
            "p_pet_ids": .array(input.petIDs.map { .string($0.uuidString) }),
            "p_check_in": .string(dateFmt.string(from: input.checkIn)),
            "p_check_out": .string(dateFmt.string(from: input.checkOut)),
            "p_special_instructions": input.specialInstructions.map { .string($0) } ?? .null,
        ]
        do {
            let id: UUID = try await client.rpc(fn, params: params).execute().value
            return id
        } catch {
            throw BookingServiceError.rpcFailed(error.localizedDescription)
        }
    }

    /// Ask Phase 0's `create_payment_intent` RPC for an iPay88 reference to use.
    /// Booking must already be `accepted` (request-to-book path) or
    /// `pending_payment` (instant-book path).
    func createPaymentIntent(bookingID: UUID) async throws -> String {
        let params: [String: AnyJSON] = [
            "p_booking_id": .string(bookingID.uuidString),
        ]
        do {
            let ref: String = try await client.rpc("create_payment_intent", params: params).execute().value
            return ref
        } catch {
            throw BookingServiceError.rpcFailed(error.localizedDescription)
        }
    }

    func cancelBookingByOwner(bookingID: UUID) async throws {
        let params: [String: AnyJSON] = [
            "p_booking_id": .string(bookingID.uuidString),
        ]
        do {
            _ = try await client.rpc("cancel_booking_by_owner", params: params).execute()
        } catch {
            throw BookingServiceError.rpcFailed(error.localizedDescription)
        }
    }

    /// Fetch the caller's bookings + join business + kennel names client-side.
    func listMyBookings() async throws -> [BookingSummary] {
        do {
            let bookings: [Booking] = try await client.from("bookings")
                .select()
                .order("check_in", ascending: false)
                .execute()
                .value

            guard !bookings.isEmpty else { return [] }

            let businessIDs = Set(bookings.map(\.business_id)).map(\.uuidString)
            let kennelIDs = Set(bookings.map(\.kennel_type_id)).map(\.uuidString)

            struct BizRow: Decodable { let id: UUID; let name: String }
            struct KennelRow: Decodable { let id: UUID; let name: String }

            async let businesses: [BizRow] = client.from("businesses")
                .select("id, name")
                .in("id", values: businessIDs)
                .execute()
                .value
            async let kennels: [KennelRow] = client.from("kennel_types")
                .select("id, name")
                .in("id", values: kennelIDs)
                .execute()
                .value

            let (bizList, kennelList) = try await (businesses, kennels)
            let bizByID = Dictionary(uniqueKeysWithValues: bizList.map { ($0.id, $0.name) })
            let kennelByID = Dictionary(uniqueKeysWithValues: kennelList.map { ($0.id, $0.name) })

            return bookings.map {
                BookingSummary(
                    booking: $0,
                    businessName: bizByID[$0.business_id] ?? "Unknown",
                    kennelName: kennelByID[$0.kennel_type_id] ?? "Unknown"
                )
            }
        } catch {
            throw BookingServiceError.fetchFailed(error.localizedDescription)
        }
    }

    func getBookingSummary(id: UUID) async throws -> BookingSummary? {
        let all = try await listMyBookings()
        return all.first { $0.id == id }
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
```

Note: `AnyJSON.null` vs `AnyJSON.null()` — Supabase Swift 2.24 uses static `.null` (case). If it errors, try `AnyJSON.null` without parentheses or `AnyJSON.null()`. Report the form that compiled.

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Sources/Bookings/BookingService.swift
git commit -m "feat(ios): BookingService wrapping Phase 0 booking RPCs"
```

---

## Task 3: Wire BookingService into AppState

**Files:**
- Modify: `ios/Sources/App/AppState.swift`

- [ ] **Step 1: Overwrite**

Replace `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/App/AppState.swift`:
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

    init() {
        let client = SupabaseClientProvider.shared
        self.authService = AuthService(client: client)
        self.petService = PetService(client: client)
        self.listingRepository = ListingRepository(client: client)
        self.bookingService = BookingService(client: client)
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

- [ ] **Step 2: Build**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
```

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Sources/App/AppState.swift
git commit -m "feat(ios): wire BookingService into AppState"
```

---

## Task 4: Thread SearchCriteria through the listing flow

Phase 2b's nav pushed a bare `BusinessSummary` to `ListingDetailView`, which fabricated a `SearchCriteria`. Replace with a value type holding both so the real criteria reaches the booking flow.

**Files:**
- Modify: `ios/Sources/Listings/SearchResultsView.swift`
- Modify: `ios/Sources/Listings/DiscoverView.swift`
- Modify: `ios/Sources/Listings/ListingDetailView.swift`
- Delete: `ios/Sources/Listings/BookingPlaceholderView.swift`

- [ ] **Step 1: Add a nav destination struct at the top of `Listing.swift`**

Open `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Listings/Listing.swift` and append at the end:

```swift

/// Nav destination for the listing detail — carries both the business to show
/// and the search criteria so the booking flow can reuse dates/pet.
struct ListingDestination: Hashable {
    let business: BusinessSummary
    let criteria: SearchCriteria
}
```

`SearchCriteria` already conforms to Hashable via the Phase 2b extension.

- [ ] **Step 2: Update `DiscoverView.swift`**

Change the navigation destination registrations. Find:
```swift
.navigationDestination(for: BusinessSummary.self) { biz in
    ListingDetailView(business: biz)
}
```
Replace with:
```swift
.navigationDestination(for: ListingDestination.self) { dest in
    ListingDetailView(destination: dest)
}
```

- [ ] **Step 3: Update `SearchResultsView.swift`**

Change the `NavigationLink(value: biz)` inside the `ForEach` to:
```swift
NavigationLink(value: ListingDestination(business: biz, criteria: criteria)) {
    BusinessCardRow(business: biz)
}
```

- [ ] **Step 4: Update `ListingDetailView.swift`**

Rewrite the view so it accepts a `ListingDestination` instead of a bare `BusinessSummary`. Change:

```swift
struct ListingDetailView: View {
    @Environment(AppState.self) private var appState
    let business: BusinessSummary
```

to:

```swift
struct ListingDetailView: View {
    @Environment(AppState.self) private var appState
    let destination: ListingDestination
    private var business: BusinessSummary { destination.business }
    private var criteria: SearchCriteria { destination.criteria }
```

Replace the `continueBar(for kennel:)` implementation — change the NavigationLink destination from `BookingPlaceholderView(...)` to:

```swift
NavigationLink {
    BookingReviewView(
        destination: destination,
        kennel: kennel
    )
} label: {
    Text("Continue").fontWeight(.semibold).padding(.horizontal, 20).padding(.vertical, 10)
        .background(Color.accentColor, in: Capsule())
        .foregroundStyle(.white)
}
```

Remove `defaultCriteriaForContinue()` entirely.

- [ ] **Step 5: Delete `BookingPlaceholderView.swift`**

```bash
rm /Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Listings/BookingPlaceholderView.swift
```

- [ ] **Step 6: Build**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
```

Expected: compiler will complain that `BookingReviewView` doesn't exist yet. That's fine — Task 5 creates it, and the final commit of this Task 4 block happens after Task 5 lands.

If you want an intermediate build-green checkpoint, temporarily replace `BookingReviewView(...)` with `Text("TODO — Task 5").padding()`. Flip back before committing Task 5.

- [ ] **Step 7 (combined after Task 5 lands): Commit**

Defer this commit until Task 5's BookingReviewView exists (see next task).

---

## Task 5: BookingReviewView

**Files:**
- Create: `ios/Sources/Bookings/BookingReviewView.swift`

- [ ] **Step 1: Write view**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Bookings/BookingReviewView.swift`:
```swift
import SwiftUI

struct BookingReviewView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let destination: ListingDestination
    let kennel: KennelTypeSummary

    @State private var pets: [Pet] = []
    @State private var selectedPetID: UUID?
    @State private var specialInstructions: String = ""
    @State private var isLoadingPets = false
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var submittedBookingID: UUID?
    @State private var goToBookings = false

    private var criteria: SearchCriteria { destination.criteria }
    private var nights: Int {
        max(1, Calendar.current.dateComponents([.day], from: criteria.checkIn, to: criteria.checkOut).day ?? 1)
    }
    private var subtotal: Double { Double(nights) * kennel.base_price_myr }

    private var selectedPet: Pet? {
        pets.first { $0.id == selectedPetID }
    }

    /// Does the chosen pet have a cert on file at all? (Phase 2a doesn't give us
    /// access to the cert expiry easily without another query — this is a
    /// soft check; the Phase 0 RPC will enforce the real precondition server-side.)
    private var canSubmit: Bool {
        selectedPet != nil && !isSubmitting
    }

    var body: some View {
        Form {
            Section("Stay") {
                LabeledContent("Business", value: destination.business.name)
                LabeledContent("Kennel", value: kennel.name)
                LabeledContent("Dates", value: "\(criteria.checkIn.formatted(date: .abbreviated, time: .omitted)) → \(criteria.checkOut.formatted(date: .abbreviated, time: .omitted))")
                LabeledContent("Nights", value: "\(nights)")
            }

            Section("Pet") {
                if isLoadingPets {
                    ProgressView()
                } else if pets.isEmpty {
                    Text("Add a pet in the Pets tab before booking.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Pet", selection: $selectedPetID) {
                        ForEach(pets) { pet in
                            Text(pet.name).tag(Optional(pet.id))
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("Notes for sitter (optional)") {
                TextEditor(text: $specialInstructions)
                    .frame(minHeight: 80)
            }

            Section("Price") {
                HStack {
                    Text("\(nights) × RM \(String(format: "%.0f", kennel.base_price_myr))")
                    Spacer()
                    Text("RM \(String(format: "%.0f", subtotal))")
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView()
                        } else {
                            Text(kennel.instant_book ? "Book now" : "Send request")
                                .fontWeight(.semibold)
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit)
            } footer: {
                if !kennel.instant_book {
                    Text("The sitter has 24 hours to respond. You'll be prompted to pay after acceptance.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadPets() }
        .navigationDestination(isPresented: $goToBookings) {
            MyBookingsView()
        }
    }

    private func loadPets() async {
        isLoadingPets = true
        defer { isLoadingPets = false }
        do {
            pets = try await appState.petService.listPets()
            if selectedPetID == nil {
                selectedPetID = criteria.petID ?? pets.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() async {
        guard let petID = selectedPetID else { return }
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let input = BookingService.CreateBookingInput(
            kennelTypeID: kennel.id,
            petIDs: [petID],
            checkIn: criteria.checkIn,
            checkOut: criteria.checkOut,
            specialInstructions: specialInstructions.trimmingCharacters(in: .whitespaces).isEmpty ? nil : specialInstructions,
            isInstantBook: kennel.instant_book
        )

        do {
            let id = try await appState.bookingService.createBooking(input)
            submittedBookingID = id
            goToBookings = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
```

This will fail until Task 6 adds `MyBookingsView`. If you prefer a green-build checkpoint, temporarily stub MyBookingsView as `struct MyBookingsView: View { var body: some View { Text("TODO — Task 6") } }` in this same file, then remove the stub once Task 6 lands.

- [ ] **Step 3: Commit (combined Task 4 + Task 5)**

After both tasks are in place and the build is green:
```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Sources/Listings/Listing.swift \
  ios/Sources/Listings/SearchResultsView.swift \
  ios/Sources/Listings/DiscoverView.swift \
  ios/Sources/Listings/ListingDetailView.swift \
  ios/Sources/Listings/BookingPlaceholderView.swift \
  ios/Sources/Bookings/BookingReviewView.swift
git commit -m "feat(ios): BookingReviewView + thread SearchCriteria through nav"
```

(Note: the deleted `BookingPlaceholderView.swift` is staged via `git add` on its path — git picks up the deletion. If `git add` complains about a missing file, use `git rm ios/Sources/Listings/BookingPlaceholderView.swift` first.)

---

## Task 6: MyBookingsView

**Files:**
- Create: `ios/Sources/Bookings/MyBookingsView.swift`

- [ ] **Step 1: Write view**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Bookings/MyBookingsView.swift`:
```swift
import SwiftUI

struct MyBookingsView: View {
    @Environment(AppState.self) private var appState
    @State private var bookings: [BookingSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var grouped: [(BookingStatus.Group, [BookingSummary])] {
        let all = bookings
        let sections: [BookingStatus.Group] = [.payNow, .awaitingResponse, .confirmed, .completed, .other]
        return sections.compactMap { group in
            let items = all.filter { $0.booking.status.group == group }
            return items.isEmpty ? nil : (group, items)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if bookings.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No bookings yet",
                        systemImage: "calendar",
                        description: Text("Your booking requests will show up here.")
                    )
                }
                ForEach(grouped, id: \.0) { (group, items) in
                    Section(group.label) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                BookingRow(summary: item)
                            }
                        }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Bookings")
            .navigationDestination(for: BookingSummary.self) { item in
                BookingDetailView(summary: item)
            }
            .overlay {
                if isLoading && bookings.isEmpty { ProgressView() }
            }
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            bookings = try await appState.bookingService.listMyBookings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension BookingStatus.Group {
    var label: String {
        switch self {
        case .awaitingResponse: "Awaiting response"
        case .payNow: "Pay now"
        case .confirmed: "Upcoming"
        case .completed: "Completed"
        case .other: "Other"
        }
    }
}

extension BookingSummary: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(booking.id) }
    static func == (lhs: BookingSummary, rhs: BookingSummary) -> Bool {
        lhs.booking.id == rhs.booking.id
    }
}

private struct BookingRow: View {
    let summary: BookingSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(summary.businessName).font(.headline)
                Spacer()
                Text(summary.booking.status.label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(tint)
            }
            Text("\(summary.kennelName) · \(summary.booking.nights) night\(summary.booking.nights == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(summary.booking.check_in.formatted(date: .abbreviated, time: .omitted)) → \(summary.booking.check_out.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var tint: Color {
        switch summary.booking.status.group {
        case .payNow: .orange
        case .awaitingResponse: .blue
        case .confirmed: .green
        case .completed: .secondary
        case .other: .gray
        }
    }
}
```

- [ ] **Step 2: Build**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
```

Build will fail until Task 7 adds `BookingDetailView`. Again you can stub temporarily. Real commit comes after Task 7.

---

## Task 7: BookingDetailView + PaymentStubView

**Files:**
- Create: `ios/Sources/Bookings/BookingDetailView.swift`
- Create: `ios/Sources/Bookings/PaymentStubView.swift`

- [ ] **Step 1: Write PaymentStubView**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Bookings/PaymentStubView.swift`:
```swift
import SwiftUI

struct PaymentStubView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    let summary: BookingSummary

    @State private var reference: String?
    @State private var isCreatingIntent = false
    @State private var errorMessage: String?
    @State private var refreshedBooking: Booking?

    private var effectiveBooking: Booking {
        refreshedBooking ?? summary.booking
    }

    var body: some View {
        Form {
            Section("Stay") {
                LabeledContent("Business", value: summary.businessName)
                LabeledContent("Kennel", value: summary.kennelName)
                LabeledContent("Dates", value: "\(summary.booking.check_in.formatted(date: .abbreviated, time: .omitted)) → \(summary.booking.check_out.formatted(date: .abbreviated, time: .omitted))")
                LabeledContent("Total", value: "RM \(String(format: "%.2f", summary.booking.subtotal_myr))")
            }

            Section {
                if let ref = reference ?? effectiveBooking.ipay88_reference {
                    LabeledContent("Reference", value: ref)
                    Text("iPay88 integration is stubbed for Phase 2c. To simulate a successful webhook, run:")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("psql \"postgresql://postgres:postgres@127.0.0.1:54322/postgres\" -c \"SELECT confirm_payment('\(ref)', \(String(format: "%.2f", summary.booking.subtotal_myr))::numeric);\"")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                } else {
                    Button {
                        Task { await createIntent() }
                    } label: {
                        HStack {
                            Spacer()
                            if isCreatingIntent { ProgressView() } else { Text("Create payment intent").fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .disabled(isCreatingIntent)
                }
            } header: { Text("Payment") }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }

            Section {
                Button { Task { await refreshStatus() } } label: {
                    HStack { Spacer(); Text("Refresh status"); Spacer() }
                }
                LabeledContent("Status", value: effectiveBooking.status.label)
            }
        }
        .navigationTitle("Pay")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func createIntent() async {
        errorMessage = nil
        isCreatingIntent = true
        defer { isCreatingIntent = false }
        do {
            reference = try await appState.bookingService.createPaymentIntent(bookingID: summary.booking.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshStatus() async {
        do {
            if let fresh = try await appState.bookingService.getBookingSummary(id: summary.booking.id) {
                refreshedBooking = fresh.booking
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Write BookingDetailView**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Bookings/BookingDetailView.swift`:
```swift
import SwiftUI

struct BookingDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let summary: BookingSummary

    @State private var refreshed: BookingSummary?
    @State private var errorMessage: String?
    @State private var isCancelling = false
    @State private var goToPayment = false

    private var effective: BookingSummary { refreshed ?? summary }

    var body: some View {
        Form {
            Section {
                LabeledContent("Business", value: effective.businessName)
                LabeledContent("Kennel", value: effective.kennelName)
                LabeledContent("Status", value: effective.booking.status.label)
            }
            Section {
                LabeledContent("Check-in", value: effective.booking.check_in.formatted(date: .long, time: .omitted))
                LabeledContent("Check-out", value: effective.booking.check_out.formatted(date: .long, time: .omitted))
                LabeledContent("Nights", value: "\(effective.booking.nights)")
                LabeledContent("Subtotal", value: "RM \(String(format: "%.2f", effective.booking.subtotal_myr))")
            }
            if let notes = effective.booking.special_instructions, !notes.isEmpty {
                Section("Notes") { Text(notes) }
            }
            if let reason = effective.booking.cancellation_reason, !reason.isEmpty {
                Section("Cancellation reason") { Text(reason).font(.footnote).foregroundStyle(.secondary) }
            }

            if effective.booking.status == .accepted || effective.booking.status == .pending_payment {
                Section {
                    Button { goToPayment = true } label: {
                        HStack { Spacer(); Text("Pay now").fontWeight(.semibold); Spacer() }
                    }
                }
            }

            if effective.booking.status == .confirmed {
                Section {
                    Button(role: .destructive) {
                        Task { await cancel() }
                    } label: {
                        HStack {
                            Spacer()
                            if isCancelling { ProgressView() } else { Text("Cancel booking") }
                            Spacer()
                        }
                    }
                    .disabled(isCancelling)
                }
            }

            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Booking")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goToPayment) {
            PaymentStubView(summary: effective)
        }
        .refreshable { await refresh() }
        .task { await refresh() }
    }

    private func refresh() async {
        do {
            if let fresh = try await appState.bookingService.getBookingSummary(id: summary.booking.id) {
                refreshed = fresh
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cancel() async {
        errorMessage = nil
        isCancelling = true
        defer { isCancelling = false }
        do {
            try await appState.bookingService.cancelBookingByOwner(bookingID: summary.booking.id)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Commit (combined Tasks 6 + 7)**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Sources/Bookings/MyBookingsView.swift \
  ios/Sources/Bookings/BookingDetailView.swift \
  ios/Sources/Bookings/PaymentStubView.swift
git commit -m "feat(ios): MyBookings list + BookingDetail + PaymentStub views"
```

---

## Task 8: TabView gains Bookings tab

**Files:**
- Modify: `ios/Sources/App/RootView.swift`

- [ ] **Step 1: Replace RootView**

Overwrite `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/App/RootView.swift`:
```swift
import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        switch appState.status {
        case .bootstrapping:
            ProgressView("Loading…")
        case .signedOut:
            SignInView()
        case .signedIn:
            MainTabs()
        }
    }
}

private struct MainTabs: View {
    var body: some View {
        TabView {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "magnifyingglass") }
            MyBookingsView()
                .tabItem { Label("Bookings", systemImage: "calendar") }
            PetListView()
                .tabItem { Label("Pets", systemImage: "pawprint") }
        }
    }
}
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
git add ios/Sources/App/RootView.swift
git commit -m "feat(ios): TabView gains Bookings tab"
```

---

## Task 9: XCTest

**Files:**
- Create: `ios/Tests/BookingServiceTests.swift`

- [ ] **Step 1: Write tests**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Tests/BookingServiceTests.swift`:
```swift
import XCTest
@testable import PetBnB

final class BookingServiceTests: XCTestCase {
    func test_booking_status_groups() {
        XCTAssertEqual(BookingStatus.requested.group, .awaitingResponse)
        XCTAssertEqual(BookingStatus.accepted.group, .payNow)
        XCTAssertEqual(BookingStatus.pending_payment.group, .payNow)
        XCTAssertEqual(BookingStatus.confirmed.group, .confirmed)
        XCTAssertEqual(BookingStatus.completed.group, .completed)
        XCTAssertEqual(BookingStatus.declined.group, .other)
        XCTAssertEqual(BookingStatus.expired.group, .other)
        XCTAssertEqual(BookingStatus.cancelled_by_owner.group, .other)
        XCTAssertEqual(BookingStatus.cancelled_by_business.group, .other)
    }

    func test_booking_status_labels_non_empty() {
        for status in BookingStatus.allCases {
            XCTAssertFalse(status.label.isEmpty, "Label missing for \(status.rawValue)")
        }
    }

    func test_booking_service_error_messages() {
        XCTAssertTrue((BookingServiceError.notAuthenticated.errorDescription ?? "").contains("Not signed in"))
        XCTAssertTrue((BookingServiceError.invalidInput("Pick at least one pet").errorDescription ?? "").contains("Pick"))
        XCTAssertTrue((BookingServiceError.rpcFailed("boom").errorDescription ?? "").contains("Server error"))
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
If iPhone 17 isn't available, list with `xcrun simctl list devices available` and substitute.

Expected: TEST SUCCEEDED, 11 tests (8 prior + 3 new).

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Tests/BookingServiceTests.swift
git commit -m "test(ios): XCTest for BookingStatus groups + error messages"
```

---

## Task 10: README + handoff

**Files:**
- Modify: `ios/README.md`
- Modify: root `PetBnB/README.md`

- [ ] **Step 1: Append to `ios/README.md`**

Append after the Phase 2b sections:

```markdown

## Phase 2c — Booking flow + payment stub

1. Tapping Continue on `ListingDetailView` now pushes `BookingReviewView`, which shows the booking summary (business, kennel, dates, pet, price) and a Send-request / Book-now button (depending on `kennel.instant_book`).
2. Submitting calls `BookingService.createBooking` which routes to Phase 0's `create_booking_request` or `create_instant_booking` RPC and returns the new booking id.
3. The app pushes `MyBookingsView` which reloads on pull-down. Bookings are grouped by status: Pay now / Awaiting response / Upcoming / Completed / Other.
4. `BookingDetailView` drills into a single booking. If status is `accepted` or `pending_payment`, a Pay-now button opens `PaymentStubView`. If status is `confirmed`, a Cancel button calls `cancel_booking_by_owner`.
5. `PaymentStubView` calls `create_payment_intent` to get the `ipay88_reference`, then shows a DEV psql snippet to simulate the webhook:
   ```
   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
     -c "SELECT confirm_payment('<ref>', <amount>::numeric);"
   ```
   Running this flips the booking to `confirmed`. Tap Refresh status to see the updated state.

## Phase 2c known limitations

- Payment completion is manual (via psql). Phase 2d wires real iPay88 + webhook handling.
- No realtime status push — pull-to-refresh.
- No cancellation refund computation.
- Cert expiry isn't preflight-checked on the client; the server RPC will reject a booking if the cert doesn't cover the stay. The error message surfaces in BookingReviewView's red text.
- One pet per booking on the iOS side (the backend supports multiple; UI can add multi-select later).
```

- [ ] **Step 2: Update root `PetBnB/README.md`**

Add to the Status section:
```
- [x] **Phase 2c** — iOS booking creation + payment-intent stub + My Bookings
```

- [ ] **Step 3: Final acceptance**

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

All must succeed: pgTAP 79, web Playwright 4, iOS XCTest 11.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/README.md README.md
git commit -m "docs: Phase 2c README and booking-flow handoff"
```

---

## Phase 2c complete — final checklist

- [ ] `git log --oneline | head -15` shows 9 new commits on top of Phase 2b (97 total).
- [ ] `supabase test db` — 79 pgTAP passing.
- [ ] `pnpm exec playwright test` — 4 web E2E passing.
- [ ] `xcodebuild test` — 11 iOS tests passing.
- [ ] Manual simulator smoke: sign up → add pet + cert → Discover → Search → ListingDetail → Continue → Review → Send request → MyBookings shows it under Awaiting response. Then business accepts via web dashboard → pull to refresh iOS → status flips to Pay now → Pay now → create intent → run the psql snippet → refresh → status becomes Confirmed.
- [ ] No credentials committed: `git log -p 2136625..HEAD | grep -E "(eyJ[A-Za-z0-9_-]{20,}|sb_secret_|sk_live_)"` empty.

Push:
```bash
git push origin main
```

Then plan Phase 2d (real iPay88 + push notifications + Realtime).
