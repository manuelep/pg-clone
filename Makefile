# -----------------------------
# Configurazione servizi PostgreSQL via .pg_service.conf
# -----------------------------
# Il file .pg_service.conf viene cercato in questo ordine:
#   1. percorso definito in PGSERVICEFILE (variabile d'ambiente o file .env locale)
#   2. ~/.pg_service.conf  (posizione di default su Linux/macOS)
#
# Struttura del file:
#
#   [remote]
#   host=<ip_o_hostname>
#   port=5432
#   user=postgres
#   password=<password_remota>
#
#   [local]
#   host=localhost
#   port=5432
#   user=postgres
#   password=<password_locale>

# Include .env se presente — utile per sovrascrivere variabili senza toccare il Makefile
-include .env

# Strip spazi/tab finali dalle variabili lette da .env
# (editor e copia-incolla lasciano spesso whitespace invisibile a fine riga)
PGPORT         := $(strip $(PGPORT))
PGCONNECT_TIMEOUT := $(strip $(PGCONNECT_TIMEOUT))
CONTAINER_NAME := $(strip $(CONTAINER_NAME))
DOCKER_IMAGE   := $(strip $(DOCKER_IMAGE))
REMOTE_SERVICE := $(strip $(REMOTE_SERVICE))
LOCAL_SERVICE  := $(strip $(LOCAL_SERVICE))
SSH_HOST       := $(strip $(SSH_HOST))
SSH_USER       := $(strip $(SSH_USER))
SSH_TUNNEL_PORT := $(strip $(SSH_TUNNEL_PORT))

# Percorso del file .pg_service.conf
# Priorità: 1) PGSERVICEFILE da ambiente o .env  2) ~/.pg_service.conf
PG_SERVICE_FILE ?= $(or $(PGSERVICEFILE),$(HOME)/.pg_service.conf)

# Nomi dei servizi (come definiti in .pg_service.conf)
REMOTE_SERVICE ?= remote
LOCAL_SERVICE  ?= local

# Cartelle locali
DUMP_DIR   := $(PWD)/dumps
INITDB_DIR := $(PWD)/initdb.d

# Immagine Docker — usata per dump remoto (via tunnel) e restore locale.
# Deve corrispondere il più possibile alla versione remota.
DOCKER_IMAGE   ?= postgis/postgis:16-3.5
CONTAINER_NAME ?= pg_init

PGPORT      ?= 5432
PERSISTENT  ?= no
DATA_VOLUME ?= $(PWD)/pgdata

# Estrae user e password dal servizio locale nel .pg_service.conf.
# Valutazione lazy tramite $(wildcard) per evitare errori awk al parse time.
_PG_SERVICE_EXISTS := $(wildcard $(PG_SERVICE_FILE))
_extract = $(if $(_PG_SERVICE_EXISTS),$(shell awk -F'=' '/^\[$(1)\]/{f=1;next} f && /^$(2)[\t ]*=/{gsub(/^[^=]*=[[:space:]]*/,"",$$0);gsub(/[[:space:]]*$$/,"",$$0);print;exit} f && /^\[/{exit}' $(PG_SERVICE_FILE)),)

PGUSER     ?= $(call _extract,$(LOCAL_SERVICE),user)
PGPASSWORD ?= $(call _extract,$(LOCAL_SERVICE),password)

# Credenziali remote estratte dal service file (usate per la connessione via tunnel)
_REMOTE_USER     := $(call _extract,$(REMOTE_SERVICE),user)
_REMOTE_PASSWORD := $(call _extract,$(REMOTE_SERVICE),password)

# Timeout di connessione in secondi (0 = attesa infinita)
PGCONNECT_TIMEOUT ?= 10

# Bind mount del file di servizio (usato dai container Docker per il restore locale)
PG_SERVICE_MOUNT := -v $(PG_SERVICE_FILE):/root/.pg_service.conf:ro \
                    -e PGSERVICEFILE=/root/.pg_service.conf

