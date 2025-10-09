#!/usr/bin/env bash
# Fetch Jira Service Desk requests from the last year using JQL,
# print aligned table with elapsed time, follow pagination via _links.next,
# and write both JSON and CSV files of the same rows.

set -u  # keep -u, drop -e so we don't bail early on non-fatal subshell errors

PAT="${PAT:-NDUwMjE1ODc2MzQ0OnI9mxl4xwAfdfxXIJHYNqsBplPb}"
BASE="${BASE:-https://jira.odin.dso.mil}"
LIMIT=50
MAX_ITEMS=297
OUT_JSON="last_requests_elapsed.json"
OUT_CSV="last_requests_elapsed.csv"

echo "🔐 PAT: ${#PAT} chars | Base: $BASE"
echo "📦 Page size: $LIMIT | Max items: $MAX_ITEMS"
echo

ONE_YEAR_AGO=$(date -d '1 year ago' +%Y-%m-%d)
JQL_QUERY="created >= \"$ONE_YEAR_AGO\""
ENCODED_JQL=$(jq -rn --arg q "$JQL_QUERY" '$q|@uri')

NEXT_URL="$BASE/rest/servicedeskapi/request?limit=$LIMIT&start=0&jql=$ENCODED_JQL"

count=0
total_elapsed_sec=0
OUT_TSV=$'KEY\tREQUESTER\tOPENED\tLAST_UPDATE\tELAPSED'
OUT_ROWS="[]"

range_1_7=0
range_8_14=0
range_15_21=0
range_22_28=0
range_29_plus=0

is_json () { head -c1 | grep -qE '^\{|

\['; }

while :; do
  echo "➡️  GET: $NEXT_URL"
  RESP=$(curl -k -s -H "Authorization: Bearer $PAT" -H "Accept: application/json" "$NEXT_URL" || true)

  if ! printf '%s' "$RESP" | is_json; then
    echo "❌ Non-JSON response. First 200 chars:"
    printf '%s' "$RESP" | head -c 200; echo
    break
  fi

  SIZE=$(echo "$RESP" | jq -r '.size // (.values|length) // 0')
  echo "📄 Reported size: $SIZE"

  mapfile -t ROWS < <(echo "$RESP" | jq -r '
    .values[]? | [
      .issueKey,
      (.reporter.displayName // "-"),
      .createdDate.iso8601,
      (.currentStatus.statusDate.iso8601 // .updatedDate.iso8601 // .createdDate.iso8601)
    ] | @tsv
  ')
  echo "🧾 Parsed rows: ${#ROWS[@]}"

  [[ ${#ROWS[@]} -eq 0 ]] && echo "ℹ️  Empty page; stopping." && break

  for row in "${ROWS[@]}"; do
    IFS=$'\t' read -r KEY REQ OPENED_ISO LAST_ISO <<< "$row"

    OPENED_EPOCH=$(date -d "$OPENED_ISO" +%s 2>/dev/null || echo 0)
    LAST_EPOCH=$(date -d "$LAST_ISO" +%s 2>/dev/null || echo 0)
    DIFF_SEC=$(( LAST_EPOCH - OPENED_EPOCH ))
    (( DIFF_SEC < 0 )) && DIFF_SEC=0
    DIFF_DAYS=$(( DIFF_SEC / 86400 ))
    DIFF_HOURS=$((( DIFF_SEC % 86400 ) / 3600 ))

    if (( DIFF_DAYS >= 1 && DIFF_DAYS <= 7 )); then
      ((range_1_7++))
    elif (( DIFF_DAYS >= 8 && DIFF_DAYS <= 14 )); then
      ((range_8_14++))
    elif (( DIFF_DAYS >= 15 && DIFF_DAYS <= 21 )); then
      ((range_15_21++))
    elif (( DIFF_DAYS >= 22 && DIFF_DAYS <= 28 )); then
      ((range_22_28++))
    elif (( DIFF_DAYS >= 29 )); then
      ((range_29_plus++))
    fi

    OUT_TSV+=$'\n'"$KEY"$'\t'"$REQ"$'\t'"$OPENED_ISO"$'\t'"$LAST_ISO"$'\t'"${DIFF_DAYS}d ${DIFF_HOURS}h"

    OUT_ROWS=$(jq -n --argjson arr "$OUT_ROWS" \
                    --arg key "$KEY" \
                    --arg req "$REQ" \
                    --arg opened "$OPENED_ISO" \
                    --arg last "$LAST_ISO" \
                    --arg d "$DIFF_DAYS" \
                    --arg h "$DIFF_HOURS" '
      $arr + [ {key:$key, requester:$req, opened:$opened, last_update:$last,
                elapsed_days:($d|tonumber), elapsed_hours:($h|tonumber)} ]
    ')

    total_elapsed_sec=$(( total_elapsed_sec + DIFF_SEC ))
    ((count++))
    if (( count >= MAX_ITEMS )); then
      echo "🏁 Reached MAX_ITEMS=$MAX_ITEMS"
      NEXT_URL=""
      break
    fi
  done

  NEXT_URL=$(echo "$RESP" | jq -r '._links.next // empty')
  echo "🔁 Next: ${NEXT_URL:-<none>}"
  [[ -z "$NEXT_URL" ]] && echo "✅ No next; done paging." && break
  echo "— Page done —"
done

echo
if (( count == 0 )); then
  echo "⚠️  No requests returned."
else
  echo "$OUT_TSV" | column -t -s $'\t'
  echo
  echo "💾 Writing JSON: ./$OUT_JSON"
  echo "$OUT_ROWS" | jq . > "$OUT_JSON"
  echo "Total listed: $count"

  echo "📊 Calculating average elapsed time..."
  AVG_SEC=$(( total_elapsed_sec / count ))
  AVG_DAYS=$(( AVG_SEC / 86400 ))
  AVG_HOURS=$((( AVG_SEC % 86400 ) / 3600 ))
  echo "🧮 Average elapsed: ${AVG_DAYS}d ${AVG_HOURS}h"

  echo "💾 Writing CSV: ./$OUT_CSV"
  {
    echo "KEY,REQUESTER,OPENED,LAST_UPDATE,ELAPSED"
    printf "%s\n" "$OUT_TSV" | tail -n +2 | while IFS=$'\t' read -r key requester opened last elapsed; do
      echo "$key,$requester,$opened,$last,\"$elapsed\""
    done
    echo "AVERAGE,,,,\"${AVG_DAYS}d ${AVG_HOURS}h\""
  } > "$OUT_CSV"

  echo
  echo "📊 Resolution Time Buckets:"
  printf "  1–7 days     : %d\n" "$range_1_7"
  printf "  8–14 days    : %d\n" "$range_8_14"
  printf "  15–21 days   : %d\n" "$range_15_21"
  printf "  22–28 days   : %d\n" "$range_22_28"
  printf "  29+ days     : %d\n" "$range_29_plus"
fi

