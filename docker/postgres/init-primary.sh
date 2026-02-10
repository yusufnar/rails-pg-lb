#!/bin/bash
set -e

# Create replication user
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER replication_user REPLICATION LOGIN CONNECTION LIMIT 100 ENCRYPTED PASSWORD 'replication_pass';
EOSQL

# Add replication entry to pg_hba.conf
echo "host replication replication_user 0.0.0.0/0 trust" >> "$PGDATA/pg_hba.conf"
