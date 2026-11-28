-- A revised sale is a new transaction that replaces the old (voided) one.
ALTER TABLE transactions ADD COLUMN replaces_id bigint REFERENCES transactions (id);

-- One version is replaced at most once; also makes "is this row replaced?" cheap.
CREATE UNIQUE INDEX transactions_replaces_key ON transactions (replaces_id) WHERE replaces_id IS NOT NULL;
