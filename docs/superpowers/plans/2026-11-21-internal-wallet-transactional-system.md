# Internal Wallet Transactional System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a PostgreSQL-backed Rails JSON API with polymorphic entity wallets, an immutable ledger, safe deposit/withdraw/transfer services, custom sign-in, and a `LatestStockPrice` library.

**Architecture:** `Wallet` belongs polymorphically to supported entity models. `WalletTransaction` stores the operation and idempotency data; signed `LedgerEntry` rows are the only source of balance. Operation-specific service objects lock wallet rows before reading balances and write the transaction plus all entries in one database transaction. API controllers authenticate existing users and call those services; the stock-price client is an isolated `lib` integration.

**Tech Stack:** Ruby 3.3.6, Ruby on Rails 8.1.4.1, PostgreSQL, Minitest, `Net::HTTP` for the RapidAPI wrapper, Rails `has_secure_password` for password hashing (minimal bcrypt dependency only, no authentication framework). The repository was empty. The local machine has PostgreSQL client 18.1 but connects to a PostgreSQL 12.22 server, which is end-of-life; use a dedicated test database and document this local server limitation.

**Spec:** User request, attached `RoR Test (1).pdf`, and the supplied conversation transcript `ROR_WALLET_TECHNICAL_TEST.md`.

## Scope and Constraints

- Use Rails + PostgreSQL and Minitest.
- Required models: `User`, `Team`, `Stock`, `Wallet`, `WalletTransaction`, `LedgerEntry`, `UserSession`.
- Wallet ownership is polymorphic and supports User, Team, Stock, and additional explicitly registered owner models.
- Derive balances with `SUM(ledger_entries.amount)`; do not add a mutable cached balance column.
- Support deposit, withdrawal, and transfer with required source/target validation, ACID transactions, row locking, database constraints, idempotency, and immutable committed ledger entries.
- Use service objects rather than STI for operation behavior.
- Implement custom sign-in/session, with no public signup and no external authentication framework.
- Implement a `lib/LatestStockPrice`-style Ruby library exposing `price`, `prices`, and `price_all` against the specified provider once its actual contract is verified.
- The stock-price library is in scope; public Rails routes that proxy stock-price calls are not required by the assessment and are excluded unless separately requested.
- Test and fix each phase before continuing. Do not claim success without actual test output.

## Explicit Proposals Requiring Confirmation Before Their Phase

The assessment leaves these business rules open. Treat these as proposals, confirm before coding the dependent behavior, and record the accepted choice in `README.md`.

1. **Currency and precision:** MVP uses one currency, IDR, and `decimal(20,2)` amounts. Reject values with more than two fractional digits; no FX or cross-currency transfer. If the intended test is currency-neutral or multi-currency, update wallet uniqueness and transfer rules before schema work.
2. **Insufficient balance:** reject withdrawals and transfers that exceed the source wallet balance. A wallet may not become negative through these operations.
3. **Wallet cardinality:** one wallet per owner per currency, enforced by a unique index on `(owner_type, owner_id, currency)`.
4. **Direction and ledger signs:** deposit has no source and credits target; withdrawal has source and no target; transfer has distinct source and target. Deposits write `+amount`, withdrawals write `-amount`, transfers write equal/opposite entries. This matches the attached PDF's credit/debit example.
5. **Idempotency:** mandatory caller key scoped to authenticated user; persist a canonical request fingerprint. Same key + same payload returns the original transaction; same key + different payload returns conflict. Unique-index races must resolve to the existing row without creating ledger entries twice.
6. **Authorization:** the source spec defines no Team membership, Stock ownership, or admin policy. Proposed minimum: access to a User wallet requires that owner to be the current user; Team/Stock wallet access requires an explicitly implemented access rule. Do not let any authenticated user mutate arbitrary wallets. Confirm how the test expects actors to be authorized to transfer between different entity types.
7. **Session transport/provisioning:** proposed API uses a secure HttpOnly session cookie backed by `UserSession`, plus CSRF protection; no signup. Seed a deterministic test user only in test. Define the non-public operational process for provisioning non-test users before release.
8. **Password dependency:** use Rails `has_secure_password` and bcrypt solely for password hashing, not an auth framework. Confirm that “without external gem” means no external authentication framework, as stated in the request; if it bans bcrypt too, choose a reviewed standard-library KDF approach before implementation.
9. **Provider contract:** API key/subscription, method inputs, endpoint paths, headers, response schema, rate limits, and unknown-symbol/error behavior must be checked against the actual RapidAPI subscription before writing the client. Do not invent paths or parameter names.

