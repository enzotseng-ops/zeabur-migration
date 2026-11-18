-- 列出每張使用者資料表的筆數，一行一張：「schema.表名 筆數」。只讀。
-- 用法：psql -q -d <db> -f pg-count.sql 2>&1 | sed 's/.*NOTICE:  //'
DO $$ DECLARE r record; n bigint; BEGIN
FOR r IN SELECT schemaname, relname FROM pg_stat_user_tables ORDER BY schemaname, relname LOOP
  EXECUTE format('SELECT count(*) FROM %I.%I', r.schemaname, r.relname) INTO n;
  RAISE NOTICE '%.% %', r.schemaname, r.relname, n;
END LOOP;
FOR r IN SELECT schemaname, sequencename, last_value FROM pg_sequences ORDER BY schemaname, sequencename LOOP
  RAISE NOTICE 'seq %.% %', r.schemaname, r.sequencename, coalesce(r.last_value, 0);
END LOOP; END $$;
