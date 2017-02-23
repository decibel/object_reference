#!/bin/sh

die () {
  code=$1
  shift
  echo "$@" >&2
  exit $code
}

drop() {
  dropdb --if-exists test_dump
  dropdb --if-exists test_load
}

if [ "$1" == "-f" ]; then
  shift
  drop
fi

echo Creating dump database
createdb test_dump && psql -f test/dump/load_all.sql test_dump || die 3 "Unable to dump database"

echo Loading dump
createdb test_load && (echo 'BEGIN;' && pg_dump test_dump && echo 'COMMIT;') | psql -q -v VERBOSITY=verbose -v ON_ERROR_STOP=true test_load || die 4 "Unable to load database"

psql -f test/dump/verify.sql test_load || die 5 "Test failed"

drop

# vi: expandtab ts=2 sw=2