# Opzione per inibire il dump dei dati (es: make dump DATA=no)
DATA ?= yes

# -----------------------------
# Tunnel SSH
#
# Il tunnel espone la porta PostgreSQL remota su localhost, permettendo
# ai container Docker di raggiungerla via --network host senza problemi
# di VPN o routing.
#
# Schema:
#   Docker (--network host) → localhost:SSH_TUNNEL_PORT
#     → [SSH] → SSH_HOST → REMOTE_PG_HOST:REMOTE_PG_PORT
#
# Configurazione nel .env:
#   SSH_HOST=bastion.example.com   # host SSH (può coincidere con il server pg)
#   SSH_USER=myuser                # utente SSH (default: utente corrente)
#   SSH_TUNNEL_PORT=15432          # porta locale del tunnel (default: 15432)
#   SSH_OPTS=-i ~/.ssh/id_rsa      # opzioni SSH aggiuntive (opzionale)
#
# Il target pg remoto viene letto automaticamente da .pg_service.conf
# -----------------------------

SSH_HOST         ?=
SSH_USER         ?= $(USER)
SSH_TUNNEL_PORT  ?= 15432
SSH_OPTS         ?=

# Host e porta remoti estratti da .pg_service.conf
_REMOTE_PG_HOST := $(call _extract,$(REMOTE_SERVICE),host)
_REMOTE_PG_PORT := $(call _extract,$(REMOTE_SERVICE),port)

# File PID del tunnel (uno per progetto, basato su SSH_TUNNEL_PORT)
_TUNNEL_PID_FILE := /tmp/pg-clone-tunnel-$(SSH_TUNNEL_PORT).pid

# Opzioni Docker per i comandi remoti (via tunnel su localhost)
_TUNNEL_DOCKER_OPTS := --rm \
                       --network host \
                       -e PGHOST=localhost \
                       -e PGPORT=$(SSH_TUNNEL_PORT) \
                       -e PGUSER=$(_REMOTE_USER) \
                       -e PGPASSWORD=$(_REMOTE_PASSWORD) \
                       -e PGCONNECT_TIMEOUT=$(PGCONNECT_TIMEOUT)

# -----------------------------
# Gestione tunnel SSH
# -----------------------------

.PHONY: tunnel-open
tunnel-open:
	@if [ -z "$(SSH_HOST)" ]; then \
		echo ""; \
		echo "ERRORE: SSH_HOST non impostato."; \
		echo "  Aggiungi nel .env:"; \
		echo "    SSH_HOST=<host_ssh>"; \
		echo "    SSH_USER=<utente_ssh>       # opzionale, default: $(USER)"; \
		echo "    SSH_TUNNEL_PORT=15432       # opzionale, default: 15432"; \
		echo "    SSH_OPTS=-i ~/.ssh/id_rsa   # opzionale"; \
		echo ""; \
		exit 1; \
	fi
	@if [ -f "$(_TUNNEL_PID_FILE)" ] && kill -0 $$(cat $(_TUNNEL_PID_FILE)) 2>/dev/null; then \
		echo "    tunnel già attivo (PID $$(cat $(_TUNNEL_PID_FILE)))"; \
	else \
		echo "=== Apertura tunnel SSH ==="; \
		echo "    $(SSH_USER)@$(SSH_HOST) → localhost:$(SSH_TUNNEL_PORT) → $(_REMOTE_PG_HOST):$(_REMOTE_PG_PORT)"; \
		ssh -f -N \
			-L $(SSH_TUNNEL_PORT):$(_REMOTE_PG_HOST):$(_REMOTE_PG_PORT) \
			-o ExitOnForwardFailure=yes \
			-o StrictHostKeyChecking=accept-new \
			$(SSH_OPTS) \
			$(SSH_USER)@$(SSH_HOST); \
		pgrep -n -f "ssh.*$(SSH_TUNNEL_PORT):$(_REMOTE_PG_HOST)" > $(_TUNNEL_PID_FILE); \
		echo "    tunnel aperto (PID $$(cat $(_TUNNEL_PID_FILE)))"; \
	fi

