# Testing

## Running the Suite

```bash
# Setup test database (first time only)
docker compose exec -e RAILS_ENV=test web bin/rails db:create db:migrate

# Run all 98 specs
docker compose exec -e RAILS_ENV=test web bundle exec rspec

# Run a specific file
docker compose exec -e RAILS_ENV=test web bundle exec rspec spec/services/orders/placement_service_spec.rb

# Run with documentation format
docker compose exec -e RAILS_ENV=test web bundle exec rspec --format documentation
```

> **Note:** Always pass `-e RAILS_ENV=test` to avoid Rails 8's development host authorization returning 403 on test requests.

## Test Breakdown

| Category | Files | Examples | What's Tested |
|----------|:-----:|:--------:|---------------|
| **Models** | 5 | ~25 | Validations, associations, scopes, API key generation |
| **Requests** | 5 | ~35 | All endpoints: auth, success, error cases, response format |
| **Services** | 5 | ~20 | Business logic: placement, fulfillment, cancellation, refund, top-up |
| **Jobs** | 1 | ~5 | Sidekiq job execution, retry behavior |
| **Concurrency** | 1 | ~6 | Thread-safety with real concurrent threads |
| **Smoke** | 1 | 1 | Basic framework health check |
| **Total** | **18** | **98** | |

## Test Categories

### Model Specs

Validate database constraints and model behavior:

- **Account:** email uniqueness, API key auto-generation, balance non-negative
- **Product:** denomination > 0, stock >= 0, `active` scope
- **Order:** reference_code uniqueness, status constants, associations
- **Voucher:** code uniqueness, belongs_to order
- **TransactionRecord:** type validation (credit/debit/refund), amount > 0

### Request Specs

Integration tests hitting the full Rails stack:

- **Accounts:** Create (201), duplicate email (422), me (200), unauthorized (401), top_up with admin (200), top_up without admin (403)
- **Orders:** Place new (202), idempotent duplicate (200), insufficient balance (422), out of stock (422), show with vouchers (200), cancel pending (200), cancel non-pending (422)
- **Products:** List active (200), replenish with admin (200), replenish without admin (403)
- **Response Envelope:** Consistent `status`/`data`/`error` structure across all responses

### Service Specs

Unit tests for business logic in isolation:

- **PlacementService:** Creates order + debits balance + decrements stock, handles idempotent duplicates, rejects insufficient balance / out of stock
- **FulfillmentService:** Generates vouchers on success, handles each `test_behavior` variant, transitions status correctly
- **CancellationService:** Cancels pending orders, rejects non-pending, triggers refund
- **RefundService:** Credits balance, restores stock, creates audit record
- **TopUpService:** Credits balance with lock, rejects invalid amounts

### Concurrency Specs

Thread-safety tests using real Ruby threads with `use_transactional_tests = false`:

```ruby
threads = 2.times.map do
  Thread.new { place_order(account, product, unique_ref) }
end
threads.each(&:join)
```

| Scenario | Assertion |
|----------|-----------|
| Duplicate reference_code | Only 1 order created, 1 debit |
| Balance exhaustion | Only 1 order succeeds, correct final balance |
| Stock exhaustion | Only 1 order succeeds, correct final stock |
| Cancel vs job race | One wins, balance/stock correct |
| Concurrent top-ups | Final balance = sum of all top-ups |
| Concurrent replenishments | Final stock = sum of all replenishments |

## Test Products

Seeded products with `test_behavior` enable deterministic testing of all order states:

| Product | Behavior | Use Case |
|---------|----------|----------|
| **Test - Always Succeeds** | Completes immediately | Happy path testing |
| **Test - Always Fails** | Fails → retries → auto-refund | Failure + refund flow |
| **Test - Stays Pending** | Stays in `processing` | Polling / status check testing |
| **Test - Fails After Retry** | Fails after processing attempt | Retry exhaustion flow |

Use these when testing via curl to get predictable outcomes. See [Curl Cookbook](curl-cookbook.md) for examples.

## Test Configuration

### Rate Limiting Safety

The test environment uses `config.cache_store = :null_store`, which means the Rails 8 `rate_limit` feature is automatically disabled during tests. No special configuration needed.

### Database Cleaning

Concurrency specs disable transactional tests and use `database_cleaner` with truncation strategy to ensure clean state between parallel thread operations.

### Factory Bot

All test data is created via factories:

```ruby
create(:account)                    # Regular account
create(:account, :admin)            # Admin account
create(:account, :with_balance)     # Account with 1000.0 balance
create(:product, test_behavior: "success")  # Test product
```
