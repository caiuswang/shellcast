# ShellCast - iOS Remote Terminal Manager

## Context
Build a native iOS/iPadOS app ("ShellCast") for managing remote terminal sessions from iPhone/iPad. The core use case is operating Claude Code sessions (granting permissions, sending input) on a laptop from a phone. Built on Tailscale + Mosh + SSH + tmux for resilient, always-on connectivity.

## Tech Stack
- **Framework**: SwiftUI, iOS 17+
- **Terminal Emulator**: SwiftTerm (SPM) — xterm-compatible terminal rendering
- **SSH**: Citadel (pure Swift, built on SwiftNIO) — password + key auth, PTY, exec
- **Mosh**: libmoshios.xcframework (cross-compiled from blinksh/build-mosh)
- **Storage**: iOS Keychain (passwords, SSH keys) + SwiftData (connection metadata)
- **Project Gen**: XcodeGen (`project.yml`)

## How Tailscale Fits In
Tailscale runs as a separate VPN app on iOS. ShellCast does **not** embed Tailscale — it connects over the network that Tailscale's VPN provides. When the user has the Tailscale iOS app active, SSH to a Tailscale IP (e.g. `100.x.y.z`) works through the VPN tunnel automatically. For Tailscale SSH (auth handled at network layer), the app connects with empty password.

## Project Structure

```
ShellCast/
├── project.yml                          # XcodeGen project spec
├── ShellCast/
│   ├── ShellCastApp.swift               # @main entry point
│   ├── Models/
│   │   ├── Connection.swift             # SwiftData @Model: host, port, username, auth, type
│   │   ├── SessionRecord.swift          # SwiftData @Model: active session tracking + thumbnail
│   │   ├── TmuxSession.swift            # Parsed tmux session struct
│   │   ├── TerminalSettings.swift       # @Observable: theme, font, cursor, scrollback (UserDefaults)
│   │   ├── AuthMethod.swift             # Enum: password, keyFile, tailscaleSSH
│   │   └── ConnectionType.swift         # Enum: auto, ssh, mosh
│   ├── Views/
│   │   ├── Main/
│   │   │   ├── HomeView.swift           # Active sessions + saved connections
│   │   │   ├── ActiveSessionCard.swift  # Terminal preview thumbnail
│   │   │   └── ConnectionRow.swift      # Saved connection list item
│   │   ├── Connection/
│   │   │   └── EditConnectionView.swift # Add/edit connection form (modal sheet)
│   │   ├── Tmux/
│   │   │   └── TmuxBrowserView.swift    # Tmux session list + session row
│   │   ├── Terminal/
│   │   │   ├── TerminalContainerView.swift  # Hosts SwiftTerm TerminalView
│   │   │   └── KeyboardToolbar.swift        # Custom key bar: Ctrl Alt Esc Tab arrows symbols
│   │   └── Settings/
│   │       └── SettingsView.swift           # Theme/font/cursor/scrollback settings + pickers
│   ├── Services/
│   │   ├── SSHService.swift             # SSH via Citadel: connect, exec, PTY shell
│   │   ├── TransportSession.swift       # Protocol: outputStream, send, resize, disconnect
│   │   ├── ConnectionManager.swift      # Orchestrator: manages active sessions
│   │   ├── TmuxParser.swift             # Parse `tmux list-sessions` output
│   │   └── KeychainService.swift        # iOS Keychain CRUD for passwords & SSH keys
│   ├── Terminal/
│   │   └── TerminalBridge.swift         # Pipes TransportSession ↔ SwiftTerm TerminalView
│   └── Utilities/
│       └── TimeFormatting.swift          # Relative time display ("1d ago")
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    SwiftUI Views                     │
│  HomeView  EditConnectionView  TmuxBrowserView      │
│                TerminalContainerView                 │
└──────────────────────┬──────────────────────────────┘
                       │
              ┌────────▼────────┐
              │ ConnectionManager│  (@Observable)
              │  + activeSessions│
              └────────┬────────┘
                       │
         ┌─────────────┼─────────────┐
         ▼             ▼             ▼
   ┌──────────┐  ┌──────────┐  ┌──────────┐
   │SSHService│  │MoshService│  │TmuxParser│
   │(Citadel) │  │(Phase 4) │  │(exec cmd)│
   └────┬─────┘  └──────────┘  └──────────┘
        │
        ▼
   ┌──────────────────────┐
   │   TransportSession   │  (protocol)
   │  SSHSession / (Mosh) │
   └──────────┬───────────┘
              │
              ▼
   ┌──────────────────────┐
   │  SwiftTerm            │
   │  TerminalView (UIKit) │  ← UIViewRepresentable
   └──────────────────────┘

   ┌──────────────────────┐
   │  KeychainService      │  passwords + SSH keys
   │  SwiftData            │  Connection, SessionRecord
   └──────────────────────┘
```

**Key abstraction**: `TransportSession` protocol with `outputStream: AsyncStream<Data>`, `send(_:)`, `resize(cols:rows:)`, `disconnect()`. Both SSH and Mosh conform to it, making the terminal layer transport-agnostic.

## Navigation Flow

```
HomeView (root)
  ├─ FAB (+) → sheet: EditConnectionView → save + connect
  ├─ Tap saved connection → SSH/Mosh connect → TmuxBrowserView (if tmux found)
  │   ├─ Tap tmux session → tmux attach → TerminalContainerView (fullscreen)
  │   └─ "Connect without tmux" → TerminalContainerView (fullscreen)
  └─ Tap active session card → TerminalContainerView (reconnect)
```

