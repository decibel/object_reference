\set ECHO none

-- Loads deps, but not extension itself
\i test/pgxntool/setup.sql

CREATE EXTENSION IF NOT EXISTS count_nulls;
CREATE EXTENSION IF NOT EXISTS cat_tools;

CREATE SCHEMA object_reference;
\i sql/object_reference.sql

\echo # TRANSACTION INTENTIONALLY LEFT OPEN!

-- vi: expandtab sw=2 ts=2
