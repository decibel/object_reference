\set ECHO none

\i test/load.sql

SELECT plan(
  0

  + 1 -- equality
);

-- TODO: load some damn data first
SELECT bag_eq(
  $$SELECT * FROM _object_reference._object_v__for_update$$
  , $$SELECT * FROM _object_reference._object_v$$
  , '_object_v__for_update matches _object_v'
);

\i test/pgxntool/finish.sql

-- vi: expandtab sw=2 ts=2
