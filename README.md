# site-monitor

Uptime sentinel for our public sites. A GitHub Actions cron job checks each
site roughly every 5 minutes and pushes a LINE notification **only when a
site's state changes** (goes down → one alert; recovers → one alert).

- `check.sh` — the checker (curl + retry-after-20s to avoid flapping)
- `state.json` — last known state, committed by the bot on change
- Alert delivery: `ALERT_WEBHOOK_URL` repository secret (token-gated endpoint)

No credentials or private data live in this repo.
