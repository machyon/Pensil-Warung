-- No scheduler: a scheduled broadcast counts as sent once scheduled_for <= now(),
-- worked out at read time. Rows are never rewritten to 'sent' when they fall due.
CREATE VIEW v_broadcasts AS
SELECT b.*,
       CASE
         WHEN b.status = 'cancelled' THEN 'cancelled'
         WHEN b.status = 'sent' OR b.scheduled_for <= now() THEN 'sent'
         ELSE 'scheduled'
       END AS effective_status,
       coalesce(b.broadcasted_at, b.scheduled_for) AS shown_at
FROM broadcasts b;

DROP INDEX broadcasts_feed_idx;
CREATE INDEX broadcasts_feed_idx ON broadcasts ((coalesce(broadcasted_at, scheduled_for)) DESC, id DESC)
  WHERE status IN ('sent', 'scheduled');
