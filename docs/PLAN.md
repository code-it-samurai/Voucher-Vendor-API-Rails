# Gift Card Order Service — Implementation Plan

## Context

Ajakus technical assessment: build a Rails API backend service that demonstrates idempotency, background job processing, retry logic, concurrency safety, and production-quality patterns. Inspired by The Reward Store's order API — specifically their `reference_code` idempotency pattern and async order fulfillment flow.

## Tech Stack

- **Ruby on Rails 7.2** (API-only mode)
- **PostgreSQL** — concurrent access, row locks, unique constraints
- **Redis + Sidekiq** — background jobs with retry, dead letter queue
- **RSpec** — full test suite (request specs, model specs, job specs, service specs)
- **Docker Compose** — Postgres + Redis + web + sidekiq (single command setup)

## Networking Architecture

```
┌──────────────────────────────────────────────────┐
│              Docker Compose Network               │
│                                                    │
│  ┌─────────┐    port 3000     ┌──────────────┐   │
│  │   web   │◄────────────────►│  Client /    │   │
│  │ (Rails) │                  │  Postman     │   │
│  └────┬────┘                  └──────────────┘   │
│       │                                           │
│       ├── TCP 5432 ──►┌──────────┐               │
│       │               │    db    │               │
│       │               │(Postgres)│               │
│       │               └──────────┘               │
│       │                    ▲                      │
│       │                    │ TCP 5432             │
│       └── TCP 6379 ──►┌───┴──────┐               │
│                        │  redis   │               │
│                        └───┬──────┘               │
│                            │ TCP 6379             │
│                        ┌───┴──────┐               │
│                        │ sidekiq  │──► db:5432    │
│                        │ (worker) │               │
│                        └──────────┘               │
└──────────────────────────────────────────────────┘
```

- **web**: Rails API server, port 3000 exposed to host. Connects to Postgres + Redis.
- **db**: PostgreSQL 16. Both web and sidekiq read/write to it. Internal only.
- **redis**: Job queue broker. Web enqueues jobs, sidekiq dequeues them. Internal only.
- **sidekiq**: Background worker. Same Rails codebase, different entrypoint. Reads Redis, writes Postgres.
- All services communicate via Docker's internal DNS (service names as hostnames).

## Domain Model

### Database Schema

```
accounts
  - id (PK)
  - name (string, not null)
  - email (string, unique, not null)
  - api_key (string, unique, not null)         # HMAC-SHA256(server_secret, email)
  - balance (decimal, not null, default: 0.0)  # INR balance
  - lock_version (integer, default: 0)         # optimistic locking safety net
  - created_at, updated_at

  Indexes: unique on email, unique on api_key

products
  - id (PK)
  - name (string, not null)
  - denomination (decimal, not null)
  - currency (string, default: "INR")
  - active (boolean, default: true)
  - stock (integer, not null, default: 0)      # available quantity
  - test_behavior (string, nullable)           # null=normal, "success"/"failure"/"pending"/"refund"
  - created_at, updated_at

orders
  - id (PK)
  - reference_code (string, unique, not null)  # idempotency key from client
  - account_id (FK, not null)
  - product_id (FK, not null)
  - quantity (integer, not null, default: 1)
  - denomination (decimal, not null)
  - total_amount (decimal, not null)
  - status (string, not null, default: "pending")
  - failure_reason (text, nullable)
  - attempts (integer, default: 0)
  - processed_at (timestamp, nullable)
  - cancelled_at (timestamp, nullable)
  - created_at, updated_at

  Indexes: unique on reference_code, index on status, account_id, product_id

vouchers
  - id (PK)
  - order_id (FK, not null)
  - code (string, not null)
  - pin (string, nullable)
  - claim_url (string, nullable)
  - expires_at (timestamp, nullable)
  - created_at, updated_at

  Indexes: index on order_id, unique on code

transaction_records (audit log)
  - id (PK)
  - account_id (FK, not null)
  - order_id (FK, nullable)          # null for top-ups
  - transaction_type (string, not null)  # credit, debit, refund
  - amount (decimal, not null)
  - balance_before (decimal, not null)
  - balance_after (decimal, not null)
  - created_at

  Indexes: index on account_id, order_id
```