## SPM Dependencies

| Package | Purpose | Status |
|---------|---------|--------|
| SwiftTerm (`migueldeicaza/SwiftTerm`) | Terminal emulation + rendering | Added |
| Citadel (`orlandos-nl/Citadel`) | Pure Swift SSH (PTY, exec, auth) | Added |
| libmoshios.xcframework (manual) | Mosh client for iOS | Phase 4 |

## Phased Implementation

### Phase 1: Foundation — SSH + Terminal ✅ COMPLETE
- [x] Create Xcode project with XcodeGen, add SwiftTerm + Citadel via SPM
- [x] `Connection` SwiftData model + `KeychainService`
- [x] `HomeView` with saved connections list
- [x] `EditConnectionView` form (Name, Host, Port, Username, Password/Key, Connection Type)
- [x] `SSHService` — real SSH via Citadel (connect, exec, PTY shell)
- [x] `ConnectionManager` — orchestrates connections, error handling
- [x] `TmuxParser` — list tmux sessions over SSH exec
- [x] Connection flow wired up: tap connection → SSH → tmux browser or terminal
- [x] `TerminalBridge` — pipes SSHSession output ↔ SwiftTerm TerminalView
- [x] `TerminalContainerView` — UIViewRepresentable wrapping SwiftTerm
- [x] Test real SSH connection end-to-end on device

**Milestone: SSH into Tailscale machine and type commands from phone.** ✅

### Phase 2: Tmux Integration — IN PROGRESS
- [x] Flow: connect → tmux browser → select session → `tmux attach -t` → terminal
- [x] "Connect without tmux" and "New tmux session" actions
- [x] Tmux window listing within a session
  - Add `TmuxWindow` model (index, name, isActive, paneCount)
  - Add `TmuxParser.listWindows()` — `tmux list-windows -t session -F format`
  - Add `TmuxWindowBrowserView` — drill-down from session to windows
  - Update `TmuxBrowserView` to navigate to window list on session tap
  - Update `HomeView.openShell` to support `tmux attach -t session:window`
- [ ] In-terminal tmux session/window switcher overlay

**Milestone: Full flow from home → tmux session → terminal.** (core flow ✅, window-level switching TODO)

### Phase 3: Keyboard Toolbar + UX Polish — IN PROGRESS
- [x] Custom `KeyboardToolbar` — persistent toolbar with Ctrl/Alt modifiers, Esc, Tab, arrows, PgUp/PgDn, symbols
  - Layout adapts based on keyboard visibility
  - Sends correct ANSI escape sequences and control characters
- [x] iPhone keyboard testing and layout
- [ ] Terminal snapshot rendering for active session cards
- [ ] `ActiveSessionCard` with live thumbnail preview
- [ ] Background session persistence (`beginBackgroundTask`)
- [ ] iPad layout optimization

**Milestone: Comfortable daily-driver terminal experience.** (keyboard ✅, polish TODO)

### Phase 4: Mosh Integration
- [ ] Clone and build `blinksh/build-mosh` → produce `libmoshios.xcframework`
- [ ] `MoshService` — SSH bootstrap → run `mosh-server` → parse MOSH_KEY + UDP port → init mosh-client
- [ ] `MoshSession` conforming to `TransportSession`
- [ ] "Auto" connection type logic (try Mosh first, fallback SSH)
- [ ] Test WiFi↔cellular handoff, sleep/wake reconnection
- [ ] Handle iOS background execution limits (Mosh UDP keeps state server-side)

**Milestone: Connections survive network changes and phone sleep.**

### Phase 5: Polish + Ship
- [ ] SSH key file import via Files app (`UIDocumentPickerViewController`)
- [ ] Tailscale SSH "none" auth support
- [x] Settings view — theme, font, font size, cursor mode/blink, scrollback
- [x] Settings applied to SwiftTerm TerminalView (colors, font, cursor style, scrollback)
- [x] Visible edit button on connection rows in main menu
- [ ] iPad layout optimization (larger terminal, sidebar option)
- [ ] App icon and launch screen
- [ ] Error handling, edge cases, empty states
- [ ] TestFlight beta

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Mosh iOS cross-compilation | High | Scheduled last (Phase 4); app is fully functional with SSH-only |
| Citadel API changes | Low | Actively maintained (last commit 2 days ago); pure Swift, no C deps |
| iOS kills background SSH | Medium | Mosh handles this; for SSH, auto-reconnect + tmux preserves work server-side |
| SwiftTerm UIKit-in-SwiftUI quirks | Low | Follow SwiftTermApp's proven UIViewRepresentable pattern |
| Keychain on Simulator | Low | Test on real device early; simple get/set wrapper with proper error handling |

## Verification
- **Phase 1**: SSH to a Tailscale host, run `ls`, `vim`, verify terminal rendering
- **Phase 2**: Verify tmux sessions listed correctly, attach/detach/switch works
- **Phase 3**: Test all toolbar keys send correct escape sequences in tmux
- **Phase 4**: Connect via Mosh, toggle airplane mode, verify auto-reconnection
- **Phase 5**: TestFlight on iPhone + iPad, full end-to-end workflow

## Reference
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — terminal emulator
- [SwiftTermApp](https://github.com/migueldeicaza/SwiftTermApp) — reference SwiftUI SSH terminal app
- [Citadel](https://github.com/orlandos-nl/Citadel) — pure Swift SSH library
- [Blink Shell](https://github.com/blinksh/blink) — open source iOS terminal with Mosh
- [build-mosh](https://github.com/blinksh/build-mosh) — scripts to build Mosh for iOS
