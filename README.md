# Codex Usage Bar

Codex Usage Bar is a small macOS menu bar app that shows Codex remaining rate-limit percentage as a battery icon.

It is intentionally local-first:

- reads the latest official Codex `rate_limits` snapshot written by logged-in Codex sessions
- falls back to local token estimation from `~/.codex/state_*.sqlite` when no recent rate-limit snapshot exists
- never sends usage data anywhere
- does not read or upload `~/.codex/auth.json`

Codex itself exposes rate limits in `/status` and `/usage`. This app uses the same local session data Codex writes after authenticated requests, so a normal Codex login is enough.

## Install

```bash
git clone https://github.com/xiangyixuan-k/codex-usage-bar.git
cd codex-usage-bar
./scripts/package-app.sh
open "dist/Codex Usage Bar.app"
```

The app appears as an Apple-style battery with the percentage inside the battery.

## Configure

On first launch, the app creates:

```text
~/.codex-usage-bar/config.json
```

Example:

```json
{
  "codexHome" : "~/.codex",
  "criticalRemainingPercent" : 10,
  "customStateDatabasePaths" : [],
  "enableOfficialRateLimitSnapshots" : true,
  "includeArchivedSessionsFallback" : false,
  "maxRateLimitSnapshotAgeMinutes" : 360,
  "period" : "monthly",
  "rateLimitDisplayWindow" : "mostConstrained",
  "refreshIntervalSeconds" : 60,
  "tokenBudget" : 300000000,
  "warningRemainingPercent" : 25
}
```

When `enableOfficialRateLimitSnapshots` is true, the menu bar uses official Codex `rate_limits` first:

- `primary` is the shorter rate-limit window
- `secondary` is the longer rate-limit window
- `mostConstrained` shows whichever window has less remaining percentage

The `tokenBudget` setting is only used by the fallback local token estimator. Set it to the amount you want to treat as 100% for the selected period. For example, if you want to watch a monthly 2,000,000-token fallback allowance:

```json
"period" : "monthly",
"tokenBudget" : 2000000
```

Supported periods:

- `daily`
- `weekly`
- `monthly`
- `rolling24h`

## Menu Actions

The menu includes:

- refresh usage now
- open the config file
- open Codex settings
- quit

## CLI Snapshot

You can test the parser without opening the menu bar UI:

```bash
swift run CodexUsageBar --once
swift run CodexUsageBar --once --json
swift run CodexUsageBar --once --budget 2000000 --period monthly
```

## Privacy

The app reads local files under your configured Codex home. It only parses session lines that contain `rate_limits`, queries token totals from the local SQLite state database when needed, and never uploads any of that data. It does not read `~/.codex/auth.json`.

## Development

```bash
./scripts/smoke-test.sh
swift build
./scripts/package-app.sh
```

## Limitations

- Rate-limit snapshots update when Codex writes new session events.
- The fallback local token estimate is not an official OpenAI quota meter.
- If Codex changes its local storage format, the app may need a parser update.
