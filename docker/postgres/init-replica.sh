#!/bin/bash
set -e

# Export password for pg_basebackup
export PGPASSWORD='replication_pass'

# Wait for primary to be ready
until pg_isready -h postgres-primary -p 5432 -U replication_user
do
  echo "Waiting for primary..."
  sleep 2
done

# Clear data directory
echo "Cleaning data directory..."
rm -rf "${PGDATA:?}"/*

# Base backup from primary
echo "Starting base backup..."
# Drop slot if exists to avoid error on retry
PGPASSWORD=password psql -h postgres-primary -U postgres -d postgres -c "SELECT pg_drop_replication_slot('replication_slot_$(hostname)');" || true

pg_basebackup -h postgres-primary -D "$PGDATA" -U replication_user -v -P -X stream -C -S replication_slot_$(hostname) -R

echo "Backup complete. Starting PostgreSQL..."
# Change ownership to postgres user
chown -R postgres:postgres "$PGDATA"
chmod 0700 "$PGDATA"

echo "Current user before gosu: $(whoami)"
echo "Executing gosu postgres postgres..."
exec gosu postgres postgres
