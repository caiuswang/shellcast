import Foundation

// MARK: - Backward Compatibility Wrapper

/// Backward-compatible wrapper that delegates to ClaudeAgent plugin
/// This allows existing code to continue working while migrating to the new plugin system
struct ClaudeCodeParser {
    
    static func isInstalled(over session: SSHSession) async throws -> Bool {
        try await ClaudeAgent.isInstalled(over: session)
    }
    
    static func resolveClaudePath(over session: SSHSession) async throws -> String {
        try await ClaudeAgent.resolveBinaryPath(over: session)
    }
    
    static func listSessions(over session: SSHSession) async throws -> [ClaudeCodeSession] {
        let sessions = try await ClaudeAgent.listSessions(over: session)
        return sessions.map { AIAgentSession.toClaudeCodeSession($0) }
    }
    
    static func resumeCommand(sessionId: String, claudePath: String = "claude") -> String {
        ClaudeAgent.resumeCommand(sessionId: sessionId, binaryPath: claudePath)
    }
    
    static func newCommand(projectPath: String?, claudePath: String = "claude") -> String {
        ClaudeAgent.newCommand(projectPath: projectPath, binaryPath: claudePath)
    }
    
    static func isRunningInSession(over session: SSHSession, tmuxSessionName: String) async throws -> Bool {
        let running = try await ClaudeAgent.detectRunningSessions(
            over: session,
            tmuxSessions: [TmuxSession(name: tmuxSessionName, windowCount: 0, lastAttached: nil, attachedClients: 0)]
        )
        return running.contains(tmuxSessionName)
    }
    
    static func detectRunningSessions(over session: SSHSession, tmuxSessions: [TmuxSession]) async throws -> Set<String> {
        try await ClaudeAgent.detectRunningSessions(over: session, tmuxSessions: tmuxSessions)
    }
    
    static func detectRunningWindows(over session: SSHSession, tmuxSessionName: String) async throws -> Set<Int> {
        try await ClaudeAgent.detectRunningWindows(over: session, tmuxSessionName: tmuxSessionName)
    }
}

// MARK: - AIAgentSession Extension

extension AIAgentSession {
    /// Convert to legacy ClaudeCodeSession for backward compatibility
    func toClaudeCodeSession() -> ClaudeCodeSession {
        ClaudeCodeSession(
            sessionId: sessionId,
            projectPath: projectPath,
            lastModified: lastModified,
            summary: summary
        )
    }
    
    static func toClaudeCodeSession(_ session: AIAgentSession) -> ClaudeCodeSession {
        session.toClaudeCodeSession()
    }
}
