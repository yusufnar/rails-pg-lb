#!/bin/bash
# test_both_replica_lag.sh - Simulate replication lag on both replicas
# Usage: ./test_both_replica_lag.sh [duration_seconds]

DURATION=${1:-10}

echo "Current status of replicas (before pausing):"
docker compose exec redis redis-cli GET "db_status:replica_1"
docker compose exec redis redis-cli GET "db_status:replica_2"

echo "---"
echo "Step 1: Pausing WAL replay on BOTH postgres-replica1 and postgres-replica2..."
docker compose exec -u postgres postgres-replica1 psql -d app_development -c "SELECT pg_wal_replay_pause();"
docker compose exec -u postgres postgres-replica2 psql -d app_development -c "SELECT pg_wal_replay_pause();"

echo "Step 2: Advancing WAL on primary to trigger lag detection..."
docker compose exec -u postgres postgres-primary psql -d app_development -c "INSERT INTO ynars (content, created_at, updated_at) VALUES ('Both Replicas Lag Check at $(date)', NOW(), NOW());"

echo "Step 3: Waiting for $DURATION seconds. Monitoring will detect lag > 1s on both..."
for i in $(seq 1 $DURATION); do
  printf "\rWait: $i/$DURATION seconds..."
  sleep 1
done
echo -e "\n"

echo "Status during lag (should be UNHEALTHY on both):"
docker compose exec redis redis-cli GET "db_status:replica_1"
docker compose exec redis redis-cli GET "db_status:replica_2"

echo "---"
echo "Step 4: Resuming WAL replay on BOTH replicas..."
docker compose exec -u postgres postgres-replica1 psql -d app_development -c "SELECT pg_wal_replay_resume();"
docker compose exec -u postgres postgres-replica2 psql -d app_development -c "SELECT pg_wal_replay_resume();"

echo "Step 5: Waiting 5 seconds for recovery..."
sleep 5

echo "Final status (should be HEALTHY on both):"
docker compose exec redis redis-cli GET "db_status:replica_1"
docker compose exec redis redis-cli GET "db_status:replica_2"
