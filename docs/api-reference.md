# API Reference

All responses use a consistent envelope format. See [Response Format](#response-format) below.

## Endpoints Overview

| Method | Endpoint | Auth | Admin | Description |
|--------|----------|:----:|:-----:|-------------|
| `POST` | `/api/v1/accounts` | No | No | Create account |
| `GET` | `/api/v1/accounts/me` | Yes | No | View current account |
| `POST` | `/api/v1/accounts/top_up` | Yes | **Yes** | Add funds to account |
| `GET` | `/api/v1/products` | Yes | No | List active products |
| `POST` | `/api/v1/products/:id/replenish` | Yes | **Yes** | Add stock to product |
| `POST` | `/api/v1/orders` | Yes | No | Place order (idempotent) |
| `GET` | `/api/v1/orders/:id` | Yes | No | Get order details + vouchers |
| `POST` | `/api/v1/orders/:id/cancel` | Yes | No | Cancel a pending order |

---

## Accounts

### POST /api/v1/accounts

Create a new account. **No authentication required.** The API key is returned only in this response.

**Request:**
```json
{
  "account": {
    "name": "Prathamesh",
    "email": "prat@example.com"
  }
}
```

**Response (201 Created):**
```json
{
  "status": "SUCCESS",
  "data": {
    "id": 1,
    "name": "Prathamesh",
    "email": "prat@example.com",
    "balance": "0.0",
    "api_key": "a1b2c3d4e5f6..."
  }
}
```

> **Important:** Save the `api_key` — it is only shown once during account creation.

**Errors:**
| Status | Code | When |
|--------|------|------|
| 422 | `INVALID_INPUT` | Missing name/email or duplicate email |

---

### GET /api/v1/accounts/me

View the current authenticated account. API key is **not** included in response.

**Response (200 OK):**
```json
{
  "status": "SUCCESS",
  "data": {
    "id": 1,
    "name": "Prathamesh",
    "email": "prat@example.com",
    "balance": "800.0"
  }
}
```

---

### POST /api/v1/accounts/top_up

Add funds to an account balance. **Admin-only.**

**Request:**
```json
{
  "amount": 1000.00
}
```

**Response (200 OK):**
```json
{
  "status": "SUCCESS",
  "data": {
    "balance": "1000.0",
    "transaction": {
      "type": "credit",
      "amount": "1000.0",
      "balance_before": "0.0",
      "balance_after": "1000.0"
    }
  }
}
```

**Errors:**
| Status | Code | When |
|--------|------|------|
| 403 | `FORBIDDEN` | Non-admin account |
| 422 | `INVALID_AMOUNT` | Amount <= 0 |

---

## Products

### GET /api/v1/products

List all active products with current stock levels.

**Response (200 OK):**
```json
{
  "status": "SUCCESS",
  "data": [
    {
      "id": 1,
      "name": "Amazon Gift Card",
      "denomination": "100.0",
      "currency": "INR",
      "stock": 50
    },
    {
      "id": 6,
      "name": "Test - Always Succeeds",
      "denomination": "100.0",
      "currency": "INR",
      "stock": 100
    }
  ]
}
```

---

### POST /api/v1/products/:id/replenish

Add stock to a product. **Admin-only.**

**Request:**
```json
{
  "quantity": 100
}
```

**Response (200 OK):**
```json
{
  "status": "SUCCESS",
  "data": {
    "id": 1,
    "name": "Amazon Gift Card",
    "stock": 150
  }
}
```

**Errors:**
| Status | Code | When |
|--------|------|------|
| 403 | `FORBIDDEN` | Non-admin account |
| 422 | `INVALID_INPUT` | Quantity <= 0 |
| 404 | `NOT_FOUND` | Product doesn't exist |

---

## Orders

### POST /api/v1/orders

Place a new order. **Idempotent** via `reference_code`.

**Request:**
```json
{
  "product_id": 1,
  "quantity": 2,
  "denomination": 100.00,
  "reference_code": "my-unique-ref-001"
}
```

**Response (202 Accepted — new order):**
```json
{
  "status": "SUCCESS",
  "data": {
    "id": 1,
    "reference_code": "my-unique-ref-001",
    "product_id": 1,
    "quantity": 2,
    "denomination": "100.0",
    "total_amount": "200.0",
    "status": "pending"
  }
}
```

**Response (200 OK — duplicate reference_code):**

Same body as above, returning the existing order. No balance debit or stock change occurs.

**Errors:**
| Status | Code | When |
|--------|------|------|
| 422 | `INSUFFICIENT_BALANCE` | Account balance < total_amount |
| 422 | `OUT_OF_STOCK` | Product stock < quantity |
| 422 | `PRODUCT_NOT_FOUND` | Product doesn't exist or inactive |
| 422 | `INVALID_INPUT` | Missing fields or invalid values |

> **Idempotency:** Two simultaneous requests with the same `reference_code` are safe. The DB unique constraint catches the second INSERT, and the service returns the existing order. See [Idempotency](idempotency.md).

---

### GET /api/v1/orders/:id

Get order details. Includes vouchers when order is `completed`.

**Response (200 OK — completed order):**
```json
{
  "status": "SUCCESS",
  "data": {
    "id": 1,
    "reference_code": "my-unique-ref-001",
    "status": "completed",
    "total_amount": "200.0",
    "vouchers": [
      {
        "code": "GC-A1B2C3D4E5F6",
        "pin": "1234",
        "claim_url": "https://voucher-vendor.example.com/claim/GC-A1B2C3D4E5F6",
        "expires_at": "2027-03-27T00:00:00.000Z"
      }
    ]
  }
}
```

**Errors:**
| Status | Code | When |
|--------|------|------|
| 404 | `NOT_FOUND` | Order not found or belongs to another account |

---

### POST /api/v1/orders/:id/cancel

Cancel a pending order. Balance and stock are refunded immediately.

**Response (200 OK):**
```json
{
  "status": "SUCCESS",
  "data": {
    "id": 1,
    "status": "cancelled",
    "cancelled_at": "2026-03-27T12:00:00.000Z"
  }
}
```

**Errors:**
| Status | Code | When |
|--------|------|------|
| 422 | `ORDER_NOT_CANCELLABLE` | Order is not in `pending` status |
| 404 | `NOT_FOUND` | Order not found or belongs to another account |

---

## Response Format

Every API response uses a consistent envelope:

<!-- tabs:start -->

#### **Success**

```json
{
  "status": "SUCCESS",
  "data": { ... }
}
```

#### **Error**

```json
{
  "status": "ERROR",
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable description"
  }
}
```

<!-- tabs:end -->

### Error Codes

| Code | HTTP Status | Description |
|------|:-----------:|-------------|
| `UNAUTHORIZED` | 401 | Missing or invalid API key |
| `FORBIDDEN` | 403 | Admin access required |
| `RATE_LIMITED` | 429 | Rate limit exceeded (60 RPM per account) |
| `INSUFFICIENT_BALANCE` | 422 | Not enough funds for the order |
| `OUT_OF_STOCK` | 422 | Product stock insufficient |
| `PRODUCT_NOT_FOUND` | 422 | Product doesn't exist or is inactive |
| `INVALID_INPUT` | 422 | Missing required fields or invalid values |
| `INVALID_AMOUNT` | 422 | Amount must be greater than 0 |
| `ORDER_NOT_CANCELLABLE` | 422 | Order is not in pending status |
| `NOT_FOUND` | 404 | Resource not found |
