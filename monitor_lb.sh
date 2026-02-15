#!/usr/bin/env bash
# monitor_lb.sh - Monitors the load balancer status endpoint every second (one line per call)
# Usage: ./monitor_lb.sh [URL]

set -euo pipefail

URL="${1:-http://localhost:3000/api/status}"
INTERVAL=0.5

GREEN="\033[32m"
RED="\033[31m"
CYAN="\033[36m"
DIM="\033[2m"
BOLD="\033[1m"
RESET="\033[0m"

# Shared format
FMT="%-10s %-18s %-20s %-10s %-8s %-12s %-12s %-12s %-6s %-6s\n"

# Print header
printf "${BOLD}${CYAN}${FMT}${RESET}" \
  "TIME" "SERVER_IP" "DB_HOST" "ROUTING" "SOURCE" "PRIMARY" "REPLICA_1" "REPLICA_2" "LAG_R1" "LAG_R2"
# Separator line length adjusted roughly for new width
echo -e "${DIM}$(printf '%.0s─' {1..130})${RESET}"

while true; do
  RESPONSE=$(curl -s --max-time 3 "$URL" 2>/dev/null || echo "CURL_FAILED")

  if [ "$RESPONSE" = "CURL_FAILED" ] || [ -z "$RESPONSE" ]; then
    echo -e "$(date '+%H:%M:%S')  ${RED}✖ UNREACHABLE${RESET}"
    sleep "$INTERVAL"
    continue
  fi

  LINE=$(echo "$RESPONSE" | jq -r '
    def status_icon: if .healthy then "✓" else "✖" end;
    def lag_val: (.lag_ms // 0) | if . >= 1000 then ((. / 100 | floor / 10 | tostring) + "s") else (tostring + "ms") end;
    [
      (.connection_info.server_ip // "N/A"),
      (.connection_info.connected_host // "N/A"),
      ((.connection_info.redis_routing_time_ms // 0 | tostring) + "ms"),
      (.connection_info.source // "N/A"),
      (.db_statuses.primary | status_icon),
      (.db_statuses.replica_1 | status_icon),
      (.db_statuses.replica_2 | status_icon),
      (.db_statuses.replica_1 | lag_val),
      (.db_statuses.replica_2 | lag_val)
    ] | @tsv
  ' 2>/dev/null) || true

  if [ -z "$LINE" ]; then
    echo -e "$(date '+%H:%M:%S')  ${RED}✖ PARSE ERROR (non-JSON response)${RESET}"
    sleep "$INTERVAL"
    continue
  fi

  IFS=$'\t' read -r SERVER_IP DB_HOST ROUTING SOURCE P_ST R1_ST R2_ST R1_LAG R2_LAG <<< "$LINE"

  # Pad plain text first, then wrap with color (ANSI codes break printf width)
  color_pad() {
    local text="$1" color="$2" width="$3"
    local padded
    padded=$(printf "%-${width}s" "$text")
    echo -e "${color}${padded}${RESET}"
  }

  [[ "$P_ST" == "✓" ]] && P_FMT=$(color_pad "HEALTHY" "$GREEN" 12) || P_FMT=$(color_pad "DOWN" "$RED" 12)
  [[ "$R1_ST" == "✓" ]] && R1_FMT=$(color_pad "HEALTHY" "$GREEN" 12) || R1_FMT=$(color_pad "DOWN" "$RED" 12)
  [[ "$R2_ST" == "✓" ]] && R2_FMT=$(color_pad "HEALTHY" "$GREEN" 12) || R2_FMT=$(color_pad "DOWN" "$RED" 12)

  # Use the same format string structure but substituting color padded strings for statuses
  printf "%-10s %-18s %-20s %-10s %-8s %b %b %b %-6s %-6s\n" \
    "$(date '+%H:%M:%S')" "$SERVER_IP" "$DB_HOST" "$ROUTING" "$SOURCE" "$P_FMT" "$R1_FMT" "$R2_FMT" "$R1_LAG" "$R2_LAG"

  sleep "$INTERVAL"
done
