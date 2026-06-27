# Stripie Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the FastAPI backend that serves the Stripie iOS Tap-to-Pay app — Stripe secret-key operations, a Postgres (Neon) payments mirror, and a Stripe webhook — and add the matching `X-API-Key` header to the iOS client.

**Architecture:** FastAPI service performs all Stripe secret-key calls; the iOS app never holds a secret key. Stripe is the source of truth for money; a Neon Postgres table mirrors payments and is kept in sync by a Stripe webhook, so `GET /transactions` reads from the DB. Manual-capture flow (auth on device, settle via `/capture`). All app endpoints require a static `X-API-Key`.

**Tech Stack:** Python 3.12, FastAPI, Uvicorn, `stripe` SDK, SQLAlchemy 2.0 async + `asyncpg`, Alembic, `pydantic-settings`, pytest + `pytest-asyncio` + `httpx`. Backend repo: `~/Code/stripie-backend/`.

## Global Constraints

- **Backend repo root:** `~/Code/stripie-backend/` (sibling to the iOS repo, separate git repo).
- **Wire format:** all JSON request/response keys are **snake_case** (the iOS client uses `convertFromSnakeCase`/`convertToSnakeCase`). Response models must emit snake_case.
- **Auth:** every app endpoint requires header `X-API-Key: <STRIPIE_API_KEY>` → `401` if missing/wrong. The webhook endpoint is exempt (Stripe signature instead).
- **Capture:** PaymentIntents are created with `capture_method="manual"` and `payment_method_types=["card_present"]`.
- **Error shape:** errors return `{ "detail": "<message>" }` (FastAPI default; iOS reads `detail` first).
- **Dates:** `created_at` is an ISO-8601 string in responses.
- **Secrets:** `.env` is gitignored; `.env.example` documents names only. The Stripe secret key is `sk_test_...` to start; the leaked `rk_live_` key must be rolled (user action).
- **DB driver:** async SQLAlchemy uses `postgresql+asyncpg://...?ssl=require`. asyncpg does **not** accept libpq's `sslmode`/`channel_binding` query params — strip them and use `ssl=require`.

## File Structure

```
~/Code/stripie-backend/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI app + lifespan + router registration + /health
│   ├── config.py            # Settings (pydantic-settings); URL normalization
│   ├── auth.py              # require_api_key dependency
│   ├── db.py                # async engine, session factory, get_session dependency
│   ├── models.py            # Payment ORM model + Base
│   ├── schemas.py           # Pydantic request/response models
│   ├── stripe_client.py     # init + thin wrappers over the stripe SDK
│   └── routers/
│       ├── __init__.py
│       ├── terminal.py      # POST /terminal/connection_token
│       ├── payments.py      # POST /payment_intents ; POST /payment_intents/{id}/capture
│       ├── transactions.py  # GET /transactions
│       └── webhooks.py      # POST /webhooks/stripe
├── alembic/                 # migration env + versions
├── alembic.ini
├── tests/
│   ├── __init__.py
│   ├── conftest.py          # app + test DB + mocked stripe fixtures
│   ├── test_auth.py
│   ├── test_terminal.py
│   ├── test_payments.py
│   ├── test_transactions.py
│   └── test_webhooks.py
├── .env.example
├── .env                     # gitignored, real secrets
├── .gitignore
├── Dockerfile
├── pyproject.toml
└── README.md

# iOS repo change (separate):
~/Code/Stripie/Stripie/Core/Networking/APIClient.swift   # add X-API-Key header
~/Code/Stripie/Stripie/Core/Config/AppConfiguration.swift # add apiKey from env
```

---

### Task 1: Project scaffold, config, and health check

**Files:**
- Create: `~/Code/stripie-backend/pyproject.toml`
- Create: `~/Code/stripie-backend/.gitignore`
- Create: `~/Code/stripie-backend/.env.example`
- Create: `~/Code/stripie-backend/app/__init__.py` (empty)
- Create: `~/Code/stripie-backend/app/config.py`
- Create: `~/Code/stripie-backend/app/main.py`
- Test: `~/Code/stripie-backend/tests/__init__.py` (empty), `~/Code/stripie-backend/tests/conftest.py`, `~/Code/stripie-backend/tests/test_health.py`

**Interfaces:**
- Produces:
  - `app.config.Settings` (pydantic-settings) with fields: `stripe_secret_key: str`, `stripe_webhook_secret: str = ""`, `database_url: str`, `stripie_api_key: str`. Plus `@property async_database_url: str` that rewrites `postgresql://`→`postgresql+asyncpg://` and replaces `sslmode=...`/`channel_binding=...` query params with `ssl=require`.
  - `app.config.get_settings() -> Settings` (cached via `functools.lru_cache`).
  - `app.main.app` (FastAPI instance). `GET /health` → `{"status": "ok"}`.
  - `tests/conftest.py` fixture `client` → `httpx.AsyncClient` bound to `app` via ASGI transport.

- [ ] **Step 1: Initialize repo and git**

```bash
mkdir -p ~/Code/stripie-backend/app/routers ~/Code/stripie-backend/tests
cd ~/Code/stripie-backend && git init -q
```

- [ ] **Step 2: Write `pyproject.toml`**

```toml
[project]
name = "stripie-backend"
version = "0.1.0"
requires-python = ">=3.12"
dependencies = [
    "fastapi>=0.111",
    "uvicorn[standard]>=0.30",
    "stripe>=9.0",
    "sqlalchemy>=2.0",
    "asyncpg>=0.29",
    "alembic>=1.13",
    "pydantic-settings>=2.2",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-asyncio>=0.23",
    "httpx>=0.27",
    "aiosqlite>=0.20",
]

[tool.pytest.ini_options]
asyncio_mode = "auto"

[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[tool.setuptools]
packages = ["app", "app.routers"]
```

