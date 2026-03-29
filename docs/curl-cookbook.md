# Curl Cookbook

A step-by-step walkthrough to manually test every flow. Run these after `docker compose up --build` — the database is auto-seeded with an admin account, a demo user, and test products.

## Step 0 — Grab Your API Keys

The seed output prints API keys in the `web` container logs. Copy them:

```bash
docker compose logs web | grep "API key"
```

Set them as environment variables for convenience:

```bash
export ADMIN_KEY="<admin api_key from logs>"
export USER_KEY="<demo api_key from logs>"
```

> **Seeded accounts:**
> - `admin@voucher-vendor.test` — admin with 10,000 balance
> - `demo@voucher-vendor.test` — regular user with 5,000 balance

---

## Step 1 — Create a Fresh Account

```bash
curl -s -X POST http://localhost:3000/api/v1/accounts \
  -H "Content-Type: application/json" \
  -d '{"account": {"name": "Reviewer", "email": "reviewer@example.com"}}' | jq .
```

Save the `api_key` from the response if you want to use this account instead of the seeded ones.

---

## Step 2 — View Your Account Balance

```bash
curl -s http://localhost:3000/api/v1/accounts/me \
  -H "Authorization: Bearer $USER_KEY" | jq .
```

---

## Step 3 — Top Up Balance (Admin Only)

Top up the demo user's account by email:

```bash
curl -s -X POST http://localhost:3000/api/v1/accounts/top_up \
  -H "Authorization: Bearer $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"amount": 5000, "email": "demo@voucher-vendor.test"}' | jq .
```

Or top up the admin's own account (omit `email`):

```bash
curl -s -X POST http://localhost:3000/api/v1/accounts/top_up \
  -H "Authorization: Bearer $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"amount": 5000}' | jq .
```

Verify the credit transaction in the response, then check balance:

```bash
curl -s http://localhost:3000/api/v1/accounts/me \
  -H "Authorization: Bearer $USER_KEY" | jq .data.balance
```

---

## Step 4 — Browse Products

```bash
curl -s http://localhost:3000/api/v1/products \
  -H "Authorization: Bearer $USER_KEY" | jq .
```

Note the product IDs — you'll need them for orders. The test products are:

| Name | Behavior | Use For |
|------|----------|---------|
| Test - Always Succeeds | Completes instantly | Success flow |
| Test - Always Fails | Fails every attempt | Failure + refund flow |
| Test - Succeeds After Retries | Fails 3 times, succeeds on attempt 4 | Retry → success flow |
| Test - Fails After Retry | Fails after retries | Auto-refund flow |

---

## Step 5 — Replenish Stock (Admin Only)

```bash
# Replace PRODUCT_ID with an actual ID from Step 4
curl -s -X POST http://localhost:3000/api/v1/products/PRODUCT_ID/replenish \
  -H "Authorization: Bearer $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"quantity": 100}' | jq .
```

---

## Step 6 — Success Flow (Place Order → Completed with Vouchers)

```bash
# Place an order with the "Test - Always Succeeds" product
# Replace PRODUCT_ID with the actual ID from Step 4
curl -s -X POST http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": PRODUCT_ID,
    "quantity": 2,
    "denomination": 100,
    "reference_code": "success-001"
  }' | jq .
# → 202 Accepted, status: "pending"
```

Wait 2-3 seconds for Sidekiq to process, then poll:

```bash
# Replace ORDER_ID with the id from the response above
curl -s http://localhost:3000/api/v1/orders/ORDER_ID \
  -H "Authorization: Bearer $USER_KEY" | jq .
# → status: "completed", vouchers array with code, pin, claim_url, expires_at
```

---

## Step 7 — Idempotency (Replay Same Reference Code)

```bash
# Send the exact same request again
curl -s -X POST http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": PRODUCT_ID,
    "quantity": 2,
    "denomination": 100,
    "reference_code": "success-001"
  }' | jq .
# → 200 OK (not 202) — returns the SAME order, no double debit
```

---

## Step 8 — Retry → Success Flow (Succeeds After Retries)

```bash
# Place an order with the "Test - Succeeds After Retries" product
curl -s -X POST http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": RETRY_PRODUCT_ID,
    "quantity": 1,
    "denomination": 100,
    "reference_code": "retry-001"
  }' | jq .
# → 202 Accepted, status: "pending"
```

Watch Sidekiq logs in another terminal to see the retry cycle:

```bash
docker compose logs -f sidekiq
# Expect: 3 failed attempts (~5s apart), then success on attempt 4
```

After ~15 seconds, poll for completion:

```bash
curl -s http://localhost:3000/api/v1/orders/ORDER_ID \
  -H "Authorization: Bearer $USER_KEY" | jq '.data | {status, attempts}'
# → status: "completed", attempts: 4
```

---

## Step 9 — Cancellation Flow

```bash
# Place an order with a real product (cancel quickly before Sidekiq processes it)
curl -s -X POST http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": PRODUCT_ID,
    "quantity": 1,
    "denomination": 100,
    "reference_code": "cancel-me-001"
  }' | jq .
# → 202 Accepted, status: "pending"
```

Cancel immediately:

```bash
curl -s -X POST http://localhost:3000/api/v1/orders/ORDER_ID/cancel \
  -H "Authorization: Bearer $USER_KEY" | jq .
# → status: "cancelled", balance and stock refunded
```

Confirm your balance was restored:

```bash
curl -s http://localhost:3000/api/v1/accounts/me \
  -H "Authorization: Bearer $USER_KEY" | jq .data.balance
```

---

## Step 10 — Auto-Refund Flow (Retry Exhaustion)

```bash
# Place an order with the "Test - Fails After Retry" product
curl -s -X POST http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": REFUND_PRODUCT_ID,
    "quantity": 1,
    "denomination": 100,
    "reference_code": "refund-001"
  }' | jq .
# → 202 Accepted, status: "pending"
```

Sidekiq will retry 3 times (5s apart), then trigger auto-refund. Monitor progress:

```bash
# Watch Sidekiq retries in the dashboard
open http://localhost:3000/sidekiq

# Poll until status changes to "refunded"
curl -s http://localhost:3000/api/v1/orders/ORDER_ID \
  -H "Authorization: Bearer $USER_KEY" | jq '.data | {status, failure_reason}'
# → status: "refunded", failure_reason: "Simulated failure..."
```

Verify balance restored:

```bash
curl -s http://localhost:3000/api/v1/accounts/me \
  -H "Authorization: Bearer $USER_KEY" | jq .data.balance
```

---

## Step 11 — Verify Audit Trail

All balance changes are recorded in `transaction_records`. Inspect via Rails console:

```bash
docker compose exec web bin/rails console
```

```ruby
TransactionRecord.last(10).each do |t|
  puts "#{t.transaction_type.ljust(8)} #{t.amount.to_s.rjust(8)}  balance: #{t.balance_before} → #{t.balance_after}"
end
```

Or check the Sidekiq dashboard for job history:

```
http://localhost:3000/sidekiq
```
