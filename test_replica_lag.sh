#!/bin/bash
# test_replica_lag.sh - Simulate replication lag on postgres-replica1
# Usage: ./test_replica_lag.sh [duration_seconds]

DURATION=${1:-10}

echo "Current status of replica1 (before pausing):"
docker compose exec redis redis-cli GET "db_status:replica_1"

echo "---"
echo "Step 1: Pausing WAL replay on postgres-replica1..."
docker compose exec -u postgres postgres-replica1 psql -c "SELECT pg_wal_replay_pause();"

echo "Step 2: Advancing WAL on primary to trigger lag detection..."
docker compose exec -u postgres postgres-primary psql -c "INSERT INTO ynars (content, created_at, updated_at) VALUES ('Manual Lag Check at $(date)', NOW(), NOW());"

echo "Step 3: Waiting for $DURATION seconds. Monitoring will detect lag > 1s..."
for i in $(seq 1 $DURATION); do
  printf "\rWait: $i/$DURATION seconds..."
  sleep 1
done
echo -e "\n"

echo "Status of replica1 during lag (should be UNHEALTHY):"
docker compose exec redis redis-cli GET "db_status:replica_1"

echo "---"
echo "Step 4: Resuming WAL replay on postgres-replica1..."
docker compose exec -u postgres postgres-replica1 psql -c "SELECT pg_wal_replay_resume();"

echo "Step 5: Waiting 5 seconds for recovery..."
sleep 5

echo "Final status of replica1 (should be HEALTHY):"
docker compose exec redis redis-cli GET "db_status:replica_1"
