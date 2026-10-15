# NotchControl

A menu-bar app for macOS that turns the notch into a small dashboard. Built from scratch in Swift and SwiftUI, with no Xcode project required.

Features:

- **Agents**: live status of your coding agent sessions (Claude Code, GitHub Copilot CLI, OpenAI Codex CLI, Gemini CLI) with lines like "Searching the web for …", git branch, session duration and a timeline per session. Permission requests can be allowed, denied, or allowed for the rest of the session from the notch. Double-click a session to focus the terminal or editor it runs in (Terminal and iTerm2 jump to the exact tab). When a session is idle you can type a reply into it (Terminal/iTerm2 directly; other apps get it on the clipboard).
- **Tasks / Focus / Notes**: a todo list with reminders, a Pomodoro timer, and a scratch note.
- **Shelf**: drop files on the notch to park them, drag them out into any app later.
- **Music**: now playing from Spotify or Music, with album art and transport controls.
- **Clipboard**: history of copied text; click an entry to copy it back. Secrets flagged by password managers are skipped.
- **Reminders**: quick local reminders that pop in the notch, as a macOS notification, and optionally in Slack.
- **Calendar**: your next events from the system calendar, with an "in N min" heads-up in the collapsed notch.
- **Bluetooth**: a short "connected" notice in the pill and a red battery warning under 20%.
- **General**: start at login and a global shortcut (⌥Space by default) to open the notch, both in Settings.
- **Slack**: an Incoming Webhook gets a message when an agent needs approval, is waiting for you, or finishes.

Works on Macs without a notch too: it draws a small pill at the top centre of the main screen.

## Install

```sh
brew install tariqp/tap/notchcontrol
```

Then open NotchControl from /Applications, go to Settings and click *Install hooks* for the agents you use.

## Build from source

Requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh            # builds build/NotchControl.app
./build.sh --install  # also copies it to ~/Applications and launches it
```

Run it from the .app bundle, not with `swift run`: calendar access and notifications need a real bundle identifier.

## Hook up your agents

Open **Settings…** from the menu-bar icon.

- **Claude Code**: click *Install hooks*. This adds entries for SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, PermissionRequest, Notification, Stop and SessionEnd to `~/.claude/settings.json` (a backup is written next to it). New Claude Code sessions pick them up.
- **OpenAI Codex CLI**: click *Install hooks*. This adds the same Claude-style events to `~/.codex/hooks.json`. Codex requires you to trust new hooks once: run `/hooks` inside codex.
- **Gemini CLI**: click *Install hooks*. This adds BeforeTool/AfterTool/BeforeAgent/AfterAgent/… to `~/.gemini/settings.json`; the bridge maps them to the Claude shape. Gemini has no approval hook, so only status is shown.
- **GitHub Copilot CLI**: click *Install hooks*. This writes `~/.copilot/hooks/notchcontrol.json` with camelCase events (preToolUse, agentStop, …). The bridge translates them to the same shape Claude Code uses.

Each hook runs `notchcontrol-bridge`, a tiny helper inside the app bundle. It sends the event to the app over a Unix socket in `~/Library/Application Support/NotchControl/` and exits immediately if the app is not running, so hooks never slow down or break an agent.

Permission requests keep the hook open until you click **Allow** or **Deny** in the notch. **Decide in terminal** releases the hook so the agent's own prompt takes over.

## Slack

Create an Incoming Webhook at https://api.slack.com/apps (Incoming Webhooks → Add New Webhook to Workspace), paste the URL into Settings and press *Send test message*. Reminders have a per-item Slack checkbox.

## Permissions macOS will ask for

- **Automation** (Music, Spotify): to read the current track and control playback.
- **Calendars**: to list upcoming events.
- **Bluetooth**: to list connected devices.
- **Notifications**: for reminder and approval alerts.

## Layout

```
Sources/NotchControl/      the app
  AppDelegate.swift      wiring, status bar menu, Slack/notification routing
  NotchWindow.swift      the always-on-top panel over the notch
  NotchView.swift        SwiftUI for the collapsed pill and the tabs
  AgentStore.swift       sessions, activity labels, pending permission decisions
  BridgeServer.swift     Unix-socket server for notchcontrol-bridge
  HookInstaller.swift    writes Claude Code hooks
  CopilotHookInstaller.swift
  NowPlayingService.swift, ClipboardStore.swift, RemindersStore.swift,
  CalendarService.swift, BluetoothService.swift, Notifiers.swift, SettingsView.swift
Sources/notchcontrol-bridge/    the hook helper
Resources/Info.plist     bundle metadata and usage descriptions
build.sh                 builds and signs the .app (ad hoc)
```

## Not included (yet)

GitHub pull-request review requests, Sparkle auto-updates, and a custom app icon.
