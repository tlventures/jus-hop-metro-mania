-- Enable Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- USERS TABLE
CREATE TABLE IF NOT EXISTS users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    phone_number_hash VARCHAR(64) UNIQUE NOT NULL,
    reward_points_balance BIGINT DEFAULT 0 CHECK (reward_points_balance >= 0),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- ONDC TRANSACTIONS TABLE
DO $$ BEGIN
    CREATE TYPE ondc_txn_status AS ENUM ('SEARCHED', 'SELECTED', 'INITIATED', 'PAID', 'CONFIRMED', 'CANCELLED', 'FAILED');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS transactions (
    transaction_id UUID PRIMARY KEY,
    user_id UUID REFERENCES users(id),
    city_code VARCHAR(16) NOT NULL,
    bpp_id VARCHAR(255) NOT NULL,
    bpp_uri VARCHAR(512) NOT NULL,
    status ondc_txn_status DEFAULT 'SEARCHED',
    total_base_fare NUMERIC(10, 2) NOT NULL,
    tax_amount NUMERIC(10, 2) DEFAULT 0.00,
    rewards_discount_amount NUMERIC(10, 2) DEFAULT 0.00,
    final_user_paid_amount NUMERIC(10, 2) DEFAULT 0.00,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- METRO TICKETS TABLE
DO $$ BEGIN
    CREATE TYPE ticket_status AS ENUM ('ISSUED', 'USED', 'EXPIRED', 'REFUNDED', 'CANCELLED');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS tickets (
    ticket_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id UUID REFERENCES transactions(transaction_id),
    user_id UUID REFERENCES users(id),
    metro_operator_id VARCHAR(128) NOT NULL,
    origin_station_id VARCHAR(128) NOT NULL,
    destination_station_id VARCHAR(128) NOT NULL,
    passenger_count INT DEFAULT 1,
    qr_payload TEXT NOT NULL, -- Encrypted QR string/token payload
    valid_from TIMESTAMP WITH TIME ZONE NOT NULL,
    valid_until TIMESTAMP WITH TIME ZONE NOT NULL,
    status ticket_status DEFAULT 'ISSUED',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- REWARDS LEDGER (2PC System)
DO $$ BEGIN
    CREATE TYPE ledger_entry_type AS ENUM ('EARNED', 'HELD', 'REDEEMED', 'RELEASED');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS points_ledger (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES users(id),
    transaction_id UUID REFERENCES transactions(transaction_id),
    points_amount BIGINT NOT NULL,
    entry_type ledger_entry_type NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- INDEXES FOR P99 QUERY OPTIMIZATION
CREATE INDEX IF NOT EXISTS idx_transactions_user_id ON transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_tickets_transaction_id ON tickets(transaction_id);
CREATE INDEX IF NOT EXISTS idx_tickets_user_status ON tickets(user_id, status);
CREATE INDEX IF NOT EXISTS idx_ledger_user_txn ON points_ledger(user_id, transaction_id);

-- PROTOCOL MESSAGE LOGS / NETWORK OBSERVABILITY SOURCE
CREATE TABLE IF NOT EXISTS protocol_messages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id VARCHAR(64),
    message_id VARCHAR(128),
    action VARCHAR(64) NOT NULL,
    direction VARCHAR(16) NOT NULL,
    subscriber_id VARCHAR(255),
    bap_id VARCHAR(255),
    bap_uri VARCHAR(512),
    bpp_id VARCHAR(255),
    bpp_uri VARCHAR(512),
    domain VARCHAR(32),
    city VARCHAR(16),
    http_status INT,
    ack_status VARCHAR(16),
    error_code VARCHAR(64),
    latency_ms INT,
    payload JSONB NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_protocol_messages_txn ON protocol_messages(transaction_id);
CREATE INDEX IF NOT EXISTS idx_protocol_messages_msg ON protocol_messages(message_id);
CREATE INDEX IF NOT EXISTS idx_protocol_messages_action ON protocol_messages(action);

-- ISSUE / GRIEVANCE MANAGEMENT
DO $$ BEGIN
    CREATE TYPE issue_status AS ENUM ('OPEN', 'ACKNOWLEDGED', 'PROCESSING', 'RESOLVED', 'CLOSED');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS issues (
    issue_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id VARCHAR(64),
    order_id VARCHAR(128),
    category VARCHAR(80) NOT NULL,
    status issue_status DEFAULT 'OPEN',
    description TEXT NOT NULL,
    resolution TEXT,
    trail JSONB NOT NULL DEFAULT '[]'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_issues_txn ON issues(transaction_id);
CREATE INDEX IF NOT EXISTS idx_issues_order ON issues(order_id);

-- RECONCILIATION / SETTLEMENT FRAMEWORK
DO $$ BEGIN
    CREATE TYPE recon_status AS ENUM ('PENDING', 'RECONCILED', 'DISPUTED', 'SETTLED');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS recon_records (
    recon_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id VARCHAR(64),
    order_id VARCHAR(128),
    payment_txn_id VARCHAR(128),
    buyer_finder_fee NUMERIC(10, 2) DEFAULT 0.00,
    settlement_party VARCHAR(128),
    settlement_amount NUMERIC(10, 2) DEFAULT 0.00,
    settlement_reference VARCHAR(128),
    refund_adjustment NUMERIC(10, 2) DEFAULT 0.00,
    status recon_status DEFAULT 'PENDING',
    details JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_recon_txn ON recon_records(transaction_id);
CREATE INDEX IF NOT EXISTS idx_recon_order ON recon_records(order_id);
CREATE INDEX IF NOT EXISTS idx_recon_payment ON recon_records(payment_txn_id);

DO $$ BEGIN
    CREATE TYPE payout_status AS ENUM ('PENDING', 'INITIATED', 'PAID', 'FAILED', 'REVERSED');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS payout_records (
    payout_id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    recon_id UUID,
    transaction_id VARCHAR(64),
    order_id VARCHAR(128),
    settlement_party VARCHAR(128),
    amount NUMERIC(10, 2) DEFAULT 0.00,
    currency VARCHAR(8) DEFAULT 'INR',
    payout_reference VARCHAR(128),
    status payout_status DEFAULT 'PENDING',
    details JSONB NOT NULL DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_payout_recon ON payout_records(recon_id);
CREATE INDEX IF NOT EXISTS idx_payout_txn ON payout_records(transaction_id);
CREATE INDEX IF NOT EXISTS idx_payout_order ON payout_records(order_id);
CREATE INDEX IF NOT EXISTS idx_payout_ref ON payout_records(payout_reference);

CREATE TABLE IF NOT EXISTS observability_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    transaction_id VARCHAR(64),
    message_id VARCHAR(128),
    action VARCHAR(64) NOT NULL,
    payload JSONB NOT NULL,
    submitted INT DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);
CREATE INDEX IF NOT EXISTS idx_observability_txn ON observability_events(transaction_id);
CREATE INDEX IF NOT EXISTS idx_observability_msg ON observability_events(message_id);
CREATE INDEX IF NOT EXISTS idx_observability_action ON observability_events(action);
