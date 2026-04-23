# PetBnB Phase 2a — iOS Scaffold + Auth + Pet Profiles

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the iOS owner app at `PetBnB/ios/` so a pet owner can sign up, sign in, create and list pets, upload a vaccination cert, and view their pet's cert metadata. Foundation for Phase 2b (browse + listing detail) and 2c (booking flow).

**Architecture:** SwiftUI app, iOS 17+. Project generated via `xcodegen` from a YAML spec (same pattern as the Court Booking POC at `Primary/CourtBooking/`). Supabase Swift SDK installed via Swift Package Manager. Auth + API calls go through the Supabase client; Observable state (iOS 17 `@Observable` macro) holds session + pet data for views. New Storage bucket `pet-vaccinations` on the Supabase side scopes cert files to the pet's owner via path-based RLS (mirrors the `kyc-documents` pattern from Phase 1b).

**Tech Stack:**
- Swift 5.9+, iOS 17+ deployment target
- SwiftUI App lifecycle, `NavigationStack`, `Observable` macro
- `supabase-swift` (supabase-community/supabase-swift) 2.x via SPM
- `xcodegen` to generate the Xcode project from `project.yml`
- `xcodebuild` for CI/scripted compile + XCTest runs
- pgTAP (reused from Phase 0) for the new Storage bucket RLS

**Spec references:** §8 (owner iOS flow)
**Phase 1 handoff:** `/Users/fabian/CodingProject/Primary/PetBnB/web/README.md`

**Scope in this slice:**
- `pet-vaccinations` Storage bucket + owner-scoped RLS + pgTAP
- Xcode project scaffold at `PetBnB/ios/` via xcodegen
- Supabase Swift client wrapper + environment config (xcconfig-driven)
- Auth flow: email+password sign-up / sign-in, session persistence via Supabase SDK's default Keychain storage
- Pet list screen, Add Pet form, Pet detail view with vaccination cert upload (PDF/JPEG/PNG)
- XCTest unit tests for the auth + pet services
- `xcodebuild build` + `xcodebuild test` both green
- README with run instructions

**Out of scope (explicitly deferred):**
- Discover / search / listing browse — Phase 2b
- Booking creation / payment / My Bookings — Phase 2c
- Real iPay88 integration — Phase 3
- Push notifications, Realtime subscriptions — Phase 2d
- TabView / multi-tab navigation — add in 2b when there are 3+ surfaces
- Pet edit / delete UI — defer to 2b or later; 2a just supports create + read
- Profile settings screen (display_name, language, etc.) — later slice
- Dark-mode tuning — iOS defaults fine for now
- Localization beyond English — Phase 5+ (spec allows `preferred_lang` but no UI pressure yet)
- App Store metadata, screenshots, submission — out of Phase 2 entirely

**Phase 2a success criteria:**
1. `cd ios && xcodegen generate` produces `PetBnB.xcodeproj` from `project.yml`.
2. `xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator'` succeeds.
3. `xcodebuild test` runs XCTest suite with ≥ 3 unit tests passing.
4. Running the app on an iOS 17+ simulator: sign-up → Pet list (empty) → Add pet ("Mochi / Poodle / 8 kg") → Pet detail shows pet → Upload PDF cert → cert metadata appears with filename + expiry.
5. pgTAP test passes: cross-owner cannot SELECT or INSERT pet-vaccinations files.
6. `supabase test db` assertions all green.

---

## File structure

```
PetBnB/
├── supabase/
│   ├── migrations/
│   │   └── 018_pet_vaccinations_storage.sql      (NEW)
│   └── tests/
│       └── 014_pet_vaccinations_rls.sql          (NEW)
└── ios/                                          (NEW — Xcode project root)
    ├── .gitignore
    ├── README.md
    ├── project.yml
    ├── Config/
    │   ├── Shared.xcconfig                        (placeholders, tracked)
    │   └── Shared.local.xcconfig.example          (tracked template)
    ├── Sources/
    │   ├── PetBnBApp.swift                        (@main, wires root)
    │   ├── Info.plist
    │   ├── App/
    │   │   ├── RootView.swift                     (auth-gated router)
    │   │   └── AppState.swift                     (Observable root state)
    │   ├── Auth/
    │   │   ├── AuthService.swift
    │   │   ├── SignInView.swift
    │   │   └── SignUpView.swift
    │   ├── Pets/
    │   │   ├── Pet.swift                          (Codable model)
    │   │   ├── PetService.swift
    │   │   ├── PetListView.swift
    │   │   ├── AddPetView.swift
    │   │   ├── PetDetailView.swift
    │   │   └── VaccinationCert.swift
    │   ├── Supabase/
    │   │   ├── SupabaseEnv.swift                  (reads xcconfig values)
    │   │   └── SupabaseClientProvider.swift
    │   └── Assets.xcassets/                       (stub AppIcon + AccentColor)
    └── Tests/
        ├── PetBnBTests.swift                      (XCTestCase top-level)
        ├── AuthServiceTests.swift
        └── PetServiceTests.swift
```

Tracked vs. gitignored:
- `Config/Shared.local.xcconfig` — **gitignored** (real secrets if any; local dev URL + anon key are low-sensitivity but keep them out per convention).
- `PetBnB.xcodeproj/` — **gitignored** (generated by xcodegen).
- `DerivedData/`, `build/`, `.build/`, `.swiftpm/` — **gitignored**.

---

## Task 1: Storage bucket + RLS migration (pet-vaccinations)

**Files:**
- Create: `supabase/migrations/018_pet_vaccinations_storage.sql`

- [ ] **Step 1: Write migration**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/migrations/018_pet_vaccinations_storage.sql`:
```sql
-- Pet vaccination certificates. Private bucket; only the pet's owner
-- can read or write. Path convention: pets/{pet_id}/{unique-filename}

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'pet-vaccinations',
  'pet-vaccinations',
  false,
  10485760,                                   -- 10 MiB
  ARRAY['application/pdf','image/jpeg','image/png']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

