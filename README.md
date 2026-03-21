# pg-clone

Uno strumento semplice per **clonare un cluster PostgreSQL remoto in locale** usando `pg_dumpall` e `pg_dump`, con supporto a container Docker PostGIS.

## ✨ Funzionalità

- Estrae lo **schema globale** (utenti, ruoli, tablespace, ecc.) con `pg_dumpall --schema-only`
- Estrae i **dati** di ogni database in dump compressi (`pg_dump -Fc`)
- Supporta `.pg_service.conf` per la gestione centralizzata delle connessioni
- Permette il **ripristino automatico** in un container Docker PostGIS
- Modalità con o senza **persistenza del volume dati**
- Dump dati **opzionale** (`DATA=no`) per ottenere solo il modello
- Dump **mirato per tabelle** tramite file `tables.txt`
- Preflight check automatici su file di configurazione e connessione remota
- Compatibile Linux e macOS (comandi standard Docker/Makefile)

## 📦 Prerequisiti

- [Docker](https://docs.docker.com/get-docker/)
- [Make](https://www.gnu.org/software/make/)
- Accesso a un cluster PostgreSQL remoto
- File `.pg_service.conf` configurato con le credenziali (vedi sotto)

## 🔧 Configurazione

### File `.pg_service.conf`

Le credenziali di connessione vengono gestite tramite il file `.pg_service.conf`, seguendo le convenzioni standard di PostgreSQL. Il file viene cercato in questo ordine:

1. Percorso definito in `PGSERVICEFILE` (variabile d'ambiente o file `.env` locale)
2. `~/.pg_service.conf` (posizione di default su Linux/macOS)

Struttura del file:

```ini
[remote]
host=144.76.198.119
port=5434
user=postgres
password=<password_remota>

[local]
host=localhost
port=5432
user=postgres
password=<password_locale>
```

> **Importante:** non committare `.pg_service.conf` nel repository. Aggiungilo al `.gitignore`.

### File `.env`

Il file `.env` nella root del progetto permette di personalizzare il comportamento del Makefile senza modificarlo. Nessuna password deve transitare da qui.

```env
# --- Connessione remota ---
REMOTE_SERVICE=remote           # Nome della sezione in .pg_service.conf
PGCONNECT_TIMEOUT=10            # Timeout connessione in secondi (0 = infinito)

# --- Rete Docker per comandi remoti ---
# host  = condivide lo stack di rete dell'host (necessario con VPN)
# bridge = rete Docker isolata (solo per server direttamente raggiungibili)
# REMOTE_NETWORK=host

# --- Container locale ---
DOCKER_IMAGE=postgis/postgis:16-3.5   # Adattare alla versione remota
CONTAINER_NAME=pg_init
PGPORT=5432
PERSISTENT=no                         # 'yes' per mantenere i dati tra riavvii
```

### Note sulla connettività remota

Se il server remoto è raggiungibile solo tramite **VPN**, impostare `REMOTE_NETWORK=host` (o lasciare il default) affinché i container Docker condividano lo stack di rete dell'host e vedano il tunnel VPN.

Se il server è esposto tramite **tunnel SSH**, aprire il tunnel prima di eseguire il dump:

```bash
# Espone la porta remota su localhost
ssh -N -f -L 0.0.0.0:5555:xxx.xxx.xxx.xxx:5432 user@ssh-host
```

E configurare il servizio in `.pg_service.conf` puntando a `localhost:5555`.

## 🎯 Selezione dei Database (Opzionale)

Per impostazione predefinita `make dump` opera su **tutti** i database del cluster. Per limitare l'operazione a un sottoinsieme, creare un file `databases.txt` nella root del progetto con un database per riga:

```
mydb
otherdb
```

Il filtro si applica sia al dump dello schema che al dump dei dati.

## 📋 Dump mirato per tabelle (Opzionale)

Per scaricare i dati di sole tabelle specifiche, creare un file `tables.txt` con il formato `db:schema:tabella`, una riga per tabella:

```
mydb:public:users
mydb:analytics:events
otherdb:public:orders
```

- Se `databases.txt` è presente, le tabelle appartenenti a database non inclusi vengono **ignorate**.
- L'output è un file per database: `<db>_tables_data.dump`.
- Se `tables.txt` è presente, ha precedenza sul dump completo dei dati.

## 🚀 Utilizzo

### 1. Dump dal server remoto

```sh
make dump
```

Comportamento:

| Condizione | Risultato |
|---|---|
| Default | Schema + dati completi |
| `databases.txt` presente | Schema + dati filtrati per i db elencati |
| `tables.txt` presente | Schema + dati delle sole tabelle elencate |
| `make dump DATA=no` | Solo schema, nessun dato |

Output nella cartella `dumps/`:
- `cluster_schema.sql` — schema globale
- `<dbname>_data.dump` — dati completi per database
- `<dbname>_tables_data.dump` — dati mirati per tabelle

È anche possibile invocare i target separatamente:

```sh
make dump-schema          # solo schema
make dump-data            # solo dati completi
make dump-tables          # solo tabelle da tables.txt
```

### 2. Avviare il container locale con ripristino automatico

```sh
make run-local-db
```

Il container:
- Avvia PostgreSQL/PostGIS
- Applica lo schema (`cluster_schema.sql`)
- Ripristina i dati (`*_data.dump`, `*_tables_data.dump`)

### 3. Controllare i log del container

```sh
make log
```

### 4. Arrestare il container

```sh
make stop
```

## 📂 Struttura repo

```
.
├── Makefile
├── .env               # configurazione locale (non committare)
├── databases.txt      # filtro database (opzionale, non committare)
├── tables.txt         # filtro tabelle (opzionale, non committare)
├── dumps/             # dump generati
├── initdb.d/          # script di ripristino (restore_all.sh)
└── pgdata/            # volume dati (se PERSISTENT=yes)
```

## 🔒 File da aggiungere al `.gitignore`

```
.env
.pg_service.conf
databases.txt
tables.txt
dumps/
pgdata/
```

## Note e Troubleshooting

**Database di grandi dimensioni:** se il ripristino fallisce per timeout o spazio disco esaurito su tabelle molto pesanti, considera di escludere i dati di quelle tabelle con `--exclude-table-data="schema.nome_tabella"` nel Makefile.

**Spazio disco Docker:** su macOS, se ricevi l'errore `No space left on device`, aumenta il limite del disco virtuale nelle impostazioni di Docker Desktop (Resources > Advanced > Disk image location).

**Trigger e Vincoli:** il ripristino viene eseguito con `--disable-triggers` per evitare errori di validazione logica o cicli di aggiornamento sulle Viste Materializzate durante l'importazione dei dati.

**Preflight check:** prima di ogni dump, il Makefile verifica automaticamente che il file `.pg_service.conf` esista e che la connessione remota sia raggiungibile. In caso di errore viene mostrato un messaggio diagnostico con le possibili cause.

## ⚠️ Note

- Non è una "replica streaming", ma un clone leggero via dump (snapshot del cluster).
- L'uso in ambienti di produzione non è raccomandato.
- Pensato per sviluppo, testing e data recovery.
- Versione di PostgreSQL consigliata: 16+

## 🤝 Contribuire al progetto

I contributi sono benvenuti 🎉  
Se utilizzi **pg-clone** e hai esigenze particolari, idee di miglioramento o riscontri problemi, puoi contribuire in diversi modi:

### 🐞 Issue e richieste di supporto

Apri una **Issue** per:
- segnalare bug o comportamenti inattesi
- richiedere supporto per casi d'uso specifici (es. cluster complessi, grandi volumi di dati, configurazioni particolari)
- proporre nuove funzionalità o miglioramenti

Quando possibile, includi: sistema operativo, versione di PostgreSQL/PostGIS, output dei comandi e log rilevanti.

### 🔧 Sviluppo e nuove implementazioni

- Clona il repository, implementa le modifiche e proponi una **Pull Request**
- Le PR piccole, focalizzate e ben documentate sono preferite
- Sentiti libero di ricondividere fork o adattamenti per i tuoi flussi di lavoro

### 🚧 Idee per sviluppi futuri

- Supporto a **Windows** (MobaXterm / PowerShell / WSL / Makefile alternativo)
- Selettori avanzati per schema e tabelle (inclusioni/esclusioni)
- Verifica automatica di compatibilità tra versione remota e locale di PostgreSQL/PostGIS

Ogni contributo, anche minimo (documentazione, test, feedback), è utile e apprezzato.

✍️ Autore: Manuele Pesenti  
Licenza: MIT
