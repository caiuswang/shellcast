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

    /// Resolve tmux binary path dynamically. Checks common install dirs first,
    /// because non-interactive SSH sessions often have a minimal PATH that
    /// excludes /opt/homebrew/bin etc., causing `command -v tmux` to fail.
    var tmuxResolveCommand: String {
        let candidates = commonBinaryPaths.map { "\($0)/tmux" }.joined(separator: " ")
        return "for __t in \(candidates); do [ -x \"$__t\" ] && echo \"$__t\" && exit 0; done; command -v tmux 2>/dev/null || echo tmux"
    }

    /// Check if any descendant process of parentPid matches the pattern.
    /// Walks the full process tree (not just direct children) because the agent
    /// binary may be a grandchild or deeper (e.g., fish -> subshell -> node/claude).
    func pgrepChildCommand(parentPid: String, pattern: String) -> String {
        // Use ps + awk to walk the entire descendant tree from parentPid
        // and check if any descendant's command line matches the pattern.
        // Must be single-line to work inside backslash-continued while loops.
        // Use tolower() for case-insensitive matching (works on both BSD awk and gawk).
        // The pattern is a POSIX ERE; we escape it for shell double-quote interpolation
        // so authors don't need to bake shell-escapes into their regex.
        let escapedPattern = Self.escapeForShellDoubleQuote(pattern)
        return "(ps -eo pid=,ppid=,args= 2>/dev/null | awk -v root=\"\(parentPid)\" -v pat=\"\(escapedPattern)\" '{ pid=$1; ppid=$2; p[pid]=ppid; a[pid]=tolower($0) } END { for (pid in p) { cur=pid; d=0; while (cur!=\"\" && cur+0!=0 && cur!=root && d<10) { cur=p[cur]; d++ } if (cur==root && pid!=root && a[pid]~pat) exit 0 } exit 1 }')"
    }

    /// Escape a string so it survives shell double-quote interpolation. Replaces
    /// the four characters that retain meaning inside double quotes (`\\`, `"`,
    /// `$`, `` ` ``). Backslash MUST be replaced first, otherwise we'd double-escape
    /// the escapes we add for the other three.
    static func escapeForShellDoubleQuote(_ raw: String) -> String {
        var out = raw
        out = out.replacingOccurrences(of: "\\", with: "\\\\")
        out = out.replacingOccurrences(of: "\"", with: "\\\"")
        out = out.replacingOccurrences(of: "$", with: "\\$")
        out = out.replacingOccurrences(of: "`", with: "\\`")
        return out
    }
}
