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

sqlite3 "$CODEX_HOME/state_5.sqlite" <<SQL
CREATE TABLE threads (
    id TEXT PRIMARY KEY,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    tokens_used INTEGER NOT NULL DEFAULT 0,
    created_at_ms INTEGER,
    updated_at_ms INTEGER
);
INSERT INTO threads (id, created_at, updated_at, tokens_used, created_at_ms, updated_at_ms)
VALUES ('fixture-a', $((NOW_MS / 1000)), $((NOW_MS / 1000)), 250, $NOW_MS, $NOW_MS);
INSERT INTO threads (id, created_at, updated_at, tokens_used, created_at_ms, updated_at_ms)
VALUES ('fixture-b', $((NOW_MS / 1000)), $((NOW_MS / 1000)), 150, $NOW_MS, $NOW_MS);
SQL

cat > "$CONFIG_PATH" <<JSON
{
  "codexHome" : "$CODEX_HOME",
  "criticalRemainingPercent" : 10,
  "customStateDatabasePaths" : [],
  "includeArchivedSessionsFallback" : false,
  "period" : "rolling24h",
  "refreshIntervalSeconds" : 60,
  "tokenBudget" : 1000,
  "warningRemainingPercent" : 25
}
JSON

OUTPUT="$(cd "$ROOT_DIR" && swift run CodexUsageBar --once --json --config "$CONFIG_PATH")"

echo "$OUTPUT" | grep '"usedTokens" : 400' >/dev/null
echo "$OUTPUT" | grep '"tokenBudget" : 1000' >/dev/null
echo "$OUTPUT" | grep '"threadCount" : 2' >/dev/null

echo "Smoke test passed"