## Key Design Details

### Relationships and database rules

- `User` has many sessions and polymorphic wallets; `Team` and `Stock` have polymorphic wallets. A small `WalletOwner` concern can share the owner-side association.
- Polymorphic owner references cannot have ordinary foreign keys to multiple owner tables. Register allowed owner classes in application code; do not `constantize` an API-provided type. Restrict deletion of any owner with wallet history.
- `WalletTransaction` has optional `source_wallet` and `target_wallet`, required `actor: User`, positive amount, type in `deposit/withdraw/transfer`, idempotency key, request fingerprint, and timestamps.
- `LedgerEntry` belongs to wallet and transaction and stores a signed nonzero amount. Add foreign keys, unique `(wallet_transaction_id, wallet_id)`, and no cascading deletion of financial history.
- Use SQL check constraints for positive transaction amounts, allowed type, and valid source/target shape. Use unique indexes for email, stock symbol, wallet ownership/currency, session token digest, and actor/idempotency key.
- Protect committed ledger rows with a PostgreSQL trigger that rejects UPDATE and DELETE. Add a deferred database constraint trigger (or equivalent robust DB enforcement) to validate at commit that each transaction has exactly the expected ledger rows and signs; Rails validations alone cannot enforce cross-row invariants for direct SQL writes.
- Owner models have no inferred Team membership/Stock entitlement. The explicit authorization decision above gates controller access.

### Balance and transaction invariants

- `Wallet#balance` runs a database `SUM` over its entries and returns a decimal zero when empty.
- All writers first open a DB transaction, lock affected wallet rows in ascending ID order, then read balance and write records. Never check balance before locking. No callback or background job may create ledger rows after the business transaction commits.
- Deposit: lock target; persist one transaction and one `+amount` entry.
- Withdrawal: lock source; check balance; persist one transaction and one `-amount` entry.
- Transfer: lock both distinct wallets in deterministic ID order; require same currency and sufficient source balance; persist one transaction, then `-amount` source and `+amount` target entries.
- Any failure rolls back the transaction and all entries. Transfer entry sum must be zero. No status field is needed for synchronous operations; failed attempts are not financial transactions.
- Idempotency lookup and insert are protected by the DB unique index and fingerprint comparison, including concurrent duplicate requests.

## File Map

- Rails bootstrap: `Gemfile`, `.ruby-version`, `config/application.rb`, `config/database.yml`, `config/routes.rb`, `README.md`.
- Migrations: owner tables; wallets; transactions; ledger entries; sessions; PostgreSQL trigger/constraint functions as separate migrations.
- Models: `app/models/{user,team,stock,wallet,wallet_transaction,ledger_entry,user_session}.rb`, plus `app/models/concerns/wallet_owner.rb` if useful.
- Services: `app/services/wallet_transactions/{base,deposit,withdrawal,transfer}.rb` and `app/services/authentication/{create_session,authenticate_session,revoke_session}.rb`.
- Authorization/API: `app/policies/wallet_access_policy.rb` (or a focused equivalent), `app/controllers/application_controller.rb`, `app/controllers/api/v1/{sessions,wallets,transactions}_controller.rb`.
- Stock client: `lib/latest_stock_price.rb`, `lib/latest_stock_price/{client,configuration,errors}.rb`.
- Tests: `test/models`, `test/services`, `test/integration`, `test/lib`, and PostgreSQL-specific concurrency/constraint tests.

## Implementation Phases

### Phase 0: Repository and decision gate

**Files:** No application code. Update this plan only if a decision changes scope.

