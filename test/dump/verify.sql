\set ECHO none

\i test/pgxntool/setup.sql

/*
 * SEE ALSO sql/all.sql!
 */

SET search_path=test_objects, test_support, tap, public;


SELECT plan( (
  0
  + c -- verify

  + c * 2 -- drop

  + 1 -- verify object table is now empty
)::int )
  FROM (SELECT count(*) c FROM test_object) c
;

SELECT c.* FROM test_object o, test__verify(o) c ORDER BY o.seq ASC;

SET client_min_messages = WARNING;
--SET client_min_messages = DEBUG;
SELECT c.* FROM test_object o, test__drop(o) c ORDER BY o.seq DESC;

SELECT is_empty(
  $$SELECT * FROM obj_ref$$
  , 'No object references remain'
);

\i test/pgxntool/finish.sql

-- vi: expandtab sw=2 ts=2