-- RLS: pet's owner can CRUD. Check via join: the second path segment must
-- be a pet UUID whose owner_id = auth.uid().
DROP POLICY IF EXISTS "pet_vax_owner_all" ON storage.objects;
CREATE POLICY "pet_vax_owner_all"
ON storage.objects
FOR ALL
TO authenticated
USING (
  bucket_id = 'pet-vaccinations'
  AND coalesce(array_length(storage.foldername(name), 1), 0) >= 2
  AND (storage.foldername(name))[1] = 'pets'
  AND (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND EXISTS (
    SELECT 1 FROM pets
    WHERE id = (storage.foldername(name))[2]::uuid
      AND owner_id = auth.uid()
  )
)
WITH CHECK (
  bucket_id = 'pet-vaccinations'
  AND coalesce(array_length(storage.foldername(name), 1), 0) >= 2
  AND (storage.foldername(name))[1] = 'pets'
  AND (storage.foldername(name))[2] ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  AND EXISTS (
    SELECT 1 FROM pets
    WHERE id = (storage.foldername(name))[2]::uuid
      AND owner_id = auth.uid()
  )
);
```

- [ ] **Step 2: Apply + verify**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
supabase db reset
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "SELECT id, public, file_size_limit FROM storage.buckets WHERE id = 'pet-vaccinations';"
psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -c "SELECT policyname FROM pg_policies WHERE policyname = 'pet_vax_owner_all';"
```
Expected: bucket row with `public=f`, one policy row.

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/migrations/018_pet_vaccinations_storage.sql
git commit -m "feat(db): pet-vaccinations Storage bucket with owner-scoped RLS"
```

---

## Task 2: pgTAP — cross-owner blocked

**Files:**
- Create: `supabase/tests/014_pet_vaccinations_rls.sql`

- [ ] **Step 1: Write test**

Create `/Users/fabian/CodingProject/Primary/PetBnB/supabase/tests/014_pet_vaccinations_rls.sql`:
```sql
BEGIN;
SELECT plan(5);

-- Two owners, each with a pet
INSERT INTO auth.users (id, email) VALUES
  ('11111111-2a00-0000-0000-000000000001', 'alice2a@t'),
  ('11111111-2a00-0000-0000-000000000002', 'bob2a@t');
INSERT INTO user_profiles (id, display_name) VALUES
  ('11111111-2a00-0000-0000-000000000001', 'Alice'),
  ('11111111-2a00-0000-0000-000000000002', 'Bob');
INSERT INTO pets (id, owner_id, name, species) VALUES
  ('aaaa2a00-0000-0000-0000-000000000001', '11111111-2a00-0000-0000-000000000001', 'Mochi', 'dog'),
  ('aaaa2a00-0000-0000-0000-000000000002', '11111111-2a00-0000-0000-000000000002', 'Luna', 'cat');

-- Seed one file per pet as postgres (bypass RLS)
INSERT INTO storage.objects (bucket_id, name, owner, metadata) VALUES
  ('pet-vaccinations',
   'pets/aaaa2a00-0000-0000-0000-000000000001/cert.pdf',
   '11111111-2a00-0000-0000-000000000001',
   '{"mimetype":"application/pdf"}'::jsonb),
  ('pet-vaccinations',
   'pets/aaaa2a00-0000-0000-0000-000000000002/cert.pdf',
   '11111111-2a00-0000-0000-000000000002',
   '{"mimetype":"application/pdf"}'::jsonb);

-- Alice
SET LOCAL request.jwt.claim.sub = '11111111-2a00-0000-0000-000000000001';
SET LOCAL role = 'authenticated';

SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='pet-vaccinations'),
  1, 'Alice sees only her pet cert');
SELECT lives_ok(
  $$ INSERT INTO storage.objects (bucket_id, name, owner, metadata)
     VALUES ('pet-vaccinations',
             'pets/aaaa2a00-0000-0000-0000-000000000001/cert2.pdf',
             '11111111-2a00-0000-0000-000000000001',
             '{"mimetype":"application/pdf"}'::jsonb) $$,
  'Alice can insert under her own pet');

SELECT throws_ok(
  $$ INSERT INTO storage.objects (bucket_id, name, owner, metadata)
     VALUES ('pet-vaccinations',
             'pets/aaaa2a00-0000-0000-0000-000000000002/hack.pdf',
             '11111111-2a00-0000-0000-000000000001',
             '{"mimetype":"application/pdf"}'::jsonb) $$,
  '42501', NULL,
  'Alice cannot insert under Bob''s pet');

-- Anonymous
RESET role;
SET LOCAL role = 'anon';
SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='pet-vaccinations'),
  0, 'anon sees nothing in private bucket');

-- A different authenticated user (no pets)
INSERT INTO auth.users (id, email) VALUES ('11111111-2a00-0000-0000-000000000099', 'carol@t');
INSERT INTO user_profiles (id, display_name) VALUES ('11111111-2a00-0000-0000-000000000099', 'Carol');
RESET role;
SET LOCAL request.jwt.claim.sub = '11111111-2a00-0000-0000-000000000099';
SET LOCAL role = 'authenticated';

SELECT is((SELECT count(*)::int FROM storage.objects WHERE bucket_id='pet-vaccinations'),
  0, 'user with no pets sees no pet-vaccination files');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
supabase test db
```
Expected: 79 assertions passing (74 prior + 5 new).

- [ ] **Step 3: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add supabase/tests/014_pet_vaccinations_rls.sql
git commit -m "test(db): pet-vaccinations Storage RLS (owner-only)"
```

---

## Task 3: iOS project scaffold with xcodegen

