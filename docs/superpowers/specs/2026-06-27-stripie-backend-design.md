# Stripie Backend — Design

**Date:** 2026-06-27
**Status:** Approved

## Purpose

A FastAPI backend that serves the Stripie iOS Tap-to-Pay app. It performs all
Stripe **secret-key** operations (the iOS client never holds a secret key) and
exposes the four endpoints the app already expects, plus a Stripe webhook and a
health check.

Stripe is the source of truth for money. Postgres (Neon) is a **read-mirror** of
payments, kept in sync by a Stripe webhook, so `GET /transactions` is fast and
queryable without paging Stripe's API on every request.

## Repo Layout

New **sibling** repository/folder: `~/Code/stripie-backend/` (separate from the
source-only iOS repo). Deploys independently.

```
stripie-backend/
├── app/
│   ├── main.py              # FastAPI app, router registration, lifespan
│   ├── config.py            # Pydantic settings (env vars)
│   ├── auth.py              # X-API-Key dependency
│   ├── db.py                # async SQLAlchemy engine/session
│   ├── models.py            # Payment ORM model
│   ├── schemas.py           # Pydantic request/response models
│   ├── stripe_client.py     # thin wrapper around the stripe SDK
│   └── routers/
│       ├── terminal.py      # POST /terminal/connection_token
│       ├── payments.py      # POST /payment_intents, POST /payment_intents/{id}/capture
│       ├── transactions.py  # GET /transactions
│       └── webhooks.py      # POST /webhooks/stripe
├── alembic/                 # migrations
├── tests/
├── .env.example             # documented var names, no secrets
├── .gitignore               # ignores .env
├── Dockerfile
├── pyproject.toml
└── README.md
```

## Architecture

```
iOS app ──X-API-Key──> FastAPI ──secret key──> Stripe API
                          │
                          └──> Postgres (Neon)   [payments mirror]
                          ▲
Stripe webhook ───────────┘  (payment_intent.* events upsert the mirror)
```

## Endpoints

All app endpoints require header `X-API-Key: <STRIPIE_API_KEY>` → 401 if
missing/wrong. The webhook is exempt (verified by Stripe signature instead).

| Method | Path | Behavior |
|---|---|---|
| `POST` | `/terminal/connection_token` | `stripe.terminal.ConnectionToken.create()` → `{ "secret": "..." }` |
| `POST` | `/payment_intents` | Create PI with `amount`, `currency`, `description`, `capture_method="manual"`, `payment_method_types=["card_present"]`. Returns `{ id, client_secret, amount, currency, status }`. |
| `POST` | `/payment_intents/{id}/capture` | `stripe.PaymentIntent.capture(id)` → `{ id, status, amount, currency, created_at }`. |
| `GET` | `/transactions?limit=&starting_after=` | Read from Postgres mirror. Returns `{ transactions: [...], has_more }`. Keyset pagination. |
| `POST` | `/webhooks/stripe` | Verify signature; upsert payment rows on `payment_intent.*` events. |
| `GET` | `/health` | Liveness check. |

### Request/Response contracts (must match iOS exactly)

The iOS client uses snake_case on the wire (`convertFromSnakeCase` /
`convertToSnakeCase`). FastAPI responses must use snake_case keys.

- **Create PI request** (from app): `{ "amount": int (cents), "currency": "usd", "description": string? }`
- **PI response**: `{ "id", "client_secret", "amount", "currency", "status" }`
- **Capture response**: `{ "id", "status", "amount", "currency", "created_at"? }`
- **Transactions response**: `{ "transactions": [ { "id", "amount", "currency", "status", "description"?, "created_at" } ], "has_more": bool }`
- **Error response**: `{ "detail": string }` (FastAPI default; iOS reads `detail` first).

`created_at` is an ISO-8601 string (iOS parses with `ISO8601DateFormatter`).

## Data Model

Single `payments` table mirroring the app's `TransactionRecord`:

