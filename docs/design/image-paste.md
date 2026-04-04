# Image Paste for Claude Code

## Problem

ShellCast connects to remote Macs via SSH/Mosh. Claude Code reads images from the **local system clipboard** when the user presses Ctrl+V, showing `[image1]`. Over a remote SSH session, the iOS clipboard and the remote Mac clipboard are separate — there's no native way to paste an image from the phone into Claude Code.

## Solution

Transfer the image from the iOS clipboard to the remote Mac, set it in the remote Mac's clipboard via `osascript`, then send Ctrl+V to trigger Claude Code's native image paste.

```
Tap photo button on toolbar
  → UIPasteboard.general.image
  → Resize/compress based on quality setting
  → Base64 encode → SSH exec (chunked) → /tmp/shellcast-img-{uuid}.png
  → osascript sets remote Mac clipboard to PNG data
  → Send Ctrl+V (0x16) into PTY
  → Claude Code reads clipboard → shows [image1]
```

## Architecture

### Data Flow

```
┌─────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│  iOS Device │     │   SSH Exec Chan  │     │    Remote Mac        │
│             │     │                  │     │                     │
│ UIImage ────┼────►│ base64 chunks ───┼────►│ /tmp/shellcast-img  │
│             │     │ (50KB each)      │     │        │            │
│             │     │                  │     │        ▼            │
│             │     │                  │     │ osascript clipboard │
│             │     │                  │     │        │            │
│ Ctrl+V ─────┼────►│ PTY stdin ───────┼────►│        ▼            │
│ (0x16)      │     │                  │     │ Claude Code [img1]  │
└─────────────┘     └──────────────────┘     └─────────────────────┘
```

### Component Responsibilities

**`ImagePasteService.swift`** — Stateless service (enum with static methods)
- `prepareImage()` — Resize and compress using quality setting from `TerminalSettings`
- `transferAndSetClipboard()` — Chunked base64 transfer + osascript clipboard
- `cleanupOldImages()` — Removes `/tmp/shellcast-img-*` files older than 60 min
- `resize()` — Uses pixel dimensions (not points) with `scale = 1.0` renderer

**`TerminalBridge.swift`** — Bridge properties
- `execSession: SSHSession?` — SSH session for exec commands (same as transport for SSH, separate for Mosh)
- `imagePasteRequested: Bool` — Published flag, set by VC, observed by SwiftUI view
- `toastMessage: String?` — Published, bridges toast messages from VC to SwiftUI

**`KeyboardToolbar.swift`** — UI button
- Photo button (`photo.on.rectangle.angled`) in `fixedRightStack`, always visible
- `onPasteImage` callback → sets `bridge.imagePasteRequested = true`
- `setImageUploading()` — Visual feedback during transfer (dimmed + accent color)

**`TerminalContainerView.swift`** — Orchestration (SwiftUI view)
- `.onChange(of: bridge.imagePasteRequested)` → calls `performImagePaste()`
- `performImagePaste()` — Gets exec session, calls service, sends Ctrl+V, shows toast
- `createExecSessionForMosh()` — Creates/reuses SSH exec session for Mosh transport

**`TerminalSettings.swift`** — Quality configuration
- `ImagePasteQuality` enum: `.low` / `.medium` / `.high`
- Persisted via UserDefaults (`image_paste_quality`)

**`SettingsView.swift`** — Settings UI
- IMAGE PASTE section with Low/Medium/High segmented control

## Key Design Decisions

### Why osascript instead of file paths?

Claude Code reads images from the **system clipboard** on Ctrl+V — it does not read file paths pasted as text and treat them as images. `osascript` is the only reliable way to set the macOS clipboard to image data from the command line.

```bash
osascript -e 'set the clipboard to (read POSIX file "/tmp/img.png" as «class PNGf»)'
```

### Why chunked base64 transfer?

A single SSH exec command with a large base64 payload (>100KB) can cause `tcpShutdown` errors in NIO SSH. Splitting into 50KB chunks via multiple `printf ... >> file` exec calls is reliable.

