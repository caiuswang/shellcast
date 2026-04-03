import Foundation

// MARK: - AI Agent Plugin Protocol

/// Protocol for AI agent CLI tool integration
/// Implement this protocol to add support for a new AI coding assistant
protocol AIAgentPlugin {
    /// Unique identifier for this agent (e.g., "claude", "opencode")
    static var agentID: String { get }
    
    /// Display name for UI (e.g., "Claude Code", "OpenCode")
    static var displayName: String { get }
    
    /// Icon name for UI (SF Symbol)
    static var iconName: String { get }
    
    /// Color theme for this agent in UI
    static var themeColor: String { get }
    
    /// Binary names to search for (e.g., ["claude"], ["opencode", "oc"])
    static var binaryNames: [String] { get }
    
    /// Common installation paths to check
    static var commonPaths: [String] { get }
    
    /// Check if this agent is installed on the server
    static func isInstalled(over session: SSHSession) async throws -> Bool
    
    /// Resolve the full path to the agent binary
    static func resolveBinaryPath(over session: SSHSession) async throws -> String
    
    /// List resumable sessions for this agent
    static func listSessions(over session: SSHSession) async throws -> [AIAgentSession]
    
    /// Build command to resume a session
    static func resumeCommand(sessionId: String, binaryPath: String) -> String
    
    /// Build command to start a new session
    static func newCommand(projectPath: String?, binaryPath: String) -> String
    
    /// Detect which tmux sessions are running this agent
    static func detectRunningSessions(over session: SSHSession, tmuxSessions: [TmuxSession]) async throws -> Set<String>
    
    /// Detect which windows in a tmux session are running this agent
    static func detectRunningWindows(over session: SSHSession, tmuxSessionName: String) async throws -> Set<Int>
}

// MARK: - AI Agent Session

/// Generic session info for any AI agent
struct AIAgentSession: Identifiable {
    let agentID: String
    let sessionId: String
    let projectPath: String
    let lastModified: Date?
    let summary: String?
    
    var id: String { "\(agentID):\(sessionId)" }
    
    var projectName: String {
        projectPath.components(separatedBy: "/").last ?? projectPath
    }
    
    var displayName: String {
        AIAgentRegistry.displayName(for: agentID)
    }
}

// MARK: - Default Implementations

extension AIAgentPlugin {

    static var commonPaths: [String] {
        [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "$HOME/.local/bin",
            "/snap/bin",
            "/home/linuxbrew/.linuxbrew/bin"
        ]
    }

    static func isInstalled(over session: SSHSession) async throws -> Bool {
        let platform = try await RemotePlatform.detect(over: session)
        let paths = platform.commonBinaryPaths
        let binary = binaryNames.first ?? agentID
        let pathChecks = paths.map { "test -x \($0)/\(binary) && echo yes" }
        // Use `command -v` (POSIX) instead of `which` for portability
        let commandVChecks = binaryNames.map { "command -v \($0) >/dev/null 2>&1 && echo yes" }

        let allChecks = pathChecks + commandVChecks
        let command = allChecks.joined(separator: " || ") + " || echo no"

        let output = try await session.exec(command)
        return output.trimmingCharacters(in: .whitespacesAndNewlines).contains("yes")
    }

    static func resolveBinaryPath(over session: SSHSession) async throws -> String {
        let platform = try await RemotePlatform.detect(over: session)
        let paths = platform.commonBinaryPaths
        let binary = binaryNames.first ?? agentID
        let conditions = paths.map { "test -x \($0)/\(binary) && echo \($0)/\(binary)" }
        // Use `command -v` (POSIX) instead of `which` for portability
        let commandVCheck = "command -v \(binary) 2>/dev/null"

        let command = conditions.joined(separator: " || ") + " || " + commandVCheck + " || echo \(binary)"

        let output = try await session.exec(command)
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? binary : path
    }
    
    static func resumeCommand(sessionId: String, binaryPath: String) -> String {
        "\(binaryPath) --resume \(shellEscape(sessionId))"
    }
    
    static func newCommand(projectPath: String?, binaryPath: String) -> String {
        if let path = projectPath, !path.isEmpty {
            return "cd \(shellEscape(path)) && \(binaryPath)"
        }
        return binaryPath
    }
    
    static func detectRunningSessions(over session: SSHSession, tmuxSessions: [TmuxSession]) async throws -> Set<String> {
        guard !tmuxSessions.isEmpty else { return [] }

        let platform = try await RemotePlatform.detect(over: session)
        let pattern = binaryNames.joined(separator: "|")

        // Resolve tmux path dynamically instead of hardcoding /opt/homebrew/bin/tmux
        let command = """
        TMUX_BIN=$(command -v tmux 2>/dev/null || echo tmux); \
        $TMUX_BIN list-panes -a -F '#{session_name} #{pane_pid}' 2>/dev/null | while read session pane_pid; do \
        [ -n "$pane_pid" ] && \(platform.pgrepChildCommand(parentPid: "$pane_pid", pattern: pattern)) && echo "$session"; \
        done | sort -u; true
        """

        debugLog("[AIAGENT] detectRunningSessions command: \(command)")

        let output = try await session.exec(command)
        debugLog("[AIAGENT] detectRunningSessions output: '\(output)'")

        var result = Set<String>()
        for line in output.split(separator: "\n") {
            let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                result.insert(name)
            }
        }
        return result
    }

    static func detectRunningWindows(over session: SSHSession, tmuxSessionName: String) async throws -> Set<Int> {
        let platform = try await RemotePlatform.detect(over: session)
        let pattern = binaryNames.joined(separator: "|")
        let escapedSession = tmuxSessionName.replacingOccurrences(of: "'", with: "'\\''")

        // Resolve tmux path dynamically instead of hardcoding /opt/homebrew/bin/tmux
        let command = """
        TMUX_BIN=$(command -v tmux 2>/dev/null || echo tmux); \
        $TMUX_BIN list-panes -a -F '#{session_name} #{window_index} #{pane_pid}' 2>/dev/null | grep '^\(escapedSession) ' | while read session widx pid; do \
        \(platform.pgrepChildCommand(parentPid: "$pid", pattern: pattern)) && echo "$widx"; \
        done | sort -u; true
        """

        debugLog("[AIAGENT] detectRunningWindows command: \(command)")

        let output = try await session.exec(command)
        debugLog("[AIAGENT] detectRunningWindows output: '\(output)'")

        var result = Set<Int>()
        for line in output.split(separator: "\n") {
            if let idx = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
                result.insert(idx)
            }
        }
        return result
    }
    
    private static func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

// MARK: - Shell Helper

private func shellEscape(_ string: String) -> String {
    "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
}
