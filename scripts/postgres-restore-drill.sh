#!/usr/bin/env bash
# Restore drills on DEV. See docs/runbooks/postgres-restore-one-database.md. <db> is ismd_tool_db or keycloak_db.
#
#   preflight <db> [date]      read-only: dump decrypts and parses, server reachable, no leftovers
#   restore <db> [date]        CREATE <db>_restore_test, pg_restore into it (date = yyyy-mm-dd, default latest)
#   compare <db>               read-only: restored copy vs live, schema, row counts, row hashes
#   rename-test <db>           rename the copy and back, touches nothing else
#   swap <db>                  live -> <db>_old, copy -> live. Refused while anything is connected
#   swap-back <db>             reverse of swap: <db> -> copy, <db>_old -> <db>
#   drop <db>                  DROP the copy. Refused while <db>_old exists
#   stop <app>                 deactivate active revisions (backend|frontend|keycloak|fuseki)
#   start <app>                new revision from the live template, wait until healthy
#   status                     revisions, health and replicas of the four apps
#   templates save|check       hash each app's template and secrets, compare later
#   suppress on|off            dev alert notifications, apr-dia-env-off-dev
#   backup                     run the backup job once, wait, list today's dumps
#   snapshot                   snapshot the Fuseki share. Refused while Fuseki has replicas
#   reconciler <label>         run the reconciler. Prompts for your login, run it in your own terminal
#   reconciler-diff <a> <b>    compare two saved reports
#
# Needs az, openssl, pg tools 16+ and jq. With Windows binaries under WSL, set PSQL, PG_RESTORE and
# WORK (a /mnt/c path). Dev is hardcoded
# on purpose. Nothing here takes an environment as an argument, and the only database it ever
# creates or drops is the restored copy.
#
# Secrets stay in env vars inside this process. Plaintext never reaches disk: dumps are piped from
# openssl into pg_restore. Row data is never printed, only counts and hashes.
set -euo pipefail

SERVER=ismd-tool-postgres-dev
HOST=$SERVER.postgres.database.azure.com
VAULT=ismd-kv-dev
ACCOUNT=ismdpgbackupdev
CONTAINER=weekly
JOB=ismd-pg-backup-dev
SHARED_RG=ismd-shared-dev
TOOL_RG=ismd-tool-dev
FUSEKI_ACCOUNT=ismdtoolfusekidev
FUSEKI_SHARE=fuseki-data
SUPPRESS_RULE=apr-dia-env-off-dev
API=https://oha03.dia.gov.cz/popisujeme
ADMIN=ismdadmin
APPS="backend frontend keycloak fuseki"
PSQL="${PSQL:-psql}"
PG_RESTORE="${PG_RESTORE:-pg_restore}"
WORK="${WORK:-${TMPDIR:-/tmp}/ismd-restore-drill}"

export PGSSLMODE=require PGCONNECT_TIMEOUT=15
# Windows binaries only see env vars listed here.
export WSLENV="PGPASSWORD:PGSSLMODE:PGCONNECT_TIMEOUT:PGOPTIONS${WSLENV:+:$WSLENV}"
export LC_ALL=C   # join needs both sides in one sort order, whatever the server collation is

die() { echo "$*" >&2; exit 1; }

set_db() {
  SOURCE_DB=${1:-}
  case "$SOURCE_DB" in
    ismd_tool_db) APP_ROLE=ismd_tool_app;     SCHEMA=ismd_schema ;;
    keycloak_db)  APP_ROLE=ismd_keycloak_app; SCHEMA=public ;;
    *) die "database must be ismd_tool_db or keycloak_db" ;;
  esac
  SCRATCH_DB=${SOURCE_DB}_restore_test
  OLD_DB=${SOURCE_DB}_old
}

app_name() {
  case " $APPS " in
    *" ${1:-} "*) echo "ismd-tool-$1-dev" ;;
    *) die "app must be one of: $APPS" ;;
  esac
}

kv_secret() { az keyvault secret show --vault-name "$VAULT" -n "$1" --query value -o tsv | tr -d '\r'; }

