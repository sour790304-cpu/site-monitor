#!/usr/bin/env bash
# Site sentinel: checks each site, compares with last known state (state.json),
# and POSTs a LINE alert (via ALERT_WEBHOOK_URL secret) only on state CHANGE
# (down once, recovered once — no spam). Runs on GitHub Actions every ~5 min.
set -euo pipefail

SITES=(
  "BR Property|https://brproperty.homes/"
  "Shanghe 上禾官網|https://shangherealestate.com/"
  "CRM 系統|https://shanghe-crm.vercel.app/login"
)

STATE_FILE="state.json"
[ -f "$STATE_FILE" ] || echo '{}' > "$STATE_FILE"

push_alert() { # $1=status $2=subject $3=detail
  curl -s -X POST "$ALERT_WEBHOOK_URL" -H "Content-Type: application/json" \
    -d "$(jq -n --arg s "$1" --arg su "$2" --arg d "$3" \
      '{source:"GitHub哨兵",status:$s,subject:$su,detail:$d}')" > /dev/null || true
}

if [ "${TEST_ALERT:-false}" = "true" ]; then
  push_alert "up" "測試:GitHub 哨兵已上線" "三站每 5 分鐘檢查一次;掛掉/恢復會推播到這裡。此為手動測試訊息。"
fi

http_code() { curl -s -o /dev/null -w "%{http_code}" --max-time 25 -L "$1" || echo "000"; }

check() { # $1=url → "up" or "down:<code>"
  local code; code=$(http_code "$1")
  case "$code" in
    2*|3*) echo "up"; return ;;
  esac
  sleep 20  # 避免瞬斷誤報:20 秒後複測一次
  code=$(http_code "$1")
  case "$code" in
    2*|3*) echo "up" ;;
    *)     echo "down:$code" ;;
  esac
}

CHANGED=0
STATE=$(cat "$STATE_FILE")
for entry in "${SITES[@]}"; do
  name="${entry%%|*}"; url="${entry##*|}"
  result=$(check "$url")
  status="${result%%:*}"
  prev=$(echo "$STATE" | jq -r --arg k "$name" '.[$k] // "up"')
  echo "[$name] $prev -> $result"
  if [ "$status" != "$prev" ]; then
    CHANGED=1
    if [ "$status" = "down" ]; then
      push_alert "down" "$name 掛了!" "網址:$url
HTTP 狀態:${result#down:}
(20 秒後複測仍失敗;恢復時會再通知)"
    else
      push_alert "up" "$name 恢復正常" "網址:$url"
    fi
  fi
  STATE=$(echo "$STATE" | jq --arg k "$name" --arg v "$status" '.[$k]=$v')
done

if [ "$CHANGED" = "1" ]; then
  echo "$STATE" > "$STATE_FILE"
  git config user.name "site-monitor-bot"
  git config user.email "site-monitor-bot@users.noreply.github.com"
  git add "$STATE_FILE"
  git commit -q -m "state: $(date -u +%FT%TZ)"
  git push -q
fi
echo "done: $STATE"