**Files:**
- Create: `ios/.gitignore`
- Create: `ios/project.yml`
- Create: `ios/Config/Shared.xcconfig`
- Create: `ios/Config/Shared.local.xcconfig.example`
- Create: `ios/Sources/Info.plist`
- Create: `ios/Sources/Assets.xcassets/AppIcon.appiconset/Contents.json`
- Create: `ios/Sources/Assets.xcassets/AccentColor.colorset/Contents.json`
- Create: `ios/Sources/Assets.xcassets/Contents.json`
- Create: `ios/Sources/PetBnBApp.swift` (minimal — will be fleshed out in Task 9)

- [ ] **Step 1: Verify xcodegen**

```bash
xcodegen --version
```
If missing: `brew install xcodegen`. Need ≥ 2.39.

- [ ] **Step 2: Write `ios/.gitignore`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/.gitignore`:
```
# Xcode / generated
PetBnB.xcodeproj
DerivedData
build
.build
.swiftpm

# Local secrets
Config/Shared.local.xcconfig

# OS
.DS_Store
```

- [ ] **Step 3: Write `project.yml`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/project.yml`:
```yaml
name: PetBnB
options:
  bundleIdPrefix: my.fabian.petbnb
  deploymentTarget:
    iOS: "17.0"
  developmentLanguage: en
  xcodeVersion: "15.0"

settings:
  base:
    SWIFT_VERSION: "5.9"
    IPHONEOS_DEPLOYMENT_TARGET: "17.0"
    SUPPORTED_PLATFORMS: "iphoneos iphonesimulator"
    TARGETED_DEVICE_FAMILY: "1,2"
    ENABLE_USER_SCRIPT_SANDBOXING: NO

configs:
  Debug: debug
  Release: release

packages:
  Supabase:
    url: https://github.com/supabase-community/supabase-swift
    from: 2.24.0

targets:
  PetBnB:
    type: application
    platform: iOS
    deploymentTarget: "17.0"
    sources:
      - path: Sources
    resources:
      - path: Sources/Assets.xcassets
    configFiles:
      Debug: Config/Shared.xcconfig
      Release: Config/Shared.xcconfig
    info:
      path: Sources/Info.plist
      properties:
        CFBundleDisplayName: PetBnB
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        UILaunchScreen:
          UIColorName: AccentColor
        UIApplicationSceneManifest:
          UIApplicationSupportsMultipleScenes: false
        NSPhotoLibraryUsageDescription: "Upload photos of your pet and their vaccination certificates."
        NSAppTransportSecurity:
          NSAllowsLocalNetworking: true
    settings:
      base:
        PRODUCT_NAME: PetBnB
        PRODUCT_BUNDLE_IDENTIFIER: my.fabian.petbnb.app
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME: AccentColor
        CODE_SIGN_STYLE: Automatic
        CODE_SIGNING_ALLOWED: NO   # simulator-only dev; flip for device/store
        SUPABASE_URL: $(SUPABASE_URL)
        SUPABASE_ANON_KEY: $(SUPABASE_ANON_KEY)
    dependencies:
      - package: Supabase
        product: Supabase

  PetBnBTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: Tests
    dependencies:
      - target: PetBnB
    settings:
      base:
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/PetBnB.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/PetBnB"
        BUNDLE_LOADER: "$(TEST_HOST)"

schemes:
  PetBnB:
    build:
      targets:
        PetBnB: all
        PetBnBTests: test
    test:
      targets:
        - PetBnBTests
    run:
      config: Debug
    archive:
      config: Release
```

- [ ] **Step 4: Write xcconfig files**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Config/Shared.xcconfig`:
```
// Shared build settings. Include local secrets in Shared.local.xcconfig
// (gitignored). That file must define SUPABASE_URL and SUPABASE_ANON_KEY.

#include? "Shared.local.xcconfig"

// Defaults (safe to commit). Overridden by Shared.local.xcconfig if present.
SUPABASE_URL = http:/$()/127.0.0.1:54321
SUPABASE_ANON_KEY = REPLACE_WITH_PUBLISHABLE_KEY
```

(The `$()` trick is required because xcconfig treats `//` as a comment; splitting the protocol with empty interpolation preserves the URL at build time.)

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Config/Shared.local.xcconfig.example`:
```
// Copy to Shared.local.xcconfig and paste in the real values from `supabase status`.
// Shared.local.xcconfig is gitignored.

SUPABASE_URL = http:/$()/127.0.0.1:54321
SUPABASE_ANON_KEY = sb_publishable_paste_here
```

- [ ] **Step 5: Write `Info.plist`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Info.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>SUPABASE_URL</key>
    <string>$(SUPABASE_URL)</string>
    <key>SUPABASE_ANON_KEY</key>
    <string>$(SUPABASE_ANON_KEY)</string>
</dict>
</plist>
```

(xcodegen will merge this with the properties it injects from project.yml. xcconfig values land as `$(VAR)` placeholders that Xcode substitutes at build time.)

- [ ] **Step 6: Write Asset catalog stubs**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Assets.xcassets/Contents.json`:
```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Assets.xcassets/AppIcon.appiconset/Contents.json`:
```json
{
  "images" : [
    {
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Assets.xcassets/AccentColor.colorset/Contents.json`:
```json
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : { "alpha" : "1.000", "blue" : "0.94", "green" : "0.64", "red" : "0.43" }
      },
      "idiom" : "universal"
    }
  ],
  "info" : { "author" : "xcode", "version" : 1 }
}
```

- [ ] **Step 7: Write minimal `PetBnBApp.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/PetBnBApp.swift`:
```swift
import SwiftUI

@main
struct PetBnBApp: App {
    var body: some Scene {
        WindowGroup {
            // Fleshed out in Task 9 (RootView with auth gate + tabs).
            Text("PetBnB — booting…")
                .font(.headline)
        }
    }
}
```

- [ ] **Step 8: Copy xcconfig + generate project**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
cp Config/Shared.local.xcconfig.example Config/Shared.local.xcconfig
# then edit Config/Shared.local.xcconfig to paste in the real Publishable key
# from `supabase status` (run from the project root).
xcodegen generate
```
Expected: produces `PetBnB.xcodeproj` without warnings.

