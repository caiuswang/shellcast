import Foundation
import Citadel
import NIOCore
import NIOSSH

enum SSHError: Error, LocalizedError {
    case connectionFailed(String)
    case authenticationFailed
    case channelOpenFailed
    case disconnected
    case execFailed(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason): return "Connection failed: \(reason)"
        case .authenticationFailed: return "Authentication failed"
        case .channelOpenFailed: return "Failed to open channel"
        case .disconnected: return "Disconnected"
        case .execFailed(let reason): return "Command failed: \(reason)"
        }
    }
}

final class SSHSession: TransportSession {
    let host: String
    let port: Int
    let username: String

    private var client: SSHClient?
    private var continuation: AsyncStream<Data>.Continuation?
    private var ptyTask: Task<Void, Error>?
    private var stdinWriter: TTYStdinWriter?
    private(set) var isConnected = false

    lazy var outputStream: AsyncStream<Data> = {
        AsyncStream { [weak self] continuation in
            self?.continuation = continuation
        }
    }()

    init(host: String, port: Int, username: String) {
        self.host = host
        self.port = port
        self.username = username
    }

    func connect(password: String) async throws {
        do {
            let client = try await SSHClient.connect(
                host: host,
                port: port,
                authenticationMethod: .passwordBased(username: username, password: password),
                hostKeyValidator: .acceptAnything(),
                reconnect: .always
            )
            self.client = client
            isConnected = true
        } catch {
            throw SSHError.connectionFailed("\(type(of: error)): \(error)")
        }
    }

    func connect(privateKey: String) async throws {
        do {
            let client = try await SSHClient.connect(
                host: host,
                port: port,
                authenticationMethod: .rsa(
                    username: username,
                    privateKey: .init(sshRsa: privateKey)
                ),
                hostKeyValidator: .acceptAnything(),
                reconnect: .always
            )
            self.client = client
            isConnected = true
        } catch {
            throw SSHError.connectionFailed(error.localizedDescription)
        }
    }

    /// Open an interactive PTY shell session and start streaming output.
    func openShell(cols: Int = 80, rows: Int = 24, tmuxCommand: String? = nil) async throws {
        guard let client = client else { throw SSHError.disconnected }

        // Access the outputStream to ensure continuation is created
        _ = self.outputStream

        let continuation = self.continuation!

        ptyTask = Task { [weak self] in
            do {
                try await client.withPTY(
                    SSHChannelRequestEvent.PseudoTerminalRequest(
                        wantReply: true,
                        term: "xterm-256color",
                        terminalCharacterWidth: cols,
                        terminalRowHeight: rows,
                        terminalPixelWidth: 0,
                        terminalPixelHeight: 0,
                        terminalModes: SSHTerminalModes([:])
                    )
                ) { inbound, outbound in
                    // Store the writer for sending input and resize
                    self?.stdinWriter = outbound

                    // If there's a tmux command, send it
                    if let tmuxCommand {
                        let cmd = "\(tmuxCommand)\n"
                        try await outbound.write(ByteBuffer(string: cmd))
                    }

                    // Read output from the PTY and yield to the stream
                    for try await chunk in inbound {
                        let data: Data
                        switch chunk {
                        case .stdout(let buffer):
                            data = Data(buffer.readableBytesView)
                        case .stderr(let buffer):
                            data = Data(buffer.readableBytesView)
                        }
                        continuation.yield(data)
                    }

                    self?.isConnected = false
                    continuation.finish()
                }
            } catch {
                self?.isConnected = false
                continuation.finish()
            }
        }
    }

    func exec(_ command: String) async throws -> String {
        guard let client = client else { throw SSHError.disconnected }
        do {
            let buffer = try await client.executeCommand(command)
            return String(buffer: buffer)
        } catch {
            throw SSHError.execFailed(error.localizedDescription)
        }
    }

    func send(_ data: Data) async throws {
        guard isConnected else { throw SSHError.disconnected }
        guard let writer = stdinWriter else { throw SSHError.channelOpenFailed }
        try await writer.write(ByteBuffer(bytes: Array(data)))
    }

    func resize(cols: Int, rows: Int) async throws {
        guard isConnected else { throw SSHError.disconnected }
        guard let writer = stdinWriter else { return }
        try await writer.changeSize(cols: cols, rows: rows, pixelWidth: 0, pixelHeight: 0)
    }

    func disconnect() async {
        isConnected = false
        ptyTask?.cancel()
        continuation?.finish()
        try? await client?.close()
        client = nil
    }
}

struct SSHService {
    static func connect(
        host: String,
        port: Int,
        username: String,
        password: String
    ) async throws -> SSHSession {
        let session = SSHSession(host: host, port: port, username: username)
        try await session.connect(password: password)
        return session
    }

    static func connect(
        host: String,
        port: Int,
        username: String,
        privateKey: String
    ) async throws -> SSHSession {
        let session = SSHSession(host: host, port: port, username: username)
        try await session.connect(privateKey: privateKey)
        return session
    }
}
