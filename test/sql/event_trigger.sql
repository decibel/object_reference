\set ECHO none

\i test/load.sql

CREATE TABLE test_table(col int);

SELECT plan(
  0
  +2 -- initial
);

SELECT lives_ok(
  $$CREATE TEMP TABLE test_object AS SELECT object_reference.object__getsert('table column', 'test_table'::regclass, 1) AS object_id;$$
  , $$CREATE TEMP TABLE test_object AS SELECT object_reference.object__getsert('table column', 'test_table'::regclass, 1) AS object_id;$$
);
SELECT is(
  (SELECT count(*) FROM test_object)
  , 1::bigint
  , 'Exactly 1 test object record'
);

\i test/pgxntool/finish.sql

-- vi: expandtab sw=2 ts=2
