# Docker PostgreSQL Replication

Docker PostgreSQL Master-Slave Replication, run:
```shell
make init
```

If changed env `COMPOSE_PROJECT_NAME` need change docker container name in `images/postgresql-slave/postgresql.auto.conf`

## Requirements:

* Docker

## Check Replication Status:

```shell
docker compose exec -it postgresql-slave psql -U postgres -c "select pg_is_in_recovery();"
docker compose exec postgresql-master psql -U postgres -c \
"select client_addr, state from pg_stat_replication;"
```

## License
[MIT License](LICENSE) (MIT)
