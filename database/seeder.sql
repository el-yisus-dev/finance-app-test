-- ============================================================
-- FINTECH PLATFORM - DATABASE SEEDER
-- PostgreSQL 14+
-- ============================================================
-- PURPOSE:
-- Inserts realistic test data for:
-- - users
-- - wallets
-- - transactions
-- - loans
-- - installments
-- ============================================================


-- ============================================================
-- 1. USERS
-- ============================================================

INSERT INTO users (
    email,
    password_hash,
    first_name,
    last_name,
    document_type,
    document_number,
    phone,
    birth_date,
    address,
    role,
    status,
    credit_score,
    monthly_income
) VALUES

-- User 1
(
    'juan@mail.com',
    'hashed_password_1',
    'Juan',
    'Pérez',
    'INE',
    'MX123456',
    '5512345678',
    '1995-06-10',
    'CDMX, Mexico',
    'customer',
    'active',
    720,
    4500000
),

-- User 2
(
    'ana@mail.com',
    'hashed_password_2',
    'Ana',
    'García',
    'INE',
    'MX987654',
    '5587654321',
    '1992-11-20',
    'Puebla, Mexico',
    'customer',
    'active',
    650,
    3200000
),

-- User 3 (admin)
(
    'admin@fintech.com',
    'hashed_admin',
    'System',
    'Admin',
    'PASS',
    'ADMIN001',
    NULL,
    NULL,
    NULL,
    'admin',
    'active',
    900,
    NULL
);


-- ============================================================
-- 2. WALLETS
-- ============================================================

INSERT INTO wallets (
    user_id,
    currency,
    balance,
    status
)
SELECT id, 'MXN', 2500000, 'active'
FROM users WHERE email = 'juan@mail.com';

INSERT INTO wallets (
    user_id,
    currency,
    balance,
    status
)
SELECT id, 'USD', 150000, 'active'
FROM users WHERE email = 'juan@mail.com';

INSERT INTO wallets (
    user_id,
    currency,
    balance,
    status
)
SELECT id, 'MXN', 1800000, 'active'
FROM users WHERE email = 'ana@mail.com';


-- ============================================================
-- 3. TRANSACTIONS
-- ============================================================

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
SELECT
    'deposit',
    NULL,
    w.id,
    500000,
    'MXN',
    'completed',
    'Initial deposit',
    now()
FROM wallets w
JOIN users u ON u.id = w.user_id
WHERE u.email = 'juan@mail.com';


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
SELECT
    'transfer',
    w1.id,
    w2.id,
    200000,
    'MXN',
    'completed',
    'Peer transfer',
    now()
FROM wallets w1
JOIN wallets w2 ON true
JOIN users u1 ON u1.id = w1.user_id
JOIN users u2 ON u2.id = w2.user_id
WHERE u1.email = 'juan@mail.com'
AND u2.email = 'ana@mail.com'
LIMIT 1;


-- ============================================================
-- 4. LOANS
-- ============================================================

INSERT INTO loans (
    user_id,
    disbursement_wallet_id,
    requested_amount,
    approved_amount,
    monthly_interest_rate,
    term_months,
    status,
    credit_score_at_application,
    approved_at,
    disbursed_at,
    approved_by
)
SELECT
    u.id,
    w.id,
    1000000,
    800000,
    0.0250,
    12,
    'active',
    u.credit_score,
    now(),
    now(),
    (SELECT id FROM users WHERE role = 'admin' LIMIT 1)
FROM users u
JOIN wallets w ON w.user_id = u.id
WHERE u.email = 'ana@mail.com';


-- ============================================================
-- 5. INSTALLMENTS
-- ============================================================

INSERT INTO installments (
    loan_id,
    installment_number,
    installment_amount,
    principal_amount,
    interest_amount,
    due_date,
    status
)
SELECT
    l.id,
    generate_series(1, 3),
    300000,
    250000,
    50000,
    (CURRENT_DATE + (generate_series(1, 3) * INTERVAL '30 days'))::DATE,
    'pending'
FROM loans l
WHERE l.status = 'active'
LIMIT 1;


-- ============================================================
-- 6. REFRESH TOKENS
-- ============================================================

INSERT INTO refresh_tokens (
    user_id,
    token_hash,
    expires_at
)
SELECT
    id,
    'mock_token_hash_1',
    now() + INTERVAL '30 days'
FROM users
WHERE email = 'juan@mail.com';