#!/bin/bash
# test_staggered_recovery.sh - Simulate staggered recovery of database replicas
# Usage: ./test_staggered_recovery.sh [wait_seconds]

WAIT=${1:-10}

echo "Step 1: Stopping BOTH replicas..."
docker compose stop postgres-replica1 postgres-replica2

echo "Step 2: Waiting $WAIT seconds (All down)..."
sleep $WAIT

echo "Step 3: Starting ONLY postgres-replica2..."
docker compose start postgres-replica2

echo "Step 4: Waiting $WAIT seconds (Replica 2 healthy, Replica 1 down)..."
sleep $WAIT

echo "Status check (R1 should be UNHEALTHY, R2 should be HEALTHY):"
docker compose exec redis redis-cli GET "db_status:replica_1"
docker compose exec redis redis-cli GET "db_status:replica_2"

echo "Step 5: Starting postgres-replica1..."
docker compose start postgres-replica1

echo "Step 6: Final wait for cluster stability..."
sleep 5

echo "Final status (All should be HEALTHY):"
docker compose exec redis redis-cli GET "db_status:replica_1"
docker compose exec redis redis-cli GET "db_status:replica_2"