- [ ] **Step 3: Write `.gitignore` and `.env.example`**

`.gitignore`:
```
.env
__pycache__/
*.pyc
.venv/
.pytest_cache/
*.egg-info/
```

`.env.example`:
```
STRIPE_SECRET_KEY=sk_test_xxx
STRIPE_WEBHOOK_SECRET=whsec_xxx
DATABASE_URL=postgresql://user:password@host/dbname?sslmode=require
STRIPIE_API_KEY=generate-a-long-random-string
```

- [ ] **Step 4: Write the failing test** — `tests/test_health.py`

```python
import pytest

@pytest.mark.asyncio
async def test_health(client):
    resp = await client.get("/health")
    assert resp.status_code == 200
    assert resp.json() == {"status": "ok"}
```

`tests/conftest.py`:
```python
import os
import pytest
import pytest_asyncio

os.environ.setdefault("STRIPE_SECRET_KEY", "sk_test_dummy")
os.environ.setdefault("STRIPIE_API_KEY", "test-api-key")
os.environ.setdefault("DATABASE_URL", "postgresql://u:p@localhost/db")

from httpx import AsyncClient, ASGITransport
from app.main import app

@pytest_asyncio.fixture
async def client():
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
```

Create empty `tests/__init__.py` and `app/__init__.py`.

- [ ] **Step 5: Write `app/config.py`**

```python
from functools import lru_cache
from urllib.parse import urlsplit, urlunsplit, parse_qsl, urlencode
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    stripe_secret_key: str
    stripe_webhook_secret: str = ""
    database_url: str
    stripie_api_key: str

    @property
    def async_database_url(self) -> str:
        parts = urlsplit(self.database_url)
        scheme = "postgresql+asyncpg"
        # asyncpg rejects libpq params; drop sslmode/channel_binding, force ssl=require
        drop = {"sslmode", "channel_binding"}
        query = [(k, v) for k, v in parse_qsl(parts.query) if k not in drop]
        if "ssl" not in dict(query):
            query.append(("ssl", "require"))
        return urlunsplit((scheme, parts.netloc, parts.path, urlencode(query), parts.fragment))


@lru_cache
def get_settings() -> Settings:
    return Settings()
```

- [ ] **Step 6: Write `app/main.py`**

```python
from fastapi import FastAPI

app = FastAPI(title="Stripie Backend")


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
```

- [ ] **Step 7: Install and run the test**

Run:
```bash
cd ~/Code/stripie-backend && python -m venv .venv && . .venv/bin/activate && pip install -q -e ".[dev]"
pytest tests/test_health.py -v
```
Expected: PASS.

- [ ] **Step 8: Add a config unit test and run it**

Append to `tests/test_health.py`:
```python
def test_async_database_url_rewrites_driver_and_ssl():
    from app.config import Settings
    s = Settings(
        stripe_secret_key="sk_test_x",
        database_url="postgresql://u:p@h.neon.tech/db?sslmode=require&channel_binding=require",
        stripie_api_key="k",
    )
    url = s.async_database_url
    assert url.startswith("postgresql+asyncpg://")
    assert "sslmode" not in url
    assert "channel_binding" not in url
    assert "ssl=require" in url
```

Run: `pytest tests/test_health.py -v` → Expected: PASS (both tests).

- [ ] **Step 9: Commit**

```bash
cd ~/Code/stripie-backend
git add -A
git commit -m "feat: scaffold FastAPI app with config and health check"
```

---

### Task 2: Database layer (engine, session, Payment model)

**Files:**
- Create: `~/Code/stripie-backend/app/db.py`
- Create: `~/Code/stripie-backend/app/models.py`
- Test: `~/Code/stripie-backend/tests/test_models.py`

**Interfaces:**
- Consumes: `app.config.get_settings`.
- Produces:
  - `app.models.Base` (DeclarativeBase).
  - `app.models.Payment` with columns: `id: Mapped[str]` (PK), `amount: Mapped[int]`, `currency: Mapped[str]`, `status: Mapped[str]`, `description: Mapped[str | None]`, `created_at: Mapped[datetime]` (tz-aware), `updated_at: Mapped[datetime]`.
  - `app.db.engine`, `app.db.SessionLocal` (async_sessionmaker), and dependency `app.db.get_session() -> AsyncIterator[AsyncSession]`.
  - `app.db.create_all()` async helper (used by tests/lifespan in dev).

- [ ] **Step 1: Write the failing test** — `tests/test_models.py`

```python
import pytest
from datetime import datetime, timezone
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from sqlalchemy import select
from app.models import Base, Payment


@pytest.mark.asyncio
async def test_payment_roundtrip():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    Session = async_sessionmaker(engine, expire_on_commit=False)
    async with Session() as s:
        s.add(Payment(
            id="pi_1", amount=2450, currency="usd", status="requires_capture",
            description="coffee",
            created_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
            updated_at=datetime(2026, 1, 1, tzinfo=timezone.utc),
        ))
        await s.commit()
        row = (await s.execute(select(Payment).where(Payment.id == "pi_1"))).scalar_one()
        assert row.amount == 2450
        assert row.status == "requires_capture"
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/test_models.py -v`
Expected: FAIL with `ModuleNotFoundError: app.models` / cannot import `Payment`.