### Status State Machine

```
pending ──→ processing ──→ completed
  │              │
  │              └──→ failed ──→ refunded
  │
  └──→ cancelled (balance refunded immediately)
```

- `pending`: Order accepted, balance debited, queued for processing
- `processing`: Background job picked it up
- `completed`: Voucher(s) generated successfully
- `failed`: Downstream failure after max retries (balance refund pending)
- `refunded`: Balance has been credited back after failure (terminal)
- `cancelled`: Client cancelled before processing, balance refunded immediately (terminal)

### Test Products (seeded)

Products with `test_behavior` allow testing all states without compromising production authenticity:

| Product Name | test_behavior | Behavior |
|---|---|---|
| Amazon Gift Card | null | Normal processing (random success/failure in dev) |
| Test - Always Succeeds | "success" | Always completes immediately |
| Test - Always Fails | "failure" | Always fails, triggers refund |
| Test - Stays Pending | "pending" | Stays in processing forever (for polling tests) |
| Test - Fails After Retry | "refund" | Fails after retries, triggers refund |

Real products have `test_behavior = null` and process normally. The fulfillment service checks this field to simulate specific behaviors.

## Authentication

**API Key generation:** `HMAC-SHA256(API_KEY_SECRET env var, email)`
- Deterministic: same email + same secret = same key (regenerable)
- `API_KEY_SECRET` comes from environment variable (set in docker-compose, .env, or secrets manager)
- Constant per environment; changing it invalidates all keys (key rotation feature)

**Validation flow:**
1. Extract key from `Authorization: Bearer <key>` header
2. `Account.find_by(api_key: key)` — single DB query
3. Found → set `current_account`, proceed
4. Not found → 401 response

**Scope:** `POST /api/v1/accounts` is unauthenticated. All other endpoints require Bearer token. Account can only access its own resources.

## Consistent Response Envelope

**Every response** uses the same structure — integrators always parse `status` first:

```json
// Success
{
  "status": "SUCCESS",
  "data": { ... }
}

// Error
{
  "status": "ERROR",
  "error": {
    "code": "INSUFFICIENT_BALANCE",
    "message": "Account balance is insufficient for this order"
  }
}
```

Error codes:
- `UNAUTHORIZED` — missing/invalid API key
- `INSUFFICIENT_BALANCE` — not enough funds
- `OUT_OF_STOCK` — product stock insufficient for requested quantity
- `INVALID_INPUT` — validation failures
- `ORDER_NOT_CANCELLABLE` — order not in pending status
- `PRODUCT_NOT_FOUND` — product doesn't exist or inactive
- `INVALID_AMOUNT` — negative or zero amount
- `NOT_FOUND` — generic resource not found

**Note:** Duplicate `reference_code` is NOT an error — it's idempotent behavior. Returns the existing order with `status: "SUCCESS"` and 200 OK.

## API Endpoints

### 1. POST /api/v1/accounts — Create Account (unauthenticated)
```json
// Request
{ "name": "Prathamesh", "email": "prat@example.com" }
// Response (201)
{ "status": "SUCCESS", "data": { "id": 1, "name": "Prathamesh", "email": "prat@example.com", "balance": "0.0", "api_key": "hmac_key_here" } }
```
API key shown ONLY on creation.

### 2. GET /api/v1/accounts/me — My Account (authenticated)
Returns name, email, balance. No api_key.

### 3. POST /api/v1/accounts/top_up — Add Funds (authenticated)
```json
// Request
{ "amount": 1000.00 }
// Response (200)
{ "status": "SUCCESS", "data": { "balance": "1000.0", "transaction": { "type": "credit", "amount": "1000.0", "balance_after": "1000.0" } } }
```

