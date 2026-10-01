#!/bin/zsh
set -euo pipefail
app_path="${1:-${LOCAL_SCREEN_RECORDER_APP:-}}"
if [[ -z "$app_path" ]]; then
  for candidate in "$HOME/Applications/本机录屏.app" '/Applications/本机录屏.app'; do
    if [[ -d "$candidate" ]]; then app_path="$candidate"; break; fi
  done
fi
[[ -n "$app_path" && "$app_path" == /* && -d "$app_path" ]] || {
  print -u2 'App not found. Install 本机录屏.app or pass its absolute path.'
  exit 1
}
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist" 2>/dev/null || true)
[[ "$bundle_id" == dev.liam.local-screen-recorder ]] || { print -u2 'Refusing to open an unrelated application.'; exit 2; }
open "$app_path"
