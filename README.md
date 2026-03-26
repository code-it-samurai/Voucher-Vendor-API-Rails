# Gift Card Order Service

A Rails API backend demonstrating idempotency, background job processing, retry logic, concurrency safety, and production-quality patterns.

Built as an Ajakus technical assessment by Prathamesh.

## Architecture

```
Client/Postman
      |
      v port 3000
+----------+     +----------+     +----------+
|   web    |---->|    db    |<----|  sidekiq |
|  (Rails) |     |(Postgres)|     | (worker) |
+----+-----+     +----------+     +----+-----+
     |                                  |
     +---------->+----------+<----------+
                 |  redis   |
                 +----------+
```

- **web**: Rails 8.1 API server
- **db**: PostgreSQL 16 with row-level locking
- **redis**: Job queue broker for Sidekiq
- **sidekiq**: Background worker for order fulfillment

## Quick Start

```bash
# Clone and start everything
docker compose up --build

# In a separate terminal, set up the database
docker compose exec web bin/rails db:create db:migrate db:seed

# Run the test suite
docker compose exec web bundle exec rspec
```

The API is available at `http://localhost:3000`.
Sidekiq Web UI is at `http://localhost:3000/sidekiq`.

## API Endpoints

All authenticated endpoints require: `Authorization: Bearer <api_key>`

### Accounts

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | /api/v1/accounts | No | Create account (returns api_key) |
| GET | /api/v1/accounts/me | Yes | Get current account |
| POST | /api/v1/accounts/top_up | Yes | Add funds to balance |

### Orders

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | /api/v1/orders | Yes | Place order (idempotent) |
| GET | /api/v1/orders/:id | Yes | Get order details + vouchers |
| POST | /api/v1/orders/:id/cancel | Yes | Cancel pending order |

### Products

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | /api/v1/products | Yes | List active products |
| POST | /api/v1/products/:id/replenish | Yes | Add stock |

## API Usage Flow

```bash
# 1. Create an account
curl -X POST http://localhost:3000/api/v1/accounts \
  -H "Content-Type: application/json" \
  -d '{"account": {"name": "Prathamesh", "email": "prat@example.com"}}'
# Save the api_key from the response

# 2. Top up balance
curl -X POST http://localhost:3000/api/v1/accounts/top_up \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -d '{"amount": 1000}'

# 3. List products
curl http://localhost:3000/api/v1/products \
  -H "Authorization: Bearer <api_key>"

# 4. Place an order (idempotent via reference_code)
curl -X POST http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer <api_key>" \
  -H "Content-Type: application/json" \
  -d '{"product_id": 1, "quantity": 2, "denomination": 100, "reference_code": "my-unique-ref-001"}'
# Returns 202 Accepted (new) or 200 OK (duplicate reference_code)

# 5. Check order status (poll until completed)
curl http://localhost:3000/api/v1/orders/1 \
  -H "Authorization: Bearer <api_key>"
# Includes vouchers when status is "completed"

# 6. Cancel a pending order
curl -X POST http://localhost:3000/api/v1/orders/1/cancel \
  -H "Authorization: Bearer <api_key>"
```

## Response Format

Every response uses a consistent envelope:

```json
{
  "status": "SUCCESS",
  "data": { ... }
}
```

```json
{
  "status": "ERROR",
  "error": {
    "code": "INSUFFICIENT_BALANCE",
    "message": "Account balance is insufficient for this order"
  }
}
```

Error codes: `UNAUTHORIZED`, `INSUFFICIENT_BALANCE`, `OUT_OF_STOCK`, `INVALID_INPUT`, `ORDER_NOT_CANCELLABLE`, `PRODUCT_NOT_FOUND`, `INVALID_AMOUNT`, `NOT_FOUND`

## Key Design Decisions

### Idempotency
Client provides a `reference_code` on order creation. Same code returns the existing order (200 OK) with no side effects. Race conditions handled via DB unique constraint + `ActiveRecord::RecordNotUnique` rescue.

### Concurrency Safety
All balance and stock mutations use `SELECT ... FOR UPDATE` row locks inside database transactions. Two competing orders for the same account: second thread waits for the lock, then sees the updated balance.

### Background Processing
Orders are fulfilled asynchronously via Sidekiq. Max 5 retries with exponential backoff. On final retry exhaustion, the order is marked as failed and the balance + stock are refunded automatically.

### Order State Machine

```
pending --> processing --> completed
  |              |
  |              +--> failed --> refunded
  |
  +--> cancelled (balance + stock refunded)
```

### Authentication
API keys are generated using `HMAC-SHA256(server_secret, email)`. Deterministic and regenerable. Key shown only on account creation.

### Test Products
Products with `test_behavior` allow deterministic testing:

| Product | Behavior |
|---------|----------|
| Test - Always Succeeds | Completes immediately |
| Test - Always Fails | Fails, triggers refund |
| Test - Stays Pending | Stays in processing (for polling tests) |
| Test - Fails After Retry | Fails after retries, triggers refund |

## Test Suite

```bash
docker compose exec web bundle exec rspec
```

96 specs covering:
- **Model specs**: Validations, associations, scopes, API key generation
- **Request specs**: All endpoints with auth, error handling, edge cases
- **Service specs**: PlacementService, FulfillmentService, RefundService, CancellationService, TopUpService
- **Job specs**: OrderFulfillmentJob
- **Concurrency specs**: Thread-safety for balance, stock, reference_code, top-ups, replenishments

## Tech Stack

- Ruby 3.3 / Rails 8.1 (API-only)
- PostgreSQL 16
- Redis 7 + Sidekiq 7
- RSpec + FactoryBot + Shoulda Matchers
- Docker Compose