- [ ] **Step 9: Compile check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodebuild build \
  -project PetBnB.xcodeproj \
  -scheme PetBnB \
  -destination 'generic/platform=iOS Simulator' \
  -quiet
```
Expected: `BUILD SUCCEEDED`. SPM will download `supabase-swift` on first build (30–60s).

If `xcodebuild` complains about missing code signing despite `CODE_SIGNING_ALLOWED = NO`, pass `CODE_SIGN_IDENTITY= DEVELOPMENT_TEAM=` as extra args.

- [ ] **Step 10: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/
git commit -m "feat(ios): scaffold PetBnB iOS app (xcodegen + SPM + Supabase)"
```

---

## Task 4: Supabase client wrapper + environment loader

**Files:**
- Create: `ios/Sources/Supabase/SupabaseEnv.swift`
- Create: `ios/Sources/Supabase/SupabaseClientProvider.swift`

- [ ] **Step 1: Write `SupabaseEnv.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Supabase/SupabaseEnv.swift`:
```swift
import Foundation

enum SupabaseEnvError: Error {
    case missing(String)
    case invalidURL(String)
}

struct SupabaseEnv {
    let url: URL
    let anonKey: String

    static func loadFromBundle() throws -> SupabaseEnv {
        let bundle = Bundle.main
        guard let urlString = bundle.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
              !urlString.isEmpty else {
            throw SupabaseEnvError.missing("SUPABASE_URL")
        }
        guard let key = bundle.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String,
              !key.isEmpty, key != "REPLACE_WITH_PUBLISHABLE_KEY" else {
            throw SupabaseEnvError.missing("SUPABASE_ANON_KEY")
        }
        guard let url = URL(string: urlString) else {
            throw SupabaseEnvError.invalidURL(urlString)
        }
        return SupabaseEnv(url: url, anonKey: key)
    }
}
```

- [ ] **Step 2: Write `SupabaseClientProvider.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Supabase/SupabaseClientProvider.swift`:
```swift
import Foundation
import Supabase

/// App-wide access to the configured `SupabaseClient`. Fails fast at launch
/// if `Shared.local.xcconfig` wasn't filled in — better a clear startup error
/// than mysterious network failures later.
enum SupabaseClientProvider {
    static let shared: SupabaseClient = {
        do {
            let env = try SupabaseEnv.loadFromBundle()
            return SupabaseClient(supabaseURL: env.url, supabaseKey: env.anonKey)
        } catch {
            fatalError(
                "Supabase env not configured: \(error).\n" +
                "Run `supabase status` and paste the URL + Publishable key into " +
                "ios/Config/Shared.local.xcconfig."
            )
        }
    }()
}
```

- [ ] **Step 3: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Sources/Supabase/
git commit -m "feat(ios): Supabase client provider + env loader"
```

---

## Task 5: AuthService + AppState + Sign-in / Sign-up views

**Files:**
- Create: `ios/Sources/App/AppState.swift`
- Create: `ios/Sources/Auth/AuthService.swift`
- Create: `ios/Sources/Auth/SignInView.swift`
- Create: `ios/Sources/Auth/SignUpView.swift`

- [ ] **Step 1: Write `AppState.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/App/AppState.swift`:
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

    init() {
        let client = SupabaseClientProvider.shared
        self.authService = AuthService(client: client)
        self.petService = PetService(client: client)
    }

    /// Called on app launch. Observes the Supabase auth session; updates `status`.
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

- [ ] **Step 2: Write `AuthService.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Auth/AuthService.swift`:
```swift
import Foundation
import Supabase
import Auth

struct AuthSignUpInput {
    let email: String
    let password: String
    let displayName: String
}

enum AuthServiceError: LocalizedError {
    case signUpFailed(String)
    case signInFailed(String)
    case profileCreationFailed(String)

    var errorDescription: String? {
        switch self {
        case .signUpFailed(let m): "Sign up failed: \(m)"
        case .signInFailed(let m): "Sign in failed: \(m)"
        case .profileCreationFailed(let m): "Profile creation failed: \(m)"
        }
    }
}

@MainActor
final class AuthService {
    enum AuthEvent {
        case signedIn(userId: UUID, displayName: String)
        case signedOut
    }

    private let client: SupabaseClient
    private let profileFetcher: UserProfileFetcher

    init(client: SupabaseClient, profileFetcher: UserProfileFetcher? = nil) {
        self.client = client
        self.profileFetcher = profileFetcher ?? LiveUserProfileFetcher(client: client)
    }

    func signUp(_ input: AuthSignUpInput) async throws {
        do {
            let resp = try await client.auth.signUp(
                email: input.email,
                password: input.password,
                data: ["display_name": .string(input.displayName)]
            )
            let userId = resp.user.id

            // Insert profile row (RLS policy allows self-insert).
            do {
                try await client.from("user_profiles")
                    .insert(["id": userId.uuidString, "display_name": input.displayName])
                    .execute()
            } catch {
                throw AuthServiceError.profileCreationFailed(error.localizedDescription)
            }
        } catch let e as AuthServiceError {
            throw e
        } catch {
            throw AuthServiceError.signUpFailed(error.localizedDescription)
        }
    }

