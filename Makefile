include .env
export $(shell sed 's/=.*//' .env)

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
DOCKER_IMAGE ?= postgis/postgis:16-3.5
CONTAINER_NAME ?= pg_init
PGUSER ?= postgres
PGPORT ?= 5432
PGPASSWORD ?= changemeWithSomethingR3allySecure!
PERSISTENT ?= no
DATA_VOLUME ?= $(PWD)/pgdata

ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# File pgpass locale
PGPASS_FILE ?= $(HOME)/.pgpass

# -----------------------------
# Dump globale + dati via container locale
# -----------------------------
.PHONY: dump-all
dump-all: $(DUMP_DIR)
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

.PHONY: dump
dump: $(DUMP_DIR)
	@if [ ! -f ./databases.txt ]; then \
		$(MAKE) dump-all; \
	else \
		echo "= 1 = Calcolo database da escludere ==="; \
		ALL_DBS=$$(docker run --rm -v $(PGPASS_FILE):/root/.pgpass:ro -e PGPASSFILE=/root/.pgpass $(DOCKER_IMAGE) \
			psql -U $(REMOTE_PGUSER) -h $(REMOTE_HOST) -p $(REMOTE_PGPORT) -Atc "SELECT datname FROM pg_database WHERE datistemplate = false;"); \
		EXCLUDE_ARGS=""; \
		for db in $$ALL_DBS; do \
			if ! grep -qxw "$$db" databases.txt; then \
				EXCLUDE_ARGS="$$EXCLUDE_ARGS --exclude-database=$$db"; \
			fi; \
		done; \
		echo "= 2 = Dump globale schema + utenti ==="; \
		docker run --rm -v $(DUMP_DIR):/dumps -v $(PGPASS_FILE):/root/.pgpass:ro \
			-e PGPASSFILE=/root/.pgpass $(DOCKER_IMAGE) \
			pg_dumpall --schema-only $$EXCLUDE_ARGS -U $(REMOTE_PGUSER) -h $(REMOTE_HOST) -p $(REMOTE_PGPORT) > $(DUMP_DIR)/cluster_schema.sql; \
		echo "= 3 = Dump dati per database selezionati ==="; \
		while read -r db || [ -n "$$db" ]; do \
			if [ -z "$$db" ]; then continue; fi; \
			echo "== Processo dati per: $$db =="; \
			docker run --rm -v $(DUMP_DIR):/dumps -v $(PGPASS_FILE):/root/.pgpass:ro \
				-e PGPASSFILE=/root/.pgpass $(DOCKER_IMAGE) \
				pg_dump -a -Fc -U $(REMOTE_PGUSER) -h $(REMOTE_HOST) -p $(REMOTE_PGPORT) \
				-d "$$db" -f /dumps/"$$db"_data.dump; \
		done < databases.txt; \
		echo "=== Dump completato con successo ==="; \
	fi

$(DUMP_DIR):
	mkdir -p $(DUMP_DIR)

# -----------------------------
# Docker init per ripristino
# -----------------------------
# Opzioni ottimizzate per importazione massiva di dati
DOCKER_OPTS := --name $(CONTAINER_NAME) \
               -e POSTGRES_USER=$(PGUSER) \
               -e POSTGRES_PASSWORD=$(PGPASSWORD) \
               -p 0.0.0.0:$(PGPORT):5432 \
               -v $(INITDB_DIR):/docker-entrypoint-initdb.d \
               -v $(DUMP_DIR):/dumps \
               --shm-size=512mb \
               -e POSTGRES_INITDB_ARGS="--auth-host=scram-sha-256"

# Comando di avvio modificato con parametri di tuning
.PHONY: docker-init
docker-init:
	@echo "Pulizia container esistenti..."
	@docker rm -f $(CONTAINER_NAME) >/dev/null 2>&1 || true
	@echo "Avvio container con Tuning per caricamento dati..."
	docker run $(DOCKER_OPTS) -d $(DOCKER_IMAGE) \
		-c max_wal_size=10GB \
		-c checkpoint_timeout=1h \
		-c synchronous_commit=off \
		-c full_page_writes=off \
		-c fsync=off
	@echo "Attesa che il container sia pronto..."
	@while ! docker exec $(CONTAINER_NAME) pg_isready -U $(PGUSER) >/dev/null 2>&1; do \
		sleep 2; \
	done
	@echo "Container pronto!"
# Alias comodo
.PHONY: run-local-db log stop
run-local-db: docker-init

log:
	@docker logs -f $(CONTAINER_NAME)

stop:
	@docker stop $(CONTAINER_NAME)
