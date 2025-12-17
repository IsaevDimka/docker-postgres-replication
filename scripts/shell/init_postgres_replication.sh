#!/usr/bin/env bash
set -euo pipefail

MASTER=postgresql-master
SLAVE=postgresql-slave
REPL_USER=replicator
REPL_PASS='rwzWbVq29K3lpXYL'
SLOT=replication_slot_slave1

MASTER_VOL="./volumes/postgresql-master-data"
SLAVE_VOL="./volumes/postgresql-slave-data"

echo "▶ Stop master (clean apply configs)"
docker compose stop "${MASTER}" || true

echo "▶ Apply configs into master volume BEFORE start"
mkdir -p "${MASTER_VOL}/data"
cp ./images/postgresql-master/postgresql.conf "${MASTER_VOL}/data/postgresql.conf"
cp ./images/postgresql-master/pg_hba.conf      "${MASTER_VOL}/data/pg_hba.conf"

echo "▶ Start master"
docker compose up -d --force-recreate "${MASTER}"

echo "▶ Wait master ready"
until docker compose exec -T "${MASTER}" pg_isready -U postgres >/dev/null 2>&1; do
  sleep 2
done

echo "▶ Show active hba_file + replication rules (debug)"
docker compose exec -T "${MASTER}" psql -U postgres -tAc "show hba_file;"
docker compose exec -T "${MASTER}" sh -lc '
HBA="$(psql -U postgres -tAc "show hba_file" | xargs)"
echo "--- ACTIVE HBA: $HBA"
grep -n "replication" "$HBA" || true
'

echo "▶ Init DB + roles"
cat ./scripts/migrations/init.sql | docker compose exec -T "${MASTER}" psql -U postgres -v ON_ERROR_STOP=1

echo "▶ Ensure replicator"
docker compose exec -T "${MASTER}" psql -U postgres -v ON_ERROR_STOP=1 <<SQL
DO \$do\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='${REPL_USER}') THEN
    CREATE ROLE ${REPL_USER} LOGIN REPLICATION PASSWORD '${REPL_PASS}';
  END IF;
END
\$do\$;
SQL

echo "▶ Ensure slot"
docker compose exec -T "${MASTER}" psql -U postgres -v ON_ERROR_STOP=1 <<SQL
DO \$do\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name='${SLOT}') THEN
    PERFORM pg_create_physical_replication_slot('${SLOT}');
  END IF;
END
\$do\$;
SQL

echo "▶ Stop slave + wipe data"
docker compose stop "${SLAVE}" || true
rm -rf "${SLAVE_VOL:?}/"*
mkdir -p "${SLAVE_VOL}"

# ВАЖНО: делаем basebackup НЕ через `compose run` (в CI это часто другая сеть),
# и НЕ стираем PGDATA у живого postgres (иначе Error 137).
# Поэтому: поднимаем контейнер SLAVE, но сразу выполняем basebackup и рестартим.
echo "▶ Start slave container (for basebackup only)"
docker compose up -d --force-recreate "${SLAVE}"

echo "▶ Wait slave container ready (pg_isready)"
until docker compose exec -T "${SLAVE}" pg_isready -U postgres >/dev/null 2>&1; do
  sleep 2
done

echo "▶ Stop postgres inside slave container (avoid wiping live PGDATA)"
# мягко остановим сервер внутри контейнера
docker compose exec -T "${SLAVE}" sh -lc 'pg_ctl -D "$PGDATA" -m fast stop || true'

echo "▶ Run pg_basebackup FROM SLAVE into its PGDATA"
docker compose exec -T "${SLAVE}" sh -lc "
set -e
rm -rf \"\$PGDATA\"/*
pg_basebackup -h ${MASTER} -U ${REPL_USER} \
  -D \"\$PGDATA\" \
  -X stream -R -S ${SLOT} -Fp -P
"

echo "▶ Start slave (as standby)"
docker compose restart "${SLAVE}"
sleep 5

echo "▶ Checks"
docker compose exec -T "${SLAVE}" psql -U postgres -c "select pg_is_in_recovery();"
docker compose exec -T "${MASTER}" psql -U postgres -c "select client_addr, state from pg_stat_replication;"
docker compose exec -T "${SLAVE}" psql -U postgres -c "\du"

echo "✅ DONE"
