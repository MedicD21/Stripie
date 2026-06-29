# Stripie — Agent Guide

iOS point-of-sale app: **Tap to Pay on iPhone** via the Stripe Terminal SDK,
backed by a separate FastAPI service. This file captures the non-obvious setup
so you don't re-derive it. Read the spec/plan/checklist linked at the bottom for
depth.

## Two repos

| Repo | Path | Role |
|---|---|---|
| iOS app | `~/Code/Stripie` (this one) | SwiftUI + MVVM client. Branch `main`. Remote: `github.com/MedicD21/Stripie`. |
| Backend | `~/Code/stripie-backend` | FastAPI: Stripe secret-key ops + Neon Postgres payments mirror + Stripe webhook. Branch `master`, **no remote** (local only). |

The app never holds a Stripe secret key. All secret operations go through the backend.

## The project is generated — do NOT edit `.pbxproj`

This repo is **XcodeGen-driven**. `Stripie.xcodeproj` is generated and **gitignored**.
`project.yml` is the source of truth.

- After changing sources layout, settings, Info.plist keys, entitlements, or the
  scheme: edit `project.yml`, then run `xcodegen generate`.
- Never hand-edit `Stripie.xcodeproj/project.pbxproj` — it gets overwritten.
- Never set signing/capabilities in Xcode's UI — they live in `project.yml` /
  `Stripie/Stripie.entitlements` or `xcodegen generate` wipes them. Team ID
  (`DEVELOPMENT_TEAM: 286LKF859M`) and `CODE_SIGN_STYLE: Automatic` are set at the
  project level in `project.yml` so they persist (no re-prompting).
- Info.plist is **generated** (`GENERATE_INFOPLIST_FILE: true`). Add plist keys via
  `INFOPLIST_KEY_<Name>` settings in `project.yml`, not a standalone plist file.

### Xcode Cloud
The `.xcodeproj` is gitignored, so `ci_scripts/ci_post_clone.sh` installs XcodeGen
(via Homebrew) and runs `xcodegen generate` after Xcode Cloud clones the repo —
that's how cloud builds get a project. The scheme is shared (XcodeGen emits it
under `xcshareddata`). SPM re-resolves Stripe Terminal `~4.0.0` per `project.yml`.
Note: the run-action scheme env vars (`STRIPIE_API_URL`, keys) do NOT reach an
Archive/cloud build — see "Moving to production" for the config-shipping fix.

## Build / test / run (verified commands)

```bash
xcodegen generate    # after any project.yml change

# Build (use a HEALTHY booted simulator id; see gotcha below)
xcodebuild build -project Stripie.xcodeproj -scheme Stripie -configuration Debug \
  -destination 'id=E853C6A5-9BA2-4513-8A02-779836408ACB' CODE_SIGNING_ALLOWED=NO

# Unit tests
xcodebuild test -project Stripie.xcodeproj -scheme Stripie \
  -destination 'id=E853C6A5-9BA2-4513-8A02-779836408ACB' -only-testing:StripieTests
```

Xcode is **Xcode-beta.app** (`open -a Xcode-beta`). An Xcode MCP (`xcode-mcp`)
is available for build/test/run-on-device. Project skills exist: `/build`,
`/test`, `/run`, `/new-view`, `/fix-errors`.

### Gotchas learned the hard way
- **Some simulators are corrupted on disk** ("Unable to boot device because it
  cannot be located on disk"). Build against a known-good booted device by `id`,
  not by `name`. `E853C6A5-9BA2-4513-8A02-779836408ACB` (TGK Test) worked.
- **Swift 5 language mode is intentional** (`SWIFT_VERSION: 5.0`,
  `SWIFT_STRICT_CONCURRENCY: targeted`). Stripe Terminal v4 is not Sendable-
  audited; Swift 6's `sending`/region-isolation checks reject passing its
  `Reader`/`PaymentIntent` through SDK callbacks. Do **not** bump to Swift 6
  until the SDK adds Sendable annotations.
- **Deployment target is iOS 17.** Don't use iOS-18-only APIs (`Tab`,
  `TabView(content:)`, `.foregroundStyle(.accent)` shorthand). Use the iOS-17
  forms (`TabView { … .tabItem }`, `Color.accentColor`).
