# Codex Usage Bar

Codex Usage Bar is a small macOS menu bar app that shows Codex remaining rate-limit percentage as a battery icon.

It is intentionally local-first:

- reads the latest Codex response-header rate limits written by logged-in Codex requests
- matches the current model before using session `rate_limits` fallbacks, so Spark limits are not shown for a GPT-5.5 session
- falls back to local token estimation from `~/.codex/state_*.sqlite` when no recent rate-limit snapshot exists
- never sends usage data anywhere
- does not read or upload `~/.codex/auth.json`

Codex writes response headers such as `x-codex-primary-used-percent` and `x-codex-secondary-used-percent` into its local request log after authenticated requests. This app reads those local headers first, so a normal Codex login is enough.

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
  "refreshIntervalSeconds" : 30,
  "tokenBudget" : 300000000,
  "warningRemainingPercent" : 25
}
```

When `enableOfficialRateLimitSnapshots` is true, the menu bar uses Codex's local response-header rate limits first:

- `primary` is the shorter rate-limit window
- `secondary` is the longer rate-limit window
- `mostConstrained` shows whichever window has less remaining percentage

If no recent response-header limit exists, the app falls back to model-matched session `rate_limits`. The `tokenBudget` setting is only used by the final local token estimator. Set it to the amount you want to treat as 100% for the selected period. For example, if you want to watch a monthly 2,000,000-token fallback allowance:

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

- the remaining percentage
- the 5h and 7d windows when Codex provides both
- choose whether the menu bar battery shows the 5h window, the 7d window, or the lower remaining value
- refresh now
- open the settings file
- open Codex
- quit

## CLI Snapshot

You can test the parser without opening the menu bar UI:

```bash
swift run CodexUsageBar --once
swift run CodexUsageBar --once --json
swift run CodexUsageBar --once --budget 2000000 --period monthly
```

## Privacy

The app reads local files under your configured Codex home. It parses Codex request headers from local logs, parses session lines that contain `rate_limits` as a fallback, queries token totals from the local SQLite state database only when needed, and never uploads any of that data. It does not read `~/.codex/auth.json`.

## Development

```bash
./scripts/smoke-test.sh
swift build
./scripts/package-app.sh
```

## Limitations

- Live limits update when Codex writes a completed request log. If the value looks stale, send or complete one Codex request and refresh.
- The fallback local token estimate is not an official OpenAI quota meter.
- If Codex changes its local storage format, the app may need a parser update.