- [ ] **Step 3: Write `app/models.py`**

```python
from datetime import datetime
from sqlalchemy import String, Integer, DateTime
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class Payment(Base):
    __tablename__ = "payments"

    id: Mapped[str] = mapped_column(String, primary_key=True)
    amount: Mapped[int] = mapped_column(Integer, nullable=False)
    currency: Mapped[str] = mapped_column(String, nullable=False)
    status: Mapped[str] = mapped_column(String, nullable=False)
    description: Mapped[str | None] = mapped_column(String, nullable=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
```

- [ ] **Step 4: Write `app/db.py`**

```python
from collections.abc import AsyncIterator
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker, AsyncSession
from app.config import get_settings
from app.models import Base

settings = get_settings()
engine = create_async_engine(settings.async_database_url, pool_pre_ping=True)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False, class_=AsyncSession)


async def get_session() -> AsyncIterator[AsyncSession]:
    async with SessionLocal() as session:
        yield session


async def create_all() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
```

- [ ] **Step 5: Run to verify it passes**

Run: `pytest tests/test_models.py -v` → Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd ~/Code/stripie-backend
git add app/db.py app/models.py tests/test_models.py
git commit -m "feat: add async db engine and Payment model"
```

---

### Task 3: Auth dependency (X-API-Key)

**Files:**
- Create: `~/Code/stripie-backend/app/auth.py`
- Modify: `~/Code/stripie-backend/app/main.py` (add a temporary protected probe route for the test, then remove in Task 4 — instead, test the dependency directly)
- Test: `~/Code/stripie-backend/tests/test_auth.py`

**Interfaces:**
- Consumes: `app.config.get_settings`.
- Produces: `app.auth.require_api_key` — a FastAPI dependency that reads header `X-API-Key`, compares (constant-time) to `settings.stripie_api_key`, raises `HTTPException(401, "Invalid or missing API key")` on mismatch. Routers include it via `dependencies=[Depends(require_api_key)]`.

- [ ] **Step 1: Write the failing test** — `tests/test_auth.py`

```python
import pytest
from fastapi import FastAPI, Depends
from httpx import AsyncClient, ASGITransport
from app.auth import require_api_key


def build_app() -> FastAPI:
    app = FastAPI()

    @app.get("/protected", dependencies=[Depends(require_api_key)])
    async def protected():
        return {"ok": True}

    return app


@pytest.mark.asyncio
async def test_missing_key_rejected():
    transport = ASGITransport(app=build_app())
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get("/protected")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_wrong_key_rejected():
    transport = ASGITransport(app=build_app())
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get("/protected", headers={"X-API-Key": "nope"})
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_correct_key_allowed():
    transport = ASGITransport(app=build_app())
    async with AsyncClient(transport=transport, base_url="http://test") as c:
        resp = await c.get("/protected", headers={"X-API-Key": "test-api-key"})
    assert resp.status_code == 200
    assert resp.json() == {"ok": True}
```

(The `test-api-key` value matches `conftest.py`'s `STRIPIE_API_KEY` env default.)

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/test_auth.py -v`
Expected: FAIL — cannot import `require_api_key`.

- [ ] **Step 3: Write `app/auth.py`**

```python
import hmac
from fastapi import Header, HTTPException
from app.config import get_settings


async def require_api_key(x_api_key: str | None = Header(default=None)) -> None:
    expected = get_settings().stripie_api_key
    if x_api_key is None or not hmac.compare_digest(x_api_key, expected):
        raise HTTPException(status_code=401, detail="Invalid or missing API key")
```

- [ ] **Step 4: Run to verify it passes**

Run: `pytest tests/test_auth.py -v` → Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
cd ~/Code/stripie-backend
git add app/auth.py tests/test_auth.py
git commit -m "feat: add X-API-Key auth dependency"
```

---

### Task 4: Stripe client wrapper + schemas

**Files:**
- Create: `~/Code/stripie-backend/app/stripe_client.py`
- Create: `~/Code/stripie-backend/app/schemas.py`
- Test: `~/Code/stripie-backend/tests/test_schemas.py`

**Interfaces:**
- Consumes: `app.config.get_settings`.
- Produces:
  - `app.stripe_client.get_stripe()` → the configured `stripe` module (sets `stripe.api_key`). Centralizes init so tests can monkeypatch `app.stripe_client.get_stripe`.
  - `app.schemas`:
    - `ConnectionTokenResponse(secret: str)`
    - `CreatePaymentIntentRequest(amount: int, currency: str = "usd", description: str | None = None)`
    - `PaymentIntentResponse(id: str, client_secret: str, amount: int, currency: str, status: str)`
    - `CapturePaymentIntentResponse(id: str, status: str, amount: int, currency: str, created_at: str | None = None)`
    - `TransactionItem(id: str, amount: int, currency: str, status: str, description: str | None, created_at: str)`
    - `TransactionListResponse(transactions: list[TransactionItem], has_more: bool)`
  - All response models use snake_case field names (already snake_case) and default Pydantic serialization.

- [ ] **Step 1: Write the failing test** — `tests/test_schemas.py`

```python
from app.schemas import PaymentIntentResponse, TransactionListResponse, TransactionItem


def test_payment_intent_response_snake_case():
    m = PaymentIntentResponse(id="pi_1", client_secret="cs_1", amount=100, currency="usd", status="requires_capture")
    dumped = m.model_dump()
    assert dumped["client_secret"] == "cs_1"
    assert set(dumped) == {"id", "client_secret", "amount", "currency", "status"}