    func signIn(email: String, password: String) async throws {
        do {
            _ = try await client.auth.signIn(email: email, password: password)
        } catch {
            throw AuthServiceError.signInFailed(error.localizedDescription)
        }
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    /// Emits an event for every session change (and a synthetic first event for
    /// the current state on subscription).
    func authEvents() -> AsyncStream<AuthEvent> {
        AsyncStream { continuation in
            let task = Task { [profileFetcher, client] in
                for await (_, session) in client.auth.authStateChanges {
                    if let session {
                        let name = (try? await profileFetcher.displayName(for: session.user.id)) ?? session.user.email ?? "Unknown"
                        continuation.yield(.signedIn(userId: session.user.id, displayName: name))
                    } else {
                        continuation.yield(.signedOut)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

protocol UserProfileFetcher: Sendable {
    func displayName(for userId: UUID) async throws -> String?
}

struct LiveUserProfileFetcher: UserProfileFetcher {
    let client: SupabaseClient

    func displayName(for userId: UUID) async throws -> String? {
        struct Row: Decodable { let display_name: String }
        let rows: [Row] = try await client.from("user_profiles")
            .select("display_name")
            .eq("id", value: userId.uuidString)
            .limit(1)
            .execute()
            .value
        return rows.first?.display_name
    }
}
```

- [ ] **Step 3: Write `SignInView.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Auth/SignInView.swift`:
```swift
import SwiftUI

struct SignInView: View {
    @Environment(AppState.self) private var appState
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false
    @State private var showSignUp = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting { ProgressView() } else { Text("Sign in") }
                    }
                    .disabled(email.isEmpty || password.isEmpty || isSubmitting)
                    Button("Create an account") { showSignUp = true }
                }
            }
            .navigationTitle("PetBnB")
            .sheet(isPresented: $showSignUp) { SignUpView() }
        }
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await appState.authService.signIn(email: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Write `SignUpView.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Auth/SignUpView.swift`:
```swift
import SwiftUI

struct SignUpView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $displayName)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password (min 8 chars)", text: $password)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if isSubmitting { ProgressView() } else { Text("Create account") }
                    }
                    .disabled(displayName.isEmpty || email.isEmpty || password.count < 8 || isSubmitting)
                }
            }
            .navigationTitle("Create account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            try await appState.authService.signUp(.init(
                email: email, password: password, displayName: displayName
            ))
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 5: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet
```
Expected: `BUILD SUCCEEDED`. (PetService is used in AppState — we'll introduce it in the next task as a stub; or add a temporary stub now.)

**Note:** `AppState.init` references `PetService(client:)`, which doesn't exist yet. Before building, add a minimal placeholder at `ios/Sources/Pets/PetService.swift`:

```swift
import Foundation
import Supabase

@MainActor
final class PetService {
    let client: SupabaseClient
    init(client: SupabaseClient) {
        self.client = client
    }
}
```

This stub will be fleshed out in Task 6. Create the file, build to confirm clean compile.

- [ ] **Step 6: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Sources/App/ ios/Sources/Auth/ ios/Sources/Pets/PetService.swift
git commit -m "feat(ios): AppState, AuthService, sign-in + sign-up views"
```

---

## Task 6: Pet model + PetService

**Files:**
- Create: `ios/Sources/Pets/Pet.swift`
- Create: `ios/Sources/Pets/VaccinationCert.swift`
- Modify: `ios/Sources/Pets/PetService.swift` (flesh out)

- [ ] **Step 1: Write `Pet.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Pets/Pet.swift`:
```swift
import Foundation

struct Pet: Identifiable, Codable, Equatable, Hashable {
    enum Species: String, Codable, CaseIterable {
        case dog
        case cat
    }

    let id: UUID
    var owner_id: UUID
    var name: String
    var species: Species
    var breed: String?
    var age_months: Int?
    var weight_kg: Double?
    var medical_notes: String?
    var avatar_url: String?
    let created_at: Date?
    var updated_at: Date?
}

struct NewPetInput {
    var name: String
    var species: Pet.Species
    var breed: String?
    var age_months: Int?
    var weight_kg: Double?
    var medical_notes: String?
}
```

- [ ] **Step 2: Write `VaccinationCert.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Pets/VaccinationCert.swift`:
```swift
import Foundation

struct VaccinationCert: Identifiable, Codable, Equatable {
    let id: UUID
    let pet_id: UUID
    let file_url: String
    let vaccines_covered: [String]
    let issued_on: Date
    let expires_on: Date
    let verified_by_business_id: UUID?
    let created_at: Date?
}
```

- [ ] **Step 3: Flesh out `PetService.swift`**

Replace `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Pets/PetService.swift`:
```swift
import Foundation
import Supabase

enum PetServiceError: LocalizedError {
    case notAuthenticated
    case fetchFailed(String)
    case createFailed(String)
    case upload(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Not signed in."
        case .fetchFailed(let m): "Couldn't load pets: \(m)"
        case .createFailed(let m): "Couldn't add pet: \(m)"
        case .upload(let m): "Upload failed: \(m)"
        }
    }
}

@MainActor
final class PetService {
    let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func listPets() async throws -> [Pet] {
        do {
            let pets: [Pet] = try await client.from("pets")
                .select()
                .order("created_at", ascending: true)
                .execute()
                .value
            return pets
        } catch {
            throw PetServiceError.fetchFailed(error.localizedDescription)
        }
    }

    func addPet(_ input: NewPetInput) async throws -> Pet {
        guard let userId = try? await client.auth.user().id else {
            throw PetServiceError.notAuthenticated
        }

        struct Row: Encodable {
            let owner_id: String
            let name: String
            let species: String
            let breed: String?
            let age_months: Int?
            let weight_kg: Double?
            let medical_notes: String?
        }
        let row = Row(
            owner_id: userId.uuidString,
            name: input.name,
            species: input.species.rawValue,
            breed: input.breed,
            age_months: input.age_months,
            weight_kg: input.weight_kg,
            medical_notes: input.medical_notes
        )

        do {
            let pet: Pet = try await client.from("pets")
                .insert(row, returning: .representation)
                .select()
                .single()
                .execute()
                .value
            return pet
        } catch {
            throw PetServiceError.createFailed(error.localizedDescription)
        }
    }

    func listCerts(for petId: UUID) async throws -> [VaccinationCert] {
        let certs: [VaccinationCert] = try await client.from("vaccination_certs")
            .select()
            .eq("pet_id", value: petId.uuidString)
            .order("expires_on", ascending: false)
            .execute()
            .value
        return certs
    }

    /// Upload a cert file to Storage + insert a vaccination_certs row.
    /// Returns the inserted cert.
    func uploadCert(
        for petId: UUID,
        data: Data,
        filename: String,
        contentType: String,
        issuedOn: Date,
        expiresOn: Date
    ) async throws -> VaccinationCert {
        let safeName = filename
            .replacingOccurrences(of: "[^A-Za-z0-9._-]+", with: "_", options: .regularExpression)
            .prefix(120)
        let uniqueId = UUID().uuidString
        let path = "pets/\(petId.uuidString)/\(uniqueId)_\(safeName)"

        do {
            _ = try await client.storage
                .from("pet-vaccinations")
                .upload(
                    path,
                    data: data,
                    options: FileOptions(contentType: contentType, upsert: false)
                )
        } catch {
            throw PetServiceError.upload(error.localizedDescription)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        struct Row: Encodable {
            let pet_id: String
            let file_url: String
            let vaccines_covered: [String]
            let issued_on: String
            let expires_on: String
        }
        let row = Row(
            pet_id: petId.uuidString,
            file_url: path,
            vaccines_covered: [],
            issued_on: formatter.string(from: issuedOn),
            expires_on: formatter.string(from: expiresOn)
        )
        let cert: VaccinationCert = try await client.from("vaccination_certs")
            .insert(row, returning: .representation)
            .select()
            .single()
            .execute()
            .value
        return cert
    }
}
```

- [ ] **Step 4: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Sources/Pets/
git commit -m "feat(ios): pet + vaccination cert models and PetService"
```

---

## Task 7: Pet list + Add pet + Pet detail views

**Files:**
- Create: `ios/Sources/Pets/PetListView.swift`
- Create: `ios/Sources/Pets/AddPetView.swift`
- Create: `ios/Sources/Pets/PetDetailView.swift`

- [ ] **Step 1: Write `PetListView.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Pets/PetListView.swift`:
```swift
import SwiftUI

struct PetListView: View {
    @Environment(AppState.self) private var appState
    @State private var pets: [Pet] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showAddPet = false

    var body: some View {
        NavigationStack {
            List {
                if pets.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No pets yet",
                        systemImage: "pawprint",
                        description: Text("Add your first pet to get started.")
                    )
                }
                ForEach(pets) { pet in
                    NavigationLink(value: pet) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pet.name).font(.headline)
                            Text([
                                pet.species.rawValue.capitalized,
                                pet.breed ?? "",
                                pet.weight_kg.map { "\(Int($0)) kg" } ?? ""
                            ].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .overlay {
                if isLoading && pets.isEmpty {
                    ProgressView()
                }
            }
            .navigationTitle("Pets")
            .navigationDestination(for: Pet.self) { pet in
                PetDetailView(pet: pet)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddPet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign out") {
                        Task { try? await appState.authService.signOut() }
                    }
                }
            }
            .sheet(isPresented: $showAddPet, onDismiss: { Task { await reload() } }) {
                AddPetView()
            }
            .alert("Error", isPresented: .constant(errorMessage != nil), actions: {
                Button("OK") { errorMessage = nil }
            }, message: { Text(errorMessage ?? "") })
            .task { await reload() }
            .refreshable { await reload() }
        }
    }

    private func reload() async {
        isLoading = true
        defer { isLoading = false }
        do {
            pets = try await appState.petService.listPets()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Write `AddPetView.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Pets/AddPetView.swift`:
```swift
import SwiftUI

struct AddPetView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var species: Pet.Species = .dog
    @State private var breed = ""
    @State private var weightText = ""
    @State private var ageMonthsText = ""
    @State private var medicalNotes = ""

    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Basics") {
                    TextField("Name", text: $name)
                    Picker("Species", selection: $species) {
                        ForEach(Pet.Species.allCases, id: \.self) { s in
                            Text(s.rawValue.capitalized).tag(s)
                        }
                    }
                    TextField("Breed (optional)", text: $breed)
                }
                Section("Details") {
                    TextField("Age in months", text: $ageMonthsText)
                        .keyboardType(.numberPad)
                    TextField("Weight in kg", text: $weightText)
                        .keyboardType(.decimalPad)
                }
                Section("Medical notes") {
                    TextEditor(text: $medicalNotes)
                        .frame(minHeight: 80)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add pet")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await submit() } } label: {
                        if isSubmitting { ProgressView() } else { Text("Save") }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isSubmitting)
                }
            }
        }
    }

