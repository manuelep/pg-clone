# pg-clone

Uno strumento semplice per **clonare un cluster PostgreSQL remoto in locale** usando `pg_dumpall` e `pg_dump`, con supporto a container Docker PostGIS.

## ✨ Funzionalità

- Estrae lo **schema globale** (utenti, ruoli, tablespace, ecc.) con `pg_dumpall --schema-only`
- Estrae i **dati** di ogni database in dump compressi (`pg_dump -Fc`)
- Supporta `.pgpass` per l’autenticazione senza password
- Permette il **ripristino automatico** in un container Docker PostGIS
- Modalità con o senza **persistenza del volume dati**
- Compatibile Linux e macOS (comandi standard Docker/Makefile)

## 📦 Prerequisiti

- [Docker](https://docs.docker.com/get-docker/)
- [Make](https://www.gnu.org/software/make/)
- Accesso a un cluster PostgreSQL remoto
- File `.pgpass` configurato con le credenziali

## 🔧 Configurazione

Tutte le variabili principali sono configurabili via ambiente o modificando il `Makefile`:

```makefile
REMOTE_HOST     = my.remote.host
REMOTE_PGUSER   = postgres
REMOTE_PGPORT   = 5432

PGUSER          = postgres
PGPASSWORD      = secret
PGPORT          = 5432

DUMP_DIR        = $(PWD)/dumps
INITDB_DIR      = $(PWD)/initdb.d
DATA_VOLUME     = $(PWD)/pgdata
PERSISTENT      = no
```

## 🚀 Utilizzo

1. Eseguire il dump dal server remoto
    ```sh
    make dump
    ```
    Risultato:
    - dumps/cluster_schema.sql → schema globale
    - dumps/<dbname>_data.dump → dati dei singoli database

2. Avviare un container locale con ripristino automatico
    ```sh
    make run-local-db
    ```
    Il container:
    - Avvia PostgreSQL/PostGIS
    - Applica lo schema (cluster_schema.sql)
    - Ripristina i dati (*_data.dump)

3. Controllare i log del container
    ```sh
    make log
    ```

4. Arrestare e rimuovere il container
    ```sh
    docker stop pg_init
    ```

# 📂 Struttura repo
```bash
.
├── Makefile
├── dumps/        # qui vengono scritti i dump
├── initdb.d/     # script di ripristino (restore_all.sh)
└── pgdata/       # volume dati (se PERSISTENT=yes)
````

# ⚠️ Note

- Non è una “replica streaming”, ma un clone leggero via dump (snapshot del cluster).
- L'uso in ambienti di produzione non è raccomandato.
- Pensato per sviluppo, testing e data recovery.

✍️ Autore: Manuele Pesenti
Licenza: MIT