def test_transaction_list_shape():
    m = TransactionListResponse(
        transactions=[TransactionItem(id="pi_1", amount=100, currency="usd", status="succeeded", description=None, created_at="2026-01-01T00:00:00Z")],
        has_more=False,
    )
    d = m.model_dump()
    assert d["has_more"] is False
    assert d["transactions"][0]["created_at"] == "2026-01-01T00:00:00Z"
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/test_schemas.py -v`
Expected: FAIL — cannot import from `app.schemas`.

- [ ] **Step 3: Write `app/schemas.py`**

```python
from pydantic import BaseModel


class ConnectionTokenResponse(BaseModel):
    secret: str


class CreatePaymentIntentRequest(BaseModel):
    amount: int
    currency: str = "usd"
    description: str | None = None


class PaymentIntentResponse(BaseModel):
    id: str
    client_secret: str
    amount: int
    currency: str
    status: str


class CapturePaymentIntentResponse(BaseModel):
    id: str
    status: str
    amount: int
    currency: str
    created_at: str | None = None


class TransactionItem(BaseModel):
    id: str
    amount: int
    currency: str
    status: str
    description: str | None
    created_at: str


class TransactionListResponse(BaseModel):
    transactions: list[TransactionItem]
    has_more: bool
```

- [ ] **Step 4: Write `app/stripe_client.py`**

```python
import stripe
from app.config import get_settings


def get_stripe():
    stripe.api_key = get_settings().stripe_secret_key
    return stripe
```

- [ ] **Step 5: Run to verify it passes**

Run: `pytest tests/test_schemas.py -v` → Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd ~/Code/stripie-backend
git add app/stripe_client.py app/schemas.py tests/test_schemas.py
git commit -m "feat: add stripe client wrapper and API schemas"
```

---

### Task 5: Terminal connection-token endpoint

**Files:**
- Create: `~/Code/stripie-backend/app/routers/__init__.py` (empty)
- Create: `~/Code/stripie-backend/app/routers/terminal.py`
- Modify: `~/Code/stripie-backend/app/main.py` (register the router)
- Test: `~/Code/stripie-backend/tests/test_terminal.py`

**Interfaces:**
- Consumes: `app.auth.require_api_key`, `app.stripe_client.get_stripe`, `app.schemas.ConnectionTokenResponse`.
- Produces: `app.routers.terminal.router` with `POST /terminal/connection_token` → `ConnectionTokenResponse`. Registered on `app` in `main.py`.

- [ ] **Step 1: Write the failing test** — `tests/test_terminal.py`

```python
import pytest
from types import SimpleNamespace
import app.stripe_client as sc


@pytest.fixture
def stub_stripe(monkeypatch):
    created = {}
    class FakeConnToken:
        @staticmethod
        def create():
            created["called"] = True
            return SimpleNamespace(secret="pst_test_123")
    fake = SimpleNamespace(terminal=SimpleNamespace(ConnectionToken=FakeConnToken))
    monkeypatch.setattr(sc, "get_stripe", lambda: fake)
    return created


@pytest.mark.asyncio
async def test_connection_token_requires_auth(client):
    resp = await client.post("/terminal/connection_token")
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_connection_token_returns_secret(client, stub_stripe):
    resp = await client.post("/terminal/connection_token", headers={"X-API-Key": "test-api-key"})
    assert resp.status_code == 200
    assert resp.json() == {"secret": "pst_test_123"}
    assert stub_stripe["called"]
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/test_terminal.py -v`
Expected: FAIL — route 404 (not registered).

- [ ] **Step 3: Write `app/routers/terminal.py`**

```python
from fastapi import APIRouter, Depends
from app.auth import require_api_key
from app.stripe_client import get_stripe
from app.schemas import ConnectionTokenResponse

router = APIRouter(dependencies=[Depends(require_api_key)])


@router.post("/terminal/connection_token", response_model=ConnectionTokenResponse)
async def connection_token() -> ConnectionTokenResponse:
    token = get_stripe().terminal.ConnectionToken.create()
    return ConnectionTokenResponse(secret=token.secret)
```

- [ ] **Step 4: Register the router in `app/main.py`**

Replace `app/main.py` with:
```python
from fastapi import FastAPI
from app.routers import terminal

app = FastAPI(title="Stripie Backend")
app.include_router(terminal.router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
```

Create empty `app/routers/__init__.py`.

- [ ] **Step 5: Run to verify it passes**

Run: `pytest tests/test_terminal.py tests/test_health.py -v` → Expected: PASS.

- [ ] **Step 6: Commit**

```bash
cd ~/Code/stripie-backend
git add app/routers/ app/main.py tests/test_terminal.py
git commit -m "feat: add terminal connection_token endpoint"
```

---

### Task 6: Payment intent create + capture endpoints

**Files:**
- Create: `~/Code/stripie-backend/app/routers/payments.py`
- Modify: `~/Code/stripie-backend/app/main.py` (register router)
- Test: `~/Code/stripie-backend/tests/test_payments.py`

**Interfaces:**
- Consumes: `app.auth.require_api_key`, `app.stripe_client.get_stripe`, `app.db.get_session`, `app.models.Payment`, schemas `CreatePaymentIntentRequest`, `PaymentIntentResponse`, `CapturePaymentIntentResponse`.
- Produces: `app.routers.payments.router`:
  - `POST /payment_intents` — creates PI (`capture_method="manual"`, `payment_method_types=["card_present"]`), upserts a `Payment` row, returns `PaymentIntentResponse`.
  - `POST /payment_intents/{id}/capture` — captures PI, upserts row, returns `CapturePaymentIntentResponse`.
  - Shared helper `upsert_payment(session, *, id, amount, currency, status, description, created_ts: int)`.
