import Foundation
import SwiftUI

@Observable
final class ConnectionManager {
    var activeSessions: [ActiveSession] = []
    var connectionError: String?
    var isConnecting = false

    /// Terminal transport for the current session (SSH or Mosh). Stored here because
    /// @State doesn't work reliably with existential protocol types (any TransportSession).
    var activeTerminalTransport: (any TransportSession)?

    /// The outer connect task — cancelling this aborts the entire connection flow.
    var connectingTask: Task<Void, Never>?

    /// Registered bridges for active terminal views — used for snapshot capture on background
    var activeBridges: [UUID: TerminalBridge] = [:]

    struct ActiveSession: Identifiable {
        let id = UUID()
        let connection: Connection
        let transport: any TransportSession
    }

    /// Register a bridge so the app can capture its snapshot when entering background.
    func registerBridge(_ bridge: TerminalBridge, for sessionId: UUID) {
        activeBridges[sessionId] = bridge
    }

    /// Remove a bridge registration.
    func unregisterBridge(for sessionId: UUID) {
        activeBridges.removeValue(forKey: sessionId)
    }

    func connect(_ connection: Connection) async throws -> SSHSession {
        isConnecting = true
        connectionError = nil
        defer { isConnecting = false }

        do {
            let transport = try await connectSSH(connection)
            try Task.checkCancellation()
            let session = ActiveSession(connection: connection, transport: transport)
            activeSessions.append(session)
            connection.lastConnectedAt = Date()
            return transport
        } catch {
            if !Task.isCancelled {
                connectionError = error.localizedDescription
            }
            throw error
        }
    }

    /// Cancel an in-progress connection attempt.
    func cancelConnect() {
        connectingTask?.cancel()
        connectingTask = nil
        isConnecting = false
    }

    func disconnect(_ session: ActiveSession) async {
        await session.transport.disconnect()
        activeSessions.removeAll { $0.id == session.id }
    }

    private func connectSSH(_ connection: Connection) async throws -> SSHSession {
        switch connection.authMethod {
        case .password:
            let password = KeychainService.getPassword(for: connection.id) ?? ""
            return try await SSHService.connect(
                host: connection.host,
                port: connection.port,
                username: connection.username,
                password: password
            )
        case .keyFile:
            guard let keyData = KeychainService.getPrivateKey(for: connection.id),
                  let keyString = String(data: keyData, encoding: .utf8) else {
                throw SSHError.connectionFailed("No SSH key found. Please import a private key file.")
            }
            let passphrase = KeychainService.getKeyPassphrase(for: connection.id)
            return try await SSHService.connect(
                host: connection.host,
                port: connection.port,
                username: connection.username,
                privateKey: keyString,
                passphrase: passphrase
            )
        case .tailscaleSSH:
            // Tailscale SSH uses no password — auth is handled at the network layer
            return try await SSHService.connect(
                host: connection.host,
                port: connection.port,
                username: connection.username,
                password: ""
            )
        }
    }
}
