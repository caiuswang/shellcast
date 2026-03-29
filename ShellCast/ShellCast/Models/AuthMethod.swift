import Foundation

enum AuthMethod: String, Codable, CaseIterable {
    case password
    case keyFile
    case tailscaleSSH
}
