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
            "$HOME/.local/bin"
        ]
    }
    
    static func isInstalled(over session: SSHSession) async throws -> Bool {
        let pathChecks = commonPaths.map { "\($0)/\(binaryNames.first ?? agentID)" }
        let whichChecks = binaryNames.map { "which \($0) >/dev/null 2>&1 && echo yes" }
        
        let allChecks = pathChecks.map { "test -x \($0) && echo yes" } + whichChecks
        let command = allChecks.joined(separator: " || ") + " || echo no"
        
        let output = try await session.exec(command)
        return output.trimmingCharacters(in: .whitespacesAndNewlines).contains("yes")
    }
    
    static func resolveBinaryPath(over session: SSHSession) async throws -> String {
        let pathChecks = commonPaths.map { "\($0)/\(binaryNames.first ?? agentID)" }
        let conditions = pathChecks.map { "test -x \($0) && echo \($0)" }
        let whichCheck = "which \(binaryNames.first ?? agentID) 2>/dev/null"
        
        let command = conditions.joined(separator: " || ") + " || " + whichCheck + " || echo \(binaryNames.first ?? agentID)"
        
        let output = try await session.exec(command)
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? (binaryNames.first ?? agentID) : path
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
        
        // Build a pattern that matches any of the binary names
        // Check ALL panes in each session, not just the first one
        let tmuxPath = "/opt/homebrew/bin/tmux"
        let pattern = binaryNames.joined(separator: "|")
        
        // Build command that checks all panes in each session
        // For each session, iterate through all panes and check if any has the agent running
        let command = """
        \(tmuxPath) list-panes -a -F '#{session_name} #{pane_pid}' 2>/dev/null | while read session pane_pid; do \
        [ -n "$pane_pid" ] && pgrep -P "$pane_pid" -f "\(pattern)" >/dev/null 2>&1 && echo "$session"; \
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
        let tmuxPath = "/opt/homebrew/bin/tmux"
        let pattern = binaryNames.joined(separator: "|")
        
        // Use list-panes -a to get all windows, filter by session name
        // Note: -t session only shows active window, -a shows all but from all sessions
        // grep pattern: session name at start of line followed by space
        let escapedSession = tmuxSessionName.replacingOccurrences(of: "'", with: "'\\''")
        
        let command = """
        \(tmuxPath) list-panes -a -F '#{session_name} #{window_index} #{pane_pid}' 2>/dev/null | grep '^\(escapedSession) ' | while read session widx pid; do \
        pgrep -P "$pid" -f "\(pattern)" >/dev/null 2>&1 && echo "$widx"; \
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
