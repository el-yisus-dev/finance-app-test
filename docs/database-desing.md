# Entity Description

| Table                  | Purpose                                                                                                                                                                                                                      |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `users`                | Stores personal information, basic credit data (credit score and monthly income), and the user's role for RBAC.                                                                                                              |
| `wallets`              | Represents a wallet owned by a user in a specific currency. It stores a cached balance that can only be modified through controlled database functions.                                                                      |
| `transactions`         | **Immutable financial ledger.** Records every money movement (deposit, withdrawal, transfer, loan disbursement, and loan payment). Transactions are never updated or deleted; reversals are represented as new transactions. |
| `loans`                | Stores loan applications and their lifecycle (pending → approved/rejected → active → paid/overdue).                                                                                                                          |
| `installments`         | Stores the repayment schedule automatically generated when a loan is approved (Exercise 3).                                                                                                                                  |
| `installment_payments` | Bridge table that associates a real financial transaction with one or more loan installments. Supports partial payments.                                                                                                     |
| `audit_log`            | Stores an audit trail for sensitive changes to support regulatory compliance (KYC/AML).                                                                                                                                      |
| `refresh_tokens`       | Stores hashed refresh tokens used for JWT authentication (Exercise 4).                                                                                                                                                       |

# Design Decisions

## Data Integrity at the Database Level

* **All monetary values are stored as `BIGINT` representing cents**, instead of `NUMERIC` or `FLOAT`. This design has two advantages: (1) it completely eliminates floating-point rounding issues in JavaScript (`0.1 + 0.2 !== 0.3`), and (2) `BIGINT` provides more than enough range—its maximum value (~9.2 quintillion) remains within JavaScript's `Number.MAX_SAFE_INTEGER` for any realistic financial amount. Therefore, no arbitrary-precision integer library is required in the backend. The API converts user input from dollars/pesos to cents (`×100`) before persisting data and converts it back (`÷100`) when returning responses. The only exception is `monthly_interest_rate`, which represents a percentage rather than money and is therefore stored as `NUMERIC(6,4)`.

* Critical business rules are enforced using database `CHECK` constraints, including `balance >= 0`, `amount > 0`, `credit_score BETWEEN 0 AND 1000`, and consistency between a transaction's type and the wallets involved (source and destination). This ensures that important business rules are enforced even if the application layer contains bugs.

* PostgreSQL `ENUM` types (`loan_status`, `transaction_status`, etc.) are used instead of free-form strings, preventing invalid values caused by typos such as `"aproved"`.

## Immutable Ledger as the Source of Truth

* Instead of only updating `wallets.balance`, every financial operation is permanently recorded in the `transactions` table. This provides complete traceability, allows balances to be reconstructed from scratch if necessary, and follows the standard ledger pattern used in financial systems (a lightweight form of event sourcing). The `wallets.balance` column acts as a cached value that is updated within the same database transaction that inserts the corresponding ledger entry (see Exercise 3).

## Duplicate Prevention / Idempotency

* `transactions.idempotency_key` is defined as `UNIQUE`. If a client retries a transfer request due to a network timeout, PostgreSQL rejects the duplicate at the constraint level instead of relying solely on application logic. This satisfies the idempotency requirement described in Exercise 4.

## Security and Data Exposure

* Every primary business entity includes a public `uuid` in addition to its internal numeric `id`. The API should expose only the UUID, preventing enumeration attacks such as `/wallets/1`, `/wallets/2`, and so on.

* Passwords and refresh tokens are never stored in plaintext. Only `password_hash` and `refresh_tokens.token_hash` are persisted.

* Financial relationships use `ON DELETE RESTRICT` to prevent deleting users, wallets, loans, or other entities that already have historical records. This preserves financial history and aligns with common KYC/AML regulatory requirements.

* `audit_log` stores `JSONB` snapshots of the data before and after sensitive changes (such as loan approvals or status changes), allowing auditing without tightly coupling the log to each table's schema.

## Performance for High-Volume Reporting (Exercise 2)

* Indexes are created on the columns most frequently used for filtering and reporting, including:

  * `transactions(created_at)`
  * `transactions(type, created_at)`
  * `loans(status)`
  * `installments(status, due_date)`
  * `wallets(user_id)`

  These indexes optimize monthly reports, delinquency dashboards, and user balance lookups.

* Separating `installments` from `installment_payments` avoids scanning the entire transaction ledger to calculate overdue payments. The installment table already contains indexed due dates and statuses specifically optimized for reporting.

## Timestamp Strategy

* Every table includes a `created_at` column. However, only entities with legitimate state transitions (`users`, `wallets`, `loans`, and `installments`) include an `updated_at` column maintained automatically by a trigger.

* Event tables (`transactions`, `installment_payments`, and `audit_log`) intentionally omit `updated_at`. If a financial transaction had a "last modified" timestamp, it would imply that it could be edited, which contradicts the immutability guarantees expected from a financial ledger.

## Soft Delete Strategy

* Instead of introducing a global `deleted_at` column, deletion behavior depends on the type of entity. This avoids maintaining two independent sources of truth (for example, `status = 'active'` while `deleted_at IS NOT NULL`).

* `users` and `wallets` implement soft deletion through their `status` column (`deleted` for users and `closed` for wallets). Their uniqueness rules (`email`, `document_number`, and `(user_id, currency)`) are implemented using **partial unique indexes** (`WHERE status <> ...`) rather than regular unique constraints. This allows users to register again or create a new wallet after closing the previous one.

* `loans` and `installments` already have terminal states (`cancelled`, `rejected`, `paid`) that naturally represent inactive records.

* `transactions`, `installment_payments`, and `audit_log` are **strictly immutable**. They can never be deleted, either physically or logically, because they represent historical financial events. This rule is enforced by PostgreSQL triggers (`protect_immutable_transaction` and `block_all_modifications`) rather than by application conventions. The only permitted modification is the legitimate status transition of a transaction (`pending → completed / failed / reversed`) together with its `completed_at` timestamp, performed by `process_transaction()` in Exercise 3.

* `refresh_tokens` uses a nullable `revoked_at` timestamp instead of a boolean `revoked` flag. This records not only whether a token has been revoked, but also when it happened, without requiring an additional column.

## Future Extensions (Out of Scope)

Potential future improvements include:

* PostgreSQL Row-Level Security (RLS) to enforce that users can only access their own records at the database level.
* An exchange rate table to support multi-currency conversions.
* Range partitioning of the `transactions` table by date to improve scalability as transaction volume grows.