### 4. POST /api/v1/orders — Place Order (idempotent, authenticated)
```json
// Request
{ "product_id": 1, "quantity": 2, "denomination": 100.00, "reference_code": "client-unique-id-123" }
// Response (202 new / 200 existing)
{ "status": "SUCCESS", "data": { "id": 1, "reference_code": "client-unique-id-123", "product_id": 1, "quantity": 2, "denomination": "100.0", "total_amount": "200.0", "status": "pending" } }
```

**Idempotency behavior:**
- New `reference_code` → create order, debit balance, enqueue job, return 202
- Existing `reference_code` → return existing order as-is, 200 (no side effects, no double debit)
- Race condition: two simultaneous requests with same `reference_code` → DB unique constraint catches the second INSERT, we rescue `ActiveRecord::RecordNotUnique` and return the existing order

**Balance debit + stock decrement (concurrency safe):**
- Lock account row (`FOR UPDATE`) → check balance >= total_amount
- Lock product row (`FOR UPDATE`) → check stock >= quantity
- Debit balance, decrement stock, create order + transaction record — all in one DB transaction
- Insufficient balance → `INSUFFICIENT_BALANCE`
- Out of stock → `OUT_OF_STOCK`
- Two orders competing: second waits for locks, then sees updated balance/stock

### 5. GET /api/v1/orders/:id — Order Details (authenticated)
Returns order with vouchers when completed. Useful for polling status after placement.

### 6. POST /api/v1/orders/:id/cancel — Cancel Order (authenticated)
- Only from `pending` status
- Row lock prevents race with job pickup
- Refunds balance + restores stock (both under locks)
- Creates refund transaction record, sets status to `cancelled`
- Non-pending → `ORDER_NOT_CANCELLABLE` error

### 7. GET /api/v1/products — List Products (authenticated)
Returns active products with denominations and stock count.

### 8. POST /api/v1/products/:id/replenish — Replenish Stock (authenticated)
```json
// Request
{ "quantity": 100 }
// Response (200)
{ "status": "SUCCESS", "data": { "id": 1, "name": "Amazon Gift Card", "stock": 150 } }
```
Simple DB increment. Uses `SELECT ... FOR UPDATE` to prevent race on concurrent replenishments.

## Background Job: OrderFulfillmentJob

```
1. Find order, check status
   - If cancelled/completed/failed → skip (idempotent, no harm in retrying)
   - If pending → proceed
2. Lock order row (FOR UPDATE), transition to "processing"
3. Check product.test_behavior:
   - null → simulate downstream (sleep 2-5s, ~20% random failure in dev)
   - "success" → succeed immediately
   - "failure" → fail immediately
   - "pending" → sleep indefinitely (stays processing)
   - "refund" → fail after simulated processing
4. On success:
   - Generate voucher(s) with code/pin/claim_url
   - Transition to "completed", set processed_at
5. On failure:
   - Increment attempts, raise error → Sidekiq retries with exponential backoff
   - On final retry exhaustion:
     - Transition to "failed", set failure_reason
     - REFUND balance (lock account row, credit balance, create refund transaction)
     - RESTORE stock (lock product row, increment stock)
     - Transition to "refunded" (terminal state)
```

**Sidekiq config:** Max 5 retries, exponential backoff, dead set callback for final failure refund.

## Key Concurrency Scenarios

| Scenario | Protection |
|---|---|
| Two orders, same `reference_code` | DB unique index + rescue RecordNotUnique |
| Two orders, same account, insufficient balance for both | `SELECT ... FOR UPDATE` on account row |
| Two orders, same product, insufficient stock for both | `SELECT ... FOR UPDATE` on product row |
| Cancel vs job pickup race | Row lock on order; one sees `pending`, other sees `cancelled`/`processing` |
| Concurrent top-ups | `SELECT ... FOR UPDATE` on account row |
| Concurrent stock replenishments | `SELECT ... FOR UPDATE` on product row |
| Job retry on already-completed order | Job checks status first, skips if not pending |