| Column | Type | Notes |
|---|---|---|
| `id` | text PK | Stripe PaymentIntent id (`pi_...`) |
| `amount` | integer | cents |
| `currency` | text | e.g. `usd` |
| `status` | text | Stripe PI status (`requires_capture`, `succeeded`, …) |
| `description` | text null | |
| `created_at` | timestamptz | from Stripe PI `created` |
| `updated_at` | timestamptz | row maintenance |

- Webhook **upserts** by `id` on `payment_intent.created/.amount_capturable_updated/.succeeded/.canceled/.payment_failed`.
- Capture endpoint also upserts immediately (don't wait for the webhook) so
  history reflects a just-captured payment without a race.
- `GET /transactions` paginates by keyset on `(created_at DESC, id DESC)`;
  `starting_after` is the last seen `id`. `has_more` = whether a row exists
  beyond the returned page.

## Capture Mode

**Manual capture** (auth-then-capture), matching the iOS flow:

```
POST /payment_intents (capture_method=manual)
  → Terminal.confirmPaymentIntent on device   (authorizes the card)
  → POST /payment_intents/{id}/capture          (settles)
```

## Authentication

Static shared secret. iOS sends `X-API-Key`; backend rejects without it. Single
value (`STRIPIE_API_KEY`) shared between app scheme and backend env. The webhook
endpoint is authenticated by Stripe signature, not the API key.

## iOS Change Required

The app currently sends no auth header. Add `X-API-Key` to
`APIClient.buildRequest(for:)`, reading the value from a new scheme env var
`STRIPIE_API_KEY`. Contained change; no flow change.

## Stack

- FastAPI + Uvicorn
- `stripe` Python SDK
- SQLAlchemy 2.0 async + `asyncpg`
- Alembic (migrations)
- `pydantic-settings` (env config)
- pytest (mocked Stripe SDK + test DB)
- Dockerfile (portable; deploy target chosen later)

## Environment Variables

### Backend (`stripie-backend/.env`, gitignored)

```
STRIPE_SECRET_KEY=sk_test_...        # rolled secret key (test mode to start)
STRIPE_WEBHOOK_SECRET=whsec_...      # from Stripe webhook registration (added during setup)
DATABASE_URL=postgresql+asyncpg://neondb_owner:<pwd>@ep-orange-dew-aj1fmsb7.c-3.us-east-2.aws.neon.tech/neondb?ssl=require
STRIPIE_API_KEY=<random long secret> # shared with the iOS app
```

> Neon `DATABASE_URL` was fetched via `neonctl` (project `delicate-sea-80612416`,
> role `neondb_owner`, db `neondb`). The raw value uses the `postgresql://`
> scheme with `sslmode=require&channel_binding=require`; for async SQLAlchemy it
> is rewritten to the `postgresql+asyncpg://` driver with `ssl=require`
> (asyncpg does not accept libpq's `sslmode`/`channel_binding` query params).

### iOS (Xcode scheme — corrected names)

```
STRIPIE_API_URL=http://localhost:8000
STRIPE_PUBLISHABLE_KEY_TEST=pk_test_51SovKy...   # present
STRIPIE_API_KEY=<same as backend>                # new
```

## Security Notes

- The leaked `rk_live_...` key (previously in `.env.local`) must be **rolled**.
  Secret keys live only on the backend as `STRIPE_SECRET_KEY`, never in the app.
- The iOS `STRIPE_PUBLISHABLE_KEY_*` slots take **publishable** (`pk_...`) keys.
- `.env` is gitignored in the backend repo; `.env.example` documents names only.

## Testing

- Unit: endpoint handlers with the Stripe SDK mocked; assert request mapping and
  response shape (snake_case keys, correct fields).
- Webhook: signature verification path + upsert logic against a test DB.
- Pagination: keyset paging returns correct pages and `has_more`.
- Auth: requests without/with wrong `X-API-Key` → 401.

## Out of Scope (YAGNI)

- Multi-user / login / JWT (single-merchant app).
- Refunds, disputes, reporting (can be added later).
- Non-card_present payment methods.
