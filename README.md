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

Tutte le variabili principali sono configurabili creando un file `.env` nella root del progetto. Questo file viene letto automaticamente dal `Makefile`.

Copia e personalizza il seguente esempio:

```env
# --- Server Remoto ---
REMOTE_HOST=144.76.198.119      # L'indirizzo IP o l'host del server da clonare
REMOTE_PGPORT=5434              # Porta del server remoto (standard: 5432)

# --- Container Locale ---
# Adatta il più possibile la versione del dbms locale a quella remota per una piena compatibilità
DOCKER_IMAGE=postgis/postgis:16-3.5
CONTAINER_NAME=pg_init          # Nome del container locale

# La porta locale 5432 è già occupata da un altro Postgres? 
# Impostane una diversa (es. 5435) per evitare conflitti:
PGPORT=5432                     

# Scegli una password robusta per il superutente del tuo ambiente locale:
PGPASSWORD=changemeWithSomethingR3allySecure!

# Vuoi che i dati sopravvivano al riavvio del container?
# 'yes' crea una cartella 'pgdata' locale, 'no' (default) tiene tutto in memoria (effimero):
PERSISTENT=no
```

### Note

- Scegli l'immagine migliore tra quelle disponibili su [hub.docker.com](https://hub.docker.com/search?q=postgresql).
- Personalizza il nome del container locale per una migliore riconoscibilità del servizio una volta avviato sul tuo sistema.

## 🎯 Selezione dei Database (Opzionale)

Per impostazione predefinita, `make dump` esegue il backup di **tutti** i database presenti sul server remoto. Se desideri clonare solo alcuni database specifici, puoi utilizzare il file `databases.txt`.

1. Crea un file chiamato `databases.txt` nella root del progetto.
2. Elenca i nomi dei database desiderati, uno per riga:
3. Eseguendo `make dump`, lo strumento:
    - Escluderà automaticamente tutti gli altri database dal dump dello schema globale.
    - Estrarrà i dati solo per i database elencati.

Se il file databases.txt non esiste, il sistema tornerà automaticamente alla modalità "dump completo".

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
```

# Note e Troubleshooting
Database di grandi dimensioni: Se il ripristino fallisce per timeout o spazio disco esaurito su tabelle molto pesanti (es. log storici o posizioni GPS), considera di escludere i dati di quelle tabelle modificando il Makefile con l'opzione `--exclude-table-data="schema.nome_tabella"`.

Spazio disco Docker: Su macOS, se ricevi l'errore No space left on device, aumenta il limite del disco virtuale nelle impostazioni di Docker Desktop (Resources > Advanced > Disk image location).

Trigger e Vincoli: Il ripristino viene eseguito con --disable-triggers per evitare errori di validazione logica o cicli di aggiornamento sulle Viste Materializzate durante l'importazione dei dati.

# ⚠️ Note

- Non è una “replica streaming”, ma un clone leggero via dump (snapshot del cluster).
- L'uso in ambienti di produzione non è raccomandato.
- Pensato per sviluppo, testing e data recovery.
- Versione di Postgresql consigliata 16+

## 🤝 Contribuire al progetto

I contributi sono benvenuti 🎉  
Se utilizzi **pg-clone** e hai esigenze particolari, idee di miglioramento o riscontri problemi, puoi contribuire in diversi modi:

### 🐞 Issue e richieste di supporto
- Apri una **Issue** per:
  - segnalare bug o comportamenti inattesi
  - richiedere supporto per casi d’uso specifici (es. cluster complessi, grandi volumi di dati, configurazioni particolari)
  - proporre nuove funzionalità o miglioramenti
- Quando possibile, includi:
  - sistema operativo
  - versione di PostgreSQL/PostGIS
  - output dei comandi e log rilevanti

### 🔧 Sviluppo e nuove implementazioni
- Puoi **clonare il repository**, implementare le tue modifiche e proporre una **Pull Request**
- Le PR piccole, focalizzate e ben documentate sono preferite
- Sentiti libero di ricondividere fork o adattamenti per i tuoi flussi di lavoro

### 🚧 Idee per sviluppi futuri
Alcune possibili evoluzioni del progetto:
- Supporto a **Windows** (MobaXterm / PowerShell / WSL / Makefile alternativo)
- Selettori avanzati per schema e tabelle (inclusioni/esclusioni)
- Verifica automatica di compatibilità tra versione remota e locale di PostgreSQL/PostGIS

Ogni contributo, anche minimo (documentazione, test, feedback), è utile e apprezzato.


✍️ Autore: Manuele Pesenti
Licenza: MIT
