#!/usr/bin/env bash
# Applies the migrations to a scratch Postgres and runs the database tests.
#
#   supabase/tests/run.sh                  # starts a throwaway postgres:16 container
#   DATABASE_URL=postgres://... run.sh     # uses an existing, EMPTY database (CI)
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/.." && pwd)"

if [[ -z "${DATABASE_URL:-}" ]]; then
    name="walkscape-db-test-$$"
    docker run -d --rm --name "$name" -e POSTGRES_PASSWORD=postgres postgres:16 >/dev/null
    trap 'docker stop "$name" >/dev/null' EXIT
    until docker exec "$name" pg_isready -U postgres >/dev/null 2>&1; do sleep 1; done
    sleep 1
    psql_cmd=(docker exec -i "$name" psql -U postgres -v ON_ERROR_STOP=1 -q)
else
    psql_cmd=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -q)
fi

{
    cat "$here/00_supabase_stub.sql"
    for migration in "$root"/migrations/*.sql; do cat "$migration"; done
} | "${psql_cmd[@]}"

for test in "$here"/[1-9]*.sql; do
    "${psql_cmd[@]}" < "$test" 2>&1 | sed -n 's/^.*NOTICE:  //p; /ERROR/p'
done
echo "All database tests passed."
