-- ============================================================
-- FINTECH PLATFORM - ANALYTICS QUERIES
-- PostgreSQL 14+
-- ============================================================


-- ============================================================
-- 1. USER WALLET BALANCE REPORT
-- ============================================================
-- Description:
-- Shows all users and their wallets with balances per currency.
-- Ensures users without wallets are still included.
-- ============================================================

SELECT
    u.id AS user_id,
    u.uuid AS user_uuid,
    CONCAT(u.first_name, ' ', u.last_name) AS user_name,
    u.email,

    w.id AS wallet_id,
    w.uuid AS wallet_uuid,
    w.currency,
    
    -- Convert cents → main currency unit
    (w.balance / 100.0) AS balance,

    w.status AS wallet_status,
    w.created_at AS wallet_created_at

FROM users u
LEFT JOIN wallets w
    ON w.user_id = u.id
ORDER BY
    user_name,
    w.currency;


-- ============================================================
-- 2. MONTHLY TRANSACTION ANALYSIS BY TYPE
-- ============================================================
-- Description:
-- Monthly aggregation of transactions by type.
-- Includes volume, count, and month-over-month growth.
-- Only completed transactions are considered.
-- ============================================================

WITH monthly_summary AS (
    SELECT
        DATE_TRUNC('month', created_at) AS month,
        type,
        COUNT(*) AS transaction_count,
        SUM(amount) AS total_volume
    FROM transactions
    WHERE status = 'completed'
    GROUP BY 1, 2
)

SELECT
    month,
    type,

    transaction_count,
    (total_volume / 100.0) AS total_volume,

    LAG(total_volume) OVER (
        PARTITION BY type
        ORDER BY month
    ) / 100.0 AS previous_month_volume,

    ROUND(
        (
            (total_volume - LAG(total_volume) OVER (
                PARTITION BY type
                ORDER BY month
            )) * 100.0
        ) /
        NULLIF(
            LAG(total_volume) OVER (
                PARTITION BY type
                ORDER BY month
            ),
            0
        ),
        2
    ) AS growth_percentage

FROM monthly_summary
ORDER BY month, type;


-- ============================================================
-- 3. CREDIT DASHBOARD OVERVIEW
-- ============================================================
-- Description:
-- Aggregates loans by status and shows distribution.
-- ============================================================

SELECT
    status AS loan_status,
    COUNT(*) AS total_loans,

    (SUM(COALESCE(approved_amount, requested_amount)) / 100.0) AS total_amount,

    ROUND(
        COUNT(*) * 100.0 /
        SUM(COUNT(*)) OVER(),
        2
    ) AS percentage

FROM loans
GROUP BY status
ORDER BY total_amount DESC;


-- ============================================================
-- 3.1 LOAN DEFAULT RATIO
-- ============================================================
-- Description:
-- Percentage of loans that are overdue.
-- ============================================================

SELECT
    COUNT(*) FILTER (WHERE status = 'overdue') AS overdue_loans,
    COUNT(*) AS total_loans,

    ROUND(
        COUNT(*) FILTER (WHERE status = 'overdue') * 100.0 /
        COUNT(*),
        2
    ) AS overdue_percentage

FROM loans;


-- ============================================================
-- 4. USER CREDIT BEHAVIOR RANKING
-- ============================================================
-- Description:
-- Scores users based on repayment behavior.
-- Uses installments performance as reliability metric.
-- ============================================================

WITH user_stats AS (
    SELECT
        u.id AS user_id,
        CONCAT(u.first_name, ' ', u.last_name) AS user_name,

        COUNT(DISTINCT l.id)
            FILTER (WHERE l.status = 'paid') AS paid_loans,

        COUNT(DISTINCT l.id)
            FILTER (WHERE l.status IN ('approved', 'active', 'paid')) AS active_loans,

        COUNT(i.id)
            FILTER (WHERE i.status = 'paid') AS paid_installments,

        COUNT(i.id)
            FILTER (WHERE i.status = 'overdue') AS overdue_installments

    FROM users u
    LEFT JOIN loans l ON l.user_id = u.id
    LEFT JOIN installments i ON i.loan_id = l.id

    GROUP BY u.id
)

SELECT
    *,
    
    ROUND(
        paid_installments * 100.0 /
        NULLIF(paid_installments + overdue_installments, 0),
        2
    ) AS punctuality_score,

    RANK() OVER (
        ORDER BY
            ROUND(
                paid_installments * 100.0 /
                NULLIF(paid_installments + overdue_installments, 0),
                2
            ) DESC
    ) AS ranking

FROM user_stats
ORDER BY ranking;