.PHONY: tunnel-close
tunnel-close:
	@if [ -f "$(_TUNNEL_PID_FILE)" ]; then \
		PID=$$(cat $(_TUNNEL_PID_FILE)); \
		if kill -0 $$PID 2>/dev/null; then \
			kill $$PID && echo "=== Tunnel SSH chiuso (PID $$PID) ==="; \
		else \
			echo "    tunnel non attivo"; \
		fi; \
		rm -f $(_TUNNEL_PID_FILE); \
	else \
		echo "    nessun tunnel attivo trovato"; \
	fi

.PHONY: tunnel-status
tunnel-status:
	@if [ -f "$(_TUNNEL_PID_FILE)" ] && kill -0 $$(cat $(_TUNNEL_PID_FILE)) 2>/dev/null; then \
		echo "    tunnel ATTIVO (PID $$(cat $(_TUNNEL_PID_FILE)))"; \
		echo "    localhost:$(SSH_TUNNEL_PORT) → $(_REMOTE_PG_HOST):$(_REMOTE_PG_PORT) via $(SSH_USER)@$(SSH_HOST)"; \
	else \
		echo "    tunnel NON attivo"; \
	fi

# -----------------------------
# Preflight: verifica che .pg_service.conf esista
# -----------------------------

.PHONY: check-pg-service
check-pg-service:
	@if [ ! -f "$(PG_SERVICE_FILE)" ]; then \
		echo ""; \
		echo "ERRORE: file di configurazione non trovato:"; \
		echo "  $(PG_SERVICE_FILE)"; \
		echo ""; \
		echo "Crea il file con questa struttura:"; \
		echo ""; \
		echo "  [$(REMOTE_SERVICE)]"; \
		echo "  host=<host_remoto>"; \
		echo "  port=5432"; \
		echo "  user=postgres"; \
		echo "  password=<password_remota>"; \
		echo ""; \
		echo "  [$(LOCAL_SERVICE)]"; \
		echo "  host=localhost"; \
		echo "  port=5432"; \
		echo "  user=postgres"; \
		echo "  password=<password_locale>"; \
		echo ""; \
		echo "Oppure imposta PGSERVICEFILE nel tuo ambiente o in un file .env locale."; \
		echo ""; \
		exit 1; \
	fi

# -----------------------------
# Preflight: verifica connessione remota via tunnel
# Distingue: tunnel non attivo, servizio non trovato, timeout, password errata
# -----------------------------

.PHONY: check-remote-connection
check-remote-connection: check-pg-service tunnel-open
	@echo "=== Verifica connessione al servizio remoto [$(REMOTE_SERVICE)] via tunnel ==="
	@echo "    localhost:$(SSH_TUNNEL_PORT) → $(_REMOTE_PG_HOST):$(_REMOTE_PG_PORT)"
	@ERR=$$(docker run \
		$(_TUNNEL_DOCKER_OPTS) \
		$(DOCKER_IMAGE) \
		psql -c "SELECT 1" 2>&1 >/dev/null); \
	RC=$$?; \
	if [ $$RC -eq 0 ]; then \
		echo "    connessione OK"; \
	elif echo "$$ERR" | grep -qiE "timeout|timed out|unreachable|no route|Connection refused"; then \
		echo ""; \
		echo "ERRORE: impossibile connettersi tramite tunnel."; \
		echo "  Dettaglio: $$ERR"; \
		echo ""; \
		echo "  Possibili cause:"; \
		echo "    - tunnel non ancora pronto (riprova tra qualche secondo)"; \
		echo "    - SSH_HOST o credenziali SSH errati"; \
		echo "    - il server pg remoto non è raggiungibile da $(SSH_HOST)"; \
		echo ""; \
		exit 1; \
	elif echo "$$ERR" | grep -qiE "password authentication failed|no password supplied"; then \
		echo ""; \
		echo "ERRORE: autenticazione PostgreSQL fallita."; \
		echo "  Dettaglio: $$ERR"; \
		echo ""; \
		echo "  Verifica la password nella sezione [$(REMOTE_SERVICE)] di $(PG_SERVICE_FILE)"; \
		echo ""; \
		exit 1; \
	else \
		echo ""; \
		echo "ERRORE: connessione fallita."; \
		echo "  Dettaglio: $$ERR"; \
		echo ""; \
		exit 1; \
	fi

