#!/usr/bin/env bash
# monitor_redis_routing.sh - Redis routing time monitor (0.5s interval, one-line JSON per call)
# Monitor script to watch Redis routing performance

set -euo pipefail

URL="${1:-http://localhost:3000/api/redis_routing}"
INTERVAL=0.5

GREEN="\033[32m"
RED="\033[31m"
CYAN="\033[36m"
YELLOW="\033[33m"
DIM="\033[2m"
BOLD="\033[1m"
RESET="\033[0m"

FMT="%-12s %-8s %-8s %-12s %-20s\n"

# Header
printf "${BOLD}${CYAN}${FMT}${RESET}" \
  "TIMESTAMP" "RT(ms)" "SOURCE" "ROLE" "DB_HOST"
echo -e "${DIM}$(printf '%.0s─' {1..64})${RESET}"

while true; do
  RESPONSE=$(curl -s --max-time 2 "$URL" 2>/dev/null || echo "CURL_FAILED")

  if [ "$RESPONSE" = "CURL_FAILED" ] || [ -z "$RESPONSE" ]; then
    echo -e "$(date '+%H:%M:%S')  ${RED}✖ UNREACHABLE${RESET}"
    sleep "$INTERVAL"
    continue
  fi

  LINE=$(echo "$RESPONSE" | jq -r '
    [
      .timestamp,
      (.redis_routing_time_ms // "N/A" | tostring),
      (.source // "N/A"),
      (.current_role // "N/A"),
      (.connected_host // "N/A")
    ] | @tsv
  ' 2>/dev/null) || true

  if [ -z "$LINE" ]; then
    echo -e "$(date '+%H:%M:%S')  ${RED}✖ PARSE ERROR${RESET} (Response: $RESPONSE)"
    sleep "$INTERVAL"
    continue
  fi

  IFS=$'\t' read -r TS RT_MS SRC ROLE DB_HOST <<< "$LINE"

  # Color the routing time based on value
  if [ "$RT_MS" = "0" ]; then
    RT_COLOR="$DIM"
  elif [ "$RT_MS" = "N/A" ]; then
    RT_COLOR="$RED"
  else
    # Compare float: > 1ms = yellow, else green
    IS_SLOW=$(echo "$RT_MS" | awk '{print ($1 > 1.0) ? "1" : "0"}')
    if [ "$IS_SLOW" = "1" ]; then
      RT_COLOR="$YELLOW"
    else
      RT_COLOR="$GREEN"
    fi
  fi

  # Color the source
  if [ "$SRC" = "cache" ]; then
    SRC_COLOR="$DIM"
  else
    SRC_COLOR="$CYAN"
  fi

  # Build colored output (pad plain text, then wrap with color)
  pad() { printf "%-${2}s" "$1"; }

  printf "%-12s %b %b %-12s %-20s\n" \
    "$(date '+%H:%M:%S.%N' | cut -c 1-12)" \
    "${RT_COLOR}$(pad "$RT_MS" 8)${RESET}" \
    "${SRC_COLOR}$(pad "$SRC" 8)${RESET}" \
    "$ROLE" \
    "$DB_HOST"

  sleep "$INTERVAL"
done