## Project Structure

```
app/
  controllers/
    application_controller.rb          # auth, error handling, response envelope
    api/v1/
      accounts_controller.rb           # create, me, top_up
      orders_controller.rb             # create, show, cancel
      products_controller.rb           # index, replenish
  models/
    account.rb                         # balance, optimistic locking, api_key generation
    order.rb                           # validations, state machine, scopes
    product.rb                         # validations, test_behavior
    voucher.rb                         # belongs_to order
    transaction_record.rb              # audit log
  services/
    accounts/
      top_up_service.rb                # add funds with locking
    orders/
      placement_service.rb             # idempotent creation + balance debit
      fulfillment_service.rb           # downstream simulation + voucher gen
      cancellation_service.rb          # cancel + refund with locking
      refund_service.rb                # refund balance on failure/cancel
  jobs/
    order_fulfillment_job.rb           # Sidekiq job

config/
  routes.rb
  sidekiq.yml
  initializers/sidekiq.rb

db/
  migrate/
    001_create_accounts.rb
    002_create_products.rb
    003_create_orders.rb
    004_create_vouchers.rb
    005_create_transaction_records.rb
  seeds.rb                             # test products + sample data
```

## Test Strategy (TDD-friendly)

All request specs include `Authorization: Bearer` header via test helper `authenticate(account)`.

### Model Specs
- Account: validations, balance >= 0, api_key generation, optimistic locking
- Order: validations, status transitions, scopes, belongs_to account/product
- Product: validations, active scope, test_behavior
- Voucher: associations, code uniqueness
- TransactionRecord: validations, types, balance_before/after

### Request Specs (with auth)
- POST /api/v1/accounts — create (no auth), duplicate email
- GET /api/v1/accounts/me — returns balance, rejects without auth
- POST /api/v1/accounts/top_up — credits balance, rejects invalid amount, rejects without auth
- POST /api/v1/orders — happy path (202), idempotent return (200), insufficient balance, out of stock, invalid product, rejects without auth
- GET /api/v1/orders/:id — found with vouchers, not found, rejects other account's orders
- POST /api/v1/orders/:id/cancel — pending (success + refund + stock restored + balance restored), processing (422), already cancelled (422)
- GET /api/v1/products — lists active products with stock counts
- POST /api/v1/products/:id/replenish — adds stock, rejects invalid quantity

### Service Specs
- Accounts::TopUpService — credits balance, creates transaction, handles locking
- Orders::PlacementService — debits balance, creates order, handles idempotent duplicates, rejects insufficient balance
- Orders::FulfillmentService — completes order, generates vouchers, handles test_behavior products, refunds balance + restores stock on permanent failure, transitions to refunded
- Orders::CancellationService — cancels pending, refunds balance + restores stock, rejects non-pending
- Orders::RefundService — credits balance, creates refund transaction

### Job Specs
- OrderFulfillmentJob — calls service, retries on failure, skips cancelled/completed orders

### Concurrency Specs
- Two orders for same account exhausting balance → only one succeeds, balance correct
- Two orders for same product exhausting stock → only one succeeds, stock correct
- Two requests with same reference_code → only one order, one debit, one stock decrement
- Cancel racing with job pickup → one wins, balance + stock correct
- Concurrent top-ups → final balance = sum of all top-ups
- Concurrent replenishments → final stock = sum of all replenishments

## Docker Setup

```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: password
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"

  web:
    build: .
    command: bin/rails server -b 0.0.0.0
    ports:
      - "3000:3000"
    depends_on:
      - db
      - redis
    environment:
      DATABASE_URL: postgres://postgres:password@db/gift_cards_development
      REDIS_URL: redis://redis:6379/0
      API_KEY_SECRET: dev_secret_key_change_in_production

  sidekiq:
    build: .
    command: bundle exec sidekiq
    depends_on:
      - db
      - redis
    environment:
      DATABASE_URL: postgres://postgres:password@db/gift_cards_development
      REDIS_URL: redis://redis:6379/0
      API_KEY_SECRET: dev_secret_key_change_in_production

volumes:
  postgres_data:
```

