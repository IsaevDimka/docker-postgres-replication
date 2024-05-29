# suppress output, run `make XXX V=` to be verbose
V := @

COMPOSE_FILE := -f docker-compose.yml

THIS_FILE := $(lastword $(MAKEFILE_LIST))

include .env

.DEFAULT_GOAL : help
help:
	@make -pRrq  -f $(THIS_FILE) : 2>/dev/null | awk -v RS= -F: '/^# File/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | grep -E -v -e '^[^[:alnum:]]' -e '^$@$$'

.PHONY: init
init: \
	init-postgres-replication \
	init-postgres-migrations \
	docker-up

.PHONY: docker-down
docker-down:
	$(V)COMPOSE_PROFILES=${COMPOSE_PROFILES} docker compose down --volumes

.PHONY: docker-clear
docker-clear: docker-down
docker-clear:
	$(V)echo "Remove ./volumes"
	$(V)rm -rf ./volumes

.PHONY: docker-up
docker-up:
	$(V)docker compose pull
	$(V)$(eval LOCAL_IP=$(shell echo `hostname -I | awk '{print $$1}'`))
	$(V)docker compose build --build-arg local_ip=$(LOCAL_IP)
	$(V)docker compose up -d

.PHONY: init-postgres-replication
init-postgres-replication:
	$(V)sh scripts/shell/init_postgres_replication.sh

.PHONY: init-postgres-migrations
init-postgres-migrations:
	$(V)cat "./scripts/migrations/init.sql" | docker compose exec -T postgresql-master psql -h localhost -p 5432 -U postgres 1>/dev/null 2>&1