# -----------------------------
# Dump schema (sempre: utenti, ruoli, tablespace)
# -----------------------------

.PHONY: dump-schema
dump-schema: check-remote-connection $(DUMP_DIR)
	@echo "=== Dump globale schema + utenti ==="
	@if [ ! -f ./databases.txt ]; then \
		docker run \
			$(_TUNNEL_DOCKER_OPTS) \
			-v $(DUMP_DIR):/dumps \
			$(DOCKER_IMAGE) \
			pg_dumpall --schema-only > $(DUMP_DIR)/cluster_schema.sql; \
	else \
		echo "= Calcolo esclusioni da databases.txt ="; \
		ALL_DBS=$$(docker run \
			$(_TUNNEL_DOCKER_OPTS) \
			$(DOCKER_IMAGE) \
			psql -Atc "SELECT datname FROM pg_database WHERE datistemplate = false;"); \
		EXCLUDE_ARGS=""; \
		for db in $$ALL_DBS; do \
			if ! grep -qxw "$$db" databases.txt; then \
				EXCLUDE_ARGS="$$EXCLUDE_ARGS --exclude-database=$$db"; \
			fi; \
		done; \
		docker run \
			$(_TUNNEL_DOCKER_OPTS) \
			-v $(DUMP_DIR):/dumps \
			$(DOCKER_IMAGE) \
			pg_dumpall --schema-only $$EXCLUDE_ARGS > $(DUMP_DIR)/cluster_schema.sql; \
	fi
	@echo "=== Schema salvato in $(DUMP_DIR)/cluster_schema.sql ==="

# -----------------------------
# Dump dati completo (tutti i db o filtrati da databases.txt)
# -----------------------------

.PHONY: dump-data
dump-data: check-pg-service $(DUMP_DIR)
	@if [ ! -f ./databases.txt ]; then \
		echo "=== Dump dati: tutti i database ==="; \
		docker run \
			$(_TUNNEL_DOCKER_OPTS) \
			$(DOCKER_IMAGE) \
			psql -Atc "SELECT datname FROM pg_database WHERE datistemplate = false;" \
		| while read db; do \
			echo "== Dump dati: $$db =="; \
			docker run \
				$(_TUNNEL_DOCKER_OPTS) \
				-v $(DUMP_DIR):/dumps \
				$(DOCKER_IMAGE) \
				pg_dump -a -Fc -d "$$db" -f /dumps/"$$db"_data.dump; \
		done; \
	else \
		echo "=== Dump dati: database in databases.txt ==="; \
		while read -r db || [ -n "$$db" ]; do \
			if [ -z "$$db" ]; then continue; fi; \
			echo "== Dump dati: $$db =="; \
			docker run \
				$(_TUNNEL_DOCKER_OPTS) \
				-v $(DUMP_DIR):/dumps \
				$(DOCKER_IMAGE) \
				pg_dump -a -Fc -d "$$db" -f /dumps/"$$db"_data.dump; \
		done < databases.txt; \
	fi
	@echo "=== Dump dati completato ==="

# -----------------------------
# Dump dati mirati per tabelle specifiche (da tables.txt)
#
# Formato tables.txt — una riga per tabella:
#   db:schema:tabella
#
# Esempio:
#   mydb:public:users
#   mydb:analytics:events
#   otherdb:public:orders
#
# Se databases.txt esiste, i db non presenti in esso vengono ignorati.
# Output: un file per database -> <db>_data.dump
# -----------------------------

