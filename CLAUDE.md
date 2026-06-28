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

## Conventions
- `@Observable` + `@MainActor` for all view models — never `ObservableObject`/`@Published`.
- All API calls go through `APIRequesting` (protocol); `APIClient` (actor) is the
  real impl, `MockAPIClient` the test stub. `request<T: Decodable & Sendable>`.
- Wire format is **snake_case** both ways (the client uses
  `convert*SnakeCase`); backend responses must emit snake_case.
- Tests use Swift Testing (`@Test`/`@Suite`/`#expect`), not XCTest.

## Moving to production

Triggered when Apple **approves the Tap to Pay entitlement**. Short version
(full runbook in the reference docs):

1. Uncomment `com.apple.developer.proximity-reader.payment.acceptance` in
   `Stripie/Stripie.entitlements`; refresh the provisioning profile.
2. **Move config out of the scheme.** Scheme env vars do **not** ship in
   Archive/TestFlight/App Store builds — the Release `AppConfiguration` branch
   would hit `requireURL(…, fallback: nil)` and **crash at launch**. Before the
   first archive, move prod config to an `.xcconfig` (referenced in
   `project.yml`) or `INFOPLIST_KEY_…` read via `Bundle.main`, not
   `ProcessInfo.environment`.
3. Set prod `STRIPIE_API_URL` (HTTPS), `pk_live_…`, matching live `STRIPIE_API_KEY`.
4. Backend: `sk_live_` secret, a **separate live-mode** webhook + its `whsec_…`,
   deploy via the included Dockerfile over HTTPS, `alembic upgrade head` on the
   prod Neon branch.
5. Archive Release → TestFlight → one real low-value charge + refund on a
   physical iPhone. (First live tap shows Apple's ToS prompt — expected.)
6. **Production backend is the Good Kitchen Netlify site** (not the retired
   `stripie-backend` FastAPI prototype). Endpoints live as `stripie-*` Netlify
   functions; `STRIPIE_API_URL = https://www.thegoodkitchen.org`. See that repo's
   `docs/stripie/ENV.md`.

## Reference docs
- Backend design: `docs/superpowers/specs/2026-06-27-stripie-backend-design.md`
- Backend impl plan: `docs/superpowers/plans/2026-06-27-stripie-backend.md`
- README: app setup + payment flow.
