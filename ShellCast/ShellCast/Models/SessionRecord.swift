import Foundation
import SwiftData

@Model
final class SessionRecord {
    var id: UUID
    var connectionId: UUID
    var tmuxSessionName: String?
    var startedAt: Date
    var lastActiveAt: Date
    var snapshotImageData: Data?
    var isActive: Bool

    init(connectionId: UUID, tmuxSessionName: String? = nil) {
        self.id = UUID()
        self.connectionId = connectionId
        self.tmuxSessionName = tmuxSessionName
        self.startedAt = Date()
        self.lastActiveAt = Date()
        self.isActive = true
    }
}
