#!/bin/bash

echo "Starting traffic generation... Press Ctrl+C to stop."

count=0
while true; do
  ((count++))
  TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
  echo "Inserting record #$count at $TIMESTAMP"

  docker compose exec -T postgres-primary psql -U postgres -d app_development -c \
    "INSERT INTO ynars (content, created_at, updated_at) VALUES ('Traffic test $TIMESTAMP', NOW(), NOW());" > /dev/null

  if (( count % 1000 == 0 )); then
    echo "Count reached $count. Truncating 'ynars' table..."
    docker compose exec -T postgres-primary psql -U postgres -d app_development -c 'TRUNCATE TABLE ynars;' > /dev/null
  fi

  sleep 1
done
