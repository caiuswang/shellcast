import Foundation

// MARK: - Remote Platform Detection

/// Detects the remote server's operating system for platform-aware command generation.
/// This is needed because shell commands like `stat`, `pgrep`, and common binary paths
/// differ between macOS and Linux.
enum RemotePlatform: String {
    case macOS
    case linux
    case unknown

    /// Detect the remote OS by running `uname` over SSH
    static func detect(over session: SSHSession) async throws -> RemotePlatform {
        let output = try await session.exec("uname -s 2>/dev/null || echo unknown")
        let os = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch os {
        case "darwin":
            return .macOS
        case "linux":
            return .linux
        default:
            return .unknown
        }
    }

    // MARK: - Platform-Aware Command Helpers

    /// `stat` command to output: <modification_epoch> <filepath>
    /// macOS: `stat -f '%m %N'`  Linux: `stat -c '%Y %n'`
    var statModTimeAndPath: String {
        switch self {
        case .macOS:
            return "stat -f '%m %N'"
        case .linux, .unknown:
            return "stat -c '%Y %n'"
        }
    }

    /// `stat` command to output modification epoch only
    /// macOS: `stat -f '%m'`  Linux: `stat -c '%Y'`
    var statModTime: String {
        switch self {
        case .macOS:
            return "stat -f '%m'"
        case .linux, .unknown:
            return "stat -c '%Y'"
        }
    }

    /// Common binary installation paths for this platform
    var commonBinaryPaths: [String] {
        switch self {
        case .macOS:
            return [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
                "$HOME/.local/bin"
            ]
        case .linux:
            return [
                "/usr/local/bin",
                "/usr/bin",
                "$HOME/.local/bin",
                "/snap/bin",
                "/home/linuxbrew/.linuxbrew/bin"
            ]
        case .unknown:
            // Union of both platforms' paths for best-effort detection
            return [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
                "$HOME/.local/bin",
                "/snap/bin",
                "/home/linuxbrew/.linuxbrew/bin"
            ]
        }
    }

    /// Resolve tmux binary path dynamically
    var tmuxResolveCommand: String {
        "command -v tmux 2>/dev/null || echo tmux"
    }

    /// pgrep command to find child processes matching a pattern.
    /// Uses `-P` (parent PID) which works on both macOS and Linux.
    /// Falls back to ps-based detection if pgrep is unavailable.
    func pgrepChildCommand(parentPid: String, pattern: String) -> String {
        // Try pgrep first, fall back to ps + grep for systems without pgrep
        return "(pgrep -P \"\(parentPid)\" -f \"\(pattern)\" >/dev/null 2>&1 || " +
            "ps -o pid=,ppid=,comm= 2>/dev/null | awk '$2 == \"\(parentPid)\" && /\(pattern)/' | grep -q .)"
    }
}
