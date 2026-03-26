# Idempotency

## Why It Matters

In real-world systems, clients retry requests due to network timeouts, load balancer retries, or user double-clicks. Without idempotency, a retried order placement would:

- Debit the account balance **twice**
- Decrement product stock **twice**
- Create **duplicate** orders

The Voucher Vendor API guarantees that submitting the same order request multiple times produces exactly one order and one balance debit.

## How It Works

### The `reference_code` Pattern

Every order request includes a client-generated `reference_code` — a unique identifier for that order intent:

```json
{
  "reference_code": "checkout-session-abc-123",
  "product_id": 1,
  "quantity": 2,
  "denomination": 100.00
}
```

### Three Layers of Protection

**Layer 1: Early lookup**

Before attempting to create an order, the service checks if a `reference_code` already exists:

```ruby
existing = Order.find_by(reference_code: params[:reference_code])
return { order: existing, created: false } if existing
```

If found, the existing order is returned with `200 OK` — no balance change, no stock change.

**Layer 2: Database unique constraint**

The `orders` table has a unique index on `reference_code`:

```ruby
add_index :orders, :reference_code, unique: true
```

Even if the early lookup misses a concurrent insert (TOCTOU race), the database enforces uniqueness.

**Layer 3: Exception rescue**

If two requests pass the early lookup simultaneously and both attempt to INSERT:

```ruby
rescue ActiveRecord::RecordNotUnique
  existing = Order.find_by!(reference_code: params[:reference_code])
  { order: existing, created: false }
end
```

The second INSERT fails with a constraint violation, which is caught and handled gracefully.

### Response Codes

| Scenario | HTTP Status | Meaning |
|----------|:-----------:|---------|
| New `reference_code` | **202 Accepted** | Order created, processing asynchronously |
| Existing `reference_code` | **200 OK** | Returning existing order, no side effects |

> A duplicate `reference_code` is **not** an error. It's the idempotency guarantee working as designed.

## Race Condition Timeline

```
Thread A                          Thread B
────────                          ────────
SELECT * WHERE ref='ABC'          SELECT * WHERE ref='ABC'
→ Not found                       → Not found

BEGIN TRANSACTION                 BEGIN TRANSACTION
LOCK account row                  (waits for lock...)
LOCK product row
Debit balance
Decrement stock
INSERT order (ref='ABC')          ...still waiting...
COMMIT                            (acquires lock)
                                  Debit balance
                                  Decrement stock
                                  INSERT order (ref='ABC')
                                  → RecordNotUnique!
                                  ROLLBACK
                                  SELECT * WHERE ref='ABC'
                                  → Returns existing order
                                  Return 200 OK
```

The rollback on Thread B means no balance was debited and no stock was decremented by the duplicate attempt.

## Client Best Practices

1. **Generate reference codes client-side** — use UUIDs, session IDs, or checkout-flow identifiers
2. **Store the reference code** before making the request so you can retry with the same code
3. **Retry safely** — the same `reference_code` will always return the same order
4. **Don't reuse codes** for different order intents — each unique order should have a unique code
