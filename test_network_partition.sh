#!/bin/bash
# test_network_partition.sh - Simulate a network partition between Primary and a Replica
# Usage: ./test_network_partition.sh [replica_host] [duration_seconds]

REPLICA_HOST="${1:-postgres-replica1}"
DURATION="${2:-30}"
PRIMARY_HOST="postgres-primary"

echo "Target Replica: $REPLICA_HOST"
echo "Duration: $DURATION seconds"

# 1. Install iptables if missing
echo "Checking for iptables in $REPLICA_HOST..."
if ! docker compose exec -u root "$REPLICA_HOST" which iptables > /dev/null; then
    echo "iptables not found. Installing..."
    docker compose exec -u root "$REPLICA_HOST" bash -c "apt-get update && apt-get install -y iptables"
else
    echo "iptables is already installed."
fi

# 2. Get Primary IP
PRIMARY_IP=$(docker compose exec "$REPLICA_HOST" getent hosts "$PRIMARY_HOST" | awk '{ print $1 }')
echo "Primary IP resolved to: $PRIMARY_IP"

if [ -z "$PRIMARY_IP" ]; then
    echo "Error: Could not resolve Primary IP."
    exit 1
fi

# 3. Apply Network Partition
echo "Simulating network partition: Blocking traffic from/to $PRIMARY_HOST ($PRIMARY_IP) on $REPLICA_HOST..."
docker compose exec -u root "$REPLICA_HOST" iptables -A OUTPUT -d "$PRIMARY_IP" -j DROP
docker compose exec -u root "$REPLICA_HOST" iptables -A INPUT -s "$PRIMARY_IP" -j DROP

echo "Partition active. Monitoring behavior..."

# 4. Monitor Loop
END_TIME=$((SECONDS + DURATION))
while [ $SECONDS -lt $END_TIME ]; do
    REMAINING=$((END_TIME - SECONDS))
    printf "\rTime remaining: %2d seconds. Checking status..." "$REMAINING"

    # Check replica status from Redis (or application logs if preferred)
    # This assumes your app writes status to Redis. If not, we can just check docker logs or something else.
    # For now, let's just show the lag if available, or just wait.

    sleep 1
done
echo -e "\nNetwork partition simulation finished."

# 5. Restore Connectivity
echo "Restoring connectivity..."
docker compose exec -u root "$REPLICA_HOST" iptables -D OUTPUT -d "$PRIMARY_IP" -j DROP
docker compose exec -u root "$REPLICA_HOST" iptables -D INPUT -s "$PRIMARY_IP" -j DROP

echo "Done."
