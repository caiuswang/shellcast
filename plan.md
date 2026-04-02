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
│   │   ├── ConnectionType.swift         # Enum: auto, ssh, mosh
│   │   └── ClaudeCodeSession.swift      # Claude Code session model (id, project, summary)
│   ├── Views/
│   │   ├── Main/
│   │   │   ├── HomeView.swift           # Active sessions + saved connections
│   │   │   ├── ActiveSessionCard.swift  # Terminal preview thumbnail
│   │   │   └── ConnectionRow.swift      # Saved connection list item
│   │   ├── Connection/
│   │   │   └── EditConnectionView.swift # Add/edit connection form (modal sheet)
│   │   ├── AITools/
│   │   │   └── ClaudeCodeBrowserView.swift  # Claude Code session browser (grouped by project)
│   │   ├── Tmux/
│   │   │   └── TmuxBrowserView.swift    # Tabbed browser: Tmux | Claude Tmux | Sessions
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
│   │   ├── AIAgent/                     # AI agent plugin architecture
│   │   │   ├── AIAgentPlugin.swift      # Protocol for agent integration
│   │   │   ├── AIAgentRegistry.swift    # Plugin registry and discovery
│   │   │   ├── ClaudeCodeParser+Compatibility.swift  # Legacy wrapper
│   │   │   ├── Plugins/
│   │   │   │   ├── ClaudeAgent.swift    # Claude Code plugin
│   │   │   │   └── OpenCodeAgent.swift  # OpenCode plugin
│   │   │   └── README.md                # Plugin development guide
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

### Phase 2: Tmux Integration ✅ COMPLETE
- [x] Flow: connect → tmux browser → select session → `tmux attach -t` → terminal
- [x] "Connect without tmux" and "New tmux session" actions
- [x] Tmux window listing within a session
  - Add `TmuxWindow` model (index, name, isActive, paneCount)
  - Add `TmuxParser.listWindows()` — `tmux list-windows -t session -F format`
  - Add `TmuxWindowBrowserView` — drill-down from session to windows
  - Update `TmuxBrowserView` to navigate to window list on session tap
  - Update `HomeView.openShell` to support `tmux attach -t session:window`
- [x] Rename and delete sessions/windows from browser
  - Add `TmuxParser` commands: renameSession, killSession, renameWindow, killWindow
  - Context menus on session/window rows with rename (text alert) and delete (confirmation)
  - Auto-refresh list after each action
- [x] In-terminal tmux session/window switcher overlay
  - Tmux button (green icon) on keyboard toolbar triggers overlay
  - `TmuxSwitcherOverlay` shows sessions → drill into windows
  - Highlights current session; switch via `tmux switch-client` / `tmux select-window`
  - `TmuxParser`: added `switchClient`, `selectWindow`, `currentSessionName`

**Milestone: Full flow from home → tmux session → terminal.** ✅

### Phase 3: Keyboard Toolbar + UX Polish ✅ COMPLETE
- [x] Custom `KeyboardToolbar` — persistent toolbar with Ctrl/Alt modifiers, Esc, Tab, arrows, PgUp/PgDn, symbols
  - Layout adapts based on keyboard visibility
  - Sends correct ANSI escape sequences and control characters
- [x] iPhone keyboard testing and layout
- [x] Terminal snapshot rendering for active session cards
  - `TerminalBridge.captureSnapshot()` renders terminal view to 360x240 JPEG thumbnail
  - Snapshots captured on minimize, close, and app background
  - `ActiveSessionCard` displays snapshot when available, falls back to terminal icon
- [x] Tab-based navigation (History, Connections, Settings)
  - History tab: sessions grouped by connection name, tap to resume, long-press to delete
  - Connections tab: saved connections with FAB add button
  - Settings tab: moved from modal sheet to dedicated tab
- [x] Terminal minimize and session resume
  - Minimize button (chevron down) dismisses terminal without disconnecting
  - Close button (X) disconnects and marks session inactive
  - Tapping a history card reconnects SSH and re-attaches to tmux session
