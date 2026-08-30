#!/bin/zsh

set -euo pipefail

script_dir=${0:A:h}
sample_dir=${script_dir:h}
install_dir="$HOME/Library/Application Support/CodexQuotaAtoll"
launch_agents_dir="$HOME/Library/LaunchAgents"
label="com.tibetgao.CodexQuotaAtoll"
plist_path="$launch_agents_dir/$label.plist"
binary_path="$install_dir/codex-quota-atoll"
stdout_path="$install_dir/companion.log"
stderr_path="$install_dir/companion-error.log"

cd "$sample_dir"
swift build -c release

mkdir -p "$install_dir" "$launch_agents_dir"
install -m 0755 ".build/release/codex-quota-atoll" "$binary_path"

rm -f "$plist_path"
plutil -create xml1 "$plist_path"
plutil -insert Label -string "$label" "$plist_path"
plutil -insert ProgramArguments -json "[\"$binary_path\",\"--interval\",\"60\"]" "$plist_path"
plutil -insert RunAtLoad -bool true "$plist_path"
plutil -insert KeepAlive -bool true "$plist_path"
plutil -insert ProcessType -string Background "$plist_path"
plutil -insert ThrottleInterval -integer 10 "$plist_path"
plutil -insert StandardOutPath -string "$stdout_path" "$plist_path"
plutil -insert StandardErrorPath -string "$stderr_path" "$plist_path"

launchctl bootout "gui/$UID/$label" 2>/dev/null || true
launchctl bootstrap "gui/$UID" "$plist_path"
launchctl kickstart -k "gui/$UID/$label"

echo "Installed $binary_path"
echo "Started $label; quota refresh interval is 60 seconds."
