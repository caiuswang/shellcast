import Foundation
import SwiftData

@Model
final class Connection {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var authMethod: AuthMethod
    var connectionType: ConnectionType
    var keyFilePath: String?
    var keychainPasswordRef: String?
    var createdAt: Date
    var lastConnectedAt: Date?
    var sortOrder: Int

    init(
        name: String = "",
        host: String = "",
        port: Int = 22,
        username: String = "",
        authMethod: AuthMethod = .password,
        connectionType: ConnectionType = .ssh
    ) {
        self.id = UUID()
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.authMethod = authMethod
        self.connectionType = connectionType
        self.createdAt = Date()
        self.sortOrder = 0
        self.keychainPasswordRef = id.uuidString
    }
}
