\set ECHO none

\i test/load.sql

CREATE TABLE test_table();
CREATE TRIGGER test_trigger
  AFTER INSERT OR UPDATE
  ON test_table
  FOR EACH ROW EXECUTE PROCEDURE suppress_redundant_updates_trigger()
;


SELECT plan(
  0
  +3 -- initial
);

SELECT lives_ok(
  $$CREATE TEMP TABLE test_object AS SELECT object_reference.object__getsert('trigger', 'test_trigger') AS object_id;$$
  , $$CREATE TEMP TABLE test_object_id AS SELECT object_reference.object__getsert('trigger', 'test_trigger') AS object_id;$$
);
SELECT is(
  (SELECT object_oid FROM _object_reference.object WHERE object_id = (SELECT object_id FROM test_object))
  , (SELECT oid FROM pg_trigger WHERE tgname = 'test_trigger' AND tgrelid = 'test_table'::regclass)
  , 'Verify regclass field is correct'
);
SELECT is(
  object_reference.object__getsert('trigger', 'test_trigger')
  , (SELECT object_id FROM test_object)
  , 'Existing object works, provides correct ID'
);

-- TODO: Test renaming of trigger

\i test/pgxntool/finish.sql

-- vi: expandtab sw=2 ts=2
