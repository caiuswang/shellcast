import Foundation

// MARK: - GitHub Copilot CLI Agent Plugin

/// Plugin for GitHub Copilot CLI (the standalone agentic `copilot` binary).
/// Not the `gh copilot` gh-extension.
///
/// Binary-name collision: AWS Copilot CLI also ships a binary named `copilot`.
/// We use `detectionPattern` to discriminate via argv — bare `copilot` or
/// `copilot <github-subcommand>`. AWS Copilot is effectively always invoked with
/// its own subcommands (app/svc/env/init/deploy/...) so it won't match.
struct CopilotAgent: AIAgentPlugin {

    static var agentID: String { "copilot" }
    static var displayName: String { "GitHub Copilot" }
    static var iconName: String { "sparkles" }
    static var themeColor: String { "gray" }
    static var binaryNames: [String] { ["copilot"] }

    // POSIX ERE applied against tolower(args). Anchored matches:
    //   `…/copilot` at end-of-line, OR
    //   `…/copilot` followed by `--<flag>` or a GitHub-Copilot verb (chat/auth/login/...).
    // AWS Copilot CLI is invoked with subcommands (app/svc/env/init/deploy/...) and is
    // therefore excluded. Pure regex — shell-escaping is RemotePlatform's job.
    static var detectionPattern: String {
        "(^|/)copilot$|(^|/)copilot[[:blank:]]+(--|chat|auth|login|logout|version|help)"
    }

    // MARK: - Custom Session Listing

    static func listSessions(over session: SSHSession) async throws -> [AIAgentSession] {
        let platform = try await RemotePlatform.detect(over: session)
        // Layout: ${COPILOT_HOME:-~/.copilot}/session-state/<uuid>/workspace.yaml
        // workspace.yaml carries: id, cwd, summary (optional), name (optional),
        // updated_at. We sort by file mtime (newest first), take the top 20,
        // then grep three fields per file. `summary` is preferred over `name`
        // for the displayed subtitle.
        let command = """
        DIR="${COPILOT_HOME:-$HOME/.copilot}/session-state"; \
        [ -d "$DIR" ] || exit 0; \
        for f in $(find "$DIR" -mindepth 2 -maxdepth 2 -name workspace.yaml -exec \(platform.statModTimeAndPath) {} \\; 2>/dev/null | sort -rn | head -20 | awk '{print $2}'); do \
        d=$(dirname "$f"); \
        sid=$(basename "$d"); \
        ts=$(\(platform.statModTime) "$f" 2>/dev/null); \
        cwd=$(grep '^cwd: ' "$f" 2>/dev/null | head -1 | sed 's/^cwd: *//'); \
        sumLine=$(grep '^summary: ' "$f" 2>/dev/null | head -1 | sed 's/^summary: *//'); \
        nameLine=$(grep '^name: ' "$f" 2>/dev/null | head -1 | sed 's/^name: *//'); \
        msg="${sumLine:-$nameLine}"; \
        echo "${ts}|||${sid}|||${cwd}|||${msg}"; \
        done; true
        """

        let output = try await session.exec(command)
        return parseSessionListOutput(output)
    }

    /// Parse the `ts|||sid|||cwd|||summary` lines emitted by the remote shell command
    /// into `AIAgentSession`s. Pure function — exposed for unit testing.
    static func parseSessionListOutput(_ raw: String) -> [AIAgentSession] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var sessions: [AIAgentSession] = []
        for line in trimmed.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = String(line).components(separatedBy: "|||")
            guard parts.count >= 2 else { continue }

            let timestampStr = parts[0].trimmingCharacters(in: .whitespaces)
            let sessionId = parts[1].trimmingCharacters(in: .whitespaces)
            let projectPath = parts.count >= 3 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
            let rawSummary = parts.count >= 4 ? parts[3].trimmingCharacters(in: .whitespaces) : nil

            guard !sessionId.isEmpty else { continue }

            let lastModified: Date?
            if let timestamp = TimeInterval(timestampStr) {
                lastModified = Date(timeIntervalSince1970: timestamp)
            } else {
                lastModified = nil
            }

            sessions.append(AIAgentSession(
                agentID: agentID,
                sessionId: sessionId,
                projectPath: projectPath.isEmpty ? "Unknown" : projectPath,
                lastModified: lastModified,
                summary: cleanSummary(rawSummary)
            ))
        }
        return sessions
    }

    // MARK: - Custom Commands

    static func resumeCommand(sessionId: String, binaryPath: String) -> String {
        // GitHub Copilot CLI uses `--resume=<id>` (equals form). Short prefixes
        // (7+ hex chars) and named sessions are also accepted. We always pass
        // the full UUID we listed.
        "\(binaryPath) --resume=\(shellEscape(sessionId))"
    }

    static func newCommand(projectPath: String?, binaryPath: String) -> String {
        if let path = projectPath, !path.isEmpty {
            return "cd \(shellEscape(path)) && \(binaryPath)"
        }
        return binaryPath
    }

    // MARK: - Private Helpers

    static func cleanSummary(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        var text = raw
        // Strip surrounding YAML quotes if present.
        if text.hasPrefix("\"") && text.hasSuffix("\"") && text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        } else if text.hasPrefix("'") && text.hasSuffix("'") && text.count >= 2 {
            text = String(text.dropFirst().dropLast())
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func shellEscape(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
