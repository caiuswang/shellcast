import Foundation

// MARK: - Claude Code Agent Plugin

/// Plugin for Claude Code CLI integration
struct ClaudeAgent: AIAgentPlugin {
    
    static var agentID: String { "claude" }
    static var displayName: String { "Claude Code" }
    static var iconName: String { "sparkles" }
    static var themeColor: String { "purple" }
    static var binaryNames: [String] { ["claude"] }
    
    // MARK: - Custom Session Listing
    
    static func listSessions(over session: SSHSession) async throws -> [AIAgentSession] {
        // Single command: find files, get timestamps, extract first user message as summary
        let command = """
        for f in $(find ~/.claude/projects -maxdepth 2 -name '*.jsonl' ! -path '*/subagents/*' -exec stat -f '%m %N' {} \\; 2>/dev/null | sort -rn | head -20 | awk '{print $2}'); do \
        ts=$(stat -f '%m' "$f" 2>/dev/null); \
        msg=$(grep -m1 '"type":"user"' "$f" 2>/dev/null | head -1 | sed 's/.*"content":"\\([^"]*\\)".*/\\1/' | cut -c1-80); \
        echo "${ts}|||${f}|||${msg}"; \
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
            let path = parts[1].trimmingCharacters(in: .whitespaces)
            let rawSummary = parts.count >= 3 ? parts[2].trimmingCharacters(in: .whitespaces) : nil
            
            let components = path.components(separatedBy: "/")
            guard let projectsIdx = components.firstIndex(of: "projects"),
                  projectsIdx + 2 < components.count else { continue }
            
            let projectDirName = components[projectsIdx + 1]
            let filename = components[projectsIdx + 2]
            let sessionId = filename.replacingOccurrences(of: ".jsonl", with: "")
            
            let projectPath = decodeProjectPath(projectDirName)
            
            let lastModified: Date?
            if let timestamp = TimeInterval(timestampStr) {
                lastModified = Date(timeIntervalSince1970: timestamp)
            } else {
                lastModified = nil
            }
            
            let summary = cleanSummary(rawSummary)
            
            sessions.append(AIAgentSession(
                agentID: agentID,
                sessionId: sessionId,
                projectPath: projectPath,
                lastModified: lastModified,
                summary: summary
            ))
        }
        
        return sessions
    }
    
    // MARK: - Private Helpers
    
    private static func decodeProjectPath(_ encoded: String) -> String {
        var parts = encoded.components(separatedBy: "-")
        if parts.first?.isEmpty == true { parts.removeFirst() }
        
        if parts.count > 2, parts[0] == "Users" {
            parts.removeFirst(2)
        }
        
        let meaningful = parts.suffix(3)
        return meaningful.joined(separator: "/")
    }
    
    private static func cleanSummary(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        var text = raw
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
