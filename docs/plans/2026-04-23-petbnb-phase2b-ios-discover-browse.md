# PetBnB Phase 2b — iOS Discover + Search + Listing Detail

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the iOS app into a real consumer browse surface. A pet owner can pick a city + dates + pet, see a list of verified boarding businesses, tap a card to open the listing detail with photos + kennel options, and tap "Continue" — which, for Phase 2b, lands on a placeholder scene that Phase 2c will replace with the real booking-request flow.

**Architecture:** New `ListingRepository` service alongside the existing `AuthService` and `PetService` in `AppState`. Public read via Supabase JS client against `businesses` + `listings` + `kennel_types` (RLS already exposes verified-active businesses to anon/authenticated per Phase 0's `008_rls_policies.sql`). Photos come from the public `listing-photos` bucket (URLs built client-side via `storage.from(...).getPublicURL`). Navigation: root `TabView` with Discover + Pets tabs. Availability-correct filtering is out of scope for 2b — Phase 2c runs real availability checks at booking-intent time.

**Tech Stack (unchanged from 2a):**
- SwiftUI + Observable, iOS 17+
- Supabase Swift 2.24 (already pinned)
- No new SPM dependencies
- Async image loading via SwiftUI's `AsyncImage`
- XCTest for view model + repository types

**Spec references:** §8 (owner iOS flow — screens 1 Discover, 2 Results, 3 Listing detail)
**Phase 2a handoff:** `/Users/fabian/CodingProject/Primary/PetBnB/ios/README.md`

**Scope in this slice:**
- `Listing`, `BusinessSummary`, `KennelTypeSummary` Swift models (Codable)
- `ListingRepository` with two queries: search (city filter → business summaries) + detail (business_id → business + listing + kennel types + photo URLs)
- `DiscoverView` — city free-text, date range (check-in / check-out), pet picker, Search
- `SearchResultsView` — scrollable list of business cards with hero image, name, rating placeholder, species + price summary
- `ListingDetailView` — photo gallery carousel, description + amenities + house rules, kennel-type picker (Continue stub for 2c)
- `RootView` with `TabView` (Discover + Pets tabs)
- XCTest for model decoding + repository stub wiring
- README updates

**Out of scope (deferred):**
- Real booking creation — Phase 2c
- Payment flows — Phase 2c + 3
- Bookings tab (My Bookings) — Phase 2c
- Availability-aware filtering in search — Phase 2c runs a precondition check at booking-intent creation
- Ratings/review counts — just stub "no reviews yet" placeholders until Phase 4 wires real review data
- Map view / location-based distance — later polish (spec mentions "3.2km" but no geocoding service yet)
- Favorites / wishlist (heart button in mockup) — later
- Photo-gallery zoom / full-screen — later
- Push-to-refresh on Discover tab — later
- Localization beyond English
- Accessibility polish beyond SwiftUI defaults
- Profile / settings screen — later (sign-out stays in Pets tab toolbar)

**Phase 2b success criteria:**
1. Launching the app in simulator and signing in (seeded owner at `owner1@petbnb.local` / whatever password you set during 2a testing, or sign up fresh) lands on a `TabView` with two tabs: Discover + Pets.
2. Discover tab shows a city field defaulting to "Kuala Lumpur", a 5-night default date range, a pet picker populated from the user's pets, and a Search button.
3. Tapping Search pushes to SearchResults showing both seeded businesses (Happy Paws KL, Bark Avenue).
4. Tapping a result pushes to ListingDetail with the business's info, any listing photos (or placeholders), and its kennels.
5. Tapping Continue on ListingDetail pushes to a "Coming in Phase 2c" placeholder.
6. `supabase test db` assertions all green.
7. `xcodebuild build` + `xcodebuild test` both green; XCTest count goes from 5 → 7+.

---

## File structure

```
PetBnB/ios/
└── Sources/
    ├── App/
    │   └── AppState.swift                       (MODIFIED — add listingRepository)
    ├── Listings/                                (NEW directory)
    │   ├── Listing.swift                        (NEW — Codable models)
    │   ├── ListingRepository.swift              (NEW)
    │   ├── DiscoverView.swift                   (NEW)
    │   ├── SearchResultsView.swift              (NEW)
    │   ├── ListingDetailView.swift              (NEW)
    │   └── BookingPlaceholderView.swift         (NEW — Continue destination for 2b)
    └── App/
        └── RootView.swift                        (MODIFIED — TabView wrap)
Tests/
    └── ListingRepositoryTests.swift             (NEW)
```

No Supabase migrations; Phase 2b is client-side only.

---

## Task 1: Listing + kennel Codable models

**Files:**
- Create: `ios/Sources/Listings/Listing.swift`

- [ ] **Step 1: Write models**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Listings/Listing.swift`:
```swift
import Foundation

/// Minimal business payload used by search results. City/state for display;
/// slug for deep-linking; cover_photo_url for the hero tile.
struct BusinessSummary: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var slug: String
    var city: String
    var state: String
    var description: String?
    var cover_photo_url: String?
}

