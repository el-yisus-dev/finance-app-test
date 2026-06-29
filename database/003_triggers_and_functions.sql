-- ============================================================
-- FINTECH PLATFORM - EXERCISE 3
-- FUNCTIONS & TRIGGERS (POSTGRESQL 14+)
-- ============================================================
--
-- PURPOSE:
-- Implements core financial security logic:
-- 1. Secure transaction processing between wallets
-- 2. Balance protection against overdrafts
-- 3. Automatic loan amortization schedule generation
--
-- DESIGN PRINCIPLES:
-- - Database-enforced financial integrity
-- - Atomic transactions using PL/pgSQL
-- - Race-condition prevention with row locking
-- - Immutable financial ledger enforcement
--
-- ============================================================


-- ============================================================
-- 1. TRANSACTION PROCESSOR FUNCTION
-- ============================================================
-- Handles secure money transfers between wallets.
-- Ensures:
-- - Sufficient balance
-- - Atomic debit/credit
-- - Transaction logging
-- ============================================================

CREATE OR REPLACE FUNCTION process_transaction(
    wallet_origin INTEGER,
    wallet_destination INTEGER,
    amount BIGINT,
    tx_type transaction_type,
    description TEXT DEFAULT NULL
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    origin_balance BIGINT;
BEGIN

    -- Validate input
    IF amount <= 0 THEN
        RAISE EXCEPTION 'Amount must be greater than 0';
    END IF;

    -- Lock origin wallet to prevent race conditions
    SELECT balance
    INTO origin_balance
    FROM wallets
    WHERE id = wallet_origin
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Origin wallet not found';
    END IF;

    -- Ensure sufficient funds
    IF origin_balance < amount THEN
        RAISE EXCEPTION 'Insufficient funds in wallet %', wallet_origin;
    END IF;

    -- Debit origin wallet
    UPDATE wallets
    SET balance = balance - amount,
        updated_at = now()
    WHERE id = wallet_origin;

    -- Credit destination wallet (if exists)
    IF wallet_destination IS NOT NULL THEN

        UPDATE wallets
        SET balance = balance + amount,
            updated_at = now()
        WHERE id = wallet_destination;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Destination wallet not found';
        END IF;

    END IF;

    -- Insert immutable transaction record
    INSERT INTO transactions (
        type,
        source_wallet_id,
        destination_wallet_id,
        amount,
        currency,
        status,
        description,
        completed_at
    )
    VALUES (
        tx_type,
        wallet_origin,
        wallet_destination,
        amount,
        'MXN',
        'completed',
        description,
        now()
    );

    RETURN TRUE;

EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;


-- ============================================================
-- 2. WALLET BALANCE SAFETY TRIGGER
-- ============================================================
-- Prevents wallet balances from becoming negative.
-- This is a database-level financial safety constraint.
-- ============================================================

CREATE OR REPLACE FUNCTION verify_sufficient_funds()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN

    IF NEW.balance < 0 THEN
        RAISE EXCEPTION
            'Insufficient funds: wallet % cannot go negative',
            NEW.id;
    END IF;

    RETURN NEW;
END;
$$;


CREATE TRIGGER trg_wallet_balance_protection
BEFORE UPDATE ON wallets
FOR EACH ROW
EXECUTE FUNCTION verify_sufficient_funds();


-- ============================================================
-- 3. LOAN PAYMENT SCHEDULE GENERATOR
-- ============================================================
-- Automatically generates installment schedule when a loan
-- is approved.
--
-- Assumptions:
-- - Simple interest model
-- - Equal distribution across installments
-- ============================================================

CREATE OR REPLACE FUNCTION generate_payment_schedule(
    loan_id_input INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    loan_record RECORD;
    total_interest BIGINT;
    total_amount BIGINT;
    monthly_amount BIGINT;
    principal_part BIGINT;
    interest_part BIGINT;
    i INTEGER;
BEGIN

    -- Fetch loan
    SELECT *
    INTO loan_record
    FROM loans
    WHERE id = loan_id_input;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Loan not found';
    END IF;

    IF loan_record.approved_amount IS NULL THEN
        RAISE EXCEPTION 'Loan must be approved before generating schedule';
    END IF;

    -- Calculate total interest
    total_interest :=
        (loan_record.approved_amount
        * loan_record.monthly_interest_rate
        * loan_record.term_months)::BIGINT;

    total_amount := loan_record.approved_amount + total_interest;

    monthly_amount := total_amount / loan_record.term_months;

    principal_part := loan_record.approved_amount / loan_record.term_months;
    interest_part := total_interest / loan_record.term_months;

    -- Create installments
    FOR i IN 1..loan_record.term_months LOOP

        INSERT INTO installments (
            loan_id,
            installment_number,
            installment_amount,
            principal_amount,
            interest_amount,
            due_date,
            status
        )
        VALUES (
            loan_record.id,
            i,
            monthly_amount,
            principal_part,
            interest_part,
            (CURRENT_DATE + (i * INTERVAL '1 month'))::DATE,
            'pending'
        );

    END LOOP;

END;
$$;
