#!/bin/sh

DIR=test/dump
create_log=$DIR/create.log
restore_log=$DIR/restore.log
verify_log=$DIR/verify.log

die () {
  code=$1
  shift
  echo "$@" >&2
  exit $code
}

drop() {
  dropdb --if-exists test_dump 2>&1 | grep -v 'does not exist, skipping'
  dropdb --if-exists test_load 2>&1 | grep -v 'does not exist, skipping'
}

if [ "$1" == "-f" ]; then
  shift
  drop
fi

echo Creating dump database
createdb test_dump && psql -f test/dump/load_all.sql test_dump > $create_log || die 3 "Unable to dump database"

echo Running dump and restore
createdb test_load && (echo 'BEGIN;' && pg_dump test_dump && echo 'COMMIT;') | psql -q -v VERBOSITY=verbose -v ON_ERROR_STOP=true test_load > $restore_log || die 4 "Unable to load database"

echo Verifying restore
psql -f test/dump/verify.sql test_load > $verify_log || die 5 "Test failed"

rc=0

if grep -q '^not ok ' $verify_log; then
  cat $verify_log
  exit 8
elif grep -q 'Looks like you planned' $verify_log; then
  grep 'Looks like you planned' $verify_log
  exit 9
fi

echo Dropping databases
drop

echo Done!

# vi: expandtab ts=2 sw=2
