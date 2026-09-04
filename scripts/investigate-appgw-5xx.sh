#!/usr/bin/env bash
#
# investigate-appgw-5xx.sh — dump Application Gateway access-log 5xx around an alert time.
#
# Use this for the ONE case App Insights can't see: gateway-generated 5xx
# (502 backend-unreachable, WAF 503/403) and per-request forensics (URL, backend
# response time, user-agent). For app-thrown 5xx, prefer App Insights `requests`
# / `exceptions` — it correlates the exception and gives the whole stack trace.
#
# Auth: uses the storage account KEY (via `az storage account keys list`), not
# AAD/RBAC — that's why it works without Storage Blob Data Reader, the same door
# the Portal blob browser uses. Needs only listKeys (Contributor-level).
#
# Time: DIA alerts render in Europe/Prague (CET/CEST). Pass the time EXACTLY as
# the alert shows it — the script converts to the UTC hour partition (incl. DST)
# and pulls that hour plus the previous one (5-min alert windows straddle
# boundaries).
#
# Usage:
#   scripts/investigate-appgw-5xx.sh "2026-07-11 14:40"
#   scripts/investigate-appgw-5xx.sh "2026-07-11 14:40" --firewall   # also WAF log
#
# Overridable via env: APPGW_LOG_ACCOUNT, APPGW_LOG_RG, APPGW_RES_PATH, ALERT_TZ
set -euo pipefail

STORAGE_ACCOUNT="${APPGW_LOG_ACCOUNT:-ismdmonglobal}"
STORAGE_RG="${APPGW_LOG_RG:-ismd-shared-global}"
ALERT_TZ="${ALERT_TZ:-Europe/Prague}"
# AppGW resource path exactly as Azure writes it into the blob prefix (UPPERCASE).
RES_PATH="${APPGW_RES_PATH:-/SUBSCRIPTIONS/7D72DA57-155C-4D56-883E-0E68A747E9E1/RESOURCEGROUPS/ISMD-SHARED-GLOBAL/PROVIDERS/MICROSOFT.NETWORK/APPLICATIONGATEWAYS/ISMD-APP-GATEWAY}"

ACCESS_CONTAINER="insights-logs-applicationgatewayaccesslog"
FW_CONTAINER="insights-logs-applicationgatewayfirewalllog"

want_fw=0
positional=()
for a in "$@"; do
  case "$a" in
    --firewall|-f) want_fw=1 ;;
    -h|--help) sed -n '3,26p' "$0"; exit 0 ;;
    *) positional+=("$a") ;;
  esac
done
if [ "${#positional[@]}" -lt 1 ]; then
  echo "usage: $0 \"YYYY-MM-DD HH:MM\" [--firewall]   (time as shown in the alert, $ALERT_TZ)" >&2
  exit 2
fi
LOCAL_TS="${positional[0]}"

# Alert-local time -> UTC epoch (GNU date; handles DST via the TZ="" prefix).
if ! BASE_EPOCH=$(date -u -d "TZ=\"$ALERT_TZ\" $LOCAL_TS" +%s 2>/dev/null); then
  echo "could not parse time '$LOCAL_TS' — expected e.g. \"2026-07-11 14:40\"" >&2
  exit 2
fi
echo ">> alert-local '$LOCAL_TS' ($ALERT_TZ)  ->  UTC $(date -u -d "@$BASE_EPOCH" '+%Y-%m-%d %H:%M'), pulling that hour + previous"

KEY=$(az storage account keys list -n "$STORAGE_ACCOUNT" -g "$STORAGE_RG" --query "[0].value" -o tsv)

# Download target hour and previous hour into one aggregate file (NDJSON).
fetch() { # $1=container -> stdout aggregate path
  local container="$1" agg; agg=$(mktemp)
  for off in 0 -3600; do
    local part name tmp
    part=$(date -u -d "@$((BASE_EPOCH + off))" '+y=%Y/m=%m/d=%d/h=%H')
    name="resourceId=${RES_PATH}/${part}/m=00/PT1H.json"
    tmp=$(mktemp)
    if az storage blob download --account-name "$STORAGE_ACCOUNT" --account-key "$KEY" \
         --container-name "$container" --name "$name" --file "$tmp" --no-progress 2>/dev/null; then
      cat "$tmp" >>"$agg"
    fi
    rm -f "$tmp"
  done
  printf '%s' "$agg"
}

echo
echo "=== ACCESS LOG — backend 5xx (time | backendStatus | setting | clientStatus | timeTaken | uri | error_info | userAgent) ==="
ACCESS_FILE=$(fetch "$ACCESS_CONTAINER")
if [ -s "$ACCESS_FILE" ]; then
  jq -rc 'select((.properties.serverStatus|tonumber? // 0)>=500)
    | [ .time, (.properties.serverStatus|tostring), .backendSettingName,
        (.properties.httpStatus|tostring), ((.properties.timeTaken|tostring)+"s"),
        .properties.requestUri, (.properties.error_info // ""), (.properties.userAgent // "") ]
    | @tsv' "$ACCESS_FILE" | sort | column -t -s $'\t' || true
else
  echo "(no access-log blob for that hour — nothing ingested, or wrong time)"
fi
rm -f "$ACCESS_FILE"

if [ "$want_fw" = 1 ]; then
  echo
  echo "=== FIREWALL LOG — WAF blocks (time | action | ruleId | uri | message) ==="
  FW_FILE=$(fetch "$FW_CONTAINER")
  if [ -s "$FW_FILE" ]; then
    jq -rc 'select(((.properties.action // "")|test("[Bb]lock"))
      or ((.properties.httpStatus|tonumber? // 0)>=500))
      | [ .time, (.properties.action // ""), (.properties.ruleId // ""),
          (.properties.requestUri // ""), (.properties.message // "") ]
      | @tsv' "$FW_FILE" | sort | column -t -s $'\t' || true
  else
    echo "(no firewall-log blob for that hour)"
  fi
  rm -f "$FW_FILE"
fi
