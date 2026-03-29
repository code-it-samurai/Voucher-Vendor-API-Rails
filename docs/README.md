# Overview

**Voucher Vendor API** is a Gift Card Order Service built as an [Ajakus](https://ajakus.com) technical assessment. It demonstrates production-grade patterns in a Rails API backend.

## Quick Start

```bash
git clone https://github.com/code-it-samurai/Voucher-Vendor-API-Rails.git
cd Voucher-Vendor-API-Rails
docker compose up --build
```

That's it. The entrypoint script automatically creates the database, runs migrations, and seeds test data. The API is live at **http://localhost:3000** and the Sidekiq dashboard at **http://localhost:3000/sidekiq**.

Seeded accounts (API keys printed in container logs):

| Account | Email | Role | Balance |
|---|---|---|---|
| Admin | `admin@voucher-vendor.test` | Admin | 10,000 |
| Demo User | `demo@voucher-vendor.test` | Regular | 5,000 |

```bash
# Grab API keys from logs
docker compose logs web | grep "API key"
```

## Running Test Specs

```bash
docker compose exec -e RAILS_ENV=test web bin/rails db:create db:migrate
docker compose exec -e RAILS_ENV=test web bundle exec rspec
```

All specs run inside the same Docker environment — no local Ruby install needed. See [Testing](testing.md) for the full breakdown of what's covered.

---

## Assessment Requirements

| Requirement | Implementation |
|---|---|
| **Idempotency** | Client-provided `reference_code` + DB unique constraint |
| **Background Processing** | Sidekiq jobs with configurable retry strategy |
| **Concurrency Safety** | `SELECT ... FOR UPDATE` row-level locks |
| **Failure Handling** | Exponential backoff retries + automatic refund on exhaustion |
| **Production Quality** | Consistent response envelope, admin auth, rate limiting, audit trail |

## Tech Stack

| Component | Version | Purpose |
|---|---|---|
| Ruby | 3.3 | Runtime |
| Rails | 8.1 | API framework (API-only mode) |
| PostgreSQL | 16 | Primary database with row-level locking |
| Redis | 7 | Job queue broker + rate limit cache store |
| Sidekiq | 7 | Background job processor |
| RSpec | 7 | Test framework |
| Docker Compose | - | Container orchestration |

## Project Structure

```
app/
  controllers/
    application_controller.rb            # Auth, rate limiting, error handling
    api/v1/
      accounts_controller.rb             # Create, view balance, top-up (admin)
      orders_controller.rb               # Place, view status, cancel
      products_controller.rb             # List, replenish stock (admin)
  models/
    account.rb                           # Balance, API key gen, admin flag
    order.rb                             # State machine, reference_code
    product.rb                           # Stock, denomination, test_behavior
    voucher.rb                           # Generated gift card codes
    transaction_record.rb                # Audit trail
  services/
    accounts/
      top_up_service.rb                  # Credit balance with row lock
    orders/
      placement_service.rb               # Idempotent creation + debit
      fulfillment_service.rb             # Async processing + vouchers
      cancellation_service.rb            # Cancel pending + refund
      refund_service.rb                  # Credit balance + restore stock
  jobs/
    order_fulfillment_job.rb             # Sidekiq job with retry
```

## What's Next?

- **[API Reference](api-reference.md)** — Every endpoint with request/response examples
- **[Architecture](architecture.md)** — System design diagrams
- **[Curl Cookbook](curl-cookbook.md)** — Test every endpoint from your terminal
- **[Testing](testing.md)** — Test specs covering models, services, jobs, and concurrency