/// A kennel-type row surfaced on the listing detail page.
struct KennelTypeSummary: Identifiable, Codable, Equatable, Hashable {
    enum SpeciesAccepted: String, Codable, CaseIterable {
        case dog, cat, both
    }
    enum SizeRange: String, Codable, CaseIterable {
        case small, medium, large
    }

    let id: UUID
    var name: String
    var species_accepted: SpeciesAccepted
    var size_range: SizeRange
    var capacity: Int
    var base_price_myr: Double
    var peak_price_myr: Double
    var instant_book: Bool
    var description: String?
}

/// Full listing payload: the business joined with its listing row (description,
/// amenities, house rules, cancellation policy, photos) + the active kennels.
struct Listing: Equatable {
    let business: BusinessSummary
    let houseRules: String?
    let amenities: [String]
    let cancellationPolicy: CancellationPolicy
    let photoPaths: [String]
    let kennels: [KennelTypeSummary]

    enum CancellationPolicy: String, Codable {
        case flexible, moderate, strict
    }
}

/// Search criteria collected by DiscoverView.
struct SearchCriteria: Equatable {
    var city: String
    var checkIn: Date
    var checkOut: Date
    var petID: UUID?

    var isValid: Bool {
        !city.trimmingCharacters(in: .whitespaces).isEmpty
            && checkOut > checkIn
    }
}
```

- [ ] **Step 2: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
```
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Sources/Listings/Listing.swift
git commit -m "feat(ios): listing + kennel + search-criteria models"
```

---

## Task 2: ListingRepository service

**Files:**
- Create: `ios/Sources/Listings/ListingRepository.swift`

- [ ] **Step 1: Write repository**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Listings/ListingRepository.swift`:
```swift
import Foundation
import Supabase

enum ListingRepositoryError: LocalizedError {
    case searchFailed(String)
    case detailFailed(String)
    case notFound

    var errorDescription: String? {
        switch self {
        case .searchFailed(let m): "Couldn't search listings: \(m)"
        case .detailFailed(let m): "Couldn't load listing: \(m)"
        case .notFound: "Listing not found."
        }
    }
}

@MainActor
final class ListingRepository {
    let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Case-insensitive substring match on city; returns verified + active
    /// businesses that have at least one listing row. Availability is not
    /// considered here (Phase 2c runs the real check at booking-intent time).
    func search(criteria: SearchCriteria) async throws -> [BusinessSummary] {
        let cityPattern = "%\(criteria.city.trimmingCharacters(in: .whitespaces))%"
        do {
            let rows: [BusinessSummary] = try await client.from("businesses")
                .select("id, name, slug, city, state, description, cover_photo_url")
                .eq("kyc_status", value: "verified")
                .eq("status", value: "active")
                .ilike("city", pattern: cityPattern)
                .order("name", ascending: true)
                .execute()
                .value
            return rows
        } catch {
            throw ListingRepositoryError.searchFailed(error.localizedDescription)
        }
    }

    /// Load the full listing detail for a given business.
    func detail(businessId: UUID) async throws -> Listing {
        struct BusinessRow: Decodable {
            let id: UUID
            let name: String
            let slug: String
            let city: String
            let state: String
            let description: String?
            let cover_photo_url: String?
        }
        struct ListingRow: Decodable {
            let id: UUID
            let photos: [String]
            let amenities: [String]
            let house_rules: String?
            let cancellation_policy: String
        }

        do {
            let business: BusinessRow = try await client.from("businesses")
                .select("id, name, slug, city, state, description, cover_photo_url")
                .eq("id", value: businessId.uuidString)
                .single()
                .execute()
                .value

            let listingRow: ListingRow = try await client.from("listings")
                .select("id, photos, amenities, house_rules, cancellation_policy")
                .eq("business_id", value: businessId.uuidString)
                .single()
                .execute()
                .value

            let kennels: [KennelTypeSummary] = try await client.from("kennel_types")
                .select("id, name, species_accepted, size_range, capacity, base_price_myr, peak_price_myr, instant_book, description")
                .eq("listing_id", value: listingRow.id.uuidString)
                .eq("active", value: true)
                .order("base_price_myr", ascending: true)
                .execute()
                .value

            let policy = Listing.CancellationPolicy(rawValue: listingRow.cancellation_policy) ?? .moderate
            return Listing(
                business: BusinessSummary(
                    id: business.id,
                    name: business.name,
                    slug: business.slug,
                    city: business.city,
                    state: business.state,
                    description: business.description,
                    cover_photo_url: business.cover_photo_url
                ),
                houseRules: listingRow.house_rules,
                amenities: listingRow.amenities,
                cancellationPolicy: policy,
                photoPaths: listingRow.photos,
                kennels: kennels
            )
        } catch {
            throw ListingRepositoryError.detailFailed(error.localizedDescription)
        }
    }

    /// Return the public URL for a listing-photos path. Sync call; the SDK
    /// just formats the URL, no network involved.
    func publicPhotoURL(for path: String) -> URL? {
        let response = client.storage.from("listing-photos").getPublicURL(path: path)
        return (try? response).flatMap { URL(string: $0.absoluteString) }
    }
}
```