load_pgpassword() {
  PGPASSWORD=$(kv_secret postgres-password)
  [ -n "$PGPASSWORD" ] || die "postgres-password came back empty"
  export PGPASSWORD
}

load_backup_key() {
  BACKUP_KEY=$(kv_secret pg-backup-encryption-key)
  [ -n "$BACKUP_KEY" ] || die "pg-backup-encryption-key came back empty"
  export BACKUP_KEY
}

# psql against one database. ro = session refuses writes, rw = it does not.
sql() {
  local mode=$1 db=$2 query=$3 opts=""
  [ "$mode" = ro ] && opts="-c default_transaction_read_only=on"
  PGOPTIONS="$opts" "$PSQL" -h "$HOST" -U "$ADMIN" -d "$db" -X -A -t -F ' | ' \
    -v ON_ERROR_STOP=1 -c "$query" 2> >(grep -v 'could not find a' >&2) | tr -d '\r'
}

db_exists() { [ -n "$(sql ro postgres "select 1 from pg_database where datname='$1'")" ]; }

db_connections() { sql ro postgres "select count(*) from pg_stat_activity where datname='$1'"; }

find_blob() { # date, or empty for the latest
  az storage blob list --account-name "$ACCOUNT" -c "$CONTAINER" --auth-mode key --only-show-errors \
    --prefix "$SOURCE_DB-${1:-}" --query "sort_by(@,&name)[-1].name" -o tsv | tr -d '\r'
}