    private func submit() async {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        let input = NewPetInput(
            name: name.trimmingCharacters(in: .whitespaces),
            species: species,
            breed: breed.isEmpty ? nil : breed,
            age_months: Int(ageMonthsText),
            weight_kg: Double(weightText),
            medical_notes: medicalNotes.isEmpty ? nil : medicalNotes
        )
        do {
            _ = try await appState.petService.addPet(input)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 3: Write `PetDetailView.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/Pets/PetDetailView.swift`:
```swift
import SwiftUI
import UniformTypeIdentifiers

struct PetDetailView: View {
    @Environment(AppState.self) private var appState
    let pet: Pet

    @State private var certs: [VaccinationCert] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showImporter = false
    @State private var isUploading = false

    var body: some View {
        List {
            Section("Profile") {
                LabeledContent("Species", value: pet.species.rawValue.capitalized)
                if let breed = pet.breed { LabeledContent("Breed", value: breed) }
                if let w = pet.weight_kg { LabeledContent("Weight", value: "\(w, specifier: "%.1f") kg") }
                if let m = pet.age_months { LabeledContent("Age", value: "\(m) months") }
                if let n = pet.medical_notes { Text(n).font(.footnote).foregroundStyle(.secondary) }
            }

            Section {
                if certs.isEmpty && !isLoading {
                    Text("No vaccination certificates uploaded yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(certs) { cert in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cert.file_url.split(separator: "/").last.map(String.init) ?? cert.file_url)
                            .font(.subheadline)
                        Text("Expires \(cert.expires_on.formatted(date: .abbreviated, time: .omitted))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                HStack {
                    Text("Vaccinations")
                    Spacer()
                    Button { showImporter = true } label: {
                        if isUploading { ProgressView() } else { Text("Upload") }
                    }
                    .disabled(isUploading)
                }
            }
            if let errorMessage { Section { Text(errorMessage).foregroundStyle(.red) } }
        }
        .navigationTitle(pet.name)
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.pdf, .jpeg, .png],
            allowsMultipleSelection: false,
            onCompletion: handleFileSelection
        )
        .task { await reloadCerts() }
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            Task { await upload(fileURL: url) }
        case .failure(let e):
            errorMessage = e.localizedDescription
        }
    }

    private func upload(fileURL: URL) async {
        errorMessage = nil
        isUploading = true
        defer { isUploading = false }

        let gotAccess = fileURL.startAccessingSecurityScopedResource()
        defer { if gotAccess { fileURL.stopAccessingSecurityScopedResource() } }

        do {
            let data = try Data(contentsOf: fileURL)
            let ext = (fileURL.pathExtension).lowercased()
            let contentType: String = switch ext {
            case "pdf": "application/pdf"
            case "jpg", "jpeg": "image/jpeg"
            case "png": "image/png"
            default: "application/octet-stream"
            }
            // Default issued_on=today, expires_on=today+1yr. User can refine in a later slice.
            let today = Date()
            let oneYear = Calendar.current.date(byAdding: .year, value: 1, to: today) ?? today
            _ = try await appState.petService.uploadCert(
                for: pet.id,
                data: data,
                filename: fileURL.lastPathComponent,
                contentType: contentType,
                issuedOn: today,
                expiresOn: oneYear
            )
            await reloadCerts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadCerts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            certs = try await appState.petService.listCerts(for: pet.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Build check**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Sources/Pets/
git commit -m "feat(ios): pet list, add pet, pet detail + cert upload views"
```

---

## Task 8: RootView + app wiring

**Files:**
- Create: `ios/Sources/App/RootView.swift`
- Modify: `ios/Sources/PetBnBApp.swift`

- [ ] **Step 1: Write `RootView.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/App/RootView.swift`:
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
            PetListView()
        }
    }
}
```

- [ ] **Step 2: Replace `PetBnBApp.swift`**

Overwrite `/Users/fabian/CodingProject/Primary/PetBnB/ios/Sources/PetBnBApp.swift`:
```swift
import SwiftUI

