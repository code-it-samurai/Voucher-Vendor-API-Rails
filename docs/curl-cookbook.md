# Curl Cookbook

A step-by-step walkthrough testing every endpoint and error case. Run these after `docker compose up --build` and `docker compose exec web bin/rails db:create db:migrate db:seed`.

> **Tip:** The seed output prints API keys for both admin and regular test accounts. Use those directly.

## Setup: Get API Keys

```bash
# Create a regular account
curl -s -X POST http://localhost:3000/api/v1/accounts \
  -H "Content-Type: application/json" \
  -d '{"account": {"name": "Reviewer", "email": "reviewer@example.com"}}' | jq .

# Save the api_key from the response
export USER_KEY="<api_key from response>"

# The admin key was printed during db:seed
# Or create an admin via rails console:
# docker compose exec web bin/rails console
# Account.find_by(email: "admin@voucher-vendor.com").api_key
export ADMIN_KEY="<admin api_key>"
```

---

## 1. Account Operations

### View Account

```bash
curl -s http://localhost:3000/api/v1/accounts/me \
  -H "Authorization: Bearer $USER_KEY" | jq .
```

### Top Up Balance (Admin Only)

```bash
# As admin — top up the reviewer account
curl -s -X POST http://localhost:3000/api/v1/accounts/top_up \
  -H "Authorization: Bearer $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"amount": 5000}' | jq .
```

### Error: Top Up as Non-Admin (403)

```bash
curl -s -X POST http://localhost:3000/api/v1/accounts/top_up \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"amount": 1000}' | jq .
# → {"status":"ERROR","error":{"code":"FORBIDDEN","message":"Admin access required"}}
```

### Error: Unauthorized (401)

```bash
curl -s http://localhost:3000/api/v1/accounts/me \
  -H "Authorization: Bearer invalid_key" | jq .
# → {"status":"ERROR","error":{"code":"UNAUTHORIZED","message":"Invalid or missing API key"}}
```

---

## 2. Products

### List All Products

```bash
curl -s http://localhost:3000/api/v1/products \
  -H "Authorization: Bearer $USER_KEY" | jq .
```

### Replenish Stock (Admin Only)

```bash
curl -s -X POST http://localhost:3000/api/v1/products/1/replenish \
  -H "Authorization: Bearer $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"quantity": 100}' | jq .
```

### Error: Replenish as Non-Admin (403)

```bash
curl -s -X POST http://localhost:3000/api/v1/products/1/replenish \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"quantity": 50}' | jq .
# → {"status":"ERROR","error":{"code":"FORBIDDEN",...}}
```

---

## 3. Order Placement

### Place a New Order (202)

```bash
curl -s -X POST http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": 6,
    "quantity": 2,
    "denomination": 100,
    "reference_code": "test-order-001"
  }' | jq .
# → 202 Accepted, status: "pending"
# Note: product_id 6 = "Test - Always Succeeds"
```

### Idempotent Retry — Same Reference Code (200)

```bash
curl -s -X POST http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": 6,
    "quantity": 2,
    "denomination": 100,
    "reference_code": "test-order-001"
  }' | jq .
# → 200 OK, same order returned — no double debit!
```

### Poll Order Status

```bash
# Replace :id with the order ID from the placement response
curl -s http://localhost:3000/api/v1/orders/1 \
  -H "Authorization: Bearer $USER_KEY" | jq .
# → status: "completed" with vouchers array
```

### Error: Insufficient Balance (422)

```bash
curl -s -X POST http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": 1,
    "quantity": 999,
    "denomination": 100,
    "reference_code": "will-fail-balance"
  }' | jq .
# → {"status":"ERROR","error":{"code":"INSUFFICIENT_BALANCE",...}}
```

### Error: Out of Stock (422)

```bash
# First ensure you have enough balance but product has low stock
curl -s -X POST http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": 1,
    "quantity": 9999,
    "denomination": 100,
    "reference_code": "will-fail-stock"
  }' | jq .
# → OUT_OF_STOCK or INSUFFICIENT_BALANCE depending on which check fails first
```

---

## 4. Order Cancellation

### Cancel a Pending Order

```bash
# Place an order with the "Stays Pending" test product (product_id varies — check /products)
curl -s -X POST http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": 8,
    "quantity": 1,
    "denomination": 100,
    "reference_code": "cancel-me-001"
  }' | jq .

# Cancel it (replace :id with the order ID)
curl -s -X POST http://localhost:3000/api/v1/orders/2/cancel \
  -H "Authorization: Bearer $USER_KEY" | jq .
# → status: "cancelled", balance and stock refunded
```

### Error: Cancel Non-Pending Order (422)

```bash
# Try cancelling the already-completed order from step 3
curl -s -X POST http://localhost:3000/api/v1/orders/1/cancel \
  -H "Authorization: Bearer $USER_KEY" | jq .
# → {"status":"ERROR","error":{"code":"ORDER_NOT_CANCELLABLE",...}}
```

---

## 5. Failure + Auto-Refund Flow

### Order That Always Fails

```bash
# Use "Test - Always Fails" product (check product_id via /products)
curl -s -X POST http://localhost:3000/api/v1/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "product_id": 7,
    "quantity": 1,
    "denomination": 100,
    "reference_code": "failure-test-001"
  }' | jq .
# → 202 Accepted, status: "pending"

# Wait for Sidekiq retries to exhaust (~30 seconds with test product)
# Then poll:
curl -s http://localhost:3000/api/v1/orders/3 \
  -H "Authorization: Bearer $USER_KEY" | jq .
# → status: "refunded", balance has been restored

# Verify balance was restored:
curl -s http://localhost:3000/api/v1/accounts/me \
  -H "Authorization: Bearer $USER_KEY" | jq .
```

---

## 6. Verify Audit Trail

Check the Sidekiq dashboard to see job history:

```
http://localhost:3000/sidekiq
```

The `transaction_records` table maintains a complete audit trail of all balance changes (credits, debits, refunds). You can inspect them via Rails console:

```bash
docker compose exec web bin/rails console
> TransactionRecord.last(10).map { |t| [t.transaction_type, t.amount, t.balance_before, t.balance_after] }
```
