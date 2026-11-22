# Postman guide

## Import and configure

1. Start Rails locally (see the project README).
2. In Postman, import `Internal Wallet API.postman_collection.json` and `Local.postman_environment.json`.
3. Select **Internal Wallet API - Local** from the environment selector.
4. Set the environment's `password` to the password for an existing provisioned user. Confirm `email` matches that user.
5. Set `sourceWalletId` to that user's IDR wallet. Set `targetWalletId` to a different existing wallet ID. Wallets cannot be created through this API; create users, teams, stocks, and their wallets administratively through Rails console or another trusted provisioning process.
6. Keep `baseUrl` consistent for every request. The default is `http://localhost:3000`; switching between `localhost` and `127.0.0.1` changes the cookie host.

## Recommended request order

1. **Health → Health check** confirms the app is reachable (`200`).
2. **Authentication → Sign in** creates a session. Postman saves the `wallet_session` and `wallet_csrf` cookies. The request test script saves the JSON CSRF token into `csrfToken` in the selected environment.
3. **Authentication → Current user** verifies the session (`200`).
4. **Wallets → Show my wallet** reads the owner wallet and its ledger-derived balance.
5. **Transactions → Deposit** can add a small internal credit for a demo. This is not proof of a real payment or a payment gateway integration.
6. **Transactions → Withdraw** can debit up to the available balance.
7. **Transactions → Transfer to another wallet** needs a different existing target wallet. It returns the source balance, but not the target balance.
8. **Wallets → My wallet transaction history** shows signed ledger rows. A credit is positive and a debit is negative.
9. **Authentication → Sign out** revokes the current session and clears the cookies.

The transaction requests use fixed example idempotency keys. Repeating the same operation with the same key and same payload returns the original transaction without writing duplicates. If you change the amount or wallet IDs, change that request's key in the environment too. Reusing a key for another payload returns `409 idempotency_conflict`.

## API rules and responses

- All JSON API routes start with `/api/v1`. The health route is `/up`.
- There is no signup, wallet creation, Team/Stock provisioning, currency conversion, external payout, or payment processing endpoint.
- The only supported currency is `IDR`; amounts must be positive decimal values with at most two decimal places. Withdrawals and transfers cannot overdraw a wallet.
- Deposits and withdrawals apply only to the signed-in user's own wallet. Transfers debit that user's own wallet and can credit any existing wallet. The API does not allow debiting a Team or Stock wallet.
- Authenticated `POST` and `DELETE` requests need the session cookie and matching CSRF token in both `wallet_csrf` cookie and `X-CSRF-Token` header. Postman manages the cookies and each write request includes the header.
- Wallet reads are restricted to the signed-in user's own wallet. The transfer response omits the target wallet's balance to avoid revealing another owner's data.
- Transaction writes require `Idempotency-Key`. Success returns `201 Created`; sign-out returns `204 No Content`.
- Error shape: `{ "error": { "code": "...", "message": "..." } }`. Common codes: `unauthorized`, `forbidden`, `csrf_invalid`, `not_found`, `validation_error`, `insufficient_funds`, and `idempotency_conflict`.

### Response shapes

Sign-in returns a CSRF token and expiry (sample token is redacted):

```json
{
  "data": {
    "id": 7,
    "email": "admin@example.com",
    "csrf_token": "<returned-token>",
    "expires_at": "2026-11-21T12:00:00Z"
  }
}
```

`GET /me` returns `{ "data": { "id": 7, "email": "admin@example.com" } }`. `GET /wallets/:id` returns `{ "data": { "id": 1, "currency": "IDR", "balance": "15.00" } }`. `GET /wallets/:id/transactions` returns a `data` array of `{ "id", "transaction_id", "type", "amount", "created_at" }` ledger-entry records.

Deposit and withdrawal return `data` with `id`, `type`, `amount`, nullable `source_wallet_id` / `target_wallet_id`, signed `ledger_entries`, and the affected `balance`. Transfer returns the same transaction and ledger fields plus `source_balance`; it intentionally has no `target_balance` field. Ledger entry `amount` is positive for credit and negative for debit.

## Troubleshooting

| Result | Likely cause | What to check |
| --- | --- | --- |
| Connection error | Rails is not running or wrong host/port | Start `bin/rails server`; verify `baseUrl` |
| `401 unauthorized` | No active session or bad credentials | Run Sign in; verify the existing user's email/password and Postman cookie jar |
| `403 csrf_invalid` | Missing/mismatched CSRF cookie/header | Run Sign in again; select the environment so `csrfToken` is saved; do not edit it manually |
| `403 forbidden` | Wallet is not owned by current user for a read/debit/deposit | Use the signed-in user's wallet as `sourceWalletId`; a transfer may use another wallet only as target |
| `404 not_found` | Wallet ID does not exist | Check `sourceWalletId` or `targetWalletId` in the selected environment |
| `422 insufficient_funds` | Amount exceeds source balance | Read the wallet balance and reduce the withdrawal/transfer amount |
| `422 validation_error` | Missing key, invalid amount, or more than two decimal places | Send a positive amount such as `10.00` and an `Idempotency-Key` |
| `409 idempotency_conflict` | The key was already used for a different operation payload | Change that operation's idempotency key, then retry |
| `404` at `/api/v1/sign_up` | Expected: signup is not implemented | Provision users administratively; use Sign in |

## Library note

`LatestStockPrice` is a Ruby library, not an HTTP route in this collection. The RapidAPI endpoint contract and credentials were unavailable, so configure the provider contract as described in the main README before making live stock-price calls.
