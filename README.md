# Codex Usage Bar

Codex Usage Bar is a small macOS menu bar app that shows an estimated local Codex token budget remaining percentage.

It is intentionally local-first:

- reads Codex local state from `~/.codex/state_*.sqlite`
- falls back to scanning local session JSONL files when SQLite state is unavailable
- never sends usage data anywhere
- lets you set your own daily, weekly, monthly, or rolling 24h token budget

OpenAI does not currently expose a public real-time "Codex remaining quota" API for personal accounts, so this app reports a practical local estimate rather than an official entitlement number.

## Install

```bash
git clone https://github.com/xiangyixuan-k/codex-usage-bar.git
cd codex-usage-bar
./scripts/package-app.sh
open "dist/Codex Usage Bar.app"
```

The app appears as a menu bar item such as `Codex 72%`.

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
  "includeArchivedSessionsFallback" : false,
  "period" : "monthly",
  "refreshIntervalSeconds" : 60,
  "tokenBudget" : 300000000,
  "warningRemainingPercent" : 25
}
```

The default `tokenBudget` is only a practical placeholder. Set it to the amount you want to treat as 100% for the selected period. For example, if you want to watch a monthly 2,000,000-token allowance:

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

The app reads only local files under your configured Codex home. It queries token totals from the local SQLite state database and does not read prompts, messages, or `~/.codex/auth.json`.

## Development

```bash
./scripts/smoke-test.sh
swift build
./scripts/package-app.sh
```

## Limitations

- This is not an official OpenAI quota meter.
- ChatGPT/Codex rate limits may not map exactly to local token totals.
- If Codex changes its local storage format, the app may need a parser update.
