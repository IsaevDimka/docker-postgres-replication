#!/usr/bin/env bash

REPL_USER=replicator
REPL_PASS='rwzWbVq29K3lpXYL'
SLOT=replication_slot_slave1

SLAVE_VOL="./volumes/postgresql-slave-data"

wait_pg() {
  local svc="$1"
  local user="${2:-postgres}"
  local timeout="${3:-120}" # seconds
  local waited=0

  echo "▶ Wait ${svc} ready (timeout ${timeout}s)"
  until docker compose exec -T "$svc" pg_isready -U "$user" >/dev/null 2>&1; do
    sleep 3
    waited=$((waited + 3))
    if [ "$waited" -ge "$timeout" ]; then
      echo "❌ Timeout waiting for ${svc}"
      return 1
    fi
  done
}

echo "▶ Start master"
docker compose up -d --force-recreate postgresql-master
sleep 3

wait_pg postgresql-master

echo "▶ Apply configs master"
docker compose exec -T postgresql-master psql -U postgres -v ON_ERROR_STOP=1 <<SQL
ALTER SYSTEM SET listen_addresses = '*';
ALTER SYSTEM SET wal_level = 'replica';
ALTER SYSTEM SET max_wal_senders = 10;
ALTER SYSTEM SET max_replication_slots = 10;
ALTER SYSTEM SET hot_standby = on;
ALTER SYSTEM SET hba_file = '/etc/postgresql/pg_hba.conf';
SQL

docker compose exec -T postgresql-master psql -U postgres -c "select pg_reload_conf();"
docker compose restart postgresql-master

wait_pg postgresql-master

echo "▶ (Optional) show which pg_hba.conf is used"
docker compose exec -T postgresql-master psql -U postgres -c "
SHOW wal_level;
SHOW max_wal_senders;
SHOW max_replication_slots;
SHOW hot_standby;
SHOW listen_addresses;
show hba_file;
"

echo "▶ Init DB + roles"
cat ./scripts/migrations/init.sql | docker compose exec -T postgresql-master psql -U postgres -v ON_ERROR_STOP=1

echo "▶ Ensure replicator"
docker compose exec -T postgresql-master psql -U postgres -v ON_ERROR_STOP=1 <<SQL
DO \$do\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${REPL_USER}') THEN
    CREATE ROLE ${REPL_USER} LOGIN REPLICATION PASSWORD '${REPL_PASS}';
  END IF;
END
\$do\$;
SQL

echo "▶ Ensure slot"
docker compose exec -T postgresql-master psql -U postgres -v ON_ERROR_STOP=1 <<SQL
DO \$do\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='${SLOT}') THEN
    PERFORM pg_create_physical_replication_slot('${SLOT}');
  END IF;
END
\$do\$;
SQL

echo "▶ Basebackup via one-shot container"
docker compose --project-name "${COMPOSE_PROJECT_NAME}" run --rm --no-deps --entrypoint sh postgresql-slave -c "
set -e
pg_basebackup -h postgresql-master -U ${REPL_USER} \
  -D \"\$PGDATA\" \
  -X stream -R -S ${SLOT} -Fp -P
"

echo "▶ Start slave"
docker compose up -d postgresql-slave
sleep 5

wait_pg postgresql-slave

echo "▶ Checks"
docker compose exec -T postgresql-slave psql -U postgres -c "\du"
docker compose exec -T postgresql-slave psql -U postgres -c "select pg_is_in_recovery();"
docker compose exec -T postgresql-master psql -U postgres -c "\du"
docker compose exec -T postgresql-master psql -U postgres -c "select client_addr, state from pg_stat_replication;"

echo "✅ DONE"
