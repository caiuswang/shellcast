import Foundation

// MARK: - Kimi Agent Plugin

/// Plugin for Kimi CLI integration (Moonshot AI's coding assistant)
/// https://www.moonshot.cn/ (kimi command line tool)
struct KimiAgent: AIAgentPlugin {
    
    static var agentID: String { "kimi" }
    static var displayName: String { "Kimi" }
    static var iconName: String { "KimiIcon" }  // Moonshot AI brand icon from @lobehub/icons
    static var themeColor: String { "gray" }      // Moonshot AI dark theme
    static var binaryNames: [String] { ["kimi", "kimi-cli"] }
    
    // MARK: - Custom Session Listing
    
    static func listSessions(over session: SSHSession) async throws -> [AIAgentSession] {
        // Kimi (Moonshot AI) session storage is not yet determined
        // Return empty to avoid duplicates with OpenCode (which may share storage)
        // Process detection (running sessions) will still work via detectRunningSessions
        return []
    }
    
    // MARK: - Custom Commands
    
    static func resumeCommand(sessionId: String, binaryPath: String) -> String {
        "\(binaryPath) resume \(shellEscape(sessionId))"
    }
    
    static func newCommand(projectPath: String?, binaryPath: String) -> String {
        if let path = projectPath, !path.isEmpty {
            return "cd \(shellEscape(path)) && \(binaryPath)"
        }
        return binaryPath
    }
    
    private static func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
