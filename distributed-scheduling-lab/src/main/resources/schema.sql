CREATE TABLE IF NOT EXISTS messages (
    id              BIGSERIAL PRIMARY KEY,
    type            VARCHAR(10)  NOT NULL,                 -- 'INTRADAY' | 'EOD'
    payload         TEXT         NOT NULL,
    status          VARCHAR(20)  NOT NULL DEFAULT 'NEW',   -- NEW | PROCESSING | DONE
    claimed_by      VARCHAR(50),
    claim_token     UUID,
    claimed_at      TIMESTAMPTZ,
    processed_at    TIMESTAMPTZ,
    attempts        INT NOT NULL DEFAULT 0,
    processed_count INT NOT NULL DEFAULT 0,   -- incremented on EVERY completion; >1 means duplicate
    created_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_messages_new
    ON messages (created_at) WHERE status = 'NEW';

CREATE INDEX IF NOT EXISTS idx_messages_leased
    ON messages (claimed_at) WHERE status = 'PROCESSING';