- [ ] **Step 2: Note on `getPublicURL`**

If `getPublicURL(path:)` returns `URL` directly (not `throws`) on your supabase-swift version, simplify to:

```swift
func publicPhotoURL(for path: String) -> URL? {
    (try? client.storage.from("listing-photos").getPublicURL(path: path)) ?? nil
}
```

If it returns a non-throwing `URL`:
```swift
func publicPhotoURL(for path: String) -> URL? {
    client.storage.from("listing-photos").getPublicURL(path: path)
}
```

Pick the form that compiles. Report which.

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
git add ios/Sources/Listings/ListingRepository.swift
git commit -m "feat(ios): ListingRepository with search + detail + photo URL"
```

---

## Task 3: Extend AppState with ListingRepository

**Files:**
- Modify: `ios/Sources/App/AppState.swift`

- [ ] **Step 1: Replace AppState contents**

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

    init() {
        let client = SupabaseClientProvider.shared
        self.authService = AuthService(client: client)
        self.petService = PetService(client: client)
        self.listingRepository = ListingRepository(client: client)
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
git commit -m "feat(ios): wire ListingRepository into AppState"
```

---

## Task 4: DiscoverView (search form)

**Files:**
- Create: `ios/Sources/Listings/DiscoverView.swift`

- [ ] **Step 1: Write view**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Listings/DiscoverView.swift`:
```swift
import SwiftUI

