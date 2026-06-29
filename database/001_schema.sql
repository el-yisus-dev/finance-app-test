-- ============================================================
-- Schema: Digital Wallet Platform + Credit System
-- Exercise 1 - Backend Fintech Technical Assessment
-- PostgreSQL 14+
--
-- MONEY CONVENTION: All monetary amounts are stored as BIGINT
-- representing cents (the smallest currency unit), never as
-- FLOAT or NUMERIC, to avoid rounding errors and floating-point
-- precision issues in JavaScript. The API must multiply values
-- by 100 when receiving user input and divide by 100 when
-- returning responses.
--
-- The only exception is monthly_interest_rate, which represents
-- a percentage (not a monetary value) and is therefore stored
-- as NUMERIC.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto; -- required for gen_random_uuid()

-- ----------------------------------------------------------------
-- ENUMS: Restrict valid values at the database engine level
-- ----------------------------------------------------------------
CREATE TYPE user_role           AS ENUM ('customer', 'credit_analyst', 'admin');
CREATE TYPE user_status         AS ENUM ('active', 'suspended', 'blocked', 'deleted');
CREATE TYPE wallet_status       AS ENUM ('active', 'blocked', 'closed');
CREATE TYPE transaction_type    AS ENUM (
    'deposit',
    'withdrawal',
    'transfer',
    'loan_disbursement',
    'loan_payment'
);

CREATE TYPE transaction_status  AS ENUM (
    'pending',
    'completed',
    'failed',
    'reversed'
);

CREATE TYPE loan_status AS ENUM (
    'pending',
    'under_review',
    'approved',
    'rejected',
    'active',
    'paid',
    'overdue',
    'cancelled'
);

CREATE TYPE installment_status AS ENUM (
    'pending',
    'paid',
    'overdue',
    'partial'
);

