#!/bin/zsh
set -euo pipefail
label="com.tibetgao.CodexQuotaAtoll"
plist_path="$HOME/Library/LaunchAgents/$label.plist"
launchctl bootout "gui/$UID/$label" 2>/dev/null || true
if [[ -f "$plist_path" ]]; then
    backup_dir=$(mktemp -d "$HOME/.Trash/CodexQuotaAtoll-uninstall.XXXXXX")
    mv "$plist_path" "$backup_dir/"
fi
echo "Stopped Codex Dashboard. Launch agent moved to Trash if present."
echo "Binary, cached data and preferences were retained."
