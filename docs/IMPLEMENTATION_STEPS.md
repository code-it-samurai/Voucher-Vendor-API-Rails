# Implementation Steps Checklist

## Phase 1: Foundation
- [ ] Step 1: Rails skeleton + Gemfile (rails new --api -d postgresql -T, add gems, bundle install)
- [ ] Step 2: Docker setup (Dockerfile, docker-compose.yml, .dockerignore, database.yml, sidekiq config)
- [ ] Step 3: RSpec setup (rspec:install, configure helpers, trivial passing spec)
- [ ] Step 4: Response envelope + global error handling (render_success/render_error, rescue_from)

## Phase 2: Data Layer
- [ ] Step 5: Accounts migration + model (name, email, api_key, balance, lock_version + validations + specs)
- [ ] Step 6: Products migration + model (name, denomination, currency, active, stock, test_behavior + specs)
- [ ] Step 7: Orders migration + model (reference_code, account_id, product_id, quantity, status + specs)
- [ ] Step 8: Vouchers migration + model (order_id, code, pin, claim_url + specs)
- [ ] Step 9: TransactionRecords migration + model (account_id, order_id, type, amount, before/after + specs)

## Phase 3: Authentication
- [ ] Step 10: Auth middleware (authenticate!, Bearer token extraction, current_account, 401 handling + specs)

## Phase 4: Account Endpoints
- [ ] Step 11: POST /api/v1/accounts (create, return api_key, skip auth + specs)
- [ ] Step 12: GET /api/v1/accounts/me (authenticated, return balance, no api_key + specs)
- [ ] Step 13: POST /api/v1/accounts/top_up + TopUpService (lock, credit, transaction record + specs)

## Phase 5: Products
- [ ] Step 14: GET /api/v1/products + seed data (list active with stock, test products + specs)
- [ ] Step 15: POST /api/v1/products/:id/replenish (lock, increment stock + specs)

## Phase 6: Order Placement
- [ ] Step 16: Orders::PlacementService (idempotency, lock account+product, debit+decrement, enqueue job + specs)
- [ ] Step 17: POST /api/v1/orders controller (202 new / 200 existing + integration specs)

## Phase 7: Background Job + Fulfillment
- [ ] Step 18: Orders::FulfillmentService (status transition, test_behavior, voucher gen + specs)
- [ ] Step 19: OrderFulfillmentJob (Sidekiq retries, retries_exhausted callback + specs)
- [ ] Step 20: Orders::RefundService (credit balance, restore stock, refund transaction + specs)

## Phase 8: Order Details + Cancellation
- [ ] Step 21: GET /api/v1/orders/:id (with vouchers, scoped to account + specs)
- [ ] Step 22: Orders::CancellationService + POST cancel (lock, verify pending, refund + specs)

## Phase 9: Concurrency Tests
- [ ] Step 23: Concurrency specs (duplicate ref_code, balance exhaustion, stock exhaustion, cancel race, concurrent top-ups/replenishments)

## Phase 10: Logging + Polish
- [ ] Step 24: Structured logging (request_id tagging, state transitions, job timing)
- [ ] Step 25: Sidekiq Web UI (mount at /sidekiq)

## Phase 11: Documentation
- [ ] Step 26: README (setup, API docs, design decisions, architecture)
- [ ] Step 27: Postman collection (all endpoints, env vars, test flow)
