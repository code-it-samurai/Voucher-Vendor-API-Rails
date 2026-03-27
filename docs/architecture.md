# System Architecture

## Network Topology

```mermaid
graph TB
    Client["Client / Postman"]

    subgraph Host["Host Machine"]
        Port3000["localhost:3000"]
        Port5433["localhost:5433"]
    end

    subgraph Docker["Docker Compose Network — voucher-vendor_default"]
        subgraph WebContainer["voucher-vendor-web-1"]
            Rails["Rails 8.1 API<br/>Puma Web Server"]
            Auth["Auth Middleware<br/>HMAC-SHA256 Bearer Token"]
            RateLimit["Rate Limiter<br/>60 RPM / account"]
            Controllers["Controllers<br/>Accounts · Orders · Products"]
            Services["Service Layer<br/>Placement · Fulfillment<br/>Cancellation · Refund · TopUp"]
        end

        subgraph SidekiqContainer["voucher-vendor-sidekiq-1"]
            Worker["Sidekiq Worker"]
            FulfillmentJob["OrderFulfillmentJob<br/>5 retries · exponential backoff"]
            RetryExhausted["retries_exhausted callback<br/>→ auto refund"]
        end

        subgraph DBContainer["voucher-vendor-db-1"]
            PG["PostgreSQL 16"]
            RowLocks["SELECT ... FOR UPDATE<br/>row-level locks"]
            UniqueIdx["UNIQUE INDEX<br/>reference_code · api_key · email"]
            Tables["Tables<br/>accounts · products · orders<br/>vouchers · transaction_records"]
        end

        subgraph RedisContainer["voucher-vendor-redis-1"]
            RedisServer["Redis 7"]
            JobQueue["Job Queue<br/>Sidekiq enqueue/dequeue"]
            CacheStore["Cache Store<br/>Rate limit counters"]
        end
    end

    Client -->|"HTTP"| Port3000
    Port3000 -->|":3000 → :3000"| Rails

    Rails --> Auth
    Auth --> RateLimit
    RateLimit --> Controllers
    Controllers --> Services

    Services -->|"TCP :5432<br/>transactions + row locks"| PG
    Services -->|"TCP :6379<br/>enqueue jobs"| RedisServer

    Worker -->|"TCP :6379<br/>dequeue jobs"| RedisServer
    FulfillmentJob -->|"TCP :5432<br/>process orders + generate vouchers"| PG
    RetryExhausted -->|"TCP :5432<br/>refund balance + restore stock"| PG

    Port5433 -->|":5433 → :5432"| PG

    RateLimit -.->|"TCP :6379<br/>increment counters"| RedisServer
```

### Service Details

| Container | Image | Internal Port | Exposed | Role |
|---|---|---|---|---|
| `voucher-vendor-web-1` | ruby:3.3-slim | 3000 | **3000 → host** | Rails API + Puma |
| `voucher-vendor-db-1` | postgres:16-alpine | 5432 | 5433 → host | Primary database |
| `voucher-vendor-redis-1` | redis:7-alpine | 6379 | Internal only | Job queue + cache |
| `voucher-vendor-sidekiq-1` | ruby:3.3-slim | — | Internal only | Background worker |

### Communication

All services communicate via Docker's internal DNS — service names resolve to container IPs. Only the web service exposes port 3000 to the host. The database is optionally accessible on host port 5433 for debugging.

---

## Order State Machine

```mermaid
stateDiagram-v2
    [*] --> pending: Order placed<br/>balance debited · stock decremented

    pending --> processing: Sidekiq job picked up
    pending --> cancelled: Client cancels<br/>balance + stock refunded

    processing --> completed: Vouchers generated
    processing --> failed: Downstream failure<br/>after 5 retries exhausted

    failed --> refunded: Automatic refund<br/>balance + stock restored

    completed --> [*]
    cancelled --> [*]
    refunded --> [*]
```

| Status | Description | Terminal? |
|---|---|:---:|
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
    W->>W: Rate limit check

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
    S->>DB: Lock order row, set status=processing
    S->>S: Generate vouchers

    alt Success
        S->>DB: INSERT INTO vouchers
        S->>DB: UPDATE orders SET status=completed
    else Failure (retries exhausted)
        S->>DB: UPDATE orders SET status=failed
        S->>DB: Lock account + product rows
        S->>DB: Credit balance + restore stock
        S->>DB: INSERT INTO transaction_records (type: refund)
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