- [x] `ActiveSessionCard` with live thumbnail preview
  - Pulsing green dot and green border on active session cards (isolated views to avoid re-render flicker)
  - `snapshotCapturedAt` timestamp on `SessionRecord`; "just now" for <60s in `TimeFormatting`
  - Snapshot capture guarded against disconnected/reconnecting overlay states
  - History tab shows all sessions (active + inactive), not just active
  - Context menu "Deactivate" marks session inactive and disconnects transport
- [x] Background session persistence (`beginBackgroundTask`)
  - `ShellCastApp` requests background time with named task `ShellCast.KeepSSHAlive`
  - On background: captures terminal snapshots for all registered bridges via `ConnectionManager.activeBridges`
  - On expiration: marks sessions inactive if transport is no longer connected
  - `TerminalContainerView` registers/unregisters bridge with `ConnectionManager` on appear/disappear
  - Foreground auto-reconnect already handled by `TerminalContainerView.checkConnectionOnForeground()`
- [x] iPad layout optimization
  - `iPadContentWidth()` view modifier for centering content with max width on iPad
  - HomeView: `LazyVGrid` for session cards on regular width, constrained connections list
  - ActiveSessionCard: responsive thumbnail (240x160 on iPad, 180x120 on iPhone)
  - KeyboardToolbar: larger buttons (15pt font, wider insets) on regular width
  - TmuxSwitcherOverlay: larger frame (480x500) on iPad
  - EditConnectionView, TmuxBrowserView, SettingsView: constrained content width
  - All adaptations use `horizontalSizeClass` (works with Split View, Stage Manager)

**Milestone: Comfortable daily-driver terminal experience.** ✅

### Phase 4: Mosh Integration ✅ COMPLETE
- [x] Pre-built `mosh.xcframework` + `Protobuf_C_.xcframework` from blinksh releases (download script)
- [x] `MoshSession` conforming to `TransportSession` — wraps `mosh_main()` with pipe I/O
- [x] `MoshService` — SSH bootstrap → run `mosh-server` → parse MOSH_KEY + UDP port → init mosh-client
- [x] "Auto" connection type logic (try Mosh first, fallback SSH)
- [x] State serialization callback for background persistence
- [x] Generalized `TerminalBridge` and `TerminalContainerView` to `TransportSession` protocol
- [x] Test WiFi↔cellular handoff, sleep/wake reconnection
  - `NetworkMonitor` service using `NWPathMonitor` for proactive handoff detection
  - Triggers SSH reconnection check on interface change (WiFi→cellular, etc.)
  - Mosh sessions log transitions but handle reconnection natively via UDP
- [x] Handle iOS background execution limits (Mosh UDP keeps state server-side)
  - `MoshService.saveSessionState()` serializes Mosh client state to disk on background
  - Auto-expiry: saved states discarded after 10 minutes (server timeout)
  - Foreground resume: detects if Mosh session survived iOS suspension
  - Graceful fallback: shows reconnect prompt if session was killed

**Milestone: Connections survive network changes and phone sleep.** ✅

### Phase 5: Polish + Ship
- [x] SSH key file import via Files app (`fileImporter` + Keychain storage)
- [x] Tailscale SSH "none" auth support (added to auth picker, no credentials needed)
- [x] Settings view — theme, font, font size, cursor mode/blink, scrollback
  - Verified redesigned Settings header with hero card, quick theme chips, and active setting badges via screenshot UI test
  - Split app appearance from terminal theme, defaulted app appearance to Graphite, and verified build plus screenshot UI test
- [x] Settings applied to SwiftTerm TerminalView (colors, font, cursor style, scrollback)
- [x] Visible edit button on connection rows in main menu
- [x] iPad layout optimization (larger terminal, sidebar option)
- [x] App icon and launch screen
  - Programmatically generated 1024x1024 icon: dark terminal with green ">_" prompt
  - Asset catalog with AppIcon.appiconset configured in project.yml
  - Generator script at `Scripts/generate_app_icon.swift` for reproducibility
- [x] Error handling, edge cases, empty states
- [x] TestFlight build infrastructure
  - `Scripts/build-testflight.sh` — archive, export IPA, optional upload
  - `Scripts/ExportOptions.plist` — automatic signing for App Store Connect
  - Auto-incrementing build numbers (timestamp-based)
  - **TODO**: Set `DEVELOPMENT_TEAM` in project.yml to your Apple Team ID, then run the script
