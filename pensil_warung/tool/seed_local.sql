-- Local seed: months of past sales for one existing account.
-- Run ONLY against the local dev database:
--   psql "$LOCAL_DATABASE_URL" -v email=you@example.com -f tool/seed_local.sql
-- One transaction. Inserts only (stock moves through stock_movements and the
-- triggers); the only UPDATEs are the documented void (status + voided_at).
\set ON_ERROR_STOP on
\if :{?email}
\else
  \echo 'usage: psql ... -v email=you@example.com -f tool/seed_local.sql'
  \quit 1
\endif

BEGIN;
SELECT set_config('seed.email', lower(:'email'), true);

-- Guards: fail before anything is written.
DO $$
DECLARE uid uuid;
BEGIN
  IF inet_server_addr() IS NOT NULL
     AND NOT (inet_server_addr() <<= '127.0.0.0/8'::inet OR inet_server_addr() <<= '::1/128'::inet) THEN
    RAISE EXCEPTION 'refusing to seed: server is not loopback (%)', inet_server_addr();
  END IF;
  SELECT id INTO uid FROM users WHERE email = current_setting('seed.email');
  IF uid IS NULL THEN
    RAISE EXCEPTION 'user % not found: register it in the app first', current_setting('seed.email');
  END IF;
  IF EXISTS (SELECT 1 FROM transactions WHERE user_id = uid
              AND occurred_at < (now() AT TIME ZONE 'Asia/Jakarta')::date AT TIME ZONE 'Asia/Jakarta') THEN
    RAISE EXCEPTION 'already seeded: % has past transactions', current_setting('seed.email');
  END IF;
  IF EXISTS (SELECT 1 FROM products WHERE user_id = uid) THEN
    RAISE EXCEPTION 'user % already has products; seed needs a fresh account', current_setting('seed.email');
  END IF;
END $$;

-- One sale (or revision when p_replaces is set). p_lines = [{"pid":..,"qty":..}, ...].
CREATE FUNCTION pg_temp.mk_sale(p_uid uuid, p_at timestamptz, p_lines jsonb, p_replaces bigint)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE tid bigint; total bigint; txt text;
BEGIN
  SELECT sum(round((l->>'qty')::numeric * p.price)),
         string_agg(p.name || ' ' || (l->>'qty'), E'\n' ORDER BY o)
    INTO total, txt
    FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS t(l, o)
    JOIN products p ON p.id = (l->>'pid')::bigint;
  INSERT INTO transactions (user_id, client_uuid, raw_text, total, occurred_at, created_at, replaces_id)
  VALUES (p_uid, uuidv7(), txt, total, p_at, p_at, p_replaces) RETURNING id INTO tid;
  INSERT INTO transaction_items (transaction_id, product_id, line_no, product_name, unit_price, quantity, line_total)
  SELECT tid, p.id, o::smallint, p.name, p.price, (l->>'qty')::numeric, round((l->>'qty')::numeric * p.price)
    FROM jsonb_array_elements(p_lines) WITH ORDINALITY AS t(l, o)
    JOIN products p ON p.id = (l->>'pid')::bigint;
  RETURN tid;
END $$;

CREATE FUNCTION pg_temp.void_sale(p_tid bigint, p_at timestamptz) RETURNS void
LANGUAGE sql AS $$
  UPDATE transactions SET status = 'voided', voided_at = p_at WHERE id = p_tid;
$$;

DO $$
DECLARE
  uid     uuid := (SELECT id FROM users WHERE email = current_setting('seed.email'));
  d       date;
  today   date := (now() AT TIME ZONE 'Asia/Jakarta')::date;
  names   text[] := ARRAY['Es teh manis','Nasi goreng','Kopi susu','Gorengan','Mie goreng','Es jeruk',
                          'Nasi telur','Air mineral','Indomie rebus','Ayam goreng','Teh hangat'];
  prices  bigint[] := ARRAY[5000,15000,6000,2000,12000,6000,10000,4000,8000,18000,5000];
  weights numeric[] := ARRAY[14,14,12,16,8,9,7,8,6,4,5];   -- Teh botol is never sold
  wsum    numeric := 103;
  pids    bigint[];
  i int; n int; k int; m int; r numeric; acc numeric; pick int;
  lines jsonb; qty int; used int[]; at_ts timestamptz; tid bigint; t2 bigint;
  mins int[]; dow int; revday date := today - 9; revdone boolean := false;
