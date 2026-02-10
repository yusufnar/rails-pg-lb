#!/bin/bash
# test_primary_down.sh - Simulate a primary database node failure and recovery
# Usage: ./test_primary_down.sh [duration_seconds]

DURATION=${1:-10}
PRIMARY="postgres-primary"

echo "Current status of $PRIMARY (before stopping):"
docker compose exec redis redis-cli GET "db_status:primary"

echo "---"
echo "Step 1: Stopping $PRIMARY container..."
docker compose stop $PRIMARY

echo "Step 2: Waiting for $DURATION seconds. Health check will mark it as UNHEALTHY..."
echo "Note: Reads should still work if replicas are healthy."
for i in $(seq 1 $DURATION); do
  printf "\rWait: $i/$DURATION seconds..."
  sleep 1
done
echo -e "\n"

echo "Status while primary is down:"
docker compose exec redis redis-cli GET "db_status:primary"

echo "---"
echo "Step 3: Starting $PRIMARY container back up..."
docker compose start $PRIMARY

echo "Step 4: Waiting 5 seconds for recovery..."
sleep 5

echo "Final status of $PRIMARY (should be HEALTHY):"
docker compose exec redis redis-cli GET "db_status:primary"
