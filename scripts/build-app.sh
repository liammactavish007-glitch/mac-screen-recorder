#!/bin/zsh
set -euo pipefail
repo_dir="${0:A:h:h}"
output_app="${1:-$repo_dir/dist/本机录屏.app}"
exec zsh "$repo_dir/skills/mac-screen-recorder/scripts/build.sh" "$output_app"