- [x] Confirm repository is empty and inspect available Ruby, Rails, and PostgreSQL versions; preserve unrelated files if any appear.
- [x] Select a supported, compatible Ruby/Rails/PostgreSQL target and pin Ruby/dependencies. Do not assume the installed Rails 5.2/Ruby 2.6 pair is suitable for a new application.
- [x] Resolve proposals 1–9 that affect schema, authorization, session transport, or external access. If a proposal is accepted unchanged, record it in `README.md` during Phase 1.
- [x] Check the supplied RapidAPI listing for endpoint documentation and credentials. Neither was available, so provider-specific requests remain deferred and no endpoint details are invented.

**Gate:** no dependent schema/API behavior is coded while a material business decision remains ambiguous.

### Phase 1: Rails bootstrap, schema, models, and constraints

**Files:** Rails application files; owner/wallet/transaction/ledger/session migrations; required model files; model/database tests.

**Interfaces:** `Wallet belongs_to :owner, polymorphic: true`; `Wallet#balance`; transaction associations `source_wallet`, `target_wallet`, and `actor`; `LedgerEntry` signed amount; `UserSession` token digest/expiry/revocation fields.

- [x] Write Minitest coverage for User/Team/Stock ownership, one wallet per owner/currency, model field requirements, transaction direction, amount precision, ledger-sum balance, and session uniqueness.
- [x] Generate an API-only Rails project using PostgreSQL and Minitest; configure DB settings through environment variables and document setup.
- [x] Create owner tables and password support; create wallets; create transactions with source/target wallet foreign keys and idempotency fingerprint; create ledger and sessions with required foreign keys/indexes/check constraints.
- [x] Add restrictive deletion policy and PostgreSQL ledger immutability/cross-row invariant enforcement. Keep trigger functions in migrations with reversible cleanup where practical.
- [x] Implement model associations and validations; keep DB constraints authoritative for race-prone uniqueness and direct SQL writes.
- [x] Run migrations from an empty test database and focused model/constraint tests. **Pass:** all migrations load on PostgreSQL; invalid rows fail at DB level; `Wallet#balance` matches ledger sums.

### Phase 2: Atomic wallet service objects and idempotency

**Files:** `app/services/wallet_transactions/*`, model refinements, service and concurrency tests.

**Interfaces:**

- `WalletTransactions::Deposit.call(target_wallet:, amount:, idempotency_key:, actor:)`
- `WalletTransactions::Withdrawal.call(source_wallet:, amount:, idempotency_key:, actor:)`
- `WalletTransactions::Transfer.call(source_wallet:, target_wallet:, amount:, idempotency_key:, actor:)`
- Success returns the persisted `WalletTransaction`; invalid input, insufficient funds, and key/payload conflict return documented domain errors.

- [x] Write failing service tests for successful deposit/withdraw/transfer, correct signed entries, source/target validation, same-wallet and currency mismatch, overdraft rejection, request precision, and rollback on any insert failure.
- [x] Add idempotency tests: same actor/key/payload replays the original transaction; changed payload conflicts; concurrent duplicate key creates only one transaction and one set of ledger entries.
- [x] Implement common normalization/validation and one transaction boundary per operation. Lock the affected wallet rows by ascending ID before computing balances; all service-created writes commit or roll back together.
- [x] Handle unique-index races by resolving the existing idempotency row and comparing fingerprints; do not swallow unrelated DB errors.
- [x] Run focused service tests. Add a PostgreSQL test using separate connections/threads and synchronized withdrawals; **pass:** no overspend, duplicate ledger write, or partial transaction.

### Phase 3: Custom authentication, authorization, and JSON API

**Files:** authentication services, wallet access policy, controllers/routes, request tests, README API contract.

**Proposed API contract (confirm before coding):**

| Method | Route | Purpose |
|---|---|---|
| `POST` | `/api/v1/sign_in` | Authenticate an existing user and create a session |
| `DELETE` | `/api/v1/sign_out` | Revoke current session and clear cookie |
| `GET` | `/api/v1/me` | Return current authenticated user |
| `GET` | `/api/v1/wallets/:id` | Return wallet metadata and derived balance |
| `GET` | `/api/v1/wallets/:id/transactions` | Return that wallet's transaction history |
| `POST` | `/api/v1/transactions/deposit` | Credit target wallet |
| `POST` | `/api/v1/transactions/withdraw` | Debit source wallet |
| `POST` | `/api/v1/transactions/transfer` | Move funds between source and target wallets |