.PHONY: dump-tables
dump-tables: check-pg-service $(DUMP_DIR)
	@echo "=== Dump dati mirati da tables.txt ==="
	@sort -t: -k1,1 tables.txt | awk -F: '{print $$1}' | uniq | while read db; do \
		if [ -f ./databases.txt ] && ! grep -qxw "$$db" databases.txt; then \
			echo "!! [$$db] non è in databases.txt: ignorato"; \
			continue; \
		fi; \
		TABLE_ARGS=$$(grep "^$$db:" tables.txt | awk -F: '{printf "-t %s.%s ", $$2, $$3}'); \
		echo "== Dump tabelle di [$$db]: $$TABLE_ARGS =="; \
		docker run \
			$(_TUNNEL_DOCKER_OPTS) \
			-v $(DUMP_DIR):/dumps \
			$(DOCKER_IMAGE) \
			pg_dump -a -Fc -d "$$db" $$TABLE_ARGS -f /dumps/"$$db"_data.dump; \
	done
	@echo "=== Dump tabelle completato ==="

# -----------------------------
# Target principale
#
# Comportamento:
#   make dump           -> schema + dati completi (o filtrati da databases.txt)
#   make dump DATA=no   -> solo schema, nessun dato
#   make dump           -> se tables.txt esiste: schema + dump tabelle mirate
#                         (tables.txt ha precedenza su dump-data)
#
# Il tunnel SSH viene aperto automaticamente e lasciato attivo al termine.
# Per chiuderlo: make tunnel-close
# -----------------------------

.PHONY: dump
dump: dump-schema
	@if [ "$(DATA)" = "no" ]; then \
		echo "=== Solo schema richiesto (DATA=no): dump dati saltato ==="; \
	elif [ -f ./tables.txt ]; then \
		echo "=== tables.txt trovato: dump dati mirati ==="; \
		$(MAKE) dump-tables; \
	else \
		$(MAKE) dump-data; \
	fi

$(DUMP_DIR):
	mkdir -p $(DUMP_DIR)

# -----------------------------
# Docker init per ripristino locale
# -----------------------------

# Opzioni ottimizzate per importazione massiva di dati
DOCKER_OPTS := --name $(CONTAINER_NAME) \
	-e POSTGRES_USER=$(PGUSER) \
	-e POSTGRES_PASSWORD=$(PGPASSWORD) \
	-p 0.0.0.0:$(PGPORT):5432 \
	-v $(INITDB_DIR):/docker-entrypoint-initdb.d \
	-v $(DUMP_DIR):/dumps \
	$(PG_SERVICE_MOUNT) \
	--shm-size=512mb \
	-e POSTGRES_INITDB_ARGS="--auth-host=scram-sha-256"

.PHONY: check-local-credentials
check-local-credentials: check-pg-service
	@if [ -z "$(PGUSER)" ] || [ -z "$(PGPASSWORD)" ]; then \
		echo ""; \
		echo "ERRORE: credenziali locali non trovate."; \
		echo "  PGUSER    = '$(PGUSER)'"; \
		echo "  PGPASSWORD= '$(PGPASSWORD)'"; \
		echo ""; \
		echo "  Verifica che $(PG_SERVICE_FILE) contenga una sezione:"; \
		echo "  [$(LOCAL_SERVICE)]"; \
		echo "  user=<utente>"; \
		echo "  password=<password>"; \
		echo ""; \
		echo "  Se la sezione ha un nome diverso, imposta LOCAL_SERVICE nel .env:"; \
		echo "  LOCAL_SERVICE=nome-sezione"; \
		echo ""; \
		exit 1; \
	fi

.PHONY: docker-init
docker-init: check-local-credentials
	@echo "Pulizia container esistenti..."
	@docker rm -f $(CONTAINER_NAME) >/dev/null 2>&1 || true
	@echo "Avvio container con tuning per caricamento dati..."
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

# Alias comodi
.PHONY: run-local-db log stop
run-local-db: docker-init

log:
	@docker logs -f $(CONTAINER_NAME)

stop:
	@docker stop $(CONTAINER_NAME)