## Implementation Order (Detailed Step-by-Step)

### Phase 1: Foundation (no features, just infrastructure)
> Get a working Rails app with Docker, database, and test framework before writing any business logic.

**Step 1: Rails skeleton + Gemfile**
- `rails new gift_cards --api -d postgresql -T` (skip minitest)
- Add gems: sidekiq, rspec-rails, factory_bot_rails, shoulda-matchers, database_cleaner-active_record
- `bundle install`
- Verify: `rails --version` works

**Step 2: Docker setup**
- Write `Dockerfile` (Ruby 3.3, bundler, app setup)
- Write `docker-compose.yml` (db, redis, web, sidekiq)
- Write `.dockerignore`
- Configure `config/database.yml` to use `DATABASE_URL`
- Configure `config/initializers/sidekiq.rb` to use `REDIS_URL`
- Write `config/sidekiq.yml` (queues: default, critical)
- Verify: `docker-compose up` starts all services, `docker-compose exec web rails db:create` works

**Step 3: RSpec setup**
- `rails generate rspec:install`
- Configure `spec/rails_helper.rb` with factory_bot, shoulda-matchers, database_cleaner
- Write a trivial passing spec to confirm test framework works
- Verify: `bundle exec rspec` passes

**Step 4: Response envelope + global error handling**
- `ApplicationController`: `render_success(data, status)` and `render_error(code, message, status)` helpers
- Global `rescue_from` for `ActiveRecord::RecordNotFound`, `ActiveRecord::RecordInvalid`, `ActionController::ParameterMissing`
- Every response returns `{ "status": "SUCCESS"/"ERROR", "data"/"error": ... }`
- Write request spec for error handling (hit unknown route → proper error format)
- Verify: specs pass, error format is consistent

### Phase 2: Data layer (migrations + models)
> All tables created, all validations in place, before any controllers or services.

**Step 5: Accounts migration + model**
- Migration: id, name, email (unique), api_key (unique), balance (decimal, default 0), lock_version, timestamps
- Model: validations (name present, email present+unique+format, balance >= 0)
- API key generation: `before_validation :generate_api_key, on: :create`
- `API_KEY_SECRET` env var, `OpenSSL::HMAC.hexdigest("SHA256", secret, email)`
- Model spec: validations, api_key generation, uniqueness
- Verify: specs pass

**Step 6: Products migration + model**
- Migration: id, name, denomination (decimal), currency (default "INR"), active (default true), stock (default 0), test_behavior (nullable), timestamps
- Model: validations (name present, denomination > 0, stock >= 0), scope `active`
- Model spec: validations, scopes
- Verify: specs pass

**Step 7: Orders migration + model**
- Migration: id, reference_code (unique), account_id (FK), product_id (FK), quantity, denomination, total_amount, status (default "pending"), failure_reason, attempts (default 0), processed_at, cancelled_at, timestamps
- Model: validations, status enum/constants, belongs_to account + product, has_many vouchers
- Status constants: PENDING, PROCESSING, COMPLETED, FAILED, REFUNDED, CANCELLED
- Model spec: validations, associations, status values
- Verify: specs pass

**Step 8: Vouchers migration + model**
- Migration: id, order_id (FK), code (unique), pin, claim_url, expires_at, timestamps
- Model: validations, belongs_to order
- Model spec: validations, associations
- Verify: specs pass

**Step 9: TransactionRecords migration + model**
- Migration: id, account_id (FK), order_id (FK, nullable), transaction_type, amount, balance_before, balance_after, created_at
- Model: validations, belongs_to account, belongs_to order (optional)
- Types: CREDIT, DEBIT, REFUND
- Model spec: validations
- Verify: specs pass

