# Quick Walkthrough

A complete end-to-end tour of the API from a fresh terminal. Copy-paste each block in order — every step builds on the previous one.

> **Prerequisites:** `docker compose up --build` is running and healthy. You'll need `curl` and `jq`.

---

## Setup — Keys & Base URL

API keys are generated at seed time and printed in the container logs. Grab them once and export them so every command below just works:

```bash
# Print the seeded API keys from the web container startup logs
docker compose logs web | grep "API key"

# Export the keys you see above — replace the placeholders
export ADMIN_KEY="<admin api_key from logs>"
export BASE="http://localhost:3000/api/v1"
```

> The admin account (`admin@voucher-vendor.test`) starts with 10,000 balance.
> A demo user (`demo@voucher-vendor.test`) starts with 5,000 balance and its key is also printed.
> In the steps below we'll create a **fresh reviewer account** so you see the full flow from zero.

---

## 1 — Create a Reviewer Account

```bash
# Creates a brand-new account with zero balance
curl -s -X POST $BASE/accounts \
  -H "Content-Type: application/json" \
  -d '{"account": {"name": "Reviewer", "email": "reviewer@example.com"}}' | jq .

# Save the api_key from the response — you'll use it for every user action
export USER_KEY="<paste api_key from response>"
```

---

## 2 — Check Your Balance (Should Be Zero)

```bash
curl -s $BASE/accounts/me \
  -H "Authorization: Bearer $USER_KEY" | jq '.data | {email, balance}'
# → balance: 0.0
```

---

## 3 — Admin Tops Up Your Account

```bash
# Only admin-keyed requests can top up — non-admins get a 403
curl -s -X POST $BASE/accounts/top_up \
  -H "Authorization: Bearer $ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"amount": 5000, "email": "reviewer@example.com"}' | jq .
```

```bash
# Confirm the credit landed
curl -s $BASE/accounts/me \
  -H "Authorization: Bearer $USER_KEY" | jq '.data.balance'
# → 5000.0
```

---

## 4 — Browse Products & Export Test Product IDs

The seed creates four special **test products** whose fulfillment behavior is deterministic — great for demoing each code path without any randomness.

```bash
# List every product — note the test ones at the bottom
curl -s $BASE/products \
  -H "Authorization: Bearer $USER_KEY" | jq '.data[] | {id, name, denomination, stock}'
```

| Product name | Behavior |
|---|---|
| **Test - Always Succeeds** | Fulfillment completes on the first attempt |
| **Test - Always Fails** | Every attempt fails → auto-refund after retries exhausted |
| **Test - Succeeds After Retries** | Fails 3 times, succeeds on attempt 4 (~15 s total) |
| **Test - Fails After Retry** | Same retry cycle as above, but never succeeds → auto-refund |

```bash
# Extract product IDs by name so every command below is ID-independent
export SUCCESS_ID=$(curl -s $BASE/products -H "Authorization: Bearer $USER_KEY" \
  | jq '.data[] | select(.name == "Test - Always Succeeds") | .id')

export RETRY_SUCCESS_ID=$(curl -s $BASE/products -H "Authorization: Bearer $USER_KEY" \
  | jq '.data[] | select(.name == "Test - Succeeds After Retries") | .id')

export RETRY_FAIL_ID=$(curl -s $BASE/products -H "Authorization: Bearer $USER_KEY" \
  | jq '.data[] | select(.name == "Test - Always Fails") | .id')

export REFUND_ID=$(curl -s $BASE/products -H "Authorization: Bearer $USER_KEY" \
  | jq '.data[] | select(.name == "Test - Fails After Retry") | .id')

echo "SUCCESS=$SUCCESS_ID  RETRY_SUCCESS=$RETRY_SUCCESS_ID  RETRY_FAIL=$RETRY_FAIL_ID  REFUND=$REFUND_ID"
```

---

## 5 — Success Flow

Places an order that completes on the first Sidekiq attempt.

```bash
curl -s -X POST $BASE/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"product_id\": $SUCCESS_ID,
    \"quantity\": 1,
    \"denomination\": 100,
    \"reference_code\": \"walkthrough-success-001\"
  }" | jq .
# → 202 Accepted, status: "pending"
# Save the order id
export ORDER_ID="<paste id from response>"
```

```bash
# Wait ~2 s for Sidekiq to process, then poll
# status will be "completed" and vouchers array will be populated
sleep 2 && curl -s $BASE/orders/$ORDER_ID \
  -H "Authorization: Bearer $USER_KEY" | jq '.data | {status, vouchers}'
```

