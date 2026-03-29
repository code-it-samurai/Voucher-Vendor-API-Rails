# Postman Collection

> Import the collection into Postman to test all API flows with auto-captured variables.

## Download

**[Voucher_Vendor_API.postman_collection.json](https://github.com/code-it-samurai/Voucher-Vendor-API-Rails/blob/main/docs/Voucher_Vendor_API.postman_collection.json)**

## What's Included

The collection is organized by entity and covers every success flow:

| Folder | Requests | What It Demonstrates |
|--------|----------|----------------------|
| **Accounts** | Create Account, Create Admin, Get Me, Top Up, Check Balance | Registration, auth, admin top-up |
| **Products** | List All, Replenish Stock | Catalog browse, admin stock management |
| **Orders — Success** | Place, Poll Status, Idempotent Replay | Full lifecycle with voucher generation |
| **Orders — Pending** | Place, Poll Status | Order stays in pending/processing state |
| **Orders — Refund** | Place, Poll Status, Verify Balance | Auto-refund after retry exhaustion |
| **Orders — Cancellation** | Place, Cancel, Verify Status, Verify Balance | Cancel before fulfillment |
| **Orders — Real Product** | Place, Get Status | Standard order with seeded product |

## Auto-Captured Variables

The collection uses **test scripts** to automatically capture IDs and API keys as you run requests in sequence. No manual variable setup needed.

| Variable | Auto-set By |
|----------|-------------|
| `api_key` | Create Account |
| `admin_api_key` | Create Admin Account |
| `product_id` | List All Products |
| `test_success_product_id` | List All Products |
| `test_pending_product_id` | List All Products |
| `test_refund_product_id` | List All Products |
| `success_order_id` | Place Order (Success) |
| `pending_order_id` | Place Order (Pending) |
| `refund_order_id` | Place Order (Refund) |
| `cancel_order_id` | Place Order (Cancel) |

## Quick Setup

1. Import `Voucher_Vendor_API.postman_collection.json` into Postman
2. Make sure the API is running: `docker compose up --build`
3. Run the **Accounts** folder first (creates accounts and adds balance)
4. Run the **Products** folder (captures product IDs)
5. Run any **Orders** folder to test specific flows

> **Note:** The database is seeded with an admin account (`admin@voucher-vendor.test`) and a demo user (`demo@voucher-vendor.test`) automatically. Check the `web` container logs for their API keys: `docker compose logs web | grep "API key"`
