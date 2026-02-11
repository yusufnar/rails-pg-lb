#!/bin/bash
# test_redis_down.sh - Simulate Redis failure

REDIS_CONTAINER="rails-db-lb-redis-1"
DURATION=${1:-10}

echo "Step 1: Checking initial status..."
docker ps | grep $REDIS_CONTAINER

echo "Step 2: Stopping Redis container..."
docker stop $REDIS_CONTAINER

echo "Step 3: Waiting for $DURATION seconds (Redis is DOWN)..."
for ((i=1; i<=DURATION; i++)); do
  echo "Time elapsed: $i/$DURATION seconds"
  sleep 1
done

echo "Step 4: Checking logs for Circuit Breaker message..."
docker logs rails-db-lb-web-1 --tail 50 | grep "Circuit breaker opened" || echo "Circuit breaker message not found in recent logs."

echo "Step 5: Restarting Redis..."
docker start $REDIS_CONTAINER

echo "Step 6: Waiting for Redis to recover..."
sleep 1
docker ps | grep $REDIS_CONTAINER

echo "Test complete."