- [x] Production-ready cleanup
  - All debug prints wrapped in `#if DEBUG` via `debugLog()` utility
  - Input validation on connection form (host format, port range 1-65535)

### Phase 6: AI Agent CLI Tool Support ✅ COMPLETE
- [x] Claude Code detection over SSH (checks `/opt/homebrew/bin/claude`, `/usr/local/bin/claude`)
- [x] Claude Code session listing by scanning `~/.claude/projects/` directory
  - Extracts first user message as session summary
  - Groups sessions by project path
  - Sorted by last modified time
- [x] Tabbed browser in TmuxBrowserView (Tmux | Claude Tmux | Sessions)
  - **Tmux**: all tmux sessions with Claude Code badges on running ones
  - **Claude Tmux**: filtered view showing only sessions/windows running Claude
  - **Sessions**: browse and resume Claude Code conversations grouped by project
- [x] Claude Code process detection via process tree walk (`pgrep -P <pane_pid> -f claude`)
  - `#{pane_current_command}` shows `node` not `claude`, so child process inspection is required
- [x] Launch Claude Code inside new tmux sessions (`tmux new-session -s claude-<ts> 'claude --resume <id>'`)
- [x] SessionRecord enhanced with `aiToolType` and `aiSessionId` fields
- [x] ActiveSessionCard shows sparkles icon for Claude Code sessions in history
- [x] `WindowNavigation` wrapper for correct claude-only filtering when navigating into windows
- [x] New files: `ClaudeCodeSession.swift`, `ClaudeCodeParser.swift`, `ClaudeCodeBrowserView.swift`

**Milestone: First-class Claude Code session management from phone.** ✅

### Phase 7: AI Agent Plugin Architecture ✅ COMPLETE
- [x] **Plugin Protocol**: Created `AIAgentPlugin` protocol for extensible agent integration
  - Default implementations for common operations (detection, process scanning)
  - Customizable per-agent: session listing, commands, icon, theme color
- [x] **Plugin Registry**: `AIAgentRegistry` manages all registered plugins
  - Auto-detects installed agents on connection
  - Provides unified interface for all AI agent operations
  - Supports concurrent operations across multiple agents
- [x] **OpenCode Support**: Added plugin for OpenCode CLI (`opencode`, `oc` binaries)
  - Session storage in `~/.opencode/sessions/`
  - Blue theme color, brain icon for visual distinction
  - Resume with `opencode resume <id>`, new with `opencode start [path]`
- [x] **Generic Views**: Updated UI components to work with any registered agent
  - Dynamic tab picker showing all installed agents
  - Agent-specific session browser with proper theming
  - Multi-agent session list with filter chips
- [x] **Backward Compatibility**: `ClaudeCodeParser` wrapper maintains existing API
  - Existing code continues to work unchanged
  - Gradual migration path for new features
- [x] **Documentation**: Added `README.md` explaining how to add new agents
  - Step-by-step guide for implementing `AIAgentPlugin`
  - Example code and protocol reference

**New Files:**
- `Services/AIAgent/AIAgentPlugin.swift` - Protocol definition
- `Services/AIAgent/AIAgentRegistry.swift` - Plugin registry
- `Services/AIAgent/ClaudeCodeParser+Compatibility.swift` - Compatibility wrapper
- `Services/AIAgent/Plugins/ClaudeAgent.swift` - Claude Code plugin
- `Services/AIAgent/Plugins/OpenCodeAgent.swift` - OpenCode plugin
- `Services/AIAgent/README.md` - Developer documentation
- `Views/AITools/AIAgentBrowserView.swift` - Generic agent browser

**Milestone: Easy integration of new AI agents via plugin system.** ✅

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
- **Phase 6**: Connect to server with claude installed, verify tabbed browser, resume/new Claude sessions

## Reference
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — terminal emulator
- [SwiftTermApp](https://github.com/migueldeicaza/SwiftTermApp) — reference SwiftUI SSH terminal app
- [Citadel](https://github.com/orlandos-nl/Citadel) — pure Swift SSH library
- [Blink Shell](https://github.com/blinksh/blink) — open source iOS terminal with Mosh
- [build-mosh](https://github.com/blinksh/build-mosh) — scripts to build Mosh for iOS
