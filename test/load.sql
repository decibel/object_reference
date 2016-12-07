\i test/pgxntool/setup.sql

-- Don't use IF NOT EXISTS here; we want to ensure we always have the latest code
CREATE EXTENSION object_reference;
