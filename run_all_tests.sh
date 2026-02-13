#!/bin/bash

# Runs all test scripts sequentially.
# Command outputs are suppressed; a status line is printed every second.
# Usage: ./run_all_tests.sh <duration>

if [ -z "$1" ]; then
  echo "Usage: $0 <duration>"
  echo "Example: $0 6"
  exit 1
fi

DURATION=$1

TESTS=(
  "./test_replica_lag.sh $DURATION"
  "./test_both_replicas_lag.sh $DURATION"
  "./test_replica_down.sh $DURATION"
  "./test_both_replicas_down.sh $DURATION"
  "./test_redis_down.sh $DURATION"
)

for test_cmd in "${TESTS[@]}"; do
  echo ""
  echo "=========================================="
  echo "▶ Starting: $test_cmd"
  echo "=========================================="

  # Run command in background, suppress output
  $test_cmd > /dev/null 2>&1 &
  pid=$!

  # Print status line every second
  while kill -0 "$pid" 2>/dev/null; do
    echo "[$(date '+%H:%M:%S')] ⏳ Running: $test_cmd"
    sleep 2
  done

  # Get exit code
  wait "$pid"
  exit_code=$?

  if [ $exit_code -eq 0 ]; then
    echo "[$(date '+%H:%M:%S')] ✅ Completed: $test_cmd"
  else
    echo "[$(date '+%H:%M:%S')] ❌ Failed (exit code: $exit_code): $test_cmd"
  fi
done

echo ""
echo "=========================================="
echo "🏁 All tests completed."
echo "=========================================="