- The SDK module is **`StripeTerminal`** (not `StripeTerminalSDK`).

## Stripe Terminal v4 specifics

`TerminalService` (`Stripie/Core/Services/Terminal/`) is the only file touching
the SDK. v4 API names (v3 names will not compile):
- `Terminal.setTokenProvider(_:)` + assign `Terminal.shared.delegate` (no
  `Terminal.initialize(...)`, no `TerminalConfiguration`).
- `TapToPayDiscoveryConfigurationBuilder().setSimulated(_).build()`,
  `TapToPayConnectionConfigurationBuilder(delegate:locationId:).build()`,
  `Terminal.shared.connectReader(_:connectionConfig:)`, `Cancelable.cancel(_:)`.
- Delegate is `TapToPayReaderDelegate` with `tapToPayReader(...)` methods.
- SDK callbacks arrive on the main thread → use `MainActor.assumeIsolated { }`
  in `nonisolated` delegate methods rather than hopping a `Task`.

### Simulated reader (testing without hardware)
`TerminalService(simulated:)` defaults to `true` in DEBUG, `false` in Release.
When on, discovery uses `setSimulated(true)` and a simulated Visa, so the full
charge flow runs on the Simulator. **Real Tap to Pay needs a physical iPhone
(XS+).** Release builds always use the real reader.

### Required Info.plist keys (in `project.yml`)
Stripe Terminal **aborts (SIGABRT)** at discovery if missing:
`NSBluetoothAlwaysUsageDescription`, `NSLocationWhenInUseUsageDescription`.

## Configuration / secrets

`AppConfiguration` reads env vars: `STRIPIE_API_URL`,
`STRIPE_PUBLISHABLE_KEY_TEST` (DEBUG) / `_LIVE` (Release), `STRIPIE_API_KEY`.
Currently set as **Xcode scheme env vars** (in `project.yml` `schemes:`).

- The app's `STRIPIE_API_KEY` must **match** the backend `.env` value or every
  request 401s.
- Never commit real keys. `.env*` and `.neon` are gitignored.
- The DEBUG `STRIPIE_API_URL` defaults to `http://localhost:8000`; on a physical
  device `localhost` won't reach the Mac — use a LAN IP or tunnel.

## Admin authentication

The app is gated behind admin login (`Features/Auth/`). It **reuses the Good
Kitchen backend's existing `admin-portal-auth` Netlify function** — no auth
backend was built for Stripie.

- **Flow** (passwordless, mirrors the website): `request_code` (email) →
  `verify_code` (email + 6-digit code) returns a Bearer token → `status` returns
  the profile incl. `is_super_admin`. Endpoint:
  `https://www.thegoodkitchen.org/.netlify/functions/admin-portal-auth` (CORS-open).
- **iOS pieces**: `AuthService` (actor, `AuthServicing` protocol — `MockAuthService`
  is the test stub) builds its own requests; `AuthSessionStore` (`@Observable`)
  owns auth state and is injected via `@Environment`. `RootView` switches on
  `.loading`/`.signedOut`/`.signedIn` → `LoginView` vs `MainTabView`. Terminal
  init runs only after sign-in (so login never triggers Bluetooth/location prompts).
- **Auth has its own base URL**: `StripieAuthURL` (Info.plist) / `STRIPIE_AUTH_URL`
  (env), read by `AppConfiguration.authBaseURL`, defaulting to production
  thegoodkitchen.org **regardless of `STRIPIE_API_URL`** — so login works even
  when payments point at `localhost:8000` in DEBUG.
- **Token storage**: Keychain (`KeychainStore`, no entitlement needed for a
  single-app generic-password item); last profile cached in UserDefaults.
