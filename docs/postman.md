# Postman Collection

> Import the collection into Postman to test all endpoints with a single click.

## Download

📦 **[Voucher-Vendor-API.postman_collection.json](https://github.com/code-it-samurai/Voucher-Vendor-API-Rails/blob/main/docs/Voucher-Vendor-API.postman_collection.json)**

## What's Included

The collection covers the full API workflow:

| Folder | Requests |
|--------|----------|
| **Setup** | Create Account, Admin Top-Up |
| **Products** | List Products, Replenish Stock (Admin) |
| **Orders** | Place Order, Get Order, Cancel Order |
| **Idempotency** | Duplicate Reference Code |
| **Error Cases** | Insufficient Balance, Out of Stock, Unauthorized, Forbidden |

## Environment Variables

The collection uses these variables — set them after creating your account:

| Variable | Description |
|----------|-------------|
| `base_url` | `http://localhost:3000` |
| `user_api_key` | API key from account creation |
| `admin_api_key` | Admin API key from `db:seed` output |

## Quick Setup

1. Import the collection JSON into Postman
2. Set the environment variables above
3. Run the **Setup** folder first to create accounts and add balance
4. Run any other folder to test specific flows