- Note: tests override `app.db.get_session` with an in-memory SQLite session via `app.dependency_overrides`.

- [ ] **Step 1: Write the failing test** — `tests/test_payments.py`

```python
import pytest
from types import SimpleNamespace
import app.stripe_client as sc
import app.db as db
from app.main import app
from app.models import Base
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker


@pytest.fixture
async def sqlite_session(monkeypatch):
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    Session = async_sessionmaker(engine, expire_on_commit=False)

    async def override():
        async with Session() as s:
            yield s

    app.dependency_overrides[db.get_session] = override
    yield Session
    app.dependency_overrides.clear()


@pytest.fixture
def stub_stripe(monkeypatch):
    class FakePI:
        @staticmethod
        def create(**kwargs):
            assert kwargs["capture_method"] == "manual"
            assert kwargs["payment_method_types"] == ["card_present"]
            return SimpleNamespace(id="pi_1", client_secret="pi_1_secret",
                                   amount=kwargs["amount"], currency=kwargs["currency"],
                                   status="requires_payment_method", created=1735689600,
                                   description=kwargs.get("description"))
        @staticmethod
        def capture(pid):
            return SimpleNamespace(id=pid, status="succeeded", amount=2450,
                                   currency="usd", created=1735689600, description="coffee")
    fake = SimpleNamespace(PaymentIntent=FakePI)
    monkeypatch.setattr(sc, "get_stripe", lambda: fake)


@pytest.mark.asyncio
async def test_create_payment_intent(client, sqlite_session, stub_stripe):
    resp = await client.post("/payment_intents",
                             headers={"X-API-Key": "test-api-key"},
                             json={"amount": 2450, "currency": "usd", "description": "coffee"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == "pi_1"
    assert body["client_secret"] == "pi_1_secret"
    assert body["amount"] == 2450


@pytest.mark.asyncio
async def test_capture_payment_intent(client, sqlite_session, stub_stripe):
    resp = await client.post("/payment_intents/pi_1/capture",
                             headers={"X-API-Key": "test-api-key"})
    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == "pi_1"
    assert body["status"] == "succeeded"
    assert body["created_at"] is not None


@pytest.mark.asyncio
async def test_create_requires_auth(client):
    resp = await client.post("/payment_intents", json={"amount": 100})
    assert resp.status_code == 401
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/test_payments.py -v`
Expected: FAIL — routes 404.

- [ ] **Step 3: Write `app/routers/payments.py`**

```python
from datetime import datetime, timezone
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from app.auth import require_api_key
from app.stripe_client import get_stripe
from app.db import get_session
from app.models import Payment
from app.schemas import (
    CreatePaymentIntentRequest,
    PaymentIntentResponse,
    CapturePaymentIntentResponse,
)

router = APIRouter(dependencies=[Depends(require_api_key)])


def _iso(ts: int) -> str:
    return datetime.fromtimestamp(ts, tz=timezone.utc).isoformat()


async def upsert_payment(session: AsyncSession, *, id: str, amount: int,
                         currency: str, status: str, description: str | None,
                         created_ts: int) -> None:
    now = datetime.now(timezone.utc)
    existing = await session.get(Payment, id)
    if existing is None:
        session.add(Payment(
            id=id, amount=amount, currency=currency, status=status,
            description=description,
            created_at=datetime.fromtimestamp(created_ts, tz=timezone.utc),
            updated_at=now,
        ))
    else:
        existing.amount = amount
        existing.currency = currency
        existing.status = status
        existing.description = description
        existing.updated_at = now
    await session.commit()


@router.post("/payment_intents", response_model=PaymentIntentResponse)
async def create_payment_intent(body: CreatePaymentIntentRequest,
                                session: AsyncSession = Depends(get_session)) -> PaymentIntentResponse:
    stripe = get_stripe()
    pi = stripe.PaymentIntent.create(
        amount=body.amount,
        currency=body.currency,
        description=body.description,
        capture_method="manual",
        payment_method_types=["card_present"],
    )
    await upsert_payment(session, id=pi.id, amount=pi.amount, currency=pi.currency,
                         status=pi.status, description=getattr(pi, "description", None),
                         created_ts=pi.created)
    return PaymentIntentResponse(id=pi.id, client_secret=pi.client_secret,
                                 amount=pi.amount, currency=pi.currency, status=pi.status)


@router.post("/payment_intents/{intent_id}/capture", response_model=CapturePaymentIntentResponse)
async def capture_payment_intent(intent_id: str,
                                 session: AsyncSession = Depends(get_session)) -> CapturePaymentIntentResponse:
    stripe = get_stripe()
    try:
        pi = stripe.PaymentIntent.capture(intent_id)
    except Exception as exc:  # stripe.error.StripeError in prod
        raise HTTPException(status_code=400, detail=str(exc))
    await upsert_payment(session, id=pi.id, amount=pi.amount, currency=pi.currency,
                         status=pi.status, description=getattr(pi, "description", None),
                         created_ts=pi.created)
    return CapturePaymentIntentResponse(id=pi.id, status=pi.status, amount=pi.amount,
                                        currency=pi.currency, created_at=_iso(pi.created))
```

- [ ] **Step 4: Register router in `app/main.py`**

Add `from app.routers import terminal, payments` and `app.include_router(payments.router)` alongside the terminal include.

