# Concurrency Safety

## The Problem

A gift card order service handles financial transactions — balance debits, stock decrements, and refunds. Without proper concurrency control:

- Two orders could both pass the balance check, overspending the account
- Two orders could both see sufficient stock, overselling the product
- A cancel and a job pickup could race, leaving the system in an inconsistent state

## The Solution: Pessimistic Row Locks

All balance and stock mutations use PostgreSQL's `SELECT ... FOR UPDATE` to acquire exclusive row locks within a transaction:

```ruby
Account.lock.find(account_id)   # SELECT * FROM accounts WHERE id=? FOR UPDATE
Product.lock.find(product_id)   # SELECT * FROM products WHERE id=? FOR UPDATE
```

The second thread attempting to lock the same row **waits** until the first transaction commits or rolls back. It then reads the **updated** values.

### Why `Account.lock.find(id)` and Not `@account.lock!`

Rails 8.1 raises an error when calling `lock!` on an object with unpersisted in-memory changes. The `Account.lock.find(id)` pattern always issues a fresh `SELECT ... FOR UPDATE` from the database, avoiding this issue.

## Concurrency Scenarios

The test suite includes thread-safety specs that prove each scenario is handled correctly:

### Duplicate Reference Code

| Thread A | Thread B | Result |
|----------|----------|--------|
| INSERT order (ref='ABC') | INSERT order (ref='ABC') | One succeeds, one gets `RecordNotUnique` → returns existing |

**Protection:** DB unique index + exception rescue. See [Idempotency](idempotency.md).

### Balance Exhaustion

| Thread A | Thread B | Result |
|----------|----------|--------|
| Lock account (balance: 200) | Waits for lock... | |
| Debit 200, commit (balance: 0) | Acquires lock, reads balance: 0 | |
| 202 Accepted | 422 INSUFFICIENT_BALANCE | |

**Protection:** `SELECT ... FOR UPDATE` on account row.

### Stock Exhaustion

| Thread A | Thread B | Result |
|----------|----------|--------|
| Lock product (stock: 1) | Waits for lock... | |
| Decrement stock, commit (stock: 0) | Acquires lock, reads stock: 0 | |
| 202 Accepted | 422 OUT_OF_STOCK | |

**Protection:** `SELECT ... FOR UPDATE` on product row.

### Cancel vs Job Pickup Race

| Cancel Request | Sidekiq Job | Result |
|----------------|-------------|--------|
| Lock order (status: pending) | Waits for lock... | |
| Set status=cancelled, refund, commit | Acquires lock, reads status: cancelled | |
| 200 OK | Skips (not pending), no-op | |

**Protection:** `SELECT ... FOR UPDATE` on order row. The job checks status after acquiring the lock.

### Concurrent Top-Ups

| Thread A | Thread B | Result |
|----------|----------|--------|
| Lock account (balance: 0) | Waits for lock... | |
| Credit 500, commit (balance: 500) | Acquires lock, reads balance: 500 | |
| | Credit 300, commit (balance: 800) | |

**Final balance:** 800 (correct: 500 + 300)

### Concurrent Replenishments

Same pattern as top-ups — row lock ensures stock increments are serialized.

## Transaction Boundaries

All mutations happen within a database transaction:

```ruby
ActiveRecord::Base.transaction do
  locked_account = Account.lock.find(account.id)
  locked_product = Product.lock.find(product.id)

  raise InsufficientBalanceError if locked_account.balance < total
  raise OutOfStockError if locked_product.stock < quantity

  locked_account.update!(balance: locked_account.balance - total)
  locked_product.update!(stock: locked_product.stock - quantity)

  order = Order.create!(...)
  TransactionRecord.create!(...)
end
```

If any step fails, the entire transaction rolls back — no partial debits or stock changes.

## Why Not Optimistic Locking?

The `accounts` table does include `lock_version` for optimistic locking as an additional safety net. However, **pessimistic locking is the primary strategy** because:

1. **Financial correctness over throughput** — a gift card service cannot tolerate balance inconsistencies
2. **Predictable behavior** — the second thread waits rather than raising `StaleObjectError` and requiring retry logic
3. **Single source of truth** — the locked row always reflects the latest committed state
