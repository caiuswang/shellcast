import Foundation

struct ClaudeCodeSession: Identifiable {
    let sessionId: String
    let projectPath: String
    let lastModified: Date?
    let summary: String?

    var id: String { sessionId }

    var projectName: String {
        projectPath.components(separatedBy: "/").last ?? projectPath
    }
}