- [ ] **Step 5: Run to verify it passes**

Run: `pytest tests/test_payments.py -v` → Expected: PASS (3 tests).

- [ ] **Step 6: Commit**

```bash
cd ~/Code/stripie-backend
git add app/routers/payments.py app/main.py tests/test_payments.py
git commit -m "feat: add payment_intents create and capture endpoints"
```

---

### Task 7: Transactions list endpoint (keyset pagination)

**Files:**
- Create: `~/Code/stripie-backend/app/routers/transactions.py`
- Modify: `~/Code/stripie-backend/app/main.py` (register router)
- Test: `~/Code/stripie-backend/tests/test_transactions.py`

**Interfaces:**
- Consumes: `app.auth.require_api_key`, `app.db.get_session`, `app.models.Payment`, schemas `TransactionItem`, `TransactionListResponse`.
- Produces: `app.routers.transactions.router` with `GET /transactions?limit=&starting_after=`. Orders by `(created_at DESC, id DESC)`. `starting_after` = last returned `id`; resolves that row's `(created_at, id)` and returns rows strictly after it in the ordering. `has_more` = a row exists beyond the page. `limit` defaults to 25, capped at 100.

- [ ] **Step 1: Write the failing test** — `tests/test_transactions.py`

```python
import pytest
from datetime import datetime, timezone
import app.db as db
from app.main import app
from app.models import Base, Payment
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker


@pytest.fixture
async def seeded(monkeypatch):
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    Session = async_sessionmaker(engine, expire_on_commit=False)
    async with Session() as s:
        for i in range(1, 4):  # pi_1 oldest .. pi_3 newest
            s.add(Payment(id=f"pi_{i}", amount=i * 100, currency="usd",
                          status="succeeded", description=None,
                          created_at=datetime(2026, 1, i, tzinfo=timezone.utc),
                          updated_at=datetime(2026, 1, i, tzinfo=timezone.utc)))
        await s.commit()

    async def override():
        async with Session() as s:
            yield s

    app.dependency_overrides[db.get_session] = override
    yield
    app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_list_first_page_newest_first(client, seeded):
    resp = await client.get("/transactions?limit=2", headers={"X-API-Key": "test-api-key"})
    assert resp.status_code == 200
    body = resp.json()
    assert [t["id"] for t in body["transactions"]] == ["pi_3", "pi_2"]
    assert body["has_more"] is True


@pytest.mark.asyncio
async def test_list_second_page(client, seeded):
    resp = await client.get("/transactions?limit=2&starting_after=pi_2",
                            headers={"X-API-Key": "test-api-key"})
    body = resp.json()
    assert [t["id"] for t in body["transactions"]] == ["pi_1"]
    assert body["has_more"] is False


@pytest.mark.asyncio
async def test_list_requires_auth(client):
    resp = await client.get("/transactions")
    assert resp.status_code == 401
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/test_transactions.py -v`
Expected: FAIL — route 404.

- [ ] **Step 3: Write `app/routers/transactions.py`**

```python
from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy import select, tuple_
from sqlalchemy.ext.asyncio import AsyncSession
from app.auth import require_api_key
from app.db import get_session
from app.models import Payment
from app.schemas import TransactionItem, TransactionListResponse

router = APIRouter(dependencies=[Depends(require_api_key)])


@router.get("/transactions", response_model=TransactionListResponse)
async def list_transactions(
    limit: int = Query(default=25, ge=1, le=100),
    starting_after: str | None = Query(default=None),
    session: AsyncSession = Depends(get_session),
) -> TransactionListResponse:
    stmt = select(Payment).order_by(Payment.created_at.desc(), Payment.id.desc())

    if starting_after is not None:
        cursor = await session.get(Payment, starting_after)
        if cursor is None:
            raise HTTPException(status_code=400, detail="Unknown starting_after cursor")
        # rows strictly "after" cursor in (created_at DESC, id DESC) ordering
        stmt = stmt.where(
            tuple_(Payment.created_at, Payment.id) < (cursor.created_at, cursor.id)
        )

    rows = (await session.execute(stmt.limit(limit + 1))).scalars().all()
    has_more = len(rows) > limit
    rows = rows[:limit]

    items = [
        TransactionItem(
            id=r.id, amount=r.amount, currency=r.currency, status=r.status,
            description=r.description, created_at=r.created_at.isoformat(),
        )
        for r in rows
    ]
    return TransactionListResponse(transactions=items, has_more=has_more)
```

- [ ] **Step 4: Register router in `app/main.py`**

Add `transactions` to the import and `app.include_router(transactions.router)`.

- [ ] **Step 5: Run to verify it passes**

Run: `pytest tests/test_transactions.py -v` → Expected: PASS (3 tests).

> Note: the `tuple_(...) < (...)` row-value comparison works on SQLite and
> Postgres. If a future engine rejects it, fall back to the expanded form:
> `(created_at < c.created_at) OR (created_at == c.created_at AND id < c.id)`.

- [ ] **Step 6: Commit**

```bash
cd ~/Code/stripie-backend
git add app/routers/transactions.py app/main.py tests/test_transactions.py
git commit -m "feat: add transactions list endpoint with keyset pagination"
```

---

### Task 8: Stripe webhook (signature verify + upsert)

**Files:**
- Create: `~/Code/stripie-backend/app/routers/webhooks.py`
- Modify: `~/Code/stripie-backend/app/main.py` (register router)
- Test: `~/Code/stripie-backend/tests/test_webhooks.py`