### Phase 3: Authentication middleware
> Auth must work before any authenticated endpoint is built.

**Step 10: Auth middleware**
- `ApplicationController#authenticate!` — extract Bearer token, find account, set `current_account`
- `before_action :authenticate!` with `skip_before_action` for unauthenticated endpoints
- Auth helper for tests: `def auth_headers(account)` returns `{ "Authorization" => "Bearer #{account.api_key}" }`
- Request spec: unauthenticated request → 401 with proper error envelope
- Request spec: authenticated request with valid key → proceeds
- Verify: specs pass

### Phase 4: Account endpoints (first working feature)
> Accounts must exist before orders can be placed.

**Step 11: POST /api/v1/accounts — create**
- Routes: `namespace :api { namespace :v1 { resources :accounts, only: [:create] } }`
- Controller: skip auth, create account, return with api_key
- Request spec: happy path (201 + api_key in response), duplicate email (422), missing fields (422)
- Verify: specs pass, can curl locally

**Step 12: GET /api/v1/accounts/me**
- Route: `get "accounts/me"`
- Controller: authenticated, return `current_account` (no api_key in response)
- Request spec: returns balance, rejects without auth
- Verify: specs pass

**Step 13: POST /api/v1/accounts/top_up + TopUpService**
- Service: `Accounts::TopUpService.call(account, amount)`
  - Validates amount > 0
  - `account.lock!` (SELECT FOR UPDATE)
  - Increments balance, creates CREDIT transaction record
  - Returns updated account + transaction
- Controller: authenticated, calls service
- Request spec: credits balance, rejects 0/negative amount, rejects without auth
- Service spec: balance + transaction record created correctly
- Verify: specs pass

### Phase 5: Products
> Products must exist before orders reference them.

**Step 14: GET /api/v1/products + seed data**
- Route: `resources :products, only: [:index]`
- Controller: authenticated, returns active products with stock
- Seed data: 4-5 real-looking products + 4 test behavior products
- Request spec: lists active products, excludes inactive
- Verify: specs pass, `rails db:seed` works

**Step 15: POST /api/v1/products/:id/replenish**
- Route: `post "products/:id/replenish"`
- Controller: authenticated, locks product row, increments stock
- Request spec: adds stock, rejects 0/negative quantity, product not found
- Verify: specs pass

### Phase 6: Order placement (most complex, most consequential)
> This is the core feature. Balance debit + stock decrement + idempotency all happen here.

**Step 16: Orders::PlacementService**
- Service: `Orders::PlacementService.call(account, params)`
  - Check if `reference_code` already exists → return existing order (idempotent)
  - Within transaction:
    - Lock account row → check balance >= total_amount
    - Lock product row → check stock >= quantity
    - Debit balance, decrement stock
    - Create order (pending) + DEBIT transaction record
  - Rescue `ActiveRecord::RecordNotUnique` → find and return existing (race condition safety)
  - Enqueue `OrderFulfillmentJob`
- Service spec:
  - Creates order + debits balance + decrements stock
  - Idempotent on same reference_code (no double debit/stock)
  - Rejects insufficient balance
  - Rejects out of stock
  - Enqueues job
- Verify: specs pass

**Step 17: POST /api/v1/orders controller**
- Route: `resources :orders, only: [:create, :show]`
- Controller: authenticated, calls PlacementService, returns 202 (new) or 200 (existing)
- Request spec: full integration — happy path, idempotent, insufficient balance, out of stock, bad input
- Verify: specs pass

### Phase 7: Background job + fulfillment
> Order processing happens async. This is where retry logic lives.

**Step 18: Orders::FulfillmentService**
- Service: `Orders::FulfillmentService.call(order)`
  - Skip if order not pending (idempotent for retries)
  - Lock order, transition to "processing"
  - Check `product.test_behavior` for test products
  - Simulate downstream (sleep + random failure for normal products)
  - On success: generate voucher(s) with random code/pin/claim_url, transition to "completed"
  - On failure: raise error (Sidekiq retries)
