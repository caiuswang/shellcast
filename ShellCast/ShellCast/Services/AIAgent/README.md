# AI Agent Plugin System

This directory contains a plugin-based architecture for integrating AI coding assistants (like Claude Code, OpenCode, etc.) with ShellCast.

> **Important:** Read [COMMON_MISTAKES.md](./COMMON_MISTAKES.md) before developing new plugins!

## Architecture

```
AIAgent/
├── AIAgentPlugin.swift          # Protocol definition + default implementations
├── AIAgentRegistry.swift        # Central registry for all plugins
├── ClaudeCodeParser+Compatibility.swift  # Backward compatibility wrapper
├── README.md                    # This file
├── COMMON_MISTAKES.md           # Pitfalls and lessons learned ⭐
└── Plugins/
    ├── ClaudeAgent.swift        # Claude Code plugin
    ├── KimiAgent.swift          # Kimi (Moonshot AI) plugin
    └── OpenCodeAgent.swift      # OpenCode plugin
```

## Adding a New AI Agent

To add support for a new AI agent, create a new file in `Plugins/` that conforms to `AIAgentPlugin`:

```swift
import Foundation

struct MyAIAgent: AIAgentPlugin {
    static var agentID: String { "myagent" }
    static var displayName: String { "My AI Agent" }
    static var iconName: String { "brain" }  // SF Symbol name
    static var themeColor: String { "blue" }  // purple, blue, green, etc.
    static var binaryNames: [String] { ["myagent", "ma"] }
    
    // Optional: Custom session listing
    static func listSessions(over session: SSHSession) async throws -> [AIAgentSession] {
        // Implement based on your agent's session storage format
        // Return empty array if not supported
        return []
    }
    
    // Optional: Custom commands
    static func resumeCommand(sessionId: String, binaryPath: String) -> String {
        "\(binaryPath) --resume \(sessionId)"
    }
    
    static func newCommand(projectPath: String?, binaryPath: String) -> String {
        if let path = projectPath {
            return "cd \(path) && \(binaryPath)"
        }
        return binaryPath
    }
}
```

Then register it in `AIAgentRegistry.swift`:

```swift
static let allPlugins: [AIAgentPlugin.Type] = [
    ClaudeAgent.self,
    OpenCodeAgent.self,
    MyAIAgent.self  // Add your agent here
]
```

## Protocol Methods

### Required (have defaults)

- `agentID`: Unique identifier (e.g., "claude", "opencode")
- `displayName`: Human-readable name for UI
- `iconName`: SF Symbol name for UI
- `themeColor`: Color theme name (purple, blue, green, etc.)
- `binaryNames`: Array of possible binary names to search for

### Optional (have default implementations)

- `commonPaths`: Installation paths to check (defaults to common locations)
- `isInstalled(over:)`: Check if agent is installed on server
- `resolveBinaryPath(over:)`: Find full path to binary
- `listSessions(over:)`: List resumable sessions
- `resumeCommand(sessionId:binaryPath:)`: Command to resume a session
- `newCommand(projectPath:binaryPath:)`: Command to start new session
- `detectRunningSessions(over:tmuxSessions:)`: Detect which tmux sessions are running this agent
- `detectRunningWindows(over:tmuxSessionName:)`: Detect which windows in a session are running this agent

## Agent Session Storage

Sessions are typically stored in:

- **Claude Code**: `~/.claude/projects/<project>/<uuid>.jsonl`
- **OpenCode**: `~/.opencode/sessions/<uuid>.json`

When implementing `listSessions`, parse your agent's session storage format and return `AIAgentSession` objects.

## Backward Compatibility

The `ClaudeCodeParser` struct remains as a compatibility wrapper that delegates to `ClaudeAgent`. Existing code using `ClaudeCodeParser` continues to work.
