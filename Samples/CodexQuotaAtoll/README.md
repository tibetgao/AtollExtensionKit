# Codex Dashboard for Atoll

A small macOS companion that reads the signed-in Codex account's current rate-limit windows from `codex app-server` and publishes a dedicated Atoll dashboard tab. It also summarizes recent local Codex tasks and detects whether the latest task is running.

## What it shows

- Remaining percentage in each available quota window
- Remaining percentage in the secondary quota window, when present
- The next reset time
- Optional credit balance and plan metadata when the account returns them
- Current task activity and latest task context
- Green, orange, and red quota states

The dashboard intentionally omits Atoll's minimalistic/closed-island replacement, so Atoll keeps its normal top-island residency and priority behavior. Its Apple Watch-inspired single-screen layout uses a circular quota complication, icon-driven activity states, and a compact current-task note without scrollable content.

The companion does not read or copy OAuth tokens. Codex owns authentication and token refresh; the companion communicates with the local `codex app-server` process over JSON-RPC.

## Requirements

- macOS 13 or later
- Atoll installed and running
- A current `codex` CLI on `PATH`, signed into the account whose quota should be displayed

## Run

From this directory:

```sh
swift run codex-quota-atoll
```

Atoll registers and authorizes `com.tibetgao.CodexQuotaAtoll` on the first run. By default the companion keeps one app-server connection open and refreshes every five minutes.
Codex reads time out after 20 seconds and Atoll RPC operations after 15 seconds, so an unavailable service produces a clear error instead of leaving the process stuck.

Useful options:

```sh
# Fetch and display once, useful for diagnostics
swift run codex-quota-atoll --once

# Refresh every 60 seconds (minimum accepted interval is 30 seconds)
swift run codex-quota-atoll --interval 60
```

## Test

```sh
swift test
```

## Protocol notes

The companion connects to the WebSocket JSON-RPC service exposed by current Atoll releases at `ws://127.0.0.1:9020`. This avoids relying on the legacy XPC listener, which is unavailable in some signed Atoll builds, while preserving Atoll's own extension authorization and validation.

The app-server field is named `usedPercent`; Atoll intentionally displays `100 - usedPercent` as quota remaining. Window labels are derived from `windowDurationMins` instead of assuming that primary always means five hours. Missing secondary-window, credit, and plan fields are handled gracefully because availability varies by account and workspace.
