\i test/pgxntool/setup.sql

-- Need to add count_nulls back into the path
SET search_path = tap, public;

-- Don't use IF NOT EXISTS here; we want to ensure we always have the latest code
CREATE EXTENSION object_reference;
