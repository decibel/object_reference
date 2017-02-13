\set ECHO none

\i test/load.sql

CREATE TABLE test_table();

SELECT plan(
  0
  +3 -- initial
  +2 -- errors
  +2 -- move
);

SELECT lives_ok(
  $$CREATE TEMP TABLE test_object AS SELECT object_reference.object__getsert('table', 'test_table') AS object_id;$$
  , $$CREATE TEMP TABLE test_object AS SELECT object_reference.object__getsert('table', 'test_table') AS object_id;$$
);
SELECT is(
  (SELECT regclass FROM _object_reference.object WHERE object_id = (SELECT object_id FROM test_object))
  , 'test_table'::regclass
  , 'Verify regclass field is correct'
);
SELECT is(
  object_reference.object__getsert('table', 'test_table')
  , (SELECT object_id FROM test_object)
  , 'Existing object works, provides correct ID'
);

SELECT throws_ok(
  $$SELECT object_reference.object__getsert('table', 'test_table', schema:='test')$$
  , NULL
  , 'schema may not be specified separately for table objects'
  , 'schema may not be specified separately for table objects'
);
SELECT throws_ok(
  $$SELECT object_reference.object__getsert('table', 'test_table', secondary:='test')$$
  , NULL
  , 'secondary may not be specified separately for table objects'
  , 'secondary may not be specified separately for table objects'
);

/*
 * I'm not sure if our extension would continue working if count_nulls was
 * relocetd. Currently a moot point since relocation isn't supported, but I'd
 * already coded the second test so might as well leave it here in case it
 * changes in the future.
 */
\set null_schema test_relocate_count_nulls
CREATE SCHEMA :null_schema;
SELECT throws_ok(
  $$ALTER EXTENSION count_nulls SET SCHEMA $$ || :'null_schema'
  , '0A000'
  , NULL
  , 'Verify count_nulls extension can not be relocated'
);
SELECT is(
  object_reference.object__getsert('table', 'test_table')
  , (SELECT object_id FROM test_object)
  , 'Still works after moving the count_nulls extension'
);

\i test/pgxntool/finish.sql

-- vi: expandtab sw=2 ts=2
