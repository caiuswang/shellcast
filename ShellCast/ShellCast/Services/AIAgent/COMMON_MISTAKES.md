# Common Mistakes in AI Agent Plugin Development

This document tracks common mistakes and pitfalls when developing AI agent plugins for ShellCast.

## 1. Short Binary Names Cause False Matches

### Problem
macOS `pgrep -f` does **partial string matching** on the full command line. Short patterns like `"oc"` can match unexpected strings.

### Example
```swift
// BAD: "oc" matches "Co" in "Kimi Code"
static var binaryNames: [String] { ["opencode", "oc"] }
```

When checking for OpenCode in a tmux session running **Kimi**:
```bash
# Process command line: "Kimi Code"
pgrep -f "oc"  # MATCHES because "Co" contains "oc" (case-insensitive on macOS!)
```

This caused Kimi sessions to be incorrectly detected as both Kimi AND OpenCode.

### Solution
Use full, specific binary names only:
```swift
// GOOD: Full name prevents false matches
static var binaryNames: [String] { ["opencode"] }  // Removed "oc"
```

### Testing
Always test patterns on real processes:
```bash
# Test your pattern against all tmux sessions
for s in $(tmux list-sessions -F '#{session_name}'); do
    p=$(tmux list-panes -t "$s" -F '#{pane_pid}' | head -1)
    if pgrep -P "$p" -f "your-pattern" >/dev/null 2>&1; then
        echo "$s: MATCHED"
    fi
done
```

### Rules for Binary Names
1. **Minimum 4 characters** - Avoid 2-3 character abbreviations
2. **Use full command names** - Prefer "opencode" over "oc"
3. **Test for overlaps** - Ensure your pattern doesn't match other agents
4. **Case sensitivity** - macOS `pgrep` is case-insensitive by default

---

## 2. Session Storage Path Conflicts

### Problem
Multiple agents may share session storage formats or paths, causing duplicate session listings.

### Example
If both Kimi and OpenCode use `~/.opencode/sessions/`, both plugins would return the same sessions.

### Solution
```swift
// Return empty if storage format is unknown or shared
static func listSessions(over session: SSHSession) async throws -> [AIAgentSession] {
    // Kimi shares storage with OpenCode - return empty to avoid duplicates
    // Process detection via detectRunningSessions still works
    return []
}
```

### Testing
Check for overlapping storage:
```bash
ls -la ~/.opencode/sessions/ 2>/dev/null
ls -la ~/.kimi/sessions/ 2>/dev/null
```

---

## 3. Incorrect pgrep Flag Usage

### Problem
Using wrong `pgrep` flags for pattern matching.

### Common Mistakes
| Flag | Meaning | Use Case |
|------|---------|----------|
| `-f` | Full command line | ✅ Correct for matching process names |
| `-E` | Extended regex | ❌ Not available on all systems |
| `-a` | Full format | Debug only |
| `-l` | Long format (with PID) | Debug only |

### Solution
Always use `pgrep -P <parent> -f <pattern>`:
```bash
# Check if agent is running in a tmux pane
pgrep -P "$pane_pid" -f "claude|opencode|kimi"
```

---

## 4. Forgetting Debug Logging

### Problem
Without logging, it's hard to diagnose detection issues in production.

### Solution
Add debug logs to all detection methods:
```swift
static func detectRunningSessions(...) async throws -> Set<String> {
    debugLog("[AIAGENT] detectRunningSessions command: \(command)")
    let output = try await session.exec(command)
    debugLog("[AIAGENT] detectRunningSessions output: '\(output)'")
    // ...
}
```

### Viewing Logs
In Xcode: Check the console for `[AIAGENT]` and `[AI-AGENTS]` prefixed logs.

---

## 5. Session Name Escaping Issues

### Problem
Tmux session names with special characters can break shell commands.

### Example
```bash
# DANGER: Session name with spaces or quotes
session_name="my session"  # Breaks: tmux list-panes -t my session
```

### Solution
Always escape session names:
```swift
private static func shellEscape(_ string: String) -> String {
    "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

let command = "tmux list-panes -t \(shellEscape(sessionName)) -F ..."
```

---

## 6. Assuming Case Sensitivity

### Problem
macOS `pgrep` is **case-insensitive** by default, Linux is case-sensitive.

### Example
```bash
# On macOS, all of these match "Kimi Code":
pgrep -f "kimi"   # matches
pgrep -f "KIMI"   # matches  
pgrep -f "Kimi"   # matches
```

### Solution
Don't rely on case for differentiation. Use distinct full names:
```swift
// GOOD: Distinct names
static var binaryNames: [String] { ["claude"] }      // Not "cl"
static var binaryNames: [String] { ["opencode"] }    // Not "oc"
static var binaryNames: [String] { ["kimi", "kimi-cli"] }
```

---

## 7. Not Testing on Real Sessions

### Problem
Unit tests may pass but real-world usage fails due to:
- Different process hierarchies
- Shell profile differences (PATH not loaded in SSH exec)
- Binary installation variations (Homebrew, pip, npm, etc.)

### Solution
Always test on actual sessions:
```bash
# 1. Build and install on device/simulator
# 2. Connect to server with real AI agents running
# 3. Check logs for detection results
# 4. Verify visual indicators in UI
```

---

## 8. UI Flashing When Filtering by Agent

### Problem
When navigating to a session filtered by AI agent (e.g., "Claude Tmux"), the view briefly shows ALL windows before filtering to only agent windows. This creates a jarring "flash" effect.

### Root Cause
The `displayedWindows` computed property returned all windows while async detection was still in progress:

```swift
// BAD: Shows all windows while loading
private var displayedWindows: [TmuxWindow] {
    if let agentFilter = agentFilter, let runningWindows = runningWindowsByAgent[agentFilter] {
        return windows.filter { runningWindows.contains($0.index) }
    }
    return windows  // <-- Shows everything while detecting!
}
```

### Solution
Return empty array while detection is in progress, and show a loading indicator:

```swift
// GOOD: Shows nothing (or loading) while detecting
private var displayedWindows: [TmuxWindow] {
    if let agentFilter = agentFilter {
        guard let runningWindows = runningWindowsByAgent[agentFilter] else {
            return []  // Detection not complete
        }
        return windows.filter { runningWindows.contains($0.index) }
    }
    return windows
}

// In body:
if isLoading || isDetectingAgentWindows {
    ProgressView()  // Show loading while detecting
}
```

---

## Checklist for New Agent Plugins

Before submitting a new AI agent plugin:

- [ ] Binary names are 4+ characters and specific
- [ ] Tested pattern matching against all other agents
- [ ] Session storage path doesn't conflict with existing agents
- [ ] Added debug logging to detection methods
- [ ] Tested on real tmux sessions with agent running
- [ ] Verified no false matches in logs
- [ ] No UI flashing when filtering by agent
- [ ] Updated `AIAgentRegistry.allPlugins` with new agent

---

## Related Files

- `AIAgentPlugin.swift` - Protocol definition
- `AIAgentRegistry.swift` - Plugin registration
- `ClaudeAgent.swift` - Reference implementation
- `KimiAgent.swift` - Example with minimal session listing
