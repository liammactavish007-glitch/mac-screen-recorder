#!/bin/zsh
set -euo pipefail
repo_dir="${0:A:h:h}"
skills_root="${1:-${CODEX_HOME:-$HOME/.codex}/skills}"
[[ "$skills_root" == /* ]] || { print -u2 'Use an absolute skills parent directory.'; exit 2; }
skill_target="$skills_root/mac-screen-recorder"
[[ ! -e "$skill_target" && ! -L "$skill_target" ]] || { print -u2 'The skill already exists; no files were replaced.'; exit 2; }
mkdir -p "$skills_root"
cp -R -X "$repo_dir/skills/mac-screen-recorder" "$skill_target"
print "Installed skill: $skill_target"
print 'Install the App separately; installing the skill does not start recording.'
