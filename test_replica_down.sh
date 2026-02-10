#!/bin/bash
# test_replica_down.sh - Simulate a replica container failure and recovery
# Usage: ./test_replica_down.sh [duration_seconds]

DURATION=${1:-10}
REPLICA="postgres-replica1"

echo "Current status of $REPLICA (before stopping):"
docker compose exec redis redis-cli GET "db_status:replica_1"

echo "---"
echo "Step 1: Stopping $REPLICA container..."
docker compose stop $REPLICA

echo "Step 2: Waiting for $DURATION seconds. Health check will mark it as UNHEALTHY (Role: Unknown)..."
for i in $(seq 1 $DURATION); do
  printf "\rWait: $i/$DURATION seconds..."
  sleep 1
done
echo -e "\n"

echo "Status while container is down:"
docker compose exec redis redis-cli GET "db_status:replica_1"

echo "---"
echo "Step 3: Starting $REPLICA container back up..."
docker compose start $REPLICA

echo "Step 4: Waiting 5 seconds for recovery and replication to sync..."
sleep 5

echo "Final status of $REPLICA (should be HEALTHY):"
docker compose exec redis redis-cli GET "db_status:replica_1"
