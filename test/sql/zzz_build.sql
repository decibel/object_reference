\set ECHO none

-- Loads deps, but not extension itself
\i test/pgxntool/setup.sql

\i sql/object_reference.sql

\echo # TRANSACTION INTENTIONALLY LEFT OPEN!

-- vi: expandtab sw=2 ts=2