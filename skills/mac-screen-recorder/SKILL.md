---
name: mac-screen-recorder
description: Open or maintain the local macOS recorder with buttons and global hotkeys for screen, system audio, and optional microphone capture. The recorder runs independently without an LLM or cloud API. Use for this recorder, not for live streaming or video editing.
---

# 本机录屏

This is a manual, button-and-hotkey recorder. Its separately installed native app runs without Codex, this skill, an LLM, a login, an API key, or a network service.

## Open and use

Run `zsh scripts/open.sh` relative to this skill's directory. It searches the user's Applications directory and `/Applications`; an absolute App path can be supplied as an argument or via `LOCAL_SCREEN_RECORDER_APP`. Opening the app leaves it idle; the user starts capture with its button or hotkey. If the App is absent, report that installation is needed rather than silently compiling or downloading it.

- Application: `~/Applications/本机录屏.app` or `/Applications/本机录屏.app`.
- `Control + Shift + R`: start / stop and save. `Control + Shift + S`: show controls. These replace the old four-key bindings. The app shows key names instead of only macOS symbols.
- System audio defaults on; microphone defaults off. Choose the microphone before starting.
- “选择画面” invokes Apple's picker for a display, window, or application. Without a selection, the main display is used. Audio capture follows the selected content; full-display capture is the mode for all system sound.
- “保存位置” chooses a directory; the default is the user's Movies/本机录屏 directory.
- H.264 MP4, 30 or 60 fps, scaled 1080p or original size. System sound and microphone are mixed into the output by Apple's recording framework on the current OS.
- Closing the control window keeps the app available in the menu bar. Quit during recording offers to stop, save, and then exit.

Screen/system-audio consent and optional microphone consent are macOS permissions. Missing microphone permission stops the requested recording instead of silently dropping human speech. Do not change system security settings or claim an untested recording is verified. The public App is an ad-hoc-signed beta, not Developer ID signed or notarized; disclose this if downloaded copies are blocked by Gatekeeper. Do not disable Gatekeeper or SIP.

## Maintain

Native source is in `scripts/native/`. Build with `zsh scripts/build.sh /absolute/path/to/本机录屏.app`. Requires Apple Silicon, macOS 15+, and the local Apple Swift toolchain. There are no third-party packages to install. Before replacing a running app, stop recording and quit normally. The 0.2 interface uses the local `StudioUI.swift` components; keep capture and permission behavior intact for cosmetic changes. The generated icon source is in `assets/`; rebuild its ICNS with `zsh scripts/prepare-icon.sh` only when changing the icon source. Image generation is a design-time step, not an app dependency.

Use `--diagnostics` only for idle launch checks; it writes local permission/hotkey state into the system temporary directory, without starting capture. A successful build or launch does not establish successful screen and dual-audio recording. Actual recordings have an adjacent JSON report with duration, track counts, source packet counts, and warnings. Check the playable picture and audible sources when validating.

For shortcut maintenance, launch with `--hotkey-test` to check registration and received key events without starting capture. The recording hotkey is intercepted in this explicit test mode; quit and relaunch normally before handing the app back to the user. Shortcut collision checks should include the current system configuration, official Codex bindings and any accessible custom overrides; do not promise compatibility with every other app.
