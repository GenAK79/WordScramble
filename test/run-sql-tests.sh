#!/usr/bin/env bash
# Runs the database tests against a scratch Postgres (14+).
#   WS_TEST_PSQL="psql -h /path/to/socket -p 5432 -U postgres" ./test/run-sql-tests.sh
# A throwaway database is created and dropped each run.
set -euo pipefail
PSQL=${WS_TEST_PSQL:-psql}
DB=ws_test_$$
HERE="$(cd "$(dirname "$0")" && pwd)"
$PSQL -d postgres -q -v ON_ERROR_STOP=1 -c "create database $DB"
trap '$PSQL -d postgres -q -c "drop database if exists $DB" >/dev/null 2>&1 || true' EXIT
$PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -f "$HERE/sql/stubs.sql" >/dev/null
$PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -f "$HERE/../supabase/schema.sql" >/dev/null
$PSQL -d "$DB" -q -v ON_ERROR_STOP=1 -f "$HERE/sql/helpers.sql" >/dev/null
$PSQL -d "$DB" -v ON_ERROR_STOP=1 -f "$HERE/sql/tests.sql" 2>&1 | sed -e 's/^psql:.*NOTICE:  //' -e 's/^NOTICE:  //'
