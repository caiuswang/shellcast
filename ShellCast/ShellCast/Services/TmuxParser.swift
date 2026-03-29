import Foundation

struct TmuxParser {
    private static let separator = "|||"

    static func listSessions(over session: SSHSession) async throws -> [TmuxSession] {
        let format = "#{session_name}\(separator)#{session_windows}\(separator)#{session_last_attached}\(separator)#{session_attached}"
        let command = "/opt/homebrew/bin/tmux list-sessions -F '\(format)'"
        let output = try await session.exec(command)

        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return output.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: separator)
            guard parts.count >= 4 else { return nil }

            let lastAttached: Date?
            if let timestamp = TimeInterval(parts[2].trimmingCharacters(in: .whitespaces)) {
                lastAttached = Date(timeIntervalSince1970: timestamp)
            } else {
                lastAttached = nil
            }

            return TmuxSession(
                name: parts[0].trimmingCharacters(in: .whitespaces),
                windowCount: Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0,
                lastAttached: lastAttached,
                attachedClients: Int(parts[3].trimmingCharacters(in: .whitespaces)) ?? 0
            )
        }
    }
}
