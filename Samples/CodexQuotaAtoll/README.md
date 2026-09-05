# Codex Dashboard for Atoll

A small macOS companion that reads the signed-in Codex account's current rate-limit windows from `codex app-server` and publishes a dedicated Atoll dashboard tab. It also summarizes recent local Codex tasks and follows their local event streams in the background.

## What it shows

- Remaining percentage in each available quota window
- Remaining percentage in the secondary quota window, when present
- The next reset time
- Optional credit balance and plan metadata when the account returns them
- Icon-based activity states: preparing, working, approval needed, question, reconnecting, completed, idle, cancelled, timed out, failed, and offline
- Up to 100 recent tasks, ordered by last activation time and revealed five at a time
- Current task plan, latest thinking/activity, model, reasoning effort, and recent effective output speed
- A temporary high-priority Atoll sneak peek when a task needs approval or an answer
- Unified purple, mint, amber, and coral dashboard colors

The dashboard intentionally omits Atoll's minimalistic/closed-island replacement. Its compact quota/reset strip stays pinned at the top while the remaining space belongs to the session view. When work is active, active tasks are expanded and history moves behind a disclosure row; when nothing is active, history opens directly. Completion and approval alerts also use Atoll's live activity API. Scroll protection requires supporting host code; JavaScript event propagation alone cannot disable Atoll's native close gesture.

Current Atoll releases clamp third-party tabs to the host's configured content height even when an extension supplies a larger `preferredHeight`. The dashboard requests the optional `.contentOnly` layout; older official hosts ignore it and keep their native header and padding. The proposed SDK support is tracked in [AtollExtensionKit #18](https://github.com/Ebullioscopic/AtollExtensionKit/pull/18). Header-free layout and hover scroll protection require a corresponding Atoll host update and are not promised on unmodified official releases. On those releases, use Atoll's global close-gesture setting if scrolling closes or blurs the tab; that setting affects other tabs too. The companion never changes it automatically.

## Distribution status

This is an independent third-party extension, not an official Atoll or OpenAI product. Install the companion alongside the official Atoll app; this distribution does not replace or patch Atoll. The first public release is a preview while host integration is under review.

Source is distributed with the repository's LGPL-3.0 license. A locally built Apple Silicon executable may be provided with the complete matching source and build scripts. It is not Developer ID signed or notarized. You can build the source with Xcode's Swift toolchain instead. Do not disable Gatekeeper to install it.

The dashboard reads local task titles, messages and usage data, caches a snapshot under `~/Library/Application Support/CodexQuotaAtoll/`, and passes display content to the local Atoll process. It does not upload task history to a service. Codex's own app-server performs account usage requests. Do not publish the snapshot, logs or bridge token with bug reports.

To uninstall the background service, run `zsh Scripts/uninstall-background-companion.sh` from this directory. It stops and removes the launch agent, while retaining the binary, cached data and preferences so removal is recoverable.

The quota strip opens ChatGPT's web Usage and billing settings, and an active card opens its task. History rows show relative activity times; a first click expands the latest result with its exact activity time, and clicking the expanded card again opens the corresponding Codex task. Active sessions stay out of history, while a newly completed session appears once as the expanded completion card. Question options copy the selected answer and open that Codex task, ready to paste; a detached companion cannot resolve a pending request owned by the already-running Codex desktop process through the public app-server surface. Navigation is handled by a loopback-only HTTP bridge bound to `127.0.0.1:9031`; it validates thread UUIDs, requires an ephemeral per-process token on every request, and never accepts remote connections.

The agenda header includes dashboard settings with five persistent accent choices. AtollExtensionKit does not currently expose a host API for adding extension-owned controls to Atoll Settings, so this control lives inside the Codex tab and persists through the companion's preferences domain.

To reduce perceived cold starts, the companion stores the last successful dashboard snapshot under `~/Library/Application Support/CodexQuotaAtoll/` and presents it immediately after authorization. Quota and the task index refresh periodically, while local task activity is polled every two seconds and rendered as soon as it changes. A failed refresh keeps the last useful data visible and marks the activity tile as timed out or offline.

For normal use, install the companion as a per-user background service. It starts at login, restarts after an unexpected exit, refreshes quota once per minute, and preserves the last successful snapshot:

```bash
./Scripts/install-background-companion.sh
```

Atoll owns the embedded `WKWebView` and currently creates it lazily when a web-backed tab is selected. The extension API has no keep-alive or prewarm hook, so cached data removes the Codex/network wait but cannot fully remove the host's first WebKit paint delay.

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

## Extension architecture

`AgentMonitoringProvider`, `AgentNavigationRouting`, and `AgentActionHandling` define provider-neutral seams for future agent integrations. Capability flags already cover session overview, approvals, questions, plan review, usage, terminal/session navigation, sounds, and remote sessions. Codex is the first provider; future Vibe Island-style features can be added without coupling their transport or actions to the dashboard renderer.
