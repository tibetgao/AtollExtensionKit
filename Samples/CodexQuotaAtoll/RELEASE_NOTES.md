# Codex Dashboard for Atoll 0.1.0-preview.1

First public preview of the independent Codex companion for Atoll.

- Account quota remaining and reset times.
- Active tasks, recent completion details and paginated history.
- One expanded history item, clipped preview text and a 0.5-second expansion.
- Relative last-activity time in rows and exact local time in details.
- Loopback-only, per-process-token-protected navigation bridge.
- Optional per-user background service with uninstall instructions.

## Install

Download the source archive and open `Samples/CodexQuotaAtoll/README.md`.
With Xcode's Swift toolchain installed, enter `Samples/CodexQuotaAtoll` and run
`swift run codex-quota-atoll`. Atoll must be running with its RPC server enabled;
approve the companion in Atoll and allow interactive extension web content.
For login startup, run `zsh Scripts/install-background-companion.sh`.

An Apple Silicon archive, when attached, includes `codex-quota-atoll` and a
`source` directory containing the complete matching source, LGPL-3.0 license
and build scripts. Run `./codex-quota-atoll --interval 60` for foreground use.
The binary has no Developer ID signature or notarization. Building from the
included source is supported; Intel users must build from source.

## Compatibility and limitations

Use the official Atoll application. This release neither bundles nor modifies
the host. On existing official hosts the extension header remains visible and
scrolling can trigger Atoll's close/blur gesture. Header-free layout and scoped
scroll protection depend on upstream host support, not just installing this
companion. SDK proposal: https://github.com/Ebullioscopic/AtollExtensionKit/pull/18.
Host proposal (dependent draft): https://github.com/Ebullioscopic/Atoll/pull/817.

Question buttons copy an answer and open Codex; they do not submit it. Task
details depend on Codex's local event format and may change with Codex updates.
This preview is not an official Atoll/OpenAI release or an endorsed integration.