**Interfaces:**
- Consumes: `app.stripe_client.get_stripe`, `app.config.get_settings`, `app.db.get_session`, `app.routers.payments.upsert_payment`.
- Produces: `app.routers.webhooks.router` with `POST /webhooks/stripe` (NO api-key dependency). Reads raw body + `Stripe-Signature` header, verifies via `stripe.Webhook.construct_event(payload, sig, webhook_secret)`. On `payment_intent.*` events, upserts the PI into `payments`. Returns `{"received": true}`. On signature failure → `400`.

- [ ] **Step 1: Write the failing test** — `tests/test_webhooks.py`

```python
import json
import pytest
from types import SimpleNamespace
import app.stripe_client as sc
import app.db as db
from app.main import app
from app.models import Base, Payment
from sqlalchemy import select
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker


@pytest.fixture
async def sqlite_session():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    Session = async_sessionmaker(engine, expire_on_commit=False)

    async def override():
        async with Session() as s:
            yield s

    app.dependency_overrides[db.get_session] = override
    yield Session
    app.dependency_overrides.clear()


@pytest.fixture
def stub_webhook(monkeypatch):
    event = {
        "type": "payment_intent.succeeded",
        "data": {"object": {
            "id": "pi_wh", "amount": 500, "currency": "usd",
            "status": "succeeded", "description": "hook", "created": 1735689600,
        }},
    }

    class FakeWebhook:
        @staticmethod
        def construct_event(payload, sig, secret):
            if sig != "good-sig":
                raise ValueError("bad signature")
            return event

    fake = SimpleNamespace(Webhook=FakeWebhook)
    monkeypatch.setattr(sc, "get_stripe", lambda: fake)
    return event


@pytest.mark.asyncio
async def test_webhook_bad_signature(client, sqlite_session, stub_webhook):
    resp = await client.post("/webhooks/stripe", content=b"{}",
                             headers={"Stripe-Signature": "bad"})
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_webhook_upserts_payment(client, sqlite_session, stub_webhook):
    resp = await client.post("/webhooks/stripe", content=b"{}",
                             headers={"Stripe-Signature": "good-sig"})
    assert resp.status_code == 200
    assert resp.json() == {"received": True}
    async with sqlite_session() as s:
        row = (await s.execute(select(Payment).where(Payment.id == "pi_wh"))).scalar_one()
        assert row.status == "succeeded"
        assert row.amount == 500
```

- [ ] **Step 2: Run to verify it fails**

Run: `pytest tests/test_webhooks.py -v`
Expected: FAIL — route 404.

- [ ] **Step 3: Write `app/routers/webhooks.py`**

```python
from fastapi import APIRouter, Request, Header, HTTPException, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.stripe_client import get_stripe
from app.config import get_settings
from app.db import get_session
from app.routers.payments import upsert_payment

router = APIRouter()


@router.post("/webhooks/stripe")
async def stripe_webhook(
    request: Request,
    stripe_signature: str | None = Header(default=None, alias="Stripe-Signature"),
    session: AsyncSession = Depends(get_session),
) -> dict[str, bool]:
    payload = await request.body()
    stripe = get_stripe()
    try:
        event = stripe.Webhook.construct_event(
            payload, stripe_signature, get_settings().stripe_webhook_secret
        )
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid signature")

    event_type = event["type"] if isinstance(event, dict) else event.type
    if event_type.startswith("payment_intent."):
        obj = (event["data"]["object"] if isinstance(event, dict)
               else event.data.object)
        await upsert_payment(
            session,
            id=obj["id"], amount=obj["amount"], currency=obj["currency"],
            status=obj["status"], description=obj.get("description"),
            created_ts=obj["created"],
        )

    return {"received": True}
```

- [ ] **Step 4: Register router in `app/main.py`**

Add `webhooks` to the import and `app.include_router(webhooks.router)`.

- [ ] **Step 5: Run to verify it passes**

Run: `pytest tests/test_webhooks.py -v` → Expected: PASS (2 tests).

- [ ] **Step 6: Run the full suite**

Run: `pytest -v` → Expected: ALL PASS.

- [ ] **Step 7: Commit**

```bash
cd ~/Code/stripie-backend
git add app/routers/webhooks.py app/main.py tests/test_webhooks.py
git commit -m "feat: add stripe webhook with signature verify and payment upsert"
```

---

### Task 9: Alembic migration, lifespan, Dockerfile, README

**Files:**
- Create: `~/Code/stripie-backend/alembic.ini`, `~/Code/stripie-backend/alembic/env.py`, `~/Code/stripie-backend/alembic/script.py.mako`, one version file under `alembic/versions/`
- Modify: `~/Code/stripie-backend/app/main.py` (optional dev lifespan calling `create_all` only if `RUN_CREATE_ALL=1`)
- Create: `~/Code/stripie-backend/Dockerfile`, `~/Code/stripie-backend/README.md`

**Interfaces:**
- Consumes: `app.models.Base`, `app.config.get_settings`.
- Produces: a runnable migration that creates the `payments` table on Neon; a Docker image; setup docs including the webhook registration step (yields `STRIPE_WEBHOOK_SECRET`).

- [ ] **Step 1: Init Alembic**

Run:
```bash
cd ~/Code/stripie-backend && . .venv/bin/activate && alembic init alembic
```

- [ ] **Step 2: Point Alembic at the models and async URL** — edit `alembic/env.py`