- **No auto-logout**: a stored token only clears on an explicit 401/403 from the
  server or manual sign-out. Transient network errors keep the user signed in
  (optimistic, using the cached profile).
- **Who is an admin** is managed on the backend, not in the app: env allowlists
  (`ADMIN_PORTAL_ALLOWED_EMAILS`, `SUPER_ADMIN_EMAILS`) or the
  `public.admin_portal_access` Neon table. Admin and super-admin currently get
  identical app access. Backend prerequisites: `ADMIN_PORTAL_AUTH_SECRET` set +
  email-sending enabled (both already power the website admin portal).

## Conventions
- `@Observable` + `@MainActor` for all view models — never `ObservableObject`/`@Published`.
- All API calls go through `APIRequesting` (protocol); `APIClient` (actor) is the
  real impl, `MockAPIClient` the test stub. `request<T: Decodable & Sendable>`.
- Wire format is **snake_case** both ways (the client uses
  `convert*SnakeCase`); backend responses must emit snake_case.
- Tests use Swift Testing (`@Test`/`@Suite`/`#expect`), not XCTest.

## Production status & config (current)

Production config **ships in the binary** via `Info.plist` keys set in
`project.yml` (`StripieAPIURL`, `StripieAPIKey`, `StripiePublishableKey`,
`StripieAuthURL`) — `AppConfiguration` reads them via `Bundle.main` in Release.
No `.xcconfig` migration was needed; scheme env vars are DEBUG-only. The Tap to
Pay entitlement is **active** in `Stripie/Stripie.entitlements` and verified
embedded in signed builds. Release builds use the **real** reader
(`simulated=false`) and the production Good Kitchen backend
(`https://www.thegoodkitchen.org`). Real Tap to Pay needs a **physical iPhone
XS+ on iOS 17.6+** (the app blocks older OS — see requirement 1.4).

Backend = Good Kitchen Netlify site (`stripie-*` functions + redirects). The
FastAPI `stripie-backend` prototype is retired. Refunds flow via the
`charge.refunded` webhook → `stripie_payments` marked refunded + a separate
`Refunds` expense txn in `financial_transactions` + `live_stats` netted. Needs
`STRIPE_WEBHOOK_ACTIVE=true` on the production Netlify context.

### Tap to Pay distribution gate (the real blocker)
Apple grants the entitlement in **two stages**. We have stage 1 (development:
install on registered test devices). App Store / TestFlight / Unlisted uploads
require stage 2 — Apple **lifting the "development distribution restriction"**
after reviewing the app against the Tap to Pay App Review requirements. Until
lifted, distribution provisioning profiles omit the entitlement and uploads to
App Store Connect fail. Submit the filled
`App Review Requirements Checklist` + the three flow recordings (Existing-User,
Checkout, New-User note) by replying to the **TTPOI Entitlements** case email.

### Go-live sequence (Unlisted, single internal merchant)
1. Wait for Apple to lift the dev-distribution restriction (stage 2 above).
2. Archive Release → Xcode Organizer → Distribute App → App Store Connect
   (bump `CURRENT_PROJECT_VERSION` in `project.yml` for each upload).
3. Request **Unlisted App Distribution**:
   developer.apple.com/app-store/unlisted-app-distribution (matches the
   "Unlisted" distribution type on the checklist).
4. Submit for standard App Review + complete App Store Connect metadata and
   **App Privacy** labels (declare payment data + customer email/phone captured
   for receipts).
5. On approval, share the **private (unlisted) App Store link** with admins;
   they install from the App Store and get auto-updates. Admin access is still
   gated by the in-app email-code login (admin/super-admin only).

TestFlight is an alternative for onboarding admins the moment the entitlement
clears, but it's beta-oriented (90-day build expiry) — Unlisted is the long-term
home.

## Reference docs
- Backend design: `docs/superpowers/specs/2026-06-27-stripie-backend-design.md`
- Backend impl plan: `docs/superpowers/plans/2026-06-27-stripie-backend.md`
- README: app setup + payment flow.
