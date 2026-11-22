# Internal Wallet Transactional System

API-only Ruby on Rails application for IDR wallets, atomic ledger-backed money operations, custom user sessions, and a configurable stock-price client.

## Runtime and setup

- Ruby `3.3.14` (pinned in `.ruby-version`; includes the November 2026 security fixes)
- Rails `8.1.4.1`
- PostgreSQL; the application is intended for a currently supported PostgreSQL release. Local development was verified with PostgreSQL `12.22`, which is end-of-life; use a supported release such as PostgreSQL 17 or 18 for a new deployment ([versioning policy](https://www.postgresql.org/support/versioning/)).
- Minitest; bcrypt is used only for password hashing. No authentication framework is installed.

Install dependencies and create the development database:

```sh
bundle install
bin/rails db:create db:migrate
```

Database connection settings can be supplied with `PGHOST`, `PGPORT`, `PGUSER`, and `PGPASSWORD`. Database names default to `internal_wallet_development` and `internal_wallet_test`; override them with `DEVELOPMENT_DATABASE` and `TEST_DATABASE`. Production uses `DATABASE_URL`.

Run tests with:

```sh
bin/rails test
```

For the local PostgreSQL 12 installation used during development, put its matching client tools first on `PATH` when loading or dumping `db/structure.sql`:

```sh
PATH="/opt/homebrew/opt/postgresql@12/bin:$PATH" bin/rails db:schema:load RAILS_ENV=test
```

PostgreSQL 18's `pg_dump` emits a setting PostgreSQL 12 cannot parse, so client/server versions should match for local structure loading. This limitation does not apply to the intended supported PostgreSQL deployment target.

## Data and money rules

- `User`, `Team`, and `Stock` can each own one IDR wallet through a polymorphic association. Adding another owner model requires a migration that extends the PostgreSQL owner-reference and owner-protection triggers; including `WalletOwner` alone does not enable it in the database.
- The wallet balance is always derived from `SUM(ledger_entries.amount)`. No mutable balance column is maintained.
- Ledger entries are signed and append-only. PostgreSQL constraints and triggers protect direction, transaction completeness, and immutability even when writes bypass validations.
- Amounts use `decimal(20,2)`. The initial policy rejects overdrafts.
- An idempotency key is unique per acting user. Repeating a key and identical operation returns the original transaction; reusing it for a different operation conflicts.
- Deposits credit only the acting user's own wallet. Withdrawals debit only that wallet. Transfers debit the acting user's wallet and may credit another user's, team's, or stock's wallet. Team/Stock debits are not exposed until an authorization policy for those owners is specified.
- Wallet rows are locked in ascending ID order before balance checks. The transaction record and all ledger entries commit or roll back together.
- Sign-in is available only for pre-provisioned users; there is no signup route.

## Implemented interfaces

Wallet transaction operations are implemented by service objects under `app/services/wallet_transactions`:

- `WalletTransactions::Deposit.call(actor:, target_wallet:, amount:, idempotency_key:)`
- `WalletTransactions::Withdrawal.call(actor:, source_wallet:, amount:, idempotency_key:)`
- `WalletTransactions::Transfer.call(actor:, source_wallet:, target_wallet:, amount:, idempotency_key:)`

Each returns a persisted `WalletTransaction` or raises a typed `WalletTransactions` domain error. Services enforce the same actor wallet policy as the API.

## JSON API

An importable Postman collection, local environment template, setup steps, request order, and troubleshooting guide are available in [`postman/`](postman/README.md).

All routes are under `/api/v1`:

| Method | Route | Purpose |
| --- | --- | --- |
| `POST` | `/sign_in` | Sign in an existing user |
| `DELETE` | `/sign_out` | Revoke the current session |
| `GET` | `/me` | Return the current user |
| `GET` | `/wallets/:id` | Return owned wallet metadata and derived balance |
| `GET` | `/wallets/:id/transactions` | Return up to 100 newest entries for an owned wallet |
| `POST` | `/transactions/deposit` | Credit the user's own wallet |
| `POST` | `/transactions/withdraw` | Debit the user's own wallet |
| `POST` | `/transactions/transfer` | Transfer from the user's wallet to any existing wallet |

Sign-in accepts JSON `{ "email": "...", "password": "..." }`. It returns a CSRF token in `data.csrf_token` and sets an HTTP-only `wallet_session` cookie plus a readable `wallet_csrf` cookie. Production session cookies use `Secure`; cookies use `SameSite=Strict`. Authenticated write requests must send the same CSRF value in `X-CSRF-Token` and the `wallet_csrf` cookie.

Deposit JSON is `{ "target_wallet_id": 1, "amount": "10.00" }`; withdrawal uses `source_wallet_id`; transfer uses both IDs. All wallet transaction requests require an `Idempotency-Key` header. Successful responses include transaction metadata and the actor's permitted wallet balance; a transfer response does not expose the target wallet's balance. Errors use `{ "error": { "code": "...", "message": "..." } }`; codes include `unauthorized`, `forbidden`, `not_found`, `validation_error`, `insufficient_funds`, `idempotency_conflict`, `csrf_invalid`, and `internal_server_error`. Unexpected server errors return a generic message while diagnostic details stay in server logs. There is no `/sign_up` route.

## Stock price integration

`LatestStockPrice` lives in `lib/`. The supplied RapidAPI listing did not expose a verifiable endpoint contract or credentials during implementation. The library therefore does not guess a host, path, request parameter, or response mapping. Provider-specific live requests remain unconfigured until those details are available; tests must use stubbed HTTP.

The provider-independent client accepts a caller-supplied REST GET contract. Configure `base_url`, `endpoints.price` (`path`, `symbol_param`), `endpoints.prices` (`path`, `symbols_param`, optional `symbols_encoding` of `repeated` or `comma_separated`), and `endpoints.price_all` (`path`). Optional headers, `api_key`/`api_key_header`, `open_timeout`, and `read_timeout` can also be set. For example, fill the values below from the provider's actual docs before enabling it:

```ruby
LatestStockPrice.configure do |config|
  config.base_url = ENV.fetch("STOCK_PRICE_BASE_URL")
  config.endpoints = {
    price: { path: ENV.fetch("STOCK_PRICE_PATH"), symbol_param: ENV.fetch("STOCK_PRICE_SYMBOL_PARAM") },
    prices: {
      path: ENV.fetch("STOCK_PRICES_PATH"),
      symbols_param: ENV.fetch("STOCK_PRICES_SYMBOLS_PARAM"),
      symbols_encoding: :repeated
    },
    price_all: { path: ENV.fetch("STOCK_PRICE_ALL_PATH") }
  }
  config.api_key_header = ENV["STOCK_PRICE_KEY_HEADER"]
  config.api_key = ENV["STOCK_PRICE_API_KEY"]
end
```

`price(symbol)`, `prices(symbols)`, and `price_all` return parsed JSON unchanged because the provider's response shape and unknown-symbol semantics are not known. The client validates that configured paths remain on the configured host, uses explicit timeouts, raises typed errors, and never logs secrets.