@main
struct PetBnBApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .task { await appState.bootstrap() }
        }
    }
}
```

- [ ] **Step 3: Build**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet
```
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Sources/App/RootView.swift ios/Sources/PetBnBApp.swift
git commit -m "feat(ios): root view wiring and auth gate"
```

---

## Task 9: XCTest unit tests

Three small tests, one per service, each of which mocks the network boundary so the test doesn't hit Supabase.

**Files:**
- Create: `ios/Tests/PetBnBTests.swift`
- Create: `ios/Tests/AuthServiceTests.swift`
- Create: `ios/Tests/PetServiceTests.swift`

- [ ] **Step 1: Write `PetBnBTests.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Tests/PetBnBTests.swift`:
```swift
import XCTest
@testable import PetBnB

final class PetBnBTests: XCTestCase {
    func test_pet_species_roundtrips_through_codable() throws {
        let pet = Pet(
            id: UUID(),
            owner_id: UUID(),
            name: "Mochi",
            species: .dog,
            breed: "Poodle",
            age_months: 24,
            weight_kg: 8.0,
            medical_notes: nil,
            avatar_url: nil,
            created_at: nil,
            updated_at: nil
        )
        let data = try JSONEncoder().encode(pet)
        let decoded = try JSONDecoder().decode(Pet.self, from: data)
        XCTAssertEqual(pet, decoded)
    }
}
```

- [ ] **Step 2: Write `AuthServiceTests.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Tests/AuthServiceTests.swift`:
```swift
import XCTest
@testable import PetBnB

final class AuthServiceTests: XCTestCase {
    func test_auth_sign_up_input_holds_values() {
        let input = AuthSignUpInput(email: "a@b.co", password: "12345678", displayName: "Test")
        XCTAssertEqual(input.email, "a@b.co")
        XCTAssertEqual(input.password.count, 8)
        XCTAssertEqual(input.displayName, "Test")
    }

    func test_auth_service_error_has_readable_description() {
        let e = AuthServiceError.signInFailed("bad credentials")
        XCTAssertNotNil(e.errorDescription)
        XCTAssertTrue(e.errorDescription!.contains("Sign in failed"))
    }
}
```

- [ ] **Step 3: Write `PetServiceTests.swift`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/Tests/PetServiceTests.swift`:
```swift
import XCTest
@testable import PetBnB

final class PetServiceTests: XCTestCase {
    func test_new_pet_input_defaults() {
        let input = NewPetInput(name: "Mochi", species: .dog, breed: nil, age_months: nil, weight_kg: nil, medical_notes: nil)
        XCTAssertEqual(input.name, "Mochi")
        XCTAssertNil(input.breed)
    }

    func test_pet_service_error_messages() {
        XCTAssertTrue((PetServiceError.notAuthenticated.errorDescription ?? "").contains("Not signed in"))
        XCTAssertTrue((PetServiceError.fetchFailed("boom").errorDescription ?? "").contains("boom"))
        XCTAssertTrue((PetServiceError.upload("oops").errorDescription ?? "").contains("Upload failed"))
    }
}
```

