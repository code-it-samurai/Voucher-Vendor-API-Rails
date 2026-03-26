# System Architecture

## Network Topology

```mermaid
graph TB
    Client["Client / Postman<br/>port 3000"]

    subgraph Docker["Docker Compose Network (voucher-vendor)"]
        Web["web<br/>(Rails 8.1 API)"]
        DB["db<br/>(PostgreSQL 16)"]
        Redis["redis<br/>(Redis 7)"]
        Sidekiq["sidekiq<br/>(Background Worker)"]
    end

    Client -->|"HTTP :3000"| Web
    Web -->|"TCP :5432"| DB
    Web -->|"TCP :6379<br/>enqueue jobs + rate limit cache"| Redis
    Sidekiq -->|"TCP :6379<br/>dequeue jobs"| Redis
    Sidekiq -->|"TCP :5432<br/>read/write orders"| DB
```

| Service | Container Name | Role | Exposed |
|---------|---------------|------|---------|
| **web** | `voucher-vendor-web-1` | Rails API server | Port 3000 to host |
| **db** | `voucher-vendor-db-1` | PostgreSQL 16 with row locks | Internal only |
| **redis** | `voucher-vendor-redis-1` | Job queue + rate limit cache | Internal only |
| **sidekiq** | `voucher-vendor-sidekiq-1` | Async job processor | Internal only |

All services communicate via Docker's internal DNS using service names as hostnames.

---

## Order State Machine

```mermaid
stateDiagram-v2
    [*] --> pending: Order placed<br/>(balance debited, stock decremented)

    pending --> processing: Sidekiq job picked up
    pending --> cancelled: Client cancels<br/>(balance + stock refunded)

    processing --> completed: Vouchers generated
    processing --> failed: Downstream failure<br/>(after 5 retries exhausted)

    failed --> refunded: Automatic refund<br/>(balance + stock restored)

    completed --> [*]
    cancelled --> [*]
    refunded --> [*]
```

| Status | Description | Terminal? |
|--------|-------------|:---------:|
| `pending` | Order accepted, balance debited, queued for async processing | No |
| `processing` | Background job picked it up, working on fulfillment | No |
| `completed` | Voucher(s) generated successfully | Yes |
| `failed` | All retries exhausted, awaiting refund | No |
| `refunded` | Balance credited back + stock restored after failure | Yes |
| `cancelled` | Client cancelled before processing began, fully refunded | Yes |

---

## Entity Relationship Diagram

```mermaid
erDiagram
    ACCOUNT ||--o{ ORDER : places
    ACCOUNT ||--o{ TRANSACTION_RECORD : has
    PRODUCT ||--o{ ORDER : "ordered as"
    ORDER ||--o{ VOUCHER : generates
    ORDER ||--o{ TRANSACTION_RECORD : triggers

    ACCOUNT {
        bigint id PK
        string name
        string email UK
        string api_key UK
        decimal balance
        boolean admin
        integer lock_version
    }

    PRODUCT {
        bigint id PK
        string name
        decimal denomination
        string currency
        boolean active
        integer stock
        string test_behavior
    }

    ORDER {
        bigint id PK
        string reference_code UK
        bigint account_id FK
        bigint product_id FK
        integer quantity
        decimal denomination
        decimal total_amount
        string status
        text failure_reason
        integer attempts
    }

    VOUCHER {
        bigint id PK
        bigint order_id FK
        string code UK
        string pin
        string claim_url
        datetime expires_at
    }

    TRANSACTION_RECORD {
        bigint id PK
        bigint account_id FK
        bigint order_id FK
        string transaction_type
        decimal amount
        decimal balance_before
        decimal balance_after
    }
```

---

## Request Flow: Order Placement

```mermaid
sequenceDiagram
    participant C as Client
    participant W as Web (Rails)
    participant DB as PostgreSQL
    participant R as Redis
    participant S as Sidekiq

    C->>W: POST /api/v1/orders<br/>{reference_code, product_id, quantity}
    W->>W: Authenticate (Bearer token)

    W->>DB: BEGIN TRANSACTION
    W->>DB: SELECT * FROM accounts WHERE id=? FOR UPDATE
    W->>DB: SELECT * FROM products WHERE id=? FOR UPDATE

    alt Balance sufficient & Stock available
        W->>DB: UPDATE accounts SET balance = balance - total
        W->>DB: UPDATE products SET stock = stock - quantity
        W->>DB: INSERT INTO orders (reference_code, ...)
        W->>DB: INSERT INTO transaction_records (type: debit)
        W->>DB: COMMIT
        W->>R: Enqueue OrderFulfillmentJob
        W-->>C: 202 Accepted {status: pending}
    else Insufficient balance
        W->>DB: ROLLBACK
        W-->>C: 422 {code: INSUFFICIENT_BALANCE}
    else Out of stock
        W->>DB: ROLLBACK
        W-->>C: 422 {code: OUT_OF_STOCK}
    end

    Note over S,R: Async processing begins
    S->>R: Dequeue job
    S->>DB: Process order, generate vouchers

    alt Success
        S->>DB: UPDATE orders SET status=completed
        S->>DB: INSERT INTO vouchers
    else Failure (retries exhausted)
        S->>DB: UPDATE orders SET status=failed
        S->>DB: Refund balance + restore stock
        S->>DB: UPDATE orders SET status=refunded
    end
```

---

## Request Flow: Idempotent Duplicate

```mermaid
sequenceDiagram
    participant C1 as Client (Request 1)
    participant C2 as Client (Request 2)
    participant W as Web (Rails)
    participant DB as PostgreSQL

    C1->>W: POST /orders {ref: "ABC-123"}
    C2->>W: POST /orders {ref: "ABC-123"}

    W->>DB: Request 1: INSERT INTO orders (reference_code='ABC-123')
    W->>DB: Request 2: INSERT INTO orders (reference_code='ABC-123')

    DB-->>W: Request 1: OK (row created)
    DB-->>W: Request 2: RecordNotUnique exception

    W->>DB: Request 2: SELECT * FROM orders WHERE reference_code='ABC-123'
    DB-->>W: Existing order

    W-->>C1: 202 Accepted (new order)
    W-->>C2: 200 OK (existing order, no side effects)
```