BEGIN
  PERFORM setseed(0.42);
  FOR i IN 1..11 LOOP
    INSERT INTO products (user_id, name, price, stock, created_at)
    VALUES (uid, names[i], prices[i], 400, '2026-06-01 06:00+07');
  END LOOP;
  INSERT INTO products (user_id, name, price, stock, created_at)
  VALUES (uid, 'Teh botol', 5000, 24, '2026-06-01 06:00+07');
  SELECT array_agg(id ORDER BY id) INTO pids FROM products WHERE user_id = uid AND name <> 'Teh botol';

  FOR d IN SELECT g::date FROM generate_series('2026-06-01'::date, today - 1, '1 day') g LOOP
    dow := extract(isodow FROM d)::int;                       -- 1 = Monday ... 6 = Saturday
    -- Restock what is running low, dated early that morning.
    FOR i IN 1..11 LOOP
      IF (SELECT stock FROM products WHERE id = pids[i]) < 150 THEN
        INSERT INTO stock_movements (product_id, reason, delta, stock_after, created_at)
        VALUES (pids[i], 'restock', 400 - (SELECT stock FROM products WHERE id = pids[i]), 0,
                (d + time '05:30') AT TIME ZONE 'Asia/Jakarta');
      END IF;
    END LOOP;
    -- Now and then some stock is thrown away.
    IF random() < 0.08 THEN
      i := 1 + floor(random() * 11)::int;
      INSERT INTO stock_movements (product_id, reason, delta, stock_after, note, created_at)
      VALUES (pids[i], 'adjustment', -(1 + floor(random() * 3)::int), 0,
              (ARRAY['basi','tumpah','rusak'])[1 + floor(random() * 3)::int],
              (d + time '21:30') AT TIME ZONE 'Asia/Jakarta');
    END IF;

    CONTINUE WHEN random() < 0.1;                              -- a day with no sales
    n := CASE dow WHEN 1 THEN 20 + floor(random() * 6)::int
                  WHEN 6 THEN 38 + floor(random() * 8)::int
                  WHEN 7 THEN 30 + floor(random() * 8)::int
                  ELSE        26 + floor(random() * 10)::int END;
    SELECT array_agg(x ORDER BY x) INTO mins
      FROM (SELECT 360 + floor(random() * 960)::int AS x FROM generate_series(1, n)) s;

    FOR k IN 1..n LOOP
      at_ts := (d + make_interval(mins => mins[k])) AT TIME ZONE 'Asia/Jakarta';
      lines := '[]'::jsonb; used := ARRAY[]::int[];
      FOR m IN 1..(1 + floor(random() * 4)::int) LOOP
        r := random() * wsum; acc := 0; pick := 11;
        FOR i IN 1..11 LOOP
          acc := acc + weights[i];
          IF r < acc THEN pick := i; EXIT; END IF;
        END LOOP;
        CONTINUE WHEN pick = ANY(used);
        used := used || pick;
        qty := 1 + floor(random() * CASE WHEN pick = 4 THEN 6 ELSE 3 END)::int;
        lines := lines || jsonb_build_object('pid', pids[pick], 'qty', qty);
      END LOOP;
      tid := pg_temp.mk_sale(uid, at_ts, lines, NULL);

      IF d = revday AND NOT revdone THEN
        -- Revision chain: v1 -> v2 -> v3 (each older version voided, then replaced).
        revdone := true;
        PERFORM pg_temp.void_sale(tid, at_ts + interval '5 minutes');
        t2 := pg_temp.mk_sale(uid, at_ts, jsonb_build_array(
                jsonb_build_object('pid', pids[2], 'qty', 3), jsonb_build_object('pid', pids[1], 'qty', 2)), tid);
        PERFORM pg_temp.void_sale(t2, at_ts + interval '20 minutes');
        PERFORM pg_temp.mk_sale(uid, at_ts, jsonb_build_array(
                jsonb_build_object('pid', pids[2], 'qty', 2), jsonb_build_object('pid', pids[1], 'qty', 2),
                jsonb_build_object('pid', pids[4], 'qty', 4)), t2);
      ELSIF random() < 0.02 THEN
        PERFORM pg_temp.void_sale(tid, at_ts + interval '3 minutes');   -- cancelled, not revised
      END IF;
    END LOOP;
  END LOOP;
END $$;

SELECT 'products' AS t, count(*) FROM products WHERE user_id = (SELECT id FROM users WHERE email = current_setting('seed.email'))
UNION ALL SELECT 'transactions', count(*) FROM transactions WHERE user_id = (SELECT id FROM users WHERE email = current_setting('seed.email'))
UNION ALL SELECT 'voided', count(*) FROM transactions WHERE status = 'voided' AND user_id = (SELECT id FROM users WHERE email = current_setting('seed.email'))
UNION ALL SELECT 'transaction_items', count(*) FROM transaction_items WHERE transaction_id IN (SELECT id FROM transactions WHERE user_id = (SELECT id FROM users WHERE email = current_setting('seed.email')))
UNION ALL SELECT 'stock_movements', count(*) FROM stock_movements WHERE product_id IN (SELECT id FROM products WHERE user_id = (SELECT id FROM users WHERE email = current_setting('seed.email')));
COMMIT;
