#!/bin/bash
# test_both_replicas_down.sh - Simulate failure and recovery of all database replicas
# Usage: ./test_both_replicas_down.sh [duration_seconds]

DURATION=${1:-10}

echo "Current status of replicas (before stopping):"
docker compose exec redis redis-cli GET "db_status:replica_1"
docker compose exec redis redis-cli GET "db_status:replica_2"

echo "---"
echo "Step 1: Stopping BOTH postgres-replica1 and postgres-replica2 containers..."
docker compose stop postgres-replica1 postgres-replica2

echo "Step 2: Waiting for $DURATION seconds. Rails balancer should fall back to PRIMARY (writing role)..."
for i in $(seq 1 $DURATION); do
  printf "\rWait: $i/$DURATION seconds..."
  sleep 1
done
echo -e "\n"

echo "Status while replicas are down:"
docker compose exec redis redis-cli GET "db_status:replica_1"
docker compose exec redis redis-cli GET "db_status:replica_2"

echo "---"
echo "Step 3: Starting BOTH replicas back up..."
docker compose start postgres-replica1 postgres-replica2

echo "Step 4: Waiting 5 seconds for recovery..."
sleep 5

echo "Final status (should be HEALTHY on both):"
docker compose exec redis redis-cli GET "db_status:replica_1"
docker compose exec redis redis-cli GET "db_status:replica_2"
