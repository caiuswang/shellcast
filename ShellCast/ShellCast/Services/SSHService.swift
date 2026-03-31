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

    /// Stored credentials for reconnection
    private var storedPassword: String?
    private var storedPrivateKey: String?
    private var storedPassphrase: String?

    /// Called when connection is lost unexpectedly (not from explicit disconnect)
    var onDisconnect: (() -> Void)?

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
        self.storedPassword = password
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

    func connect(privateKey: String, passphrase: String? = nil) async throws {
        self.storedPrivateKey = privateKey
        self.storedPassphrase = passphrase
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

    /// Check if the SSH connection is still alive by attempting a lightweight operation.
    func checkAlive() async -> Bool {
        guard isConnected, client != nil else { return false }
        do {
            _ = try await exec("echo 1")
            return true
        } catch {
            return false
        }
    }

    /// Reconnect the SSH session using stored credentials, then reopen a shell.
    func reconnect(cols: Int = 80, rows: Int = 24, tmuxCommand: String? = nil) async throws {
        // Clean up old state
        ptyTask?.cancel()
        stdinWriter = nil
        try? await client?.close()
        client = nil

        // Create a fresh output stream and continuation
        continuation = nil
        outputStream = AsyncStream { [weak self] continuation in
            self?.continuation = continuation
        }

        // Reconnect using stored credentials
        if let privateKey = storedPrivateKey {
            try await connect(privateKey: privateKey, passphrase: storedPassphrase)
        } else if let password = storedPassword {
            try await connect(password: password)
        } else {
            throw SSHError.connectionFailed("No stored credentials for reconnection")
        }

        // Reopen the shell
        try await openShell(cols: cols, rows: rows, tmuxCommand: tmuxCommand)
    }

    /// Open an interactive PTY shell session and start streaming output.
    func openShell(cols: Int = 80, rows: Int = 24, tmuxCommand: String? = nil) async throws {
        guard let client = client else { throw SSHError.disconnected }

        // Access the outputStream to ensure continuation is created
        _ = self.outputStream

        guard let continuation = self.continuation else {
            throw SSHError.connectionFailed("Failed to initialize output stream")
        }

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
                    ),
                    environment: [
                        .init(wantReply: true, name: "LANG", value: "en_US.UTF-8"),
                        .init(wantReply: true, name: "LC_ALL", value: "en_US.UTF-8"),
                    ]
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
                    self?.onDisconnect?()
                }
            } catch {
                self?.isConnected = false
                continuation.finish()
                self?.onDisconnect?()
            }
        }
    }

    func exec(_ command: String) async throws -> String {
        guard let client = client else { throw SSHError.disconnected }

        do {
            let buffer = try await client.executeCommand(command)
            let result = String(buffer: buffer)
            return result
        } catch {
            // Citadel's executeCommand uses mergeStreams: false by default,
            // which throws TTYSTDError when stderr has output.
            // Try again with mergeStreams to capture stdout regardless.

            do {
                let buffer = try await client.executeCommand(command, mergeStreams: true)
                let result = String(buffer: buffer)
                return result
            } catch {

                throw SSHError.execFailed("\(type(of: error)): \(error)")
            }
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
        privateKey: String,
        passphrase: String? = nil
    ) async throws -> SSHSession {
        let session = SSHSession(host: host, port: port, username: username)
        try await session.connect(privateKey: privateKey, passphrase: passphrase)
        return session
    }
}
