# Changelog

## [1.1.0] - 2026-03-20

### ⚠️ Breaking Changes

- **Rimossa la gestione delle credenziali tramite `.env`** — le password non transitano più dal Makefile né dal file `.env`. Tutta la configurazione di connessione (host, porta, utente, password) è ora delegata al file `.pg_service.conf`, seguendo le convenzioni standard di libpq.
- La variabile `PGPASS_FILE` e il mount di `.pgpass` sono stati eliminati.
- Le variabili `REMOTE_HOST`, `REMOTE_PGUSER`, `REMOTE_PGPORT` sono state eliminate. Sostituire con una sezione nel `.pg_service.conf`.

### ✨ Nuove funzionalità

#### Autenticazione via `.pg_service.conf`
- Il file di servizio viene cercato automaticamente in `PGSERVICEFILE` (da ambiente o `.env`) oppure in `~/.pg_service.conf` (default Linux/macOS).
- Il percorso può essere sovrascritto tramite la variabile `PGSERVICEFILE` nel `.env` locale.
- `PGUSER` e `PGPASSWORD` per il container di restore locale vengono estratti automaticamente dalla sezione `[local]` del file di servizio.

#### Dump modulare
- Introdotti target separati e componibili:
  - `make dump-schema` — solo schema globale (utenti, ruoli, tablespace)
  - `make dump-data` — solo dati, completi o filtrati da `databases.txt`
  - `make dump-tables` — solo dati delle tabelle specificate in `tables.txt`
  - `make dump` — orchestratore principale (comportamento configurabile)
- `make dump DATA=no` — esegue solo lo schema, salta interamente il dump dei dati.

#### Dump mirato per tabelle (`tables.txt`)
- Nuovo file opzionale `tables.txt` con formato `db:schema:tabella` (una riga per tabella).
- Le tabelle dello stesso database vengono raggruppate in una singola invocazione di `pg_dump` per efficienza.
- Output: un file per database → `<db>_tables_data.dump`.
- Se `databases.txt` è presente, le tabelle appartenenti a database non inclusi vengono saltate con avviso esplicito.
- Quando `tables.txt` è presente, ha precedenza sul dump completo dei dati nel target `dump`.

#### Logica di priorità del target `dump`
| Condizione | Comportamento |
|---|---|
| `DATA=no` | Solo schema |
| `tables.txt` presente | Schema + dump tabelle mirate |
| `databases.txt` presente | Schema + dati filtrati per db |
| Nessun file di filtro | Schema + dati completi |

#### Preflight check
- Nuovo target `check-pg-service`: verifica che `.pg_service.conf` esista e mostra istruzioni dettagliate in caso di assenza.
- Nuovo target `check-remote-connection`: esegue una connessione di test (`SELECT 1`) prima di avviare il dump. Distingue e segnala con messaggi specifici:
  - Sezione di servizio non trovata nel file
  - Timeout / server irraggiungibile (con suggerimenti su VPN e firewall)
  - Autenticazione fallita (password errata o mancante)
  - Qualsiasi altro errore con dettaglio grezzo
- `check-remote-connection` è prerequisito automatico di `dump-schema`.
- `check-pg-service` è prerequisito di tutti i target che usano Docker.

#### Timeout di connessione configurabile
- Nuova variabile `PGCONNECT_TIMEOUT` (default: `10` secondi). Sovrascrivibile da `.env` o da riga di comando (`make dump PGCONNECT_TIMEOUT=30`). Valore `0` = attesa infinita.

#### Rete Docker configurabile per comandi remoti
- Nuova variabile `REMOTE_NETWORK` (default: `host`) che controlla la rete Docker usata dai container che parlano con il server remoto.
- `host` è necessario per raggiungere server dietro VPN o tunnel SSH locali.
- Il commento nel Makefile avvisa esplicitamente di non impostare `bridge` in presenza di VPN.

### 🔧 Modifiche interne

- Introdotta variabile `REMOTE_DOCKER_OPTS` che centralizza le opzioni comuni (`--network`, mount service file, `PGSERVICE`, `PGCONNECT_TIMEOUT`) per tutti i `docker run` remoti, eliminando la ripetizione.
- La valutazione di `PGUSER` e `PGPASSWORD` è ora **lazy**: usa `$(wildcard)` + `$(if ...)` per evitare errori `awk` al parse time di Make quando il file di servizio non esiste ancora.
- Il filtro `databases.txt` ora si applica coerentemente sia al dump dello schema (`pg_dumpall --exclude-database`) che al dump dei dati.
- `docker-init` dipende ora da `check-pg-service`.

### 📄 Documentazione

- `README.md` aggiornato integralmente: rimossi i riferimenti a `.pgpass` e alle variabili di connessione deprecate; documentati `.pg_service.conf`, tutti i nuovi target, `tables.txt`, note sulla connettività VPN/tunnel SSH e lista file da aggiungere al `.gitignore`.