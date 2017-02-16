\set ECHO none

\i test/load.sql

CREATE SCHEMA object_identity_temp_test_schema;
SET search_path=object_identity_temp_test_schema,tap,public;

CREATE TABLE table_under_test(column_test int, filler int);

SELECT plan(
  0
  +4 * 2 -- column_test
  +4 -- table_test

  +4 -- column rename
  +5 -- schema rename
  +5 -- table rename

  +3 -- column drop
  +3 -- table drop
);

/*
 * column_test
 */
SELECT lives_ok(
  $$CREATE TEMP TABLE column_test AS SELECT * FROM _object_reference.object__getsert('table column', 'table_under_test'::regclass, 1)$$
  , $$CREATE TEMP TABLE column_test AS SELECT * FROM _object_reference.object__getsert('table column', 'table_under_test'::regclass, 1)$$
);
SELECT is(
  (SELECT count(*) FROM column_test)
  , 1::bigint
  , 'Exactly 1 test object record'
);
SELECT lives_ok(
  $$CREATE TEMP VIEW column_test_view AS SELECT o.* FROM _object_reference.object o JOIN column_test t USING(object_id)$$
  , 'Create column_test_view'
);
SELECT is(
  (SELECT count(*) FROM column_test_view)
  , 1::bigint
  , 'Exactly 1 test view record'
);

-- s/column_test/column_filler/g
-- Change 1 to 2 in getsert
SELECT lives_ok(
  $$CREATE TEMP TABLE column_filler AS SELECT * FROM _object_reference.object__getsert('table column', 'table_under_test'::regclass, 2)$$
  , $$CREATE TEMP TABLE column_filler AS SELECT * FROM _object_reference.object__getsert('table column', 'table_under_test'::regclass, 2)$$
);
SELECT is(
  (SELECT count(*) FROM column_filler)
  , 1::bigint
  , 'Exactly 1 test object record'
);
SELECT lives_ok(
  $$CREATE TEMP VIEW column_filler_view AS SELECT o.* FROM _object_reference.object o JOIN column_filler t USING(object_id)$$
  , 'Create column_filler_view'
);
SELECT is(
  (SELECT count(*) FROM column_filler_view)
  , 1::bigint
  , 'Exactly 1 test view record'
);

/*
 * table_test
 */
SELECT lives_ok(
  $$CREATE TEMP TABLE table_test AS SELECT * FROM _object_reference.object__getsert('table', 'table_under_test'::regclass, 0)$$
  , $$CREATE TEMP TABLE table_test AS SELECT * FROM _object_reference.object__getsert('table', 'table_under_test'::regclass, 0)$$
);
SELECT is(
  (SELECT count(*) FROM table_test)
  , 1::bigint
  , 'Exactly 1 test object record'
);
SELECT lives_ok(
  $$CREATE TEMP VIEW table_test_view AS SELECT o.* FROM _object_reference.object o JOIN table_test t USING(object_id)$$
  , 'Create table_test_view'
);
SELECT is(
  (SELECT count(*) FROM table_test_view)
  , 1::bigint
  , 'Exactly 1 test view record'
);

/*
 * Test helpers
 */
CREATE FUNCTION pg_temp.check_column(text)
RETURNS SETOF text LANGUAGE sql AS $body$
SELECT results_eq(
  $$SELECT * FROM column_test_view$$
  , $$SELECT * FROM column_test$$
  , $1
)
$body$;
CREATE FUNCTION pg_temp.check_table(text)
RETURNS SETOF text LANGUAGE sql AS $body$
SELECT results_eq(
  $$SELECT * FROM table_test_view$$
  , $$SELECT * FROM table_test$$
  , $1
)
$body$;
CREATE FUNCTION pg_temp.check_both(text)
RETURNS SETOF text LANGUAGE sql AS $body$
SELECT pg_temp.check_table('table_test: ' || $1)
UNION ALL
SELECT pg_temp.check_column('column_test: ' || $1)
$body$;


/*
 *Rename column
 */
SELECT lives_ok(
  $$ALTER TABLE table_under_test RENAME column_test TO test_column2$$
  , 'Rename column'
);
SELECT lives_ok(
  $$UPDATE column_test SET object_names[3] = 'test_column2'$$
  , 'Update column_test'
);
SELECT pg_temp.check_both('verify column rename');

-- Rename schema
SELECT lives_ok(
  $$ALTER SCHEMA object_identity_temp_test_schema RENAME TO test_schema2$$
  , 'Rename schema'
);
SET search_path=test_schema2,tap,public;
SELECT lives_ok(
  $$UPDATE table_test SET object_names[1] = 'test_schema2'$$
  , 'Update table_test'
);
SELECT lives_ok(
  $$UPDATE column_test SET object_names[1] = 'test_schema2'$$
  , 'Update column_test'
);
SELECT pg_temp.check_both('verify table rename');

-- Rename table
SELECT lives_ok(
  $$ALTER TABLE table_under_test RENAME TO test_table2$$
  , 'Rename table'
);
SELECT lives_ok(
  $$UPDATE table_test SET object_names[2] = 'test_table2'$$
  , 'Update table_test'
);
SELECT lives_ok(
  $$UPDATE column_test SET object_names[2] = 'test_table2'$$
  , 'Update column_test'
);
SELECT pg_temp.check_both('verify table rename');

-- Drop column
SELECT lives_ok(
  $$ALTER TABLE test_table2 DROP test_column2$$
  , 'Drop column'
);
SELECT is_empty(
  $$SELECT * FROM column_test_view$$
  , 'Verify column record is deleted'
);
SELECT pg_temp.check_table('Verify table record is unchanged');

-- Drop table
SELECT lives_ok(
  $$DROP TABLE test_table2$$
  , 'Drop table'
);
SELECT is_empty(
  $$SELECT * FROM table_test_view$$
  , 'Verify table record is deleted'
);
SELECT is_empty(
  $$SELECT * FROM column_filler_view$$
  , 'Verify filler column record is deleted'
);

\i test/pgxntool/finish.sql

-- vi: expandtab sw=2 ts=2
