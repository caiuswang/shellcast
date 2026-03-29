import Foundation

struct TmuxSession: Identifiable {
    let name: String
    let windowCount: Int
    let lastAttached: Date?
    let attachedClients: Int

    var id: String { name }

    var isInUse: Bool { attachedClients > 0 }
}
