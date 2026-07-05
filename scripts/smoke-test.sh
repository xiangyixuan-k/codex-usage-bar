#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CODEX_HOME="$TMP_DIR/codex-home"
CONFIG_PATH="$TMP_DIR/config.json"
mkdir -p "$CODEX_HOME"

NOW_MS="$(python3 - <<'PY'
import time
print(int(time.time() * 1000))
PY
)"
NOW_S="$((NOW_MS / 1000))"

sqlite3 "$CODEX_HOME/state_5.sqlite" <<SQL
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    tokens_used INTEGER NOT NULL DEFAULT 0,
    created_at_ms INTEGER,
    updated_at_ms INTEGER,
    model TEXT
);
INSERT INTO threads (id, created_at, updated_at, tokens_used, created_at_ms, updated_at_ms)
VALUES ('fixture-a', $NOW_S, $NOW_S, 250, $NOW_MS, $NOW_MS);
INSERT INTO threads (id, created_at, updated_at, tokens_used, created_at_ms, updated_at_ms)
VALUES ('fixture-b', $NOW_S, $NOW_S, 150, $NOW_MS, $NOW_MS);
UPDATE threads SET model = 'gpt-5.5';
SQL

sqlite3 "$CODEX_HOME/logs_2.sqlite" <<SQL
CREATE TABLE logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts INTEGER NOT NULL,
    ts_nanos INTEGER NOT NULL,
    feedback_log_body TEXT
);
INSERT INTO logs (ts, ts_nanos, feedback_log_body)
VALUES ($NOW_S, 0, 'turn{model=gpt-5.5}: Request completed headers={"x-codex-primary-used-percent":"74","x-codex-secondary-used-percent":"54","x-codex-primary-window-minutes":"300","x-codex-secondary-window-minutes":"10080","x-codex-primary-reset-after-seconds":"3600","x-codex-secondary-reset-after-seconds":"604800","x-codex-active-limit":"premium","x-codex-plan-type":"prolite"}');
SQL

cat > "$CONFIG_PATH" <<JSON
{
  "codexHome" : "$CODEX_HOME",
  "criticalRemainingPercent" : 10,
  "customStateDatabasePaths" : [],
  "enableOfficialRateLimitSnapshots" : false,
  "includeArchivedSessionsFallback" : false,
  "language" : "simplifiedChinese",
  "maxRateLimitSnapshotAgeMinutes" : 360,
  "period" : "rolling24h",
  "rateLimitDisplayWindow" : "mostConstrained",
  "refreshIntervalSeconds" : 60,
  "tokenBudget" : 1000,
  "warningRemainingPercent" : 25
}
JSON

OUTPUT="$(cd "$ROOT_DIR" && swift run CodexUsageBar --once --json --config "$CONFIG_PATH")"

echo "$OUTPUT" | grep '"usedTokens" : 400' >/dev/null
echo "$OUTPUT" | grep '"tokenBudget" : 1000' >/dev/null
echo "$OUTPUT" | grep '"threadCount" : 2' >/dev/null

SESSION_DIR="$CODEX_HOME/sessions/2026/07/05"
mkdir -p "$SESSION_DIR"
cat > "$SESSION_DIR/rate-limit-fixture.jsonl" <<JSONL
{"timestamp":"2026-07-05T12:00:00.000Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"spark_fixture","limit_name":"GPT-5.3-Codex-Spark","primary":{"used_percent":0,"window_minutes":300,"resets_at":1783243762},"secondary":{"used_percent":0,"window_minutes":10080,"resets_at":1783830562},"credits":{"has_credits":false,"unlimited":false,"balance":null},"individual_limit":null,"plan_type":null,"rate_limit_reached_type":null}}}
JSONL

perl -0pi -e 's/"enableOfficialRateLimitSnapshots" : false/"enableOfficialRateLimitSnapshots" : true/' "$CONFIG_PATH"
OFFICIAL_OUTPUT="$(cd "$ROOT_DIR" && swift run CodexUsageBar --once --json --config "$CONFIG_PATH")"
echo "$OFFICIAL_OUTPUT" | grep '"limitName" : "gpt-5.5"' >/dev/null
echo "$OFFICIAL_OUTPUT" | grep '"source" : "Codex response headers: logs_2.sqlite"' >/dev/null
echo "$OFFICIAL_OUTPUT" | grep '"usedPercent" : 74' >/dev/null
echo "$OFFICIAL_OUTPUT" | grep '"usedPercent" : 54' >/dev/null

perl -0pi -e 's/"rateLimitDisplayWindow" : "mostConstrained"/"rateLimitDisplayWindow" : "secondary"/' "$CONFIG_PATH"
SECONDARY_OUTPUT="$(cd "$ROOT_DIR" && swift run CodexUsageBar --once --json --config "$CONFIG_PATH")"
echo "$SECONDARY_OUTPUT" | grep '"displayWindow" : "secondary"' >/dev/null

echo "Smoke test passed"
