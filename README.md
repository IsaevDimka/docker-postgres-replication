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
docker exec -it postgresql-master bash
```

```shell
psql_master
```
* After entering psql
  ```sql
  SELECT * FROM pg_stat_replication;
  ```

## License
[MIT License](LICENSE) (MIT)