Set the target metadata and URL (replace the relevant parts of the generated file):
```python
from app.models import Base
from app.config import get_settings

target_metadata = Base.metadata

def get_url() -> str:
    # Alembic runs sync; use the plain (non-asyncpg) URL.
    return get_settings().database_url

# in run_migrations_offline / online, use get_url() for the connection URL
config.set_main_option("sqlalchemy.url", get_url())
```

(Leave the rest of the generated `env.py` intact; for the online path, the
standard generated engine-from-config works with the sync `postgresql://` URL.)

- [ ] **Step 3: Generate the migration**

Run (requires real `DATABASE_URL` in `.env` or env):
```bash
alembic revision --autogenerate -m "create payments table"
```
Inspect the generated version file: it must `create_table("payments", ...)` with
columns `id (PK), amount, currency, status, description, created_at, updated_at`.

- [ ] **Step 4: Apply the migration to Neon**

Run:
```bash
alembic upgrade head
```
Expected: no error; `payments` table now exists on Neon.

- [ ] **Step 5: Verify the table exists via neonctl**

Run:
```bash
neonctl projects list  # confirm project delicate-sea-80612416
psql "$(grep ^DATABASE_URL .env | cut -d= -f2-)" -c "\d payments"
```
Expected: table definition prints. (If `psql` is unavailable, skip — the
`alembic upgrade head` success is sufficient evidence.)

- [ ] **Step 6: Write `Dockerfile`**

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY pyproject.toml .
RUN pip install --no-cache-dir -e .
COPY . .
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

- [ ] **Step 7: Write `README.md`**

Include: setup (`python -m venv`, `pip install -e ".[dev]"`), env vars (point to
`.env.example`), `alembic upgrade head`, `uvicorn app.main:app --reload`, running
tests (`pytest`), and the **Stripe webhook setup**:

```
Stripe Dashboard → Developers → Webhooks → Add endpoint
  URL:  https://<your-host>/webhooks/stripe   (use `stripe listen --forward-to localhost:8000/webhooks/stripe` for local)
  Events: payment_intent.created, payment_intent.succeeded,
          payment_intent.amount_capturable_updated, payment_intent.canceled,
          payment_intent.payment_failed
Copy the signing secret (whsec_...) into STRIPE_WEBHOOK_SECRET.
```

- [ ] **Step 8: Run the server once to smoke-test**

Run:
```bash
STRIPIE_API_KEY=test STRIPE_SECRET_KEY=sk_test_x uvicorn app.main:app --port 8000 &
sleep 2 && curl -s localhost:8000/health && kill %1
```
Expected: `{"status":"ok"}`.

- [ ] **Step 9: Commit**

```bash
cd ~/Code/stripie-backend
git add -A
git commit -m "chore: add alembic migration, Dockerfile, and setup docs"
```

---

### Task 10: iOS — send X-API-Key header

**Files:**
- Modify: `~/Code/Stripie/Stripie/Core/Config/AppConfiguration.swift`
- Modify: `~/Code/Stripie/Stripie/Core/Networking/APIClient.swift:49-67` (`buildRequest`)
- Test: (manual — the iOS app can't be built in this environment; verify in Xcode)

**Interfaces:**
- Consumes: nothing new.
- Produces: `AppConfiguration.apiKey: String` read from env `STRIPIE_API_KEY`; `APIClient.buildRequest` sets header `X-API-Key` when non-empty.

- [ ] **Step 1: Add `apiKey` to `AppConfiguration`**

In `AppConfiguration.swift`, add a stored property and populate it in `init()`:
```swift
let apiKey: String
```
And in both `#if DEBUG` and `#else` branches:
```swift
apiKey = env["STRIPIE_API_KEY"] ?? ""
```
(Place after the `stripePublishableKey` assignment in each branch.)

- [ ] **Step 2: Pass the key into `APIClient`**

In `APIClient.init`, capture it:
```swift
private let apiKey: String
```
and in `init(configuration:)`:
```swift
self.apiKey = configuration.apiKey
```

- [ ] **Step 3: Set the header in `buildRequest`**

In `buildRequest(for:)`, after the `Accept` header line, add:
```swift
if !apiKey.isEmpty {
    request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
}
```

- [ ] **Step 4: Add the scheme env var**

Document/set in Xcode scheme (Edit Scheme → Run → Environment Variables):
```
STRIPIE_API_KEY=<same value as backend>
```

- [ ] **Step 5: Verify in Xcode**

Build (`⌘B`) in Xcode-beta. Expected: compiles. Run against the local backend
and confirm a request succeeds (200) with the key set and fails (401) without it.
(This step is manual — no iOS build is possible in the agent environment.)

- [ ] **Step 6: Commit (iOS repo)**

```bash
cd ~/Code/Stripie
git add Stripie/Core/Config/AppConfiguration.swift Stripie/Core/Networking/APIClient.swift
git commit -m "feat: send X-API-Key header on backend requests"
```

---

## Notes for the Implementer

- The backend repo is **separate** from the iOS repo. Tasks 1–9 run in
  `~/Code/stripie-backend/`; Task 10 runs in `~/Code/Stripie/`.
- Tasks 1–8 use **mocked Stripe** and **in-memory SQLite** — they need no
  network, no real keys, no Neon. They are fully runnable in CI.
- Task 9 step 3–5 (autogenerate + apply migration) need the **real `DATABASE_URL`**
  and will write to Neon. The connection string was fetched via `neonctl`
  (project `delicate-sea-80612416`, role `neondb_owner`, db `neondb`); put it in
  `.env` (gitignored). Use the plain `postgresql://...` form for Alembic.
- The leaked `rk_live_` key must be **rolled** before any live use; start with
  `sk_test_...`.