```
exec("printf '%s' '<chunk0>' > /tmp/file.b64")
exec("printf '%s' '<chunk1>' >> /tmp/file.b64")
exec("base64 -d < /tmp/file.b64 > /tmp/file.png && rm -f /tmp/file.b64")
```

### Why orchestrate in SwiftUI instead of UIKit VC?

The `TerminalViewController` (UIKit) doesn't have access to `ConnectionManager` or `ModelContext` needed to create SSH exec sessions for Mosh. The SwiftUI `TerminalContainerView` has these via `@Environment`. The VC sets a published flag, the SwiftUI view observes and acts — same pattern as the tmux switcher.

### Why keep Mosh exec session alive?

Creating a new SSH connection for each image paste adds 2-5 seconds of latency. The exec session is created eagerly on `onAppear` and kept alive for reuse by both tmux switching and image paste. Only cleaned up on `onDisappear`.

### Why pixel dimensions in resize?

`UIImage.size` is in points. On a @3x device, a 3000pt image is 9000 actual pixels. Using `size * scale` ensures consistent output regardless of device. The renderer uses `scale = 1.0` for 1:1 point-to-pixel mapping.

## SSH Exec Session Lifecycle (Mosh)

```
onAppear
  └─ connectExecSessionForMosh()     // Eager creation
       └─ connectionManager.connectExecSession(connection)
            └─ SSHService.connect(host, port, username, password)
                 └─ moshExecSession = session
                 └─ bridge.execSession = session

performImagePaste()
  └─ sshTransportForExec             // Returns moshExecSession if available
  └─ if nil → createExecSessionForMosh()   // Fallback: create new

onDisappear
  └─ moshExecSession?.disconnect()
  └─ moshExecSession = nil
  └─ bridge.execSession = nil
```

For SSH transport, `bridge.execSession` is simply the transport itself (`transport as? SSHSession`) — no separate session needed.

## Quality Settings

| Level    | Max Dimension | Max Size | Format           | Use Case        |
|----------|---------------|----------|------------------|-----------------|
| Low      | 800px         | 300KB    | PNG → JPEG 0.85  | Cellular/slow   |
| Medium   | 1600px        | 1MB      | PNG → JPEG 0.85  | Balanced        |
| High     | 2048px        | 2MB      | PNG → JPEG 0.85  | Best quality    |

Compression strategy: Try PNG first (lossless). If PNG exceeds `maxBytes`, fall back to JPEG at decreasing quality (0.85 → 0.7 → 0.5). Last resort: reduce dimensions to 1200px + JPEG 0.7.

## Files

| File | Role |
|------|------|
| `Services/ImagePasteService.swift` | Image compression, chunked transfer, clipboard setting |
| `Terminal/TerminalBridge.swift` | `execSession`, `imagePasteRequested`, `toastMessage` |
| `Views/Terminal/KeyboardToolbar.swift` | Photo button, upload state |
| `Views/Terminal/TerminalContainerView.swift` | Orchestration, exec session management |
| `Models/TerminalSettings.swift` | `ImagePasteQuality` enum and setting |
| `Views/Settings/SettingsView.swift` | Quality picker UI |
| `ShellCastTests/ImagePasteServiceTests.swift` | Unit tests for image preparation |

## macOS Requirements

- **Remote Login (SSH) enabled** — System Settings > General > Sharing > Remote Login
- **Active GUI session** — A user must be logged in to the Mac desktop. The clipboard belongs to the GUI session; `osascript` cannot access it from the login screen
- **Mac must be awake** — If the lid is closed and the Mac sleeps, the GUI session becomes inaccessible. Use `caffeinate` or energy saver settings to prevent sleep
- **No extra config needed** — `osascript` is built-in, no Automation permissions required for `set the clipboard`

## Limitations

- **macOS only** — `osascript` is macOS-specific. Linux remotes would need a different clipboard mechanism (e.g., `xclip`), not currently implemented
- **GUI session required** — The remote Mac must have an active desktop session for clipboard access
- **Mosh requires separate SSH** — Mosh runs over UDP and doesn't support exec channels. A separate SSH connection is needed for file transfer
- **Clipboard permission** — iOS may show a paste permission prompt on first `UIPasteboard.general.image` access
