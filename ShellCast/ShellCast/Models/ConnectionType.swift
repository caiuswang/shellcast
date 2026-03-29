import Foundation

enum ConnectionType: String, Codable, CaseIterable {
    case auto
    case ssh
    case mosh
}
