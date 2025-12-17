#!/usr/bin/env bash

MASTER=postgresql-master
SLAVE=postgresql-slave
REPL_USER=replicator
REPL_PASS='rwzWbVq29K3lpXYL'
SLOT=replication_slot_slave1

MASTER_VOL="./volumes/postgresql-master-data"
SLAVE_VOL="./volumes/postgresql-slave-data"

docker compose up -d --force-recreate ${MASTER}
sleep 3
echo "▶ Stop master (to apply pg_hba.conf on startup)"
docker compose stop ${MASTER} || true

echo "▶ Apply configs into master volume BEFORE start"
mkdir -p "${MASTER_VOL}"
cp ./images/postgresql-master/postgresql.conf ./volumes/postgresql-master-data/data/postgresql.conf
cp ./images/postgresql-master/pg_hba.conf ./volumes/postgresql-master-data/data/pg_hba.conf

echo "▶ Start master"
docker compose up -d --force-recreate ${MASTER}

echo "▶ Wait master ready"
until docker compose exec -T ${MASTER} pg_isready -U postgres >/dev/null 2>&1; do
  sleep 2
done

echo "▶ (Optional) show which pg_hba.conf is used"
docker compose exec -T ${MASTER} psql -U postgres -tAc "show hba_file;" || true

echo "▶ Init DB + roles"
cat ./scripts/migrations/init.sql | docker compose exec -T ${MASTER} psql -U postgres -v ON_ERROR_STOP=1

echo "▶ Ensure replicator"
docker compose exec -T ${MASTER} psql -U postgres -v ON_ERROR_STOP=1 <<SQL
DO \$do\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${REPL_USER}') THEN
    CREATE ROLE ${REPL_USER} LOGIN REPLICATION PASSWORD '${REPL_PASS}';
  END IF;
END
\$do\$;
SQL

echo "▶ Ensure slot"
docker compose exec -T ${MASTER} psql -U postgres -v ON_ERROR_STOP=1 <<SQL
DO \$do\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='${SLOT}') THEN
    PERFORM pg_create_physical_replication_slot('${SLOT}');
  END IF;
END
\$do\$;
SQL

echo "▶ Stop slave + wipe data"
docker compose stop ${SLAVE} || true
rm -rf "${SLAVE_VOL:?}/"*
mkdir -p "${SLAVE_VOL}"

echo "▶ Basebackup via one-shot container"
docker compose run --rm --no-deps --entrypoint sh ${SLAVE} -c "
set -e
pg_basebackup -h ${MASTER} -U ${REPL_USER} \
  -D \"\$PGDATA\" \
  -X stream -R -S ${SLOT} -Fp -P
"

echo "▶ Start slave"
docker compose up -d ${SLAVE}
sleep 5

echo "▶ Checks"
docker compose exec -T ${SLAVE} psql -U postgres -c "select pg_is_in_recovery();"
docker compose exec -T ${MASTER} psql -U postgres -c "select client_addr, state from pg_stat_replication;"
docker compose exec -T ${SLAVE} psql -U postgres -c "\du"

echo "✅ DONE"