- [ ] **Step 4: Run tests**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB/ios
xcodegen generate
xcodebuild test \
  -project PetBnB.xcodeproj \
  -scheme PetBnB \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -quiet
```
If no iPhone 15 simulator exists, substitute any installed simulator name: list with `xcrun simctl list devices available`.

Expected: `TEST SUCCEEDED`, 5 tests passing.

- [ ] **Step 5: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/Tests/
git commit -m "test(ios): XCTest unit tests for pet + auth service types"
```

---

## Task 10: README + handoff

**Files:**
- Create: `ios/README.md`
- Modify: root `PetBnB/README.md`

- [ ] **Step 1: Write `ios/README.md`**

Create `/Users/fabian/CodingProject/Primary/PetBnB/ios/README.md`:
```markdown
# PetBnB iOS (Phase 2a)

Owner-facing SwiftUI app. Backed by the Supabase project at `../supabase`.

## Setup

1. `brew install xcodegen` (if not already installed).
2. From `../`, start Supabase: `supabase start`.
3. Copy the xcconfig template and paste the Publishable key from `supabase status`:
   ```bash
   cp Config/Shared.local.xcconfig.example Config/Shared.local.xcconfig
   # edit Shared.local.xcconfig — paste Publishable key
   ```
4. Generate the Xcode project:
   ```bash
   xcodegen generate
   open PetBnB.xcodeproj
   ```
5. In Xcode: select an iOS 17+ simulator, Cmd-R to run.

## CLI

```bash
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB \
  -destination 'generic/platform=iOS Simulator'
xcodebuild test  -project PetBnB.xcodeproj -scheme PetBnB \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

## Layout

```
Sources/
  PetBnBApp.swift             @main entry
  App/
    AppState.swift            Observable root state
    RootView.swift            auth-gated router
  Auth/
    AuthService.swift
    SignInView.swift
    SignUpView.swift
  Pets/
    Pet.swift                 Codable model
    VaccinationCert.swift
    PetService.swift
    PetListView.swift
    AddPetView.swift
    PetDetailView.swift
  Supabase/
    SupabaseEnv.swift
    SupabaseClientProvider.swift
  Info.plist                  xcconfig values injected at build
Tests/
  PetBnBTests.swift
  AuthServiceTests.swift
  PetServiceTests.swift
Config/
  Shared.xcconfig             defaults (tracked)
  Shared.local.xcconfig       real values (gitignored)
```

## Handoff to Phase 2b

- TabView with Discover + Bookings + Profile goes into `RootView.swift` when there are enough surfaces.
- Listing browse + detail pages read from the public `listings` + `kennel_types` tables — RLS already allows anon read for verified/active businesses.
- Phase 2b will introduce `ListingService` + `ListingRepository` alongside the existing `PetService`.

## Phase 2a limitations

- No photo thumbnail for pets yet (avatar_url is in the schema but UI is text-only in 2a).
- Cert expiry date defaults to "today + 1 year" on upload; user picks the real expiry later (2b or later slice).
- No edit or delete for pets in 2a; only create + read.
- Sign-out button is in the Pet list toolbar for dev convenience; proper Settings screen comes in 2b or 2c.
- Works only against local Supabase (`http://127.0.0.1:54321`) out of the box. The xcconfig also allows pointing at a hosted instance by changing `SUPABASE_URL` + `SUPABASE_ANON_KEY`.
```

- [ ] **Step 2: Update root `PetBnB/README.md`**

In the Status section, add a line after the Phase 1 block:

`- [x] **Phase 2a** — iOS scaffold, auth, pet profiles + vaccination cert upload`

And in the "Local dev" section, add:
```
### iOS app (Phase 2a+)

See `ios/README.md` for xcodegen + xcconfig setup. TL;DR:
```bash
cd ios
cp Config/Shared.local.xcconfig.example Config/Shared.local.xcconfig
# paste Publishable key from `supabase status` into Shared.local.xcconfig
xcodegen generate
open PetBnB.xcodeproj
```
```

- [ ] **Step 3: Final acceptance**

From `/Users/fabian/CodingProject/Primary/PetBnB/`:
```bash
supabase test db                                    # expect 79 passing
./supabase/scripts/verify-phase0.sh                 # green
cd ios
xcodegen generate
xcodebuild build -project PetBnB.xcodeproj -scheme PetBnB -destination 'generic/platform=iOS Simulator' -quiet
xcodebuild test  -project PetBnB.xcodeproj -scheme PetBnB -destination 'platform=iOS Simulator,name=iPhone 15' -quiet
```
All must succeed.

- [ ] **Step 4: Commit**

```bash
cd /Users/fabian/CodingProject/Primary/PetBnB
git add ios/README.md README.md
git commit -m "docs: Phase 2a README and iOS handoff"
```

---

## Phase 2a complete — final checklist

- [ ] `git log --oneline | head -15` shows 10 new commits on top of Phase 1d (79 total).
- [ ] `supabase test db` — 79 pgTAP assertions passing.
- [ ] `xcodebuild build` succeeds on a generic iOS Simulator destination.
- [ ] `xcodebuild test` passes all XCTest cases.
- [ ] Manual simulator smoke test: launch → sign up → Pet list (empty) → Add pet → Pet detail → Upload PDF cert → cert appears in Vaccinations section with filename + expiry.
- [ ] No credentials committed: `git log -p fa93fa6..HEAD -- ios | grep -E "(eyJ[A-Za-z0-9_-]{20,}|sb_publishable_|sb_secret_)"` returns nothing except `REPLACE_WITH_PUBLISHABLE_KEY`.

Push:
```bash
git push origin main
```

Then plan Phase 2b (Discover + browse + listing detail).