- Service spec: completes order, generates vouchers, handles each test_behavior, raises on failure
- Verify: specs pass

**Step 19: OrderFulfillmentJob**
- Job: calls FulfillmentService, configures Sidekiq retries (5 max)
- `sidekiq_retries_exhausted` callback: transition to "failed" → call RefundService → transition to "refunded"
- Job spec: calls service, handles retries, triggers refund on exhaustion
- Verify: specs pass

**Step 20: Orders::RefundService**
- Service: `Orders::RefundService.call(order)`
  - Lock account row → credit balance
  - Lock product row → restore stock
  - Create REFUND transaction record
  - Transition order to "refunded"
- Service spec: balance restored, stock restored, transaction created, status = refunded
- Verify: specs pass

### Phase 8: Order details + cancellation
> Read endpoints and cancel flow, which also uses RefundService.

**Step 21: GET /api/v1/orders/:id**
- Controller: authenticated, returns order + vouchers (if completed), scoped to current_account
- Request spec: found, not found, other account's order → 404, includes vouchers when completed
- Verify: specs pass

**Step 22: Orders::CancellationService + POST /api/v1/orders/:id/cancel**
- Service: `Orders::CancellationService.call(order)`
  - Lock order row → verify status = pending
  - Refund balance + restore stock (reuses RefundService or inline)
  - Transition to "cancelled", set cancelled_at
  - Non-pending → raise error
- Route: `post "orders/:id/cancel"`
- Controller: authenticated, calls service
- Request spec: cancel pending (success + balance/stock restored), cancel processing (422), cancel completed (422)
- Service spec: status change, refund, stock restore, rejects non-pending
- Verify: specs pass

### Phase 9: Concurrency tests
> Prove the system is safe under concurrent load.

**Step 23: Concurrency specs**
- Two threads: same reference_code → only one order created, one debit, one stock decrement
- Two threads: same account, balance only enough for one → one succeeds, one gets INSUFFICIENT_BALANCE
- Two threads: same product, stock only enough for one → one succeeds, one gets OUT_OF_STOCK
- Two threads: cancel vs job pickup → one wins, balance/stock correct
- Two threads: concurrent top-ups → final balance = sum
- Two threads: concurrent replenishments → final stock = sum
- Verify: all specs pass

### Phase 10: Logging + polish

**Step 24: Structured logging**
- Tagged logging with `request_id` in controllers
- Log order state transitions in services
- Log job start/complete/failure with timing in jobs
- JSON formatter for production

**Step 25: Sidekiq Web UI**
- Mount Sidekiq::Web at `/sidekiq` (with basic auth in production)
- Verify: accessible at localhost:3000/sidekiq

### Phase 11: Documentation + deliverables

**Step 26: README**
- Project overview, architecture diagram
- Setup instructions (docker-compose up)
- API documentation with examples
- Design decisions and assumptions
- Test product behaviors

**Step 27: Postman collection**
- All endpoints with example requests/responses
- Environment variables for base_url and api_key
- Pre-request scripts for auth header
- Test flow: create account → top up → place order → check status → cancel

## Verification

1. `docker-compose up` → all services start
2. `docker-compose exec web bundle exec rspec` → full suite passes
3. Manual flow:
   - Create account → get api_key, balance 0
   - Top up 500 → balance 500
   - Replenish product stock to 10
   - Place order (qty 2, 100 each = 200 total) → 202, balance 300, stock 8
   - Same reference_code → 200, same order, balance still 300, stock still 8
   - GET order → status updates to completed, vouchers appear
   - Place order for "Test - Always Fails" product → fails → refunded, balance + stock restored
   - Place order → cancel → balance + stock restored
   - Place order when stock = 0 → OUT_OF_STOCK error
   - Two rapid orders exhausting balance → one succeeds, one gets INSUFFICIENT_BALANCE
4. Sidekiq Web UI at `/sidekiq`