> 💡 **Tip — watch jobs process in real time:**
> Open [Sidekiq dashboard → http://localhost:3000/sidekiq](http://localhost:3000/sidekiq) to see the job move through the queue.
> Or tail container logs via [Dozzle → http://localhost:8080](http://localhost:8080) for a live stream.

---

## 6 — Idempotency

Replaying the exact same `reference_code` returns the original order — no second charge, no duplicate vouchers.

```bash
# Identical body to Step 5 — reference_code is the idempotency key
curl -s -X POST $BASE/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"product_id\": $SUCCESS_ID,
    \"quantity\": 1,
    \"denomination\": 100,
    \"reference_code\": \"walkthrough-success-001\"
  }" | jq '{status: .status, id: .data.id}'
# → HTTP 200 (not 202) — same order id as before, balance unchanged
```

---

## 7 — Retry → Success Flow

This product fails fulfillment 3 times before succeeding on attempt 4. The retry delay is 5 s, so the whole cycle takes ~15–20 s.

```bash
# Open a second terminal and tail Sidekiq logs to watch retries happen live:
# docker compose logs -f sidekiq
# Or open the Sidekiq dashboard: http://localhost:3000/sidekiq → Retries tab

curl -s -X POST $BASE/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"product_id\": $RETRY_SUCCESS_ID,
    \"quantity\": 1,
    \"denomination\": 100,
    \"reference_code\": \"walkthrough-retry-001\"
  }" | jq .
export RETRY_ORDER_ID="<paste id from response>"
```

```bash
# Poll after ~20 s — you should see status: "completed" and attempts: 4
sleep 20 && curl -s $BASE/orders/$RETRY_ORDER_ID \
  -H "Authorization: Bearer $USER_KEY" | jq '.data | {status, attempts, vouchers}'
```

---

## 8 — Cancellation Flow

Cancel a pending order before Sidekiq processes it — balance and stock are immediately restored.

```bash
# Use the always-fails product here so Sidekiq doesn't race us to complete it,
# but any product works as long as you cancel before the job runs (~1–2 s window)
curl -s -X POST $BASE/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"product_id\": $RETRY_FAIL_ID,
    \"quantity\": 1,
    \"denomination\": 100,
    \"reference_code\": \"walkthrough-cancel-001\"
  }" | jq .
export CANCEL_ORDER_ID="<paste id from response>"
```

```bash
# Cancel it — balance and stock are refunded synchronously
curl -s -X POST $BASE/orders/$CANCEL_ORDER_ID/cancel \
  -H "Authorization: Bearer $USER_KEY" | jq '.data | {status}'
# → status: "cancelled"
```

```bash
# Confirm balance was restored
curl -s $BASE/accounts/me \
  -H "Authorization: Bearer $USER_KEY" | jq '.data.balance'
```

---

## 9 — Auto-Refund Flow (Retry Exhaustion)

This product always fails. After 3 retries the job gives up and triggers an automatic refund.

```bash
# Open Sidekiq dashboard to watch retries: http://localhost:3000/sidekiq
# Or stream logs live: docker compose logs -f sidekiq

curl -s -X POST $BASE/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"product_id\": $REFUND_ID,
    \"quantity\": 1,
    \"denomination\": 100,
    \"reference_code\": \"walkthrough-refund-001\"
  }" | jq .
export REFUND_ORDER_ID="<paste id from response>"
```

```bash
# Wait ~20 s for 3 retries to exhaust, then poll
sleep 20 && curl -s $BASE/orders/$REFUND_ORDER_ID \
  -H "Authorization: Bearer $USER_KEY" | jq '.data | {status, failure_reason}'
# → status: "refunded", failure_reason: explains why fulfillment failed
```

```bash
# Confirm balance was fully restored after the auto-refund
curl -s $BASE/accounts/me \
  -H "Authorization: Bearer $USER_KEY" | jq '.data.balance'
```

---

## 10 — Final Balance Check

After the cancel (Step 8) and the auto-refund (Step 9) your balance should be close to the 5,000 you started with, minus the completed order from Step 5.

```bash
curl -s $BASE/accounts/me \
  -H "Authorization: Bearer $USER_KEY" | jq '.data | {balance}'
# → 5000 - (1 × 100 from Step 5) = ~4900.0
```

---

## 11 — Error Cases

A quick tour of the guardrails — each one returns a structured error, never a stack trace.

```bash
# No Authorization header → 401 Unauthorized
curl -s $BASE/products | jq .

# Regular user tries to top up → 403 Forbidden
curl -s -X POST $BASE/accounts/top_up \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"amount": 100}' | jq .

# Malformed JSON body → 400 with a clear message, no crash
curl -s -X POST $BASE/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d '{bad json}' | jq .

# Order total exceeds balance → 422 with "Insufficient balance"
curl -s -X POST $BASE/orders \
  -H "Authorization: Bearer $USER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"product_id\": $SUCCESS_ID,
    \"quantity\": 100,
    \"denomination\": 500,
    \"reference_code\": \"walkthrough-broke-001\"
  }" | jq .
```

---

> **Where to go next:**
> - **[API Reference](api-reference.md)** — full endpoint docs with every field documented
> - **[Curl Cookbook](curl-cookbook.md)** — deeper dives into each flow with more variations
> - **[Observability](observability.md)** — Dozzle log viewer and Sidekiq dashboard
