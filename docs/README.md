# Overview

**Voucher Vendor API** is a Gift Card Order Service built as an [Ajakus](https://ajakus.com) technical assessment. It demonstrates production-grade patterns in a Rails API backend:

| Requirement | Implementation |
|-------------|---------------|
| **Idempotency** | Client-provided `reference_code` + DB unique constraint |
| **Background Processing** | Sidekiq jobs with configurable retry strategy |
| **Concurrency Safety** | `SELECT ... FOR UPDATE` row-level locks |
| **Failure Handling** | Exponential backoff retries + automatic refund on exhaustion |
| **Production Quality** | Consistent response envelope, admin auth, rate limiting, audit trail |

## Tech Stack

| Component | Version | Purpose |
|-----------|---------|---------|
| Ruby | 3.3 | Runtime |
| Rails | 8.1 | API framework (API-only mode) |
| PostgreSQL | 16 | Primary database with row-level locking |
| Redis | 7 | Job queue broker + rate limit cache store |
| Sidekiq | 7 | Background job processor |
| RSpec | 7 | Test framework |
| Docker Compose | - | Container orchestration |

## Quick Start

```bash
# 1. Clone and start all services
git clone https://github.com/prathameshpatil7/Voucher-Vendor-API-Rails.git
cd Voucher-Vendor-API-Rails
docker compose up --build

# 2. Setup database (in another terminal)
docker compose exec web bin/rails db:create db:migrate db:seed

# 3. Run the test suite
docker compose exec -e RAILS_ENV=test web bin/rails db:create db:migrate
docker compose exec -e RAILS_ENV=test web bundle exec rspec
```

The API is live at **http://localhost:3000**
Sidekiq dashboard at **http://localhost:3000/sidekiq**

## Project Structure

```
app/
  controllers/
    application_controller.rb            # Auth, rate limiting, error handling, response envelope
    api/v1/
      accounts_controller.rb             # Create account, view balance, top-up (admin)
      orders_controller.rb               # Place order, view status, cancel
      products_controller.rb             # List products, replenish stock (admin)
  models/
    account.rb                           # Balance, API key generation, admin flag
    order.rb                             # Status state machine, reference_code uniqueness
    product.rb                           # Stock, denomination, test_behavior
    voucher.rb                           # Generated gift card codes
    transaction_record.rb                # Audit trail for all balance changes
  services/
    accounts/
      top_up_service.rb                  # Credit balance with row lock + audit
    orders/
      placement_service.rb               # Idempotent order creation + balance debit + stock decrement
      fulfillment_service.rb             # Async processing + voucher generation
      cancellation_service.rb            # Cancel pending + refund
      refund_service.rb                  # Credit balance + restore stock
  jobs/
    order_fulfillment_job.rb             # Sidekiq job with retry + exhaustion callback
```

## What's Next?

Explore the docs using the sidebar:

- **[API Reference](api-reference.md)** - Every endpoint with request/response examples
- **[Architecture](architecture.md)** - System design diagrams
- **[Curl Cookbook](curl-cookbook.md)** - Test every endpoint from your terminal
- **[Testing](testing.md)** - 98 specs covering models, services, jobs, and concurrency
