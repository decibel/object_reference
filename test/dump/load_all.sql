\set ECHO none

\i test/load.sql

/*
 * SEE ALSO sql/all.sql!
 */

CREATE SCHEMA test_support;
SET search_path = test_support, tap, public;

\i test/helpers/object_table.sql

CREATE SCHEMA test_objects; -- THIS NEEDS TO FAIL IF THE SCHEMA EXISTS!
SET search_path=test_objects, test_support, tap, public;

SELECT plan( (
  0
  
  + (SELECT count(*) FROM test_prereq)
  + c -- create

  + c -- register
  + c -- verify

)::int )
  FROM (SELECT count(*) c FROM test_object) c
;

SELECT lives_ok(
      command
      , 'prereq: ' || command
    )
  FROM test_prereq
;

SELECT c.* FROM test_object o, test__create(o) c ORDER BY o.seq ASC;

SELECT c.* FROM test_object o, test__register(o) c ORDER BY o.seq DESC; -- Would be nice to randomize...
SELECT c.* FROM test_object o, test__verify(o) c ORDER BY o.seq ASC;

--SET client_min_messages = DEBUG;
--\i test/pgxntool/finish.sql
SELECT finish();
COMMIT;

-- vi: expandtab sw=2 ts=2