-- ----------------------------------------------------------------
-- USERS
-- ----------------------------------------------------------------
CREATE TABLE users (
    id                  BIGSERIAL PRIMARY KEY,
    uuid                UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,

    email               VARCHAR(255) NOT NULL,
    password_hash       VARCHAR(255) NOT NULL,

    first_name          VARCHAR(100) NOT NULL,
    last_name           VARCHAR(100) NOT NULL,

    document_type       VARCHAR(20) NOT NULL,
    document_number     VARCHAR(50) NOT NULL,

    phone               VARCHAR(20),

    birth_date          DATE,

    address             TEXT,

    role                user_role NOT NULL DEFAULT 'customer',

    status              user_status NOT NULL DEFAULT 'active',

    credit_score        SMALLINT NOT NULL DEFAULT 500
                        CHECK (credit_score BETWEEN 0 AND 1000),

    monthly_income      BIGINT
                        CHECK (
                            monthly_income IS NULL
                            OR monthly_income >= 0
                        ), -- cents

    created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Partial unique indexes (not global):
-- Once a user is marked as deleted, both the email address and
-- document become available again, allowing the person to register
-- with the same information in the future.
-- Using regular UNIQUE constraints would permanently block them.

CREATE UNIQUE INDEX idx_users_active_email
ON users (email)
WHERE status <> 'deleted';

CREATE UNIQUE INDEX idx_users_active_document
ON users (document_type, document_number)
WHERE status <> 'deleted';

CREATE INDEX idx_users_status
ON users(status);

-- ----------------------------------------------------------------
-- WALLETS
-- ----------------------------------------------------------------

CREATE TABLE wallets (

    id BIGSERIAL PRIMARY KEY,

    uuid UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,

    user_id BIGINT NOT NULL
        REFERENCES users(id)
        ON DELETE RESTRICT,

    currency VARCHAR(3) NOT NULL DEFAULT 'MXN', -- ISO 4217

    balance BIGINT NOT NULL DEFAULT 0
        CHECK (balance >= 0), -- cents

    status wallet_status NOT NULL DEFAULT 'active',

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()

);

CREATE INDEX idx_wallets_user
ON wallets(user_id);

CREATE INDEX idx_wallets_status
ON wallets(status);

-- Partial unique index:
-- If a user closes a wallet in a specific currency,
-- they can later create a new wallet using the same
-- currency without conflicting with the closed one.

CREATE UNIQUE INDEX idx_wallets_user_currency_active
ON wallets(user_id, currency)
WHERE status <> 'closed';

-- ----------------------------------------------------------------
-- TRANSACTIONS
-- Immutable ledger: the single source of truth for every
-- financial movement in the system.
-- ----------------------------------------------------------------

CREATE TABLE transactions (

    id BIGSERIAL PRIMARY KEY,

    uuid UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,

    type transaction_type NOT NULL,

    source_wallet_id BIGINT
        REFERENCES wallets(id)
        ON DELETE RESTRICT,

    destination_wallet_id BIGINT
        REFERENCES wallets(id)
        ON DELETE RESTRICT,

    amount BIGINT NOT NULL
        CHECK (amount > 0), -- cents

    currency VARCHAR(3) NOT NULL,

    status transaction_status NOT NULL DEFAULT 'pending',

    idempotency_key VARCHAR(100) UNIQUE,

    loan_id BIGINT, -- FK added after creating loans table

    description TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    completed_at TIMESTAMPTZ,

    CHECK (

        (
            type = 'deposit'
            AND source_wallet_id IS NULL
            AND destination_wallet_id IS NOT NULL
        )

        OR

        (
            type = 'withdrawal'
            AND source_wallet_id IS NOT NULL
            AND destination_wallet_id IS NULL
        )

        OR

        (
            type = 'transfer'
            AND source_wallet_id IS NOT NULL
            AND destination_wallet_id IS NOT NULL
            AND source_wallet_id <> destination_wallet_id
        )

        OR

        (
            type IN (
                'loan_disbursement',
                'loan_payment'
            )
        )
    )

);

CREATE INDEX idx_transactions_source
ON transactions(source_wallet_id);

CREATE INDEX idx_transactions_destination
ON transactions(destination_wallet_id);

CREATE INDEX idx_transactions_created_at
ON transactions(created_at);

CREATE INDEX idx_transactions_type_created_at
ON transactions(type, created_at);

CREATE INDEX idx_transactions_status
ON transactions(status);


-- ----------------------------------------------------------------
-- LOANS
-- ----------------------------------------------------------------

CREATE TABLE loans (

    id BIGSERIAL PRIMARY KEY,

    uuid UUID NOT NULL DEFAULT gen_random_uuid() UNIQUE,

    user_id BIGINT NOT NULL
        REFERENCES users(id)
        ON DELETE RESTRICT,

    disbursement_wallet_id BIGINT NOT NULL
        REFERENCES wallets(id)
        ON DELETE RESTRICT,

    requested_amount BIGINT NOT NULL
        CHECK (requested_amount > 0), -- cents

    approved_amount BIGINT
        CHECK (
            approved_amount IS NULL
            OR approved_amount > 0
        ), -- cents

    monthly_interest_rate NUMERIC(6,4) NOT NULL
        CHECK (monthly_interest_rate >= 0),
        -- Percentage, not money.
        -- Example: 0.0250 = 2.5%

    term_months SMALLINT NOT NULL
        CHECK (term_months > 0),

    status loan_status NOT NULL DEFAULT 'pending',

    credit_score_at_application SMALLINT,

    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    approved_at TIMESTAMPTZ,

    disbursed_at TIMESTAMPTZ,

    approved_by BIGINT
        REFERENCES users(id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()

);

ALTER TABLE transactions
ADD CONSTRAINT fk_transactions_loan
FOREIGN KEY (loan_id)
REFERENCES loans(id)
ON DELETE RESTRICT;

CREATE INDEX idx_loans_user
ON loans(user_id);

CREATE INDEX idx_loans_status
ON loans(status);

-- ----------------------------------------------------------------
-- INSTALLMENTS
-- Loan repayment schedule
-- ----------------------------------------------------------------

CREATE TABLE installments (

    id BIGSERIAL PRIMARY KEY,

    loan_id BIGINT NOT NULL
        REFERENCES loans(id)
        ON DELETE CASCADE,

    installment_number SMALLINT NOT NULL,

    installment_amount BIGINT NOT NULL
        CHECK (installment_amount > 0), -- cents

    principal_amount BIGINT NOT NULL
        CHECK (principal_amount >= 0), -- cents

    interest_amount BIGINT NOT NULL
        CHECK (interest_amount >= 0), -- cents

    paid_amount BIGINT NOT NULL DEFAULT 0
        CHECK (paid_amount >= 0), -- cents

    due_date DATE NOT NULL,

    paid_at TIMESTAMPTZ,

    status installment_status NOT NULL DEFAULT 'pending',

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    UNIQUE (loan_id, installment_number)

);

CREATE INDEX idx_installments_loan
ON installments(loan_id);

CREATE INDEX idx_installments_status_due_date
ON installments(status, due_date);

-- ----------------------------------------------------------------
-- INSTALLMENT PAYMENTS
-- Associates a real transaction with the installment(s)
-- it fully or partially covers.
-- ----------------------------------------------------------------

CREATE TABLE installment_payments (

    id BIGSERIAL PRIMARY KEY,

    installment_id BIGINT NOT NULL
        REFERENCES installments(id)
        ON DELETE RESTRICT,

    transaction_id BIGINT NOT NULL
        REFERENCES transactions(id)
        ON DELETE RESTRICT,

    amount BIGINT NOT NULL
        CHECK (amount > 0), -- cents

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()

);

CREATE INDEX idx_installment_payments_installment
ON installment_payments(installment_id);

CREATE INDEX idx_installment_payments_transaction
ON installment_payments(transaction_id);

-- ----------------------------------------------------------------
-- AUDIT LOG
-- Audit trail / regulatory compliance
-- ----------------------------------------------------------------

CREATE TABLE audit_log (

    id BIGSERIAL PRIMARY KEY,

    table_name VARCHAR(50) NOT NULL,

    record_id BIGINT NOT NULL,

    action VARCHAR(10) NOT NULL
        CHECK (
            action IN (
                'INSERT',
                'UPDATE',
                'DELETE'
            )
        ),

    old_data JSONB,

    new_data JSONB,

    user_id BIGINT
        REFERENCES users(id),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()

);

CREATE INDEX idx_audit_log_table_record
ON audit_log(table_name, record_id);

-- ----------------------------------------------------------------
-- REFRESH TOKENS
-- Used for JWT authentication (Exercise 4)
-- ----------------------------------------------------------------

CREATE TABLE refresh_tokens (

    id BIGSERIAL PRIMARY KEY,

    user_id BIGINT NOT NULL
        REFERENCES users(id)
        ON DELETE CASCADE,

    token_hash VARCHAR(255) NOT NULL UNIQUE,
    -- The raw refresh token is never stored.

    revoked_at TIMESTAMPTZ,
    -- NULL = active
    -- Timestamp = revoked

    expires_at TIMESTAMPTZ NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now()

);

CREATE INDEX idx_refresh_tokens_user
ON refresh_tokens(user_id);

CREATE INDEX idx_refresh_tokens_active
ON refresh_tokens(user_id)
WHERE revoked_at IS NULL;

-- ----------------------------------------------------------------
-- Generic trigger:
-- Automatically updates updated_at
-- ----------------------------------------------------------------

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS
$$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$
LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at
BEFORE UPDATE ON users
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_wallets_updated_at
BEFORE UPDATE ON wallets
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_loans_updated_at
BEFORE UPDATE ON loans
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER trg_installments_updated_at
BEFORE UPDATE ON installments
FOR EACH ROW
EXECUTE FUNCTION set_updated_at();


-- ----------------------------------------------------------------
-- IMMUTABILITY
-- The financial ledger is protected at the database level.
-- Transactions are never deleted or rewritten.
-- The only permitted modification is a legitimate status transition
-- (pending -> completed / failed / reversed), performed by
-- process_transaction().
-- ----------------------------------------------------------------

CREATE OR REPLACE FUNCTION protect_immutable_transaction()
RETURNS TRIGGER AS
$$
BEGIN

    IF TG_OP = 'DELETE' THEN

        RAISE EXCEPTION
            'Transactions cannot be deleted (immutable ledger). id=%',
            OLD.id;

    END IF;

    IF TG_OP = 'UPDATE' THEN

        IF NEW.amount <> OLD.amount

           OR NEW.type <> OLD.type

           OR NEW.currency <> OLD.currency

           OR COALESCE(
                NEW.source_wallet_id,
                -1
              ) <> COALESCE(
                OLD.source_wallet_id,
                -1
              )

           OR COALESCE(
                NEW.destination_wallet_id,
                -1
              ) <> COALESCE(
                OLD.destination_wallet_id,
                -1
              )

           OR COALESCE(
                NEW.idempotency_key,
                ''
              ) <> COALESCE(
                OLD.idempotency_key,
                ''
              )

           OR COALESCE(
                NEW.loan_id,
                -1
              ) <> COALESCE(
                OLD.loan_id,
                -1
              )

        THEN

            RAISE EXCEPTION
                'Transaction data cannot be modified once recorded (id=%). Only status and completed_at may be updated.',
                OLD.id;

        END IF;

    END IF;

    RETURN NEW;

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_transactions_immutable

BEFORE UPDATE OR DELETE
ON transactions

FOR EACH ROW

EXECUTE FUNCTION protect_immutable_transaction();

-- ----------------------------------------------------------------
-- audit_log and installment_payments are append-only tables.
-- They have no legitimate state transitions after insertion,
-- therefore UPDATE and DELETE operations are completely blocked.
-- ----------------------------------------------------------------

CREATE OR REPLACE FUNCTION block_all_modifications()

RETURNS TRIGGER AS
$$
BEGIN

    RAISE EXCEPTION
        'Table "%" is append-only. UPDATE and DELETE operations are not allowed for id=%.',
        TG_TABLE_NAME,
        COALESCE(OLD.id, NEW.id);

END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_audit_log_immutable

BEFORE UPDATE OR DELETE
ON audit_log

FOR EACH ROW

EXECUTE FUNCTION block_all_modifications();

CREATE TRIGGER trg_installment_payments_immutable

BEFORE UPDATE OR DELETE
ON installment_payments

FOR EACH ROW

EXECUTE FUNCTION block_all_modifications();

-- ----------------------------------------------------------------
-- NOTE
--
-- Business functions such as:
--
--    process_transaction()
--   sufficient_funds trigger
--   generate_payment_schedule()
--
-- are implemented in Exercise 3 using this schema.
-- ----------------------------------------------------------------