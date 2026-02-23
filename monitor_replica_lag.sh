#!/bin/bash

QUERY="WITH stats AS (
    SELECT 
        pg_last_wal_receive_lsn() as receive_lsn,
        (pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn()) as is_sync,
        COALESCE(EXTRACT(EPOCH FROM (now() - pg_last_xact_replay_timestamp())), 0) as lag_s
),
wal_recv AS (
    SELECT
        status as replication_status,
        EXTRACT(EPOCH FROM (now() - last_msg_send_time)) as last_msg_send_lag_s,                  
        EXTRACT(EPOCH FROM (now() - last_msg_receipt_time)) as last_msg_receipt_lag_s,
        EXTRACT(EPOCH FROM (last_msg_receipt_time - last_msg_send_time)) as transport_lag_s,
        EXTRACT(EPOCH FROM (now() - latest_end_time)) as last_wal_end_lag_s
    FROM pg_stat_wal_receiver
)
SELECT 
    COALESCE(receive_lsn::text, 'N/A'),
    COALESCE(is_sync::text, 'N/A'),
    COALESCE(replication_status::text, 'N/A'),
    COALESCE(ROUND(lag_s::numeric, 3)::text, 'N/A'),
    COALESCE((CASE WHEN is_sync THEN 0 ELSE ROUND(lag_s::numeric, 3) END)::text, 'N/A'),
    COALESCE(ROUND(last_msg_receipt_lag_s::numeric, 3)::text, 'N/A'),
    COALESCE(ROUND(last_msg_send_lag_s::numeric, 3)::text, 'N/A'),
    COALESCE(ROUND(transport_lag_s::numeric, 3)::text, 'N/A'),
    COALESCE(ROUND(last_wal_end_lag_s::numeric, 3)::text, 'N/A')
FROM stats
LEFT JOIN wal_recv ON true;"

echo "Starting replica lag monitor... Press Ctrl+C to stop."
sleep 1 # Slight delay before freezing the screen

printf "%-10s %-12s %-12s %-7s %-12s %-7s %-10s %-13s %-11s %-15s %-14s\n" "TIME" "REPLICA" "RECEIVE_LSN" "IS_SYNC" "STATUS" "LAG_S" "REAL_LAG_S" "RECEIPT_LAG_S" "SEND_LAG_S" "TRANSPORT_LAG_S" "WAL_END_LAG_S"
printf '%.s─' {1..130}
echo ""

while true; do
    TIME=$(date "+%H:%M:%S")
    
    OUT1=$(docker compose exec -T postgres-replica1 psql -U postgres -t -A -F"," -c "$QUERY" 2>/dev/null)
    OUT2=$(docker compose exec -T postgres-replica2 psql -U postgres -t -A -F"," -c "$QUERY" 2>/dev/null)
    
    # Check if we got output
    if [ -z "$OUT1" ]; then OUT1="N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A"; fi
    if [ -z "$OUT2" ]; then OUT2="N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A,N/A"; fi

    IFS=',' read -r r_lsn1 is_sync1 status1 lag_s1 real_lag_s1 receipt_lag1 send_lag1 transport_lag1 end_lag1 <<< "$OUT1"
    IFS=',' read -r r_lsn2 is_sync2 status2 lag_s2 real_lag_s2 receipt_lag2 send_lag2 transport_lag2 end_lag2 <<< "$OUT2"
    
    printf "%-10s %-12s %-12s %-7s %-12s %-7s %-10s %-13s %-11s %-15s %-14s\n" "$TIME" "replica1" "${r_lsn1:-N/A}" "${is_sync1:-N/A}" "${status1:-N/A}" "${lag_s1:-N/A}" "${real_lag_s1:-N/A}" "${receipt_lag1:-N/A}" "${send_lag1:-N/A}" "${transport_lag1:-N/A}" "${end_lag1:-N/A}"
    printf "%-10s %-12s %-12s %-7s %-12s %-7s %-10s %-13s %-11s %-15s %-14s\n" "$TIME" "replica2" "${r_lsn2:-N/A}" "${is_sync2:-N/A}" "${status2:-N/A}" "${lag_s2:-N/A}" "${real_lag_s2:-N/A}" "${receipt_lag2:-N/A}" "${send_lag2:-N/A}" "${transport_lag2:-N/A}" "${end_lag2:-N/A}"
    
    sleep 1
done