struct DiscoverView: View {
    @Environment(AppState.self) private var appState
    @State private var criteria = SearchCriteria(
        city: "Kuala Lumpur",
        checkIn: Self.defaultCheckIn(),
        checkOut: Self.defaultCheckOut(),
        petID: nil
    )
    @State private var pets: [Pet] = []
    @State private var errorMessage: String?
    @State private var isLoadingPets = false
    @State private var navPath = NavigationPath()

    private static func defaultCheckIn() -> Date {
        Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    }
    private static func defaultCheckOut() -> Date {
        Calendar.current.date(byAdding: .day, value: 12, to: Date()) ?? Date()
    }

    var body: some View {
        NavigationStack(path: $navPath) {
            Form {
                Section {
                    TextField("City", text: $criteria.city)
                }
                Section {
                    DatePicker(
                        "Check-in",
                        selection: $criteria.checkIn,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    DatePicker(
                        "Check-out",
                        selection: $criteria.checkOut,
                        in: (criteria.checkIn.addingTimeInterval(86_400))...,
                        displayedComponents: .date
                    )
                }
                Section("Pet") {
                    if isLoadingPets {
                        ProgressView()
                    } else if pets.isEmpty {
                        Text("You haven't added a pet yet. Tap the Pets tab to add one.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Pet", selection: $criteria.petID) {
                            ForEach(pets) { pet in
                                Text(pet.name).tag(Optional(pet.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        navPath.append(criteria)
                    } label: {
                        HStack {
                            Spacer()
                            Text("Search")
                                .fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(!criteria.isValid)
                }
            }
            .navigationTitle("Find boarding")
            .navigationDestination(for: SearchCriteria.self) { c in
                SearchResultsView(criteria: c)
            }
            .navigationDestination(for: BusinessSummary.self) { biz in
                ListingDetailView(business: biz)
            }
            .task { await loadPets() }
        }
    }

    private func loadPets() async {
        isLoadingPets = true
        defer { isLoadingPets = false }
        do {
            pets = try await appState.petService.listPets()
            if criteria.petID == nil { criteria.petID = pets.first?.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

extension SearchCriteria: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(city)
        hasher.combine(checkIn)
        hasher.combine(checkOut)
        hasher.combine(petID)
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
git add ios/Sources/Listings/DiscoverView.swift
git commit -m "feat(ios): DiscoverView — city + dates + pet picker search form"
```

---

## Task 5: SearchResultsView

**Files:**
- Create: `ios/Sources/Listings/SearchResultsView.swift`

- [ ] **Step 1: Write view**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Listings/SearchResultsView.swift`:
```swift
import SwiftUI

struct SearchResultsView: View {
    @Environment(AppState.self) private var appState
    let criteria: SearchCriteria

    @State private var results: [BusinessSummary] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var nights: Int {
        max(1, Calendar.current.dateComponents([.day], from: criteria.checkIn, to: criteria.checkOut).day ?? 1)
    }

    var body: some View {
        List {
            Section {
                if results.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No listings found",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different city or dates.")
                    )
                }
                ForEach(results) { biz in
                    NavigationLink(value: biz) {
                        BusinessCardRow(business: biz)
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("\(nights) night\(nights == 1 ? "" : "s") in \(criteria.city) · \(results.count) place\(results.count == 1 ? "" : "s")")
                    .textCase(nil)
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .overlay {
            if isLoading && results.isEmpty { ProgressView() }
        }
        .navigationTitle("Results")
        .task { await search() }
    }

    private func search() async {
        isLoading = true
        defer { isLoading = false }
        do {
            results = try await appState.listingRepository.search(criteria: criteria)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct BusinessCardRow: View {
    let business: BusinessSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            heroImage
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                Text(business.name)
                    .font(.headline)
                Text("\(business.city), \(business.state)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let desc = business.description, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var heroImage: some View {
        if let urlString = business.cover_photo_url, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: placeholderGradient
                }
            }
        } else {
            placeholderGradient
        }
    }

    private var placeholderGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.99, green: 0.86, blue: 0.58), Color(red: 0.96, green: 0.61, blue: 0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
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
git add ios/Sources/Listings/SearchResultsView.swift
git commit -m "feat(ios): SearchResultsView — business card list"
```

---

## Task 6: ListingDetailView + BookingPlaceholderView

**Files:**
- Create: `ios/Sources/Listings/ListingDetailView.swift`
- Create: `ios/Sources/Listings/BookingPlaceholderView.swift`

- [ ] **Step 1: Write BookingPlaceholderView**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Listings/BookingPlaceholderView.swift`:
```swift
import SwiftUI

struct BookingPlaceholderView: View {
    let business: BusinessSummary
    let kennel: KennelTypeSummary
    let criteria: SearchCriteria

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Coming in Phase 2c")
                .font(.title2).fontWeight(.semibold)
            Text(
                "The booking request flow lands here. For now, you've picked:\n"
                + "\(business.name) · \(kennel.name) · "
                + "\(criteria.checkIn.formatted(date: .abbreviated, time: .omitted)) → "
                + "\(criteria.checkOut.formatted(date: .abbreviated, time: .omitted))."
            )
            .multilineTextAlignment(.center)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
        }
        .padding()
        .navigationTitle("Continue")
    }
}
```

- [ ] **Step 2: Write ListingDetailView**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Listings/ListingDetailView.swift`:
```swift
import SwiftUI

struct ListingDetailView: View {
    @Environment(AppState.self) private var appState
    let business: BusinessSummary

    @State private var listing: Listing?
    @State private var selectedKennelID: UUID?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photoCarousel
                content
            }
            .padding(.vertical)
        }
        .navigationTitle(business.name)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if let kennel = selectedKennel {
                continueBar(for: kennel)
            }
        }
        .overlay {
            if isLoading && listing == nil { ProgressView() }
        }
        .task { await load() }
    }

    private var selectedKennel: KennelTypeSummary? {
        listing?.kennels.first { $0.id == selectedKennelID }
    }

    private var photoCarousel: some View {
        TabView {
            if let paths = listing?.photoPaths, !paths.isEmpty {
                ForEach(paths, id: \.self) { path in
                    photo(for: path)
                }
            } else {
                placeholderGradient
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(height: 260)
    }

    @ViewBuilder
    private func photo(for path: String) -> some View {
        if let url = appState.listingRepository.publicPhotoURL(for: path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().scaledToFill()
                default: placeholderGradient
                }
            }
            .clipped()
        } else {
            placeholderGradient
        }
    }

    private var placeholderGradient: some View {
        LinearGradient(
            colors: [Color(red: 0.99, green: 0.86, blue: 0.58), Color(red: 0.96, green: 0.61, blue: 0.15)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(business.name).font(.title2).fontWeight(.semibold)
            Text("\(business.city), \(business.state)").font(.subheadline).foregroundStyle(.secondary)

            if let desc = business.description, !desc.isEmpty {
                Text(desc)
            }

            if let amenities = listing?.amenities, !amenities.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Amenities").font(.subheadline).fontWeight(.semibold)
                    Text(amenities.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let rules = listing?.houseRules, !rules.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("House rules").font(.subheadline).fontWeight(.semibold)
                    Text(rules).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Divider().padding(.vertical, 4)

            Text("Choose a room").font(.headline)
            if let kennels = listing?.kennels, !kennels.isEmpty {
                ForEach(kennels) { kennel in
                    kennelRow(kennel)
                }
            } else if !isLoading {
                Text("No rooms available at the moment.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .padding(.horizontal)
    }

    private func kennelRow(_ kennel: KennelTypeSummary) -> some View {
        Button {
            selectedKennelID = kennel.id
        } label: {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(kennel.name).font(.subheadline).fontWeight(.semibold)
                    Text(kennel.species_accepted.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if kennel.instant_book {
                        Text("Instant book")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("RM \(kennel.base_price_myr, specifier: "%.0f")")
                        .font(.subheadline).fontWeight(.semibold)
                    Text("/ night").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(selectedKennelID == kennel.id ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: selectedKennelID == kennel.id ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func continueBar(for kennel: KennelTypeSummary) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(kennel.name).font(.caption).foregroundStyle(.secondary)
                Text("RM \(kennel.base_price_myr, specifier: "%.0f") / night")
                    .font(.subheadline).fontWeight(.semibold)
            }
            Spacer()
            NavigationLink {
                BookingPlaceholderView(
                    business: business,
                    kennel: kennel,
                    criteria: defaultCriteriaForContinue()
                )
            } label: {
                Text("Continue").fontWeight(.semibold).padding(.horizontal, 20).padding(.vertical, 10)
                    .background(Color.accentColor, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    /// Placeholder criteria for the 2b Continue stub. 2c will thread through the
    /// real SearchCriteria from DiscoverView → ResultsView → this view.
    private func defaultCriteriaForContinue() -> SearchCriteria {
        let today = Date()
        let week = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
        let weekPlusFive = Calendar.current.date(byAdding: .day, value: 5, to: week) ?? week
        return SearchCriteria(
            city: business.city,
            checkIn: week,
            checkOut: weekPlusFive,
            petID: nil
        )
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let detail = try await appState.listingRepository.detail(businessId: business.id)
            listing = detail
            selectedKennelID = detail.kennels.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

Note on `"RM \(kennel.base_price_myr, specifier: "%.0f")"`: Phase 2a hit an issue with this interpolation syntax under iOS 26 SDK. If the build errors out on that line, replace with `String(format: "RM %.0f", kennel.base_price_myr)` exactly as was done in 2a. Apply the fix across all three such interpolation sites in this file and report.

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
git add ios/Sources/Listings/ListingDetailView.swift ios/Sources/Listings/BookingPlaceholderView.swift
git commit -m "feat(ios): ListingDetailView with photo carousel, kennel picker, continue stub"
```

---

## Task 7: TabView wrap in RootView

Replace the single-surface PetListView with a TabView of Discover + Pets.

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
                .tabItem {
                    Label("Discover", systemImage: "magnifyingglass")
                }
            PetListView()
                .tabItem {
                    Label("Pets", systemImage: "pawprint")
                }
        }
    }
}
```

- [ ] **Step 2: Build + manual smoke (optional — final check happens in Task 9)**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=
```

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Sources/App/RootView.swift
git commit -m "feat(ios): TabView wrap — Discover + Pets"
```

---

## Task 8: XCTest — repository smoke test

**Files:**
- Create: `ios/Tests/ListingRepositoryTests.swift`

- [ ] **Step 1: Write tests**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Tests/ListingRepositoryTests.swift`:
```swift
import XCTest
@testable import PetBnB

final class ListingRepositoryTests: XCTestCase {
    func test_search_criteria_validity() {
        let valid = SearchCriteria(
            city: "KL",
            checkIn: Date(),
            checkOut: Date().addingTimeInterval(86_400),
            petID: nil
        )
        XCTAssertTrue(valid.isValid)

        let noCity = SearchCriteria(
            city: "",
            checkIn: Date(),
            checkOut: Date().addingTimeInterval(86_400),
            petID: nil
        )
        XCTAssertFalse(noCity.isValid)

        let invertedDates = SearchCriteria(
            city: "KL",
            checkIn: Date().addingTimeInterval(86_400),
            checkOut: Date(),
            petID: nil
        )
        XCTAssertFalse(invertedDates.isValid)
    }

    func test_listing_cancellation_policy_raw() {
        XCTAssertEqual(Listing.CancellationPolicy.flexible.rawValue, "flexible")
        XCTAssertEqual(Listing.CancellationPolicy.moderate.rawValue, "moderate")
        XCTAssertEqual(Listing.CancellationPolicy.strict.rawValue, "strict")
    }

    func test_business_summary_codable_roundtrip() throws {
        let biz = BusinessSummary(
            id: UUID(),
            name: "Test",
            slug: "test",
            city: "KL",
            state: "WP",
            description: "desc",
            cover_photo_url: nil
        )
        let data = try JSONEncoder().encode(biz)
        let decoded = try JSONDecoder().decode(BusinessSummary.self, from: data)
        XCTAssertEqual(biz, decoded)
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
If iPhone 17 isn't available, list via `xcrun simctl list devices available` and use whatever iPhone simulator is booted or installed. Report which you used.

Expected: TEST SUCCEEDED, 8 tests passing (5 prior + 3 new).

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Tests/ListingRepositoryTests.swift
git commit -m "test(ios): XCTest for SearchCriteria + Listing models"
```

---

## Task 9: README + handoff

**Files:**
- Modify: `ios/README.md`
- Modify: root `PetBnB/README.md`

- [ ] **Step 1: Append to `ios/README.md`**

Append after existing "Handoff to Phase 2b" and "Phase 2a limitations" sections:

```markdown

## Phase 2b — Discover + browse

1. `RootView` now wraps the authenticated app in a `TabView` with Discover + Pets tabs.
2. `DiscoverView` collects a `SearchCriteria` (city, check-in, check-out, selected pet) and pushes to `SearchResultsView`.
3. `SearchResultsView` calls `ListingRepository.search(criteria:)` — case-insensitive city match, filtered to `kyc_status='verified' AND status='active'` via existing Phase 0 RLS.
4. Tapping a result pushes to `ListingDetailView` which calls `ListingRepository.detail(businessId:)` to fetch the business + listing + active kennels.
5. `ListingDetailView` has a photo carousel (built from `listing-photos` public bucket URLs) and a kennel picker. Tapping Continue navigates to `BookingPlaceholderView` — the real booking flow lands here in Phase 2c.
6. Availability-aware filtering isn't done yet. The search returns any verified/active business in the city; Phase 2c runs the real availability check at booking-intent creation.

## Known Phase 2b limitations

- No ratings / review counts — still shows placeholder; wires up in Phase 4.
- No favorites/wishlist.
- No map view or distance-to-user.
- No availability filter on search (Phase 2c).
- Photo carousel has no full-screen zoom.
- `BookingPlaceholderView` uses synthetic dates (today+7 → today+12) because the Phase 2b nav doesn't thread the real `SearchCriteria` through to the detail screen. Phase 2c plumbs it properly when the real booking-request screen takes over.
```

- [ ] **Step 2: Update root `PetBnB/README.md`**

Add to the Status section:
```
- [x] **Phase 2b** — iOS Discover + search + listing detail (browse)
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
All must succeed. pgTAP 79, web Playwright 4, iOS XCTest 8.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/README.md README.md
git commit -m "docs: Phase 2b README and browse-flow handoff"
```

---

## Phase 2b complete — final checklist

- [ ] `git log --oneline | head -15` shows 9 new commits on top of Phase 2a (88 total).
- [ ] `supabase test db` — 79 pgTAP passing.
- [ ] `pnpm exec playwright test` — 4 web tests passing.
- [ ] `xcodebuild test` — 8 iOS tests passing.
- [ ] Manual smoke: launch simulator, sign in, Discover tab, Search — see 2 seeded businesses, tap one, see ListingDetail, tap a kennel, tap Continue → BookingPlaceholder.
- [ ] No credentials committed: `git log -p 89d5400..HEAD | grep -E "(eyJ[A-Za-z0-9_-]{20,}|sb_secret_|sk_live_)"` empty.

Push:
```bash
git push origin main
```

Then plan Phase 2c (booking creation + payment-intent stub + My Bookings).