- [x] Write request tests for valid/invalid sign-in, no signup route, logout, missing/expired/revoked session, CSRF/session cookie behavior, wallet balance/history, all three operations, malformed/overprecision amounts, unauthenticated access, forbidden wallet access, and idempotency replay/conflict.
- [x] Implement custom session creation from existing users only; store a digest of a high-entropy token, set expiry/revocation, secure the cookie, and never persist/log the raw token. Use a reviewed password KDF; no auth framework.
- [x] Implement explicit `WalletAccessPolicy` from the Phase 0 decision. Controllers must not accept a polymorphic class name and must authorize every wallet before invoking services.
- [x] Keep controllers thin. Map domain failures to stable JSON error codes and HTTP responses (`unauthorized`, `forbidden`, `not_found`, `validation_error`, `insufficient_funds`, `idempotency_conflict`). Never put ledger writes in controllers.
- [x] Run focused request/security tests. **Pass:** no public signup, unauthorized actors cannot move funds, and controller operations use the service layer.

### Phase 4: `LatestStockPrice` library

**Files:** `lib/latest_stock_price.rb`, `lib/latest_stock_price/{client,configuration,errors}.rb`, `test/lib/latest_stock_price_test.rb`.

**Interface:** `LatestStockPrice.configure`; module methods `price(symbol)`, `prices(symbols)`, and `price_all`; a `LatestStockPrice::Client` owns the HTTP calls. Exact arguments and normalized return shape follow verified provider docs.

- [x] Record the provider listing's unavailable endpoint contract/credentials in README and document the caller-supplied configuration required before live use.
- [x] Write isolated tests using stubbed HTTP for each method, non-2xx responses, timeout, malformed JSON, unknown-symbol response handling, and missing API key.
- [x] Implement a provider-independent configurable `Net::HTTP` GET client with explicit open/read timeouts, JSON parsing, typed errors, and secret-safe logging. Do not make live network calls in Minitest.
- [x] Run library tests. **Pass:** all methods use a test-supplied contract and tests require no network or real API key. Provider-specific contract verification remains pending external details.

### Phase 5: Full verification and handoff

**Files:** README and any focused regression tests discovered during integration.

- [x] Run all migrations from empty through `20261121000006` in a fresh PostgreSQL test database, and load `db/structure.sql` in a separate fresh test database; run the complete `bin/rails test` suite on both.
- [x] Verify concurrency tests use separate checked-out database connections and are not hidden by transactional fixtures.
- [x] Verify DB constraints independently of model validations; verify committed ledger update/delete fails; verify transfer entries balance to zero.
- [x] Verify no test reaches RapidAPI, no credentials appear in logs/fixtures, and no public signup or unauthorized wallet access exists.
- [x] Document setup, environment variables, route/error contract, chosen business rules, and known provider limitations. Inspect Git status if repository metadata exists; otherwise list generated files.
- [x] Report only executed checks and their actual results; identify unresolved decisions without claiming implementation success.

## Acceptance Checklist

- [x] User, Team, Stock, and registered future entities can own wallets; unsupported polymorphic types cannot be injected through API input.
- [x] Wallet balance is derived only from `SUM(ledger_entries.amount)`.
- [x] Deposit, withdrawal, and transfer obey source/target and sign rules.
- [x] All wallet writes are atomic; affected rows are locked before balance reads; concurrent withdrawals cannot overspend.
- [x] Idempotency survives retries and concurrent duplicate requests without duplicate ledger entries.
- [x] Database constraints and PostgreSQL triggers protect key invariants; committed ledger rows cannot be updated or deleted.
- [x] Custom sign-in/session works with existing users only; authorization is explicit and no auth framework is used.
- [ ] `LatestStockPrice` exposes `price`, `prices`, and `price_all` using a verified provider contract. The provider-specific part is blocked on actual RapidAPI endpoint documentation and credentials; the generic configurable client is implemented.
- [x] Focused tests pass after each phase and the full PostgreSQL-backed Minitest suite passes at handoff.
