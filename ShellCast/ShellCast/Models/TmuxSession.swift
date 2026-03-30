import Foundation

struct TmuxSession: Identifiable, Hashable {
    let name: String
    let windowCount: Int
    let lastAttached: Date?
    let attachedClients: Int

    var id: String { name }

    var isInUse: Bool { attachedClients > 0 }
}

struct TmuxWindow: Identifiable {
    let index: Int
    let name: String
    let isActive: Bool
    let paneCount: Int

    var id: Int { index }
}
