#!/bin/bash

echo "Docker up postgresql-master and postgresql-slave"
docker compose up -d --force-recreate postgresql-master postgresql-slave

while [ -z "$(docker compose logs postgresql-master | grep 'database system is ready to accept connections')" ]
do
  echo "awaiting postgresql initialization for 5s..."
  sleep 5
done

echo 'Copy from master postgresql.conf'
cp ./images/postgresql-master/postgresql.conf ./volumes/postgresql-master-data/postgresql.conf
echo 'Copy from master pg_hba.conf'
cp ./images/postgresql-master/pg_hba.conf ./volumes/postgresql-master-data/pg_hba.conf
echo 'Create user replicator'
docker-compose exec -it postgresql-master sh -c "psql -h localhost -p 5432 -U postgres -c 'CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD '\''rwzWbVq29K3lpXYL'\'';'"
sleep 3
echo 'Create replication_slot_slave1'
docker-compose exec -it postgresql-master sh -c "psql -h localhost -p 5432 -U postgres -c 'SELECT * FROM pg_create_physical_replication_slot('\''replication_slot_slave1'\'');'"
sleep 3
docker-compose exec -it postgresql-master sh -c "psql -h localhost -p 5432 -U postgres -c 'SELECT * FROM pg_replication_slots;'"
sleep 3
echo 'Running pg_basebackup'
docker-compose exec -it postgresql-master sh -c "pg_basebackup -D /var/lib/postgresql/data/postgres-slave -S replication_slot_slave1 -X stream -P -U replicator -Fp -R"
sleep 5
echo 'Make postgresql-slave-data'
rm -rf ./volumes/postgresql-slave-data/*
echo 'Move backup from master to slave'
mv ./volumes/postgresql-master-data/postgres-slave/* ./volumes/postgresql-slave-data
echo 'Cleanup backup folder'
rm -rf ./volumes/postgresql-master-data/postgres-slave
echo 'Copy slave postgresql.conf'
cp ./images/postgresql-slave/postgresql.conf ./volumes/postgresql-slave-data/postgresql.conf
echo 'Copy slave postgresql.auto.conf'
cp ./images/postgresql-slave/postgresql.auto.conf ./volumes/postgresql-slave-data/postgresql.auto.conf
echo 'Restart postgresql-master'
docker-compose restart postgresql-master
sleep 5
echo 'Build postgresql-slave'
docker-compose up -d --build postgresql-slave
