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
createdb test_dump && psql -f test/dump/load_all.sql test_dump > $create_log || die 3 "Unable to create dump database"

# Ensure no errors in log
check_log() {
  file=$1
  step=$2

  test=`tail -n +2 $file | egrep -v '^ok ' | head -n1`
  if [ -n "$test" ]; then
    cat $file
    #echo "x${test}x"
    die 11 "Errors during $step"
  fi
}

check_log $create_log creation

echo Running dump and restore
# No real need to cat the log on failure here; psql will generate an error and even if not verify will almost certainly catch it
createdb test_load && (echo 'BEGIN;' && pg_dump test_dump && echo 'COMMIT;') | psql -q -v VERBOSITY=verbose -v ON_ERROR_STOP=true test_load > $restore_log || die 4 "Unable to load database"

echo Verifying restore
psql -f test/dump/verify.sql test_load > $verify_log || die 5 "Test failed"

check_log $create_log verify

echo Dropping databases
drop

echo Done!

# vi: expandtab ts=2 sw=2
