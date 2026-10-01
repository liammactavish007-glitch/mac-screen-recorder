#!/bin/zsh
set -euo pipefail
script_dir="${0:A:h}"
app_dir="${1:?Usage: zsh build.sh /absolute/path/to/本机录屏.app}"
[[ "$app_dir" == /* && "$app_dir" == *.app ]] || { print -u2 'Output must be an absolute .app path'; exit 2; }
if [[ -e "$app_dir" ]]; then
  existing_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_dir/Contents/Info.plist" 2>/dev/null || true)
  [[ "$existing_id" == dev.liam.local-screen-recorder ]] || { print -u2 'Refusing to replace an unrelated application'; exit 2; }
fi
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
xcrun swiftc -swift-version 5 -parse-as-library -O -target arm64-apple-macosx15.0 \
  "$script_dir/native/Main.swift" -o "$app_dir/Contents/MacOS/LocalScreenRecorder" \
  "$script_dir/native/StudioUI.swift" \
  -framework AppKit -framework AVFoundation -framework Carbon -framework ScreenCaptureKit
cp -X "$script_dir/native/Info.plist" "$app_dir/Contents/Info.plist"
if [[ -f "$script_dir/native/Resources/AppIcon.icns" ]]; then
  cp -X "$script_dir/native/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
  cp -X "$script_dir/native/Resources/AppIcon1024.png" "$app_dir/Contents/Resources/AppIcon1024.png"
fi
if [[ -f "$script_dir/../LICENSE" ]]; then
  cp -X "$script_dir/../LICENSE" "$app_dir/Contents/Resources/LICENSE.txt"
fi
# Remove Finder/resource-fork metadata from our generated build only, before signing.
# Quarantine attributes and system security policy are left untouched.
xattr -r -d com.apple.FinderInfo "$app_dir" 2>/dev/null || true
xattr -r -d com.apple.ResourceFork "$app_dir" 2>/dev/null || true
codesign --force --sign - --identifier dev.liam.local-screen-recorder "$app_dir"
codesign --verify --deep --strict --verbose=2 "$app_dir"
print "$app_dir"
