#!/bin/zsh
set -euo pipefail
script_dir="${0:A:h}"
icon_source="${1:-$script_dir/../assets/app-icon-source-v1.png}"
[[ -f "$icon_source" ]] || { print -u2 'Icon source PNG is missing'; exit 2; }
resources="$script_dir/native/Resources"
icon_tmp=$(mktemp -d -t local-recorder-icon)
iconset="$icon_tmp/AppIcon.iconset"
mkdir -p "$resources" "$iconset"
sips -z 1024 1024 "$icon_source" --out "$resources/AppIcon1024.png" >/dev/null
for icon_size in 16 32 128 256 512; do
  sips -z "$icon_size" "$icon_size" "$resources/AppIcon1024.png" --out "$iconset/icon_${icon_size}x${icon_size}.png" >/dev/null
  retina_size=$((icon_size * 2))
  sips -z "$retina_size" "$retina_size" "$resources/AppIcon1024.png" --out "$iconset/icon_${icon_size}x${icon_size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$resources/AppIcon.icns"
print "$resources/AppIcon.icns"
