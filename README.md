# ShellCast

**Website:** [shellcast.ccday.top](https://shellcast.ccday.top)

A native iOS/iPadOS terminal app for managing remote sessions from your phone. Built for the use case of operating terminal sessions (e.g. Claude Code) on your laptop while away from it — grant permissions, send commands, check output, all from your pocket.

## How It Works

Connect to your machines over Tailscale's private network, browse and attach to tmux sessions, and interact through a full terminal emulator with a touch-optimized keyboard toolbar.

```
iPhone/iPad  →  Tailscale VPN  →  SSH  →  tmux attach  →  Full Terminal
```

## Tech Stack

- **SwiftUI** / iOS 17+
- **SwiftTerm** — xterm-256color terminal emulator
- **Citadel** — pure Swift SSH (SwiftNIO-based)
- **Tailscale** — private network layer (separate VPN app)
- **SwiftData** — connection storage
- **iOS Keychain** — credential storage

## Features

### Implemented

- **SSH Connections** — password auth, SSH key authentication, Tailscale SSH (zero-password), saved connections with Keychain storage
- **Mosh Protocol** — survive network switches and long sleep without reconnecting
- **Tmux Integration** — list sessions, attach to existing, create new, or connect without tmux
- **Full Terminal Emulator** — xterm-256color via SwiftTerm with proper ANSI rendering
- **Keyboard Toolbar** — Ctrl, Alt, Esc, Tab, arrow keys, PgUp/PgDn, and common symbols (`| / \ ~ - _`) above the keyboard
- **Auto-Reconnect** — detects connection loss on returning from background, automatically reconnects SSH and reattaches tmux session
- **Voice Input** — dictate commands via WhisperKit (on-device) or Apple Speech Recognition, with multiline preview before sending
- **AI Agent Detection** — plugin architecture to detect and display AI agents (Claude, OpenCode, Kimi) with brand icons
- **Session Snapshots** — terminal preview thumbnails on the home screen
- **Settings** — theme (dark/light/custom), font selection (SF Mono, Menlo, JetBrains Mono Nerd Font), font size, cursor mode/blink, scrollback buffer size
- **Background Resilience** — extends background execution to keep SSH alive during brief phone locks

## Requirements

- iOS 17.0+
- Xcode 15+
- [Tailscale](https://apps.apple.com/app/tailscale/id1470499037) iOS app (for Tailscale network access)

## Building

```bash
open ShellCast/ShellCast.xcodeproj
```

Dependencies are managed via Swift Package Manager and resolve automatically on first build.

## License

MIT
