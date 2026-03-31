import Foundation

struct ClaudeCodeParser {
    private static let tmuxPath = "/opt/homebrew/bin/tmux"

    /// Check if claude CLI is available on the server
    /// Note: SSH exec sessions don't load shell profiles, so PATH may not include /opt/homebrew/bin.
    /// We check common install locations explicitly.
    static func isInstalled(over session: SSHSession) async throws -> Bool {
        let output = try await session.exec("test -x /opt/homebrew/bin/claude && echo yes || test -x /usr/local/bin/claude && echo yes || which claude >/dev/null 2>&1 && echo yes || echo no")
        let result = output.trimmingCharacters(in: .whitespacesAndNewlines).contains("yes")
        debugLog("[CLAUDE] isInstalled raw output: '\(output)', result: \(result)")
        return result
    }

    /// List resumable Claude Code sessions by scanning ~/.claude/projects/ directory
    static func listSessions(over session: SSHSession) async throws -> [ClaudeCodeSession] {
        return try await listSessionsFromFilesystem(over: session)
    }

    /// Resolve the full path to the claude binary
    static func resolveClaudePath(over session: SSHSession) async throws -> String {
        let output = try await session.exec("test -x /opt/homebrew/bin/claude && echo /opt/homebrew/bin/claude || test -x /usr/local/bin/claude && echo /usr/local/bin/claude || which claude 2>/dev/null || echo claude")
        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)
        debugLog("[CLAUDE] resolved claude path: '\(path)'")
        return path.isEmpty ? "claude" : path
    }

    /// Build command to resume a Claude Code session
    static func resumeCommand(sessionId: String, claudePath: String = "claude") -> String {
        "\(claudePath) --resume \(sessionId)"
    }

    /// Build command to start a new Claude Code session
    static func newCommand(projectPath: String?, claudePath: String = "claude") -> String {
        if let path = projectPath, !path.isEmpty {
            return "cd \(shellEscape(path)) && \(claudePath)"
        }
        return claudePath
    }

    /// Detect if claude is running in a tmux session by checking child processes of the pane
    /// Note: #{pane_current_command} shows "node" not "claude", so we walk the process tree
    static func isRunningInSession(over session: SSHSession, tmuxSessionName: String) async throws -> Bool {
        let command = """
        pid=$(\(tmuxPath) list-panes -t \(shellEscape(tmuxSessionName)) -F '#{pane_pid}' 2>/dev/null | head -1) && \
        pgrep -P "$pid" -f claude >/dev/null 2>&1 && echo yes || echo no
        """
        let output = try await session.exec(command)
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "yes"
    }

    /// Detect which tmux sessions are running Claude Code
    static func detectRunningSessions(over session: SSHSession, tmuxSessions: [TmuxSession]) async throws -> Set<String> {
        debugLog("[CLAUDE] detectRunningSessions called with \(tmuxSessions.count) sessions: \(tmuxSessions.map { $0.name })")
        guard !tmuxSessions.isEmpty else {
            debugLog("[CLAUDE] detectRunningSessions: no tmux sessions, returning empty")
            return []
        }

        // Check all sessions in one command using a shell for loop
        let sessionNames = tmuxSessions.map { $0.name }.joined(separator: " ")
        let command = """
        for s in \(sessionNames); do \
        p=$(\(tmuxPath) list-panes -t "$s" -F '#{pane_pid}' 2>/dev/null | head -1); \
        [ -n "$p" ] && pgrep -P "$p" -f claude >/dev/null 2>&1 && echo "$s"; \
        done; true
        """
        debugLog("[CLAUDE] detectRunningSessions command: \(command)")

        let output: String
        do {
            output = try await session.exec(command)
            debugLog("[CLAUDE] detectRunningSessions raw output: '\(output)'")
        } catch {
            debugLog("[CLAUDE] detectRunningSessions exec failed: \(error)")
            throw error
        }

        var result = Set<String>()
        for line in output.split(separator: "\n") {
            let name = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                result.insert(name)
            }
        }
        debugLog("[CLAUDE] detectRunningSessions result: \(result)")
        return result
    }

    /// Detect which windows in a tmux session are running Claude Code
    static func detectRunningWindows(over session: SSHSession, tmuxSessionName: String) async throws -> Set<Int> {
        let command = """
        \(tmuxPath) list-panes -t '\(tmuxSessionName)' -F '#{window_index} #{pane_pid}' 2>/dev/null | while read widx pid; do \
        pgrep -P "$pid" -f claude >/dev/null 2>&1 && echo "$widx"; \
        done; true
        """
        let output = try await session.exec(command)
        debugLog("[CLAUDE] detectRunningWindows for '\(tmuxSessionName)' output: '\(output)'")

        var result = Set<Int>()
        for line in output.split(separator: "\n") {
            if let idx = Int(line.trimmingCharacters(in: .whitespacesAndNewlines)) {
                result.insert(idx)
            }
        }
        return result
    }

    // MARK: - Private

    /// List sessions by scanning ~/.claude/projects/ directory
    /// Real structure: ~/.claude/projects/<project-dir-name>/<uuid>.jsonl
    /// Project dir name is the path with / replaced by - (e.g., -Users-<username>-myproject)
    private static func listSessionsFromFilesystem(over session: SSHSession) async throws -> [ClaudeCodeSession] {
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

        var sessions: [ClaudeCodeSession] = []
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

            // Clean up summary
            let summary = cleanSummary(rawSummary)

            sessions.append(ClaudeCodeSession(
                sessionId: sessionId,
                projectPath: projectPath,
                lastModified: lastModified,
                summary: summary
            ))
        }

        return sessions
    }

    /// Clean up raw summary text extracted from session file
    private static func cleanSummary(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        var text = raw
        // Strip XML-like tags from slash commands
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        return text
    }

    /// Convert encoded project directory name back to a readable short path
    /// e.g., "-Users-<username>-projects-myapp" → "projects/myapp"
    private static func decodeProjectPath(_ encoded: String) -> String {
        // Remove leading dash and split by the home directory prefix
        var parts = encoded.components(separatedBy: "-")
        // Remove empty first element from leading dash
        if parts.first?.isEmpty == true { parts.removeFirst() }

        // Try to find and skip the home directory prefix (Users/<username>)
        if parts.count > 2, parts[0] == "Users" {
            parts.removeFirst(2) // Remove "Users" and username
        }

        // Reconstruct: take last 2-3 meaningful segments as display path
        let meaningful = parts.suffix(3)
        return meaningful.joined(separator: "/")
    }

    private static func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
