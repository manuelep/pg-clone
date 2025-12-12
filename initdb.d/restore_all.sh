#!/bin/bash
set -e

PGUSER=${POSTGRES_USER:-postgres}
DUMP_DIR=/dumps

# Attendi che il server PostgreSQL sia pronto
until pg_isready -U "$PGUSER"; do
  echo "Attesa server PostgreSQL..."
  sleep 2
done

echo "=== Inizio ripristino database ==="

# 1️⃣ Ripristino dump globale schema + utenti
if [ -f "$DUMP_DIR/cluster_schema.sql" ]; then
    echo "--- Ripristino schema globale ---"
    psql -U "$PGUSER" -f "$DUMP_DIR/cluster_schema.sql"
fi

# 2️⃣ Ripristino dump dati per ciascun database
for data_file in "$DUMP_DIR"/*_data.dump; do
    [ -f "$data_file" ] || continue
    db_name=$(basename "$data_file" _data.dump)
    echo "--- Ripristino dati di $db_name in corso ---"
    pg_restore -v --disable-triggers -U "$PGUSER" -d "$db_name" "$data_file"
    echo "--- Ripristino dati di $db_name completato ---"
done

echo "=== Ripristino completato ==="
