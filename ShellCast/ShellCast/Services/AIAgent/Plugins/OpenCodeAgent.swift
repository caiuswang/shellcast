import Foundation

// MARK: - OpenCode Agent Plugin

/// Plugin for OpenCode CLI integration (https://github.com/opencode-ai/opencode)
/// OpenCode is an open-source AI coding assistant
/// Note: Also detects 'kimi' (Moonshot AI) as it's commonly aliased or packaged together
struct OpenCodeAgent: AIAgentPlugin {
    
    static var agentID: String { "opencode" }
    static var displayName: String { "OpenCode" }
    static var iconName: String { "OpenCodeIcon" }  // OpenCode brand icon from @lobehub/icons
    static var themeColor: String { "blue" }
    static var binaryNames: [String] { ["opencode"] }  // Note: removed "oc" as it's too short and matches 'Co' in 'Kimi Code'
    
    // MARK: - Custom Session Listing
    
    static func listSessions(over session: SSHSession) async throws -> [AIAgentSession] {
        let platform = try await RemotePlatform.detect(over: session)
        // OpenCode stores sessions in ~/.opencode/sessions/
        // Use platform-aware `stat` format: macOS uses -f '%m %N', Linux uses -c '%Y %n'
        let command = """
        for f in $(find ~/.opencode/sessions -maxdepth 1 -name '*.json' -exec \(platform.statModTimeAndPath) {} \\; 2>/dev/null | sort -rn | head -20 | awk '{print $2}'); do \
        ts=$(\(platform.statModTime) "$f" 2>/dev/null); \
        msg=$(cat "$f" 2>/dev/null | grep -o '"last_message"[^}]*' | head -1 | sed 's/.*"content":"\\([^"]*\\)".*/\\1/' | cut -c1-80); \
        proj=$(cat "$f" 2>/dev/null | grep -o '"project_path"[^,]*' | head -1 | sed 's/.*":"\\([^"]*\\)".*/\\1/'); \
        sid=$(basename "$f" .json); \
        echo "${ts}|||${sid}|||${proj}|||${msg}"; \
        done; true
        """
        
        let output = try await session.exec(command)
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        var sessions: [AIAgentSession] = []
        let lines = trimmed.split(separator: "\n")
        
        for line in lines {
            let parts = String(line).components(separatedBy: "|||")
            guard parts.count >= 2 else { continue }
            
            let timestampStr = parts[0].trimmingCharacters(in: .whitespaces)
            let sessionId = parts[1].trimmingCharacters(in: .whitespaces)
            let projectPath = parts.count >= 3 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
            let rawSummary = parts.count >= 4 ? parts[3].trimmingCharacters(in: .whitespaces) : nil
            
            let lastModified: Date?
            if let timestamp = TimeInterval(timestampStr) {
                lastModified = Date(timeIntervalSince1970: timestamp)
            } else {
                lastModified = nil
            }
            
            let summary = cleanSummary(rawSummary)
            let displayProjectPath = projectPath.isEmpty ? "Unknown" : projectPath
            
            sessions.append(AIAgentSession(
                agentID: agentID,
                sessionId: sessionId,
                projectPath: displayProjectPath,
                lastModified: lastModified,
                summary: summary
            ))
        }
        
        return sessions
    }
    
    // MARK: - Custom Commands
    
    static func resumeCommand(sessionId: String, binaryPath: String) -> String {
        "\(binaryPath) resume \(shellEscape(sessionId))"
    }
    
    static func newCommand(projectPath: String?, binaryPath: String) -> String {
        if let path = projectPath, !path.isEmpty {
            return "\(binaryPath) start \(shellEscape(path))"
        }
        return "\(binaryPath) start"
    }
    
    // MARK: - Private Helpers
    
    private static func cleanSummary(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        var text = raw
        // Strip markdown and common formatting
        text = text.replacingOccurrences(of: "`", with: "")
        text = text.replacingOccurrences(of: "\\n", with: " ")
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
    
    private static func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
