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

    static func renameSession(over session: SSHSession, oldName: String, newName: String) async throws {
        let command = "/opt/homebrew/bin/tmux rename-session -t \(oldName) \(newName)"
        _ = try await session.exec(command)
    }

    static func killSession(over session: SSHSession, sessionName: String) async throws {
        let command = "/opt/homebrew/bin/tmux kill-session -t \(sessionName)"
        _ = try await session.exec(command)
    }

    static func renameWindow(over session: SSHSession, sessionName: String, windowIndex: Int, newName: String) async throws {
        let command = "/opt/homebrew/bin/tmux rename-window -t \(sessionName):\(windowIndex) \(newName)"
        _ = try await session.exec(command)
    }

    static func killWindow(over session: SSHSession, sessionName: String, windowIndex: Int) async throws {
        let command = "/opt/homebrew/bin/tmux kill-window -t \(sessionName):\(windowIndex)"
        _ = try await session.exec(command)
    }

    static func switchClient(over session: SSHSession, targetSession: String) async throws {
        let command = "/opt/homebrew/bin/tmux switch-client -t \(targetSession)"
        _ = try await session.exec(command)
    }

    static func selectWindow(over session: SSHSession, sessionName: String, windowIndex: Int) async throws {
        let command = "/opt/homebrew/bin/tmux select-window -t \(sessionName):\(windowIndex)"
        _ = try await session.exec(command)
    }

    static func currentSessionName(over session: SSHSession) async throws -> String? {
        let command = "/opt/homebrew/bin/tmux display-message -p '#{session_name}'"
        let output = try await session.exec(command)
        let name = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    static func listWindows(over session: SSHSession, sessionName: String) async throws -> [TmuxWindow] {
        let format = "#{window_index}\(separator)#{window_name}\(separator)#{window_active}\(separator)#{window_panes}"
        let command = "/opt/homebrew/bin/tmux list-windows -t \(sessionName) -F '\(format)'"
        let output = try await session.exec(command)

        guard !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return output.split(separator: "\n").compactMap { line in
            let parts = line.components(separatedBy: separator)
            guard parts.count >= 4 else { return nil }

            return TmuxWindow(
                index: Int(parts[0].trimmingCharacters(in: .whitespaces)) ?? 0,
                name: parts[1].trimmingCharacters(in: .whitespaces),
                isActive: parts[2].trimmingCharacters(in: .whitespaces) == "1",
                paneCount: Int(parts[3].trimmingCharacters(in: .whitespaces)) ?? 1
            )
        }
    }
}
