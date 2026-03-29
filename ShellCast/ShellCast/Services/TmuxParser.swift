import Foundation

struct TmuxParser {
    static func listSessions(over session: SSHSession) async throws -> [TmuxSession] {
        let format = "#{session_name}\\t#{session_windows}\\t#{session_last_attached}\\t#{session_attached}"
        let output = try await session.exec("tmux list-sessions -F '\(format)' 2>/dev/null || true")

        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 4 else { return nil }

            let lastAttached: Date?
            if let timestamp = TimeInterval(String(parts[2])) {
                lastAttached = Date(timeIntervalSince1970: timestamp)
            } else {
                lastAttached = nil
            }

            return TmuxSession(
                name: String(parts[0]),
                windowCount: Int(parts[1]) ?? 0,
                lastAttached: lastAttached,
                attachedClients: Int(parts[3]) ?? 0
            )
        }
    }
}
