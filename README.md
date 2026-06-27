# Stripie

iOS point-of-sale app powered by Stripe Terminal (Tap to Pay on iPhone).

---

## Tech Stack

| Layer        | Technology                   |
| ------------ | ---------------------------- |
| Language     | Swift 5 mode (targeted concurrency) |
| UI           | SwiftUI + `@Observable`      |
| Architecture | MVVM                         |
| Payments     | Stripe Terminal SDK v4.x     |
| Backend      | FastAPI + Neon/Postgres      |
| Min iOS      | 17.0                         |

---

## Getting Started

### 1. Create the Xcode Project

> **This repo is source-only.** There is no `.xcodeproj` checked in — `Package.swift`
> only documents the SPM dependency. You must create the Xcode project wrapper once:

1. Open Xcode → **File → New → Project**
2. Choose **iOS → App**
3. Set:
   - Product Name: `Stripie`
   - Bundle ID: `com.dushin.stripie`
   - Interface: SwiftUI
   - Language: Swift
   - Minimum Deployment: iOS 17.0
4. Save into this repo root (it will create `Stripie.xcodeproj/`)
5. **Add all `.swift` files** from `Stripie/` to the project target
6. **Add all test files** from `StripieTests/` to the test target

> ⚠️ Never let Claude Code modify `.pbxproj` directly. Always add files through Xcode.

### 2. Add SPM Dependencies

In Xcode: **File → Add Package Dependencies**

| Package         | URL                                             | Version  |
| --------------- | ----------------------------------------------- | -------- |
| Stripe Terminal | `https://github.com/stripe/stripe-terminal-ios` | `~> 4.0` |

### 3. Add Entitlements

In Xcode → your target → **Signing & Capabilities**:

- **Tap to Pay on iPhone** — requires the entitlement from Apple: `com.apple.developer.proximity-reader.payment.acceptance`
- **Location When In Use** — add to `Info.plist`: `NSLocationWhenInUseUsageDescription`

### 4. Configure Environment

Set these in your Xcode scheme (**Edit Scheme → Run → Environment Variables**):

```
STRIPE_PUBLISHABLE_KEY_TEST=pk_test_...
STRIPIE_API_URL=http://localhost:8000
```

### 5. Backend Requirements

Minimum endpoints required from the FastAPI backend:

- `POST /terminal/connection_token` → `{ "secret": "..." }`
- `POST /payment_intents` → PaymentIntent object
- `POST /payment_intents/{id}/capture` → captured PaymentIntent
- `GET /transactions?limit=25&starting_after=` → paginated list

---

## Project Structure

```
Stripie/
├── Stripie/
│   ├── App/                    # Entry point, AppState, RootView
│   ├── Core/
│   │   ├── Config/             # AppConfiguration (env switching)
│   │   ├── Errors/             # AppError, NetworkError, TerminalError
│   │   ├── Extensions/         # SwiftUI + Foundation extensions
│   │   ├── Networking/         # APIClient (actor), APIEndpoint, models
│   │   └── Services/
│   │       ├── Terminal/       # StripeTerminal wrapper service
│   │       └── Location/       # CLLocationManager wrapper
│   ├── DesignSystem/           # Theme tokens, PrimaryButton, LoadingOverlay
│   └── Features/
│       ├── Payment/            # Charge screen, keypad, confirmation
│       ├── Reader/             # Reader discovery & connection
│       └── Transactions/       # Transaction history list & detail
├── StripieTests/
│   ├── Mocks/                  # MockAPIClient
│   └── Unit/                   # Swift Testing suites
└── .claude/commands/           # /build, /test, /run, /new-view, /fix-errors
```

---

## Payment Flow

```
Enter amount
  → POST /payment_intents         (create on backend)
  → Terminal.collectPaymentMethod (Tap to Pay presentation)
  → Terminal.confirmPaymentIntent (SDK confirms)
  → POST /payment_intents/{id}/capture (capture on backend)
  → Show success screen
```

---

## Development Notes

- **Swift 5 language mode** with `targeted` strict concurrency. (Swift 6 mode's
  `sending`/region-isolation checks are incompatible with the Stripe Terminal v4
  SDK, which is not yet concurrency-audited; revisit when the SDK adds Sendable
  annotations.)
- **`@Observable`** is required for all ViewModels — never `ObservableObject`/`@Published`.
- **Stripe secret key** never touches the iOS client. All secret operations go through FastAPI.
- **Location permission** must be granted before Terminal initializes (required by Stripe).
