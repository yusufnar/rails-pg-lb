#!/bin/bash
set -e

echo "Cleaning up inactive replication slots..."
docker exec rails-db-lb-postgres-primary-1 psql -U postgres -c "
DO \$\$
DECLARE
  slot_record RECORD;
BEGIN
  FOR slot_record IN SELECT slot_name FROM pg_replication_slots WHERE active = false LOOP
    PERFORM pg_drop_replication_slot(slot_record.slot_name);
    RAISE NOTICE 'Dropped replication slot: %', slot_record.slot_name;
  END LOOP;
END \$\$;
"
echo "Cleanup complete."