# A Windows az under WSL cannot read Linux paths.
az_path() { case "$(command -v az)" in /mnt/*) wslpath -w "$1" ;; *) echo "$1" ;; esac; }

download_blob() {
  mkdir -p "$WORK"
  az storage blob download --account-name "$ACCOUNT" -c "$CONTAINER" --auth-mode key --only-show-errors \
    --no-progress -n "$1" -f "$(az_path "$WORK/$1")" -o none
}

decrypt() { openssl enc -d -aes-256-cbc -pbkdf2 -iter 600000 -pass env:BACKUP_KEY -in "$1"; }

pg_restore_bin() { "$PG_RESTORE" "$@" 2> >(grep -v 'could not find a' >&2); }

preflight() {
  set_db "${1:-}"
  local blob; blob=$(find_blob "${2:-}")
  [ -n "$blob" ] && [ "$blob" != None ] || die "no matching $SOURCE_DB dump in $ACCOUNT/$CONTAINER"
  echo "dump: $blob"
  download_blob "$blob"
  echo "encrypted bytes: $(wc -c < "$WORK/$blob")"

  load_backup_key
  # The whole stream, not just the TOC: a wrong key or a truncated blob fails here.
  echo "decrypted bytes: $(decrypt "$WORK/$blob" | wc -c)"
  # Parses every data block without a server. The SQL goes down the pipe and is only counted.
  echo "COPY blocks parsed: $(decrypt "$WORK/$blob" | pg_restore_bin --no-acl -f - | grep -c '^COPY ')"
  unset BACKUP_KEY
  rm -f "$WORK/$blob"

  load_pgpassword
  sql ro postgres "select 'connected as ' || current_user || ' to ' || split_part(version(),' on ',1)"
  sql ro postgres "select 'createdb: ' || rolcreatedb from pg_roles where rolname='$ADMIN'"
  sql ro postgres "select 'can set role $APP_ROLE: ' || pg_has_role('$ADMIN','$APP_ROLE','SET')"
  db_exists "$SCRATCH_DB" && die "NOT READY: $SCRATCH_DB already exists"
  db_exists "$OLD_DB" && die "NOT READY: $OLD_DB already exists"
  echo "PREFLIGHT OK"
}

restore() {
  set_db "${1:-}"
  load_pgpassword
  db_exists "$SCRATCH_DB" && die "refusing: $SCRATCH_DB already exists"
  local blob; blob=$(find_blob "${2:-}")
  [ -n "$blob" ] && [ "$blob" != None ] || die "no matching $SOURCE_DB dump in $ACCOUNT/$CONTAINER"
  download_blob "$blob"
  load_backup_key

  local start=$SECONDS
  # Same owner and CONNECT rule as the live database. Otherwise every role could read this copy.
  sql rw postgres "CREATE DATABASE $SCRATCH_DB OWNER $APP_ROLE"
  sql rw postgres "REVOKE CONNECT ON DATABASE $SCRATCH_DB FROM PUBLIC"

  # --no-acl: the dump's only ACLs are 75 azuresu grants on pg_catalog, which a non-superuser
  # cannot replay. Ownership is kept, because restoring it is part of what is being proved.
  # No -j: the job pipes pg_dump, so the dump has no data offsets and cannot restore in parallel.
  local log="$WORK/restore-$SOURCE_DB.log"
  set +e
  decrypt "$WORK/$blob" | "$PG_RESTORE" -h "$HOST" -U "$ADMIN" -d "$SCRATCH_DB" --no-acl 2> "$log"
  local status=("${PIPESTATUS[@]}")
  set -e
  unset BACKUP_KEY
  rm -f "$WORK/$blob"

  # pg_restore 18 sends SET transaction_timeout, which Postgres 16 rejects. Known and harmless,
  # see the runbook. Anything else is a real error.
  local errors known other
  errors=$(tr -d '\r' < "$log" | grep -c 'error:' || true)
  known=$(tr -d '\r' < "$log" | grep -c 'unrecognized configuration parameter "transaction_timeout"' || true)
  other=$((errors - known))

  echo "dump: $blob"
  echo "elapsed: $((SECONDS - start))s"
  echo "openssl exit ${status[0]}, pg_restore exit ${status[1]}"
  echo "errors: $errors ($known known transaction_timeout, $other other)"
  echo "log: $log"
  [ "${status[0]}" = 0 ] && [ "$other" = 0 ] || die "RESTORE HAD ERRORS, read the log. $SCRATCH_DB is still there."
  echo "RESTORE OK"
}

catalog_query() { cat <<EOF
select 'db encoding/collate/owner', pg_encoding_to_char(encoding) || ' ' || datcollate || ' ' || pg_get_userbyid(datdba) from pg_database where datname=current_database()
union all select 'db acl', datacl::text from pg_database where datname=current_database()
union all select 'schema ' || nspname, pg_get_userbyid(nspowner) || ' ' || coalesce(nspacl::text, 'default') from pg_namespace where nspname !~ '^pg_' and nspname <> 'information_schema'
union all select 'extension ' || extname, extversion from pg_extension
union all select 'table ' || tablename, tableowner from pg_tables where schemaname = '$SCHEMA'
union all select 'column count', count(*)::text from information_schema.columns where table_schema = '$SCHEMA'
union all select 'index count', count(*)::text from pg_indexes where schemaname = '$SCHEMA'
union all select 'constraint count ' || contype::text, count(*)::text from pg_constraint where connamespace = '$SCHEMA'::regnamespace group by contype
union all select 'sequence count', count(*)::text from pg_sequences where schemaname = '$SCHEMA'
EOF
}

# Row count and row hash per table, in one query. Only the count and the hash leave the server.
rows_query() { cat <<EOF
select tablename,
  (xpath('/row/c/text()', query_to_xml(format('select count(*) c from %I.%I', schemaname, tablename), false, true, '')))[1]::text,
  (xpath('/row/h/text()', query_to_xml(format('select md5(coalesce(string_agg(x, chr(10) order by x), %L)) h from (select t::text x from %I.%I t) s', '', schemaname, tablename), false, true, '')))[1]::text
from pg_tables where schemaname = '$SCHEMA'
EOF
}

compare() {
  set_db "${1:-}"
  load_pgpassword
  db_exists "$SCRATCH_DB" || die "$SCRATCH_DB does not exist, run restore first"
  local d; d=$(mktemp -d); trap "rm -rf '$d'" EXIT

  sql ro "$SCRATCH_DB" "$(catalog_query)" | sort > "$d/cat.scratch"
  sql ro "$SOURCE_DB" "$(catalog_query)" | sort > "$d/cat.live"
  echo "== catalog (restored < vs > live; nothing listed means identical)"
  local same=1
  diff "$d/cat.scratch" "$d/cat.live" || same=0
  echo "objects compared: $(wc -l < "$d/cat.live")"

  sql ro "$SCRATCH_DB" "$(rows_query)" | sort > "$d/rows.scratch"
  sql ro "$SOURCE_DB" "$(rows_query)" | sort > "$d/rows.live"
  echo "== tables whose rows differ (table | restored count | live count)"
  join -t '|' -a1 -a2 -e MISSING -o 0,1.2,2.2,1.3,2.3 "$d/rows.scratch" "$d/rows.live" \
    | awk -F'|' '{ if ($4 != $5) { print $1 "|" $2 "|" $3; n++ } else same++ }
                 END { print "tables identical by hash: " same+0 ", differing: " n+0 }'
  [ "$same" = 1 ] && echo "CATALOG IDENTICAL" || echo "CATALOG DIFFERS"
}

rename_db() { sql rw postgres "ALTER DATABASE $1 RENAME TO $2"; }

rename_test() {
  set_db "${1:-}"
  load_pgpassword
  db_exists "$SCRATCH_DB" || die "$SCRATCH_DB does not exist"
  rename_db "$SCRATCH_DB" "${SCRATCH_DB}_rn"
  rename_db "${SCRATCH_DB}_rn" "$SCRATCH_DB"
  echo "RENAME OK"
}

swap() {
  set_db "${1:-}"
  load_pgpassword
  db_exists "$SCRATCH_DB" || die "refusing: $SCRATCH_DB does not exist"
  db_exists "$OLD_DB" && die "refusing: $OLD_DB already exists"
  local live copy
  live=$(db_connections "$SOURCE_DB"); copy=$(db_connections "$SCRATCH_DB")
  [ "$live" = 0 ] && [ "$copy" = 0 ] || die "refusing: connections on $SOURCE_DB: $live, on $SCRATCH_DB: $copy"
  rename_db "$SOURCE_DB" "$OLD_DB"
  rename_db "$SCRATCH_DB" "$SOURCE_DB"
  echo "SWAPPED: $SOURCE_DB is now the restored copy, the original is $OLD_DB"
}

swap_back() {
  set_db "${1:-}"
  load_pgpassword
  db_exists "$OLD_DB" || die "refusing: $OLD_DB does not exist"
  db_exists "$SCRATCH_DB" && die "refusing: $SCRATCH_DB already exists"
  local live old
  live=$(db_connections "$SOURCE_DB"); old=$(db_connections "$OLD_DB")
  [ "$live" = 0 ] && [ "$old" = 0 ] || die "refusing: connections on $SOURCE_DB: $live, on $OLD_DB: $old"
  rename_db "$SOURCE_DB" "$SCRATCH_DB"
  rename_db "$OLD_DB" "$SOURCE_DB"
  echo "SWAPPED BACK: $SOURCE_DB is the original again, the restored copy is $SCRATCH_DB"
}

drop() {
  set_db "${1:-}"
  load_pgpassword
  db_exists "$OLD_DB" && die "refusing: $OLD_DB exists, swap back first"
  if db_exists "$SCRATCH_DB"; then
    sql rw postgres "DROP DATABASE $SCRATCH_DB"
    echo "dropped $SCRATCH_DB"
  else
    echo "$SCRATCH_DB does not exist, nothing to drop"
  fi
  rm -f "$WORK/restore-$SOURCE_DB.log"
  sql ro postgres "select datname from pg_database where datname !~ '^(template|azure)' order by 1"
}

status() {
  local a n
  for a in $APPS; do
    n=$(app_name "$a")
    echo "$a: $(az containerapp revision list -g "$TOOL_RG" -n "$n" --query "[?properties.active].[name,properties.healthState,properties.replicas]" -o tsv | tr -d '\r' | tr '\t\n' ' ;')"
  done
}

# Replicas across every revision the app still lists. A replica list without --revision only looks
# at the latest one, and comes back empty while a deactivated revision's pods are still running.
running_replicas() {
  local n=$1 rev total=0 c
  for rev in $(az containerapp revision list -g "$TOOL_RG" -n "$n" --all --query "[].name" -o tsv | tr -d '\r'); do
    c=$(az containerapp replica list -g "$TOOL_RG" -n "$n" --revision "$rev" --query 'length(@)' -o tsv 2>/dev/null | tr -d '\r' || true)
    total=$((total + ${c:-0}))
  done
  echo "$total"
}

stop() {
  local n; n=$(app_name "${1:-}")
  local rev begin=$SECONDS
  for rev in $(az containerapp revision list -g "$TOOL_RG" -n "$n" --query "[?properties.active].name" -o tsv | tr -d '\r'); do
    az containerapp revision deactivate -g "$TOOL_RG" -n "$n" --revision "$rev" -o none
    echo "deactivated $rev"
  done
  local i active
  for i in $(seq 1 60); do
    active=$(running_replicas "$n")
    [ "$active" = 0 ] && { echo "STOPPED $n, no replicas after $((SECONDS - begin))s"; return; }
    sleep 10
  done
  die "$n still has $active replicas after 10 minutes"
}

start() {
  local n; n=$(app_name "${1:-}")
  local begin=$SECONDS suffix; suffix="drill$(date -u +%m%d%H%M%S)"
  az containerapp update -g "$TOOL_RG" -n "$n" --revision-suffix "$suffix" -o none
  # The update reactivates the revision that was deactivated. Left alone, an old backend connects to
  # whatever database is live, and an old Fuseki retakes the TDB2 lock and deadlocks the new one.
  local rev
  for rev in $(az containerapp revision list -g "$TOOL_RG" -n "$n" --query "[?properties.active && name!='$n--$suffix'].name" -o tsv | tr -d '\r'); do
    az containerapp revision deactivate -g "$TOOL_RG" -n "$n" --revision "$rev" -o none
    echo "deactivated reactivated $rev"
  done
  local i health
  for i in $(seq 1 60); do
    health=$(az containerapp revision show -g "$TOOL_RG" -n "$n" --revision "$n--$suffix" --query properties.healthState -o tsv | tr -d '\r')
    [ "$health" = Healthy ] && { echo "STARTED $n--$suffix, healthy after $((SECONDS - begin))s"; return; }
    sleep 10
  done
  die "$n--$suffix not healthy after 10 minutes, last state: $health"
}

templates() {
  mkdir -p "$WORK"
  local a n line out=""
  for a in $APPS; do
    n=$(app_name "$a")
    # Scale, secrets and containers. Secret entries are names and references, never values.
    line=$(az containerapp show -g "$TOOL_RG" -n "$n" \
      --query "{c:properties.template.containers,s:properties.template.scale,v:properties.template.volumes,sec:properties.configuration.secrets,i:properties.configuration.ingress.targetPort}" -o json \
      | tr -d '\r' | sha256sum | cut -d' ' -f1)
    out+="$a $line"$'\n'
  done
  case "${1:-}" in
    save) printf '%s' "$out" > "$WORK/templates.txt"; echo "saved $(wc -l < "$WORK/templates.txt") template hashes" ;;
    check) diff "$WORK/templates.txt" <(printf '%s' "$out") && echo "TEMPLATES UNCHANGED" ;;
    *) die "templates save|check" ;;
  esac
}

suppress() {
  local value
  case "${1:-}" in on) value=true ;; off) value=false ;; *) die "suppress on|off" ;; esac
  az monitor alert-processing-rule update -g "$SHARED_RG" -n "$SUPPRESS_RULE" --enabled "$value" -o none --only-show-errors
  echo "$SUPPRESS_RULE enabled: $(az monitor alert-processing-rule show -g "$SHARED_RG" -n "$SUPPRESS_RULE" --query properties.enabled -o tsv --only-show-errors | tr -d '\r')"
}

backup() {
  local today; today=$(date -u +%F)
  local existing
  existing=$(az storage blob list --account-name "$ACCOUNT" -c "$CONTAINER" --auth-mode key --only-show-errors \
    --query "length([?contains(name,'$today')])" -o tsv | tr -d '\r')
  [ "$existing" = 0 ] || die "refusing: $existing dumps dated $today exist, the upload would collide"
  local exec_name
  exec_name=$(az containerapp job start -g "$SHARED_RG" -n "$JOB" --query name -o tsv | tr -d '\r')
  echo "started $exec_name"
  local i state
  for i in $(seq 1 60); do
    state=$(az containerapp job execution show -g "$SHARED_RG" -n "$JOB" --job-execution-name "$exec_name" --query properties.status -o tsv | tr -d '\r')
    case "$state" in
      Succeeded) break ;;
      Failed|Stopped|Degraded) die "$exec_name ended $state" ;;
    esac
    sleep 10
  done
  [ "$state" = Succeeded ] || die "$exec_name still $state after 10 minutes"
  echo "$exec_name Succeeded"
  az storage blob list --account-name "$ACCOUNT" -c "$CONTAINER" --auth-mode key --only-show-errors \
    --query "[?contains(name,'$today')].[name,properties.contentLength]" -o tsv | tr -d '\r'
  echo "BACKUP OK"
}

snapshot() {
  local n; n=$(app_name fuseki)
  local replicas; replicas=$(running_replicas "$n")
  [ "$replicas" = 0 ] || die "refusing: Fuseki has $replicas replicas, the store is open"
  az storage share snapshot --account-name "$FUSEKI_ACCOUNT" --name "$FUSEKI_SHARE" --only-show-errors --query snapshot -o tsv | tr -d '\r'
  echo "SNAPSHOT OK"
}

reconciler() {
  local label=${1:-}
  [ -n "$label" ] || die "reconciler <label>"
  [ -t 0 ] || die "run this in your own terminal, it asks for your login"
  command -v jq > /dev/null || die "jq is needed"
  local user pass token
  read -r -p "Keycloak username (realm ismd, ADMIN role): " user
  read -r -s -p "Password: " pass; echo
  # Stdin, not arguments: arguments are visible in the process list.
  token=$(printf %s "$pass" | curl -sS --fail-with-body "$API/auth/realms/ismd/protocol/openid-connect/token" \
    --data-urlencode "grant_type=password" --data-urlencode "client_id=ismd-app" \
    --data-urlencode "username=$user" --data-urlencode "password@-" | jq -r .access_token)
  unset pass
  [ -n "$token" ] && [ "$token" != null ] || die "no token. Check the login and that direct grants work for this user."
  mkdir -p "$WORK"
  local out="$WORK/reconciler-$label.json" code
  code=$(printf 'Authorization: Bearer %s\n' "$token" | curl -sS -X POST -H @- -o "$out" -w '%{http_code}' --max-time 300 "$API/be/api/admin/reconciler/run")
  unset token
  [ "$code" = 200 ] || die "reconciler returned HTTP $code. 403 means this user lacks ADMIN."
  jq '.data | {totalMismatches, ownedRdfConceptsScanned, pgConceptsScanned, graphsScanned, countsByCategory}' "$out"
  echo "saved: $out"
}

reconciler_diff() {
  local a="$WORK/reconciler-${1:-}.json" b="$WORK/reconciler-${2:-}.json"
  [ -f "$a" ] && [ -f "$b" ] || die "reconciler-diff <label a> <label b>, both must be saved reports"
  local f='.data.mismatches[] | [.category, .graphName, .conceptIri] | @tsv'
  diff <(jq -r "$f" "$a" | sort) <(jq -r "$f" "$b" | sort) && echo "REPORTS MATCH"
}

case "${1:-}" in
  preflight|restore|compare|swap|drop|stop|start|status|templates|suppress|backup|snapshot|reconciler)
    cmd=$1; shift; "$cmd" "$@" ;;
  rename-test) shift; rename_test "$@" ;;
  swap-back) shift; swap_back "$@" ;;
  reconciler-diff) shift; reconciler_diff "$@" ;;
  *) sed -n 2,22p "$0" >&2; exit 2 ;;
esac
