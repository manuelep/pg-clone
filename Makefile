# -----------------------------
# Configurazione server remoto
# -----------------------------
REMOTE_HOST ?= your.remote.host
REMOTE_PGUSER ?= postgres
REMOTE_PGPORT ?= 5432

# Cartelle locali
DUMP_DIR := $(PWD)/dumps
INITDB_DIR := $(PWD)/initdb.d

# Docker/PostGIS locale
DOCKER_IMAGE := postgis/postgis:16-3.5
CONTAINER_NAME := pg_init
PGUSER ?= postgres
PGPORT ?= 5432
PGPASSWORD ?= changemeWithSomethingR3allySecure!
PERSISTENT ?= no
DATA_VOLUME ?= $(PWD)/pgdata

# File pgpass locale
PGPASS_FILE ?= $(HOME)/.pgpass

# -----------------------------
# Dump globale + dati via container locale
# -----------------------------
.PHONY: dump
dump: $(DUMP_DIR)
	@echo "=== Dump globale schema + utenti ==="
	docker run --rm -v $(DUMP_DIR):/dumps -v $(PGPASS_FILE):/root/.pgpass:ro \
		-e PGPASSFILE=/root/.pgpass $(DOCKER_IMAGE) \
		pg_dumpall --schema-only -U $(REMOTE_PGUSER) -h $(REMOTE_HOST) -p $(REMOTE_PGPORT) > $(DUMP_DIR)/cluster_schema.sql

	@echo "=== Dump dati per ogni database ==="
	docker run --rm -v $(DUMP_DIR):/dumps -v $(PGPASS_FILE):/root/.pgpass:ro \
		-e PGPASSFILE=/root/.pgpass $(DOCKER_IMAGE) bash -c "\
		psql -U $(REMOTE_PGUSER) -h $(REMOTE_HOST) -p $(REMOTE_PGPORT) -Atc \"SELECT datname FROM pg_database WHERE datistemplate = false;\" \
	" | while read db; do \
		docker run --rm -v $(DUMP_DIR):/dumps -v $(PGPASS_FILE):/root/.pgpass:ro \
			-e PGPASSFILE=/root/.pgpass $(DOCKER_IMAGE) \
			pg_dump -a -Fc -U $(REMOTE_PGUSER) -h $(REMOTE_HOST) -p $(REMOTE_PGPORT) \
			-d $$db -f /dumps/$$db"_data.dump"; \
	done
	@echo "=== Dump completato nella cartella $(DUMP_DIR) ==="


$(DUMP_DIR):
	mkdir -p $(DUMP_DIR)

# -----------------------------
# Docker init per ripristino
# -----------------------------
DOCKER_OPTS := --name $(CONTAINER_NAME) -e POSTGRES_USER=$(PGUSER) -e POSTGRES_PASSWORD=$(PGPASSWORD) -p $(PGPORT):5432 \
               -v $(INITDB_DIR):/docker-entrypoint-initdb.d -v $(DUMP_DIR):/dumps

.PHONY: docker-init
docker-init:
	@echo "Avvio container PostgreSQL con PostGIS..."
ifeq ($(PERSISTENT),yes)
	docker run $(DOCKER_OPTS) -v $(DATA_VOLUME):/var/lib/postgresql/data -d $(DOCKER_IMAGE)
else
	docker run $(DOCKER_OPTS) --rm -d $(DOCKER_IMAGE)
endif
	@echo "Attesa che il container sia pronto..."
	@while ! docker exec $(CONTAINER_NAME) pg_isready -U $(PGUSER) >/dev/null 2>&1; do \
		sleep 2; \
	done
	@echo "Container pronto! Tutti i dump saranno stati ripristinati automaticamente."

# Alias comodo
.PHONY: run-local-db log stop
run-local-db: docker-init

log:
	@docker logs -f pg_init

stop:
	@docker stop pg_init