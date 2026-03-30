import Foundation

enum MoshError: Error, LocalizedError {
    case bootstrapFailed(String)
    case parseConnectFailed
    case sessionFailed(String)
    case serverNotInstalled
    case frameworkNotAvailable

    var errorDescription: String? {
        switch self {
        case .bootstrapFailed(let reason): return "Mosh bootstrap failed: \(reason)"
        case .parseConnectFailed: return "Failed to parse MOSH CONNECT response"
        case .sessionFailed(let reason): return "Mosh session failed: \(reason)"
        case .serverNotInstalled: return "mosh-server is not installed on the remote host"
        case .frameworkNotAvailable: return "Mosh support is not available in this build"
        }
    }
}

// MARK: - MoshSession

#if canImport(mosh)
import mosh

final class MoshSession: TransportSession {
    let host: String
    let port: String
    let key: String

    private(set) var isConnected = false
    /// True until start() is called — terminal view should call start() with correct dimensions
    private(set) var needsStart = true
    private var continuation: AsyncStream<Data>.Continuation?
    private var moshThread: Thread?
    private var inputPipe: Pipe?
    private var winSize = winsize()
    private var serializedState: Data?

    /// Called when session ends unexpectedly
    var onDisconnect: (() -> Void)?

    let outputStream: AsyncStream<Data>

    init(host: String, port: String, key: String) {
        self.host = host
        self.port = port
        self.key = key
        var cont: AsyncStream<Data>.Continuation?
        self.outputStream = AsyncStream { continuation in
            cont = continuation
        }
        self.continuation = cont
    }

    /// Start the mosh-client session. Blocks until session ends (runs on background thread).
    func start(cols: Int = 80, rows: Int = 24, encodedState: Data? = nil) {
        print("[MOSH] start() called: cols=\(cols) rows=\(rows) needsStart=\(needsStart)")
        needsStart = false
        winSize.ws_col = UInt16(cols)
        winSize.ws_row = UInt16(rows)

        guard let continuation = self.continuation else {
            print("[MOSH] ERROR: continuation is nil!")
            return
        }
        print("[MOSH] continuation OK, setting up pipes")

        let inputPipe = Pipe()
        self.inputPipe = inputPipe

        let outputPipe = Pipe()
        // Store the read file descriptor before mosh thread starts
        let outputReadFD = outputPipe.fileHandleForReading.fileDescriptor

        isConnected = true

        // Read mosh output on a dedicated reader thread
        let readerThread = Thread { [weak self] in
            let bufferSize = 16384
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer { buffer.deallocate() }
            while true {
                let bytesRead = read(outputReadFD, buffer, bufferSize)
                if bytesRead <= 0 {
                    self?.handleDisconnect()
                    break
                }
                let data = Data(bytes: buffer, count: bytesRead)
                continuation.yield(data)
            }
        }
        readerThread.name = "MoshReader"
        readerThread.qualityOfService = .userInteractive
        readerThread.start()

        // Copy state for the mosh thread (avoid escaping withUnsafeBytes)
        let stateData: Data? = encodedState ?? self.serializedState

        // Run mosh_main on a dedicated thread (it blocks)
        let thread = Thread { [weak self] in
            guard let self else { return }

            let fIn = fdopen(inputPipe.fileHandleForReading.fileDescriptor, "r")
            let fOut = fdopen(outputPipe.fileHandleForWriting.fileDescriptor, "w")

            guard let fIn, let fOut else {
                self.handleDisconnect()
                return
            }

            // Disable buffering on output
            setvbuf(fOut, nil, _IONBF, 0)

            let selfPtr = Unmanaged.passRetained(self).toOpaque()

            if let stateData, !stateData.isEmpty {
                stateData.withUnsafeBytes { rawBuffer in
                    let ptr = rawBuffer.baseAddress?.assumingMemoryBound(to: CChar.self)
                    mosh_main(
                        fIn, fOut, &self.winSize,
                        { context, buffer, size in
                            guard let context, let buffer else { return }
                            let session = Unmanaged<MoshSession>.fromOpaque(context).takeUnretainedValue()
                            session.serializedState = Data(bytes: buffer, count: size)
                        },
                        selfPtr,
                        self.host, self.port, self.key, "adaptive",
                        ptr, stateData.count, "yes"
                    )
                }
            } else {
                mosh_main(
                    fIn, fOut, &self.winSize,
                    { context, buffer, size in
                        guard let context, let buffer else { return }
                        let session = Unmanaged<MoshSession>.fromOpaque(context).takeUnretainedValue()
                        session.serializedState = Data(bytes: buffer, count: size)
                    },
                    selfPtr,
                    self.host, self.port, self.key, "adaptive",
                    nil, 0, "yes"
                )
            }

            // mosh_main returned — session ended
            Unmanaged<MoshSession>.fromOpaque(selfPtr).release()
            fclose(fIn)
            fclose(fOut)
            self.handleDisconnect()
        }
        thread.name = "MoshSession"
        thread.qualityOfService = .userInteractive
        self.moshThread = thread
        thread.start()
    }

    private func handleDisconnect() {
        guard isConnected else { return }
        isConnected = false
        continuation?.finish()
        DispatchQueue.main.async { [weak self] in
            self?.onDisconnect?()
        }
    }

    // MARK: - TransportSession

    var needsDeferredStart: Bool { needsStart }

    func startWithDimensions(cols: Int, rows: Int) {
        guard needsStart else { return }
        start(cols: cols, rows: rows)
    }

    func send(_ data: Data) async throws {
        guard isConnected, let pipe = inputPipe else { return }
        pipe.fileHandleForWriting.write(data)
    }

    func resize(cols: Int, rows: Int) async throws {
        winSize.ws_col = UInt16(cols)
        winSize.ws_row = UInt16(rows)
        // mosh_main reads winSize pointer directly on each iteration
    }

    func disconnect() async {
        isConnected = false
        inputPipe?.fileHandleForWriting.closeFile()
        inputPipe = nil
        continuation?.finish()
        moshThread?.cancel()
        moshThread = nil
    }

    /// Get serialized state for background persistence
    func getSerializedState() -> Data? {
        return serializedState
    }
}
#endif

// MARK: - MoshService

struct MoshService {
    /// Bootstrap only: SSH to server, start mosh-server, parse MOSH CONNECT.
    /// Returns a MoshSession that is NOT yet started — call `start(cols:rows:)` once the terminal view is sized.
    static func bootstrap(
        sshSession: SSHSession,
        host: String,
        shellCommand: String? = nil
    ) async throws -> any TransportSession {
        #if canImport(mosh)
        // Run mosh-server on the remote host
        // Pass shell command after -- so mosh-server runs it directly instead of login shell
        var command = "mosh-server new -s -c 256 -l LANG=en_US.UTF-8"
        if let shellCommand {
            command += " -- \(shellCommand)"
        }
        print("[MOSH] Exec: \(command)")
        let output: String
        do {
            output = try await sshSession.exec(command)
        } catch {
            print("[MOSH] Exec failed: \(error)")
            throw MoshError.bootstrapFailed(error.localizedDescription)
        }
        print("[MOSH] Server output: \(output)")

        // Parse "MOSH CONNECT <port> <key>" from output
        guard let (port, key) = parseMoshConnect(output) else {
            if output.contains("command not found") || output.contains("No such file") {
                throw MoshError.serverNotInstalled
            }
            print("[MOSH] Failed to parse MOSH CONNECT from output")
            throw MoshError.parseConnectFailed
        }
        print("[MOSH] Parsed: port=\(port) key=\(key.prefix(8))...")

        // Close the SSH session — Mosh takes over via UDP
        await sshSession.disconnect()
        print("[MOSH] SSH disconnected, returning MoshSession (not started)")

        return MoshSession(host: host, port: port, key: key)
        #else
        throw MoshError.frameworkNotAvailable
        #endif
    }

    /// Parse "MOSH CONNECT <port> <key>" from mosh-server output.
    static func parseMoshConnect(_ output: String) -> (port: String, key: String)? {
        for line in output.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("MOSH CONNECT") {
                let parts = trimmed.components(separatedBy: " ")
                guard parts.count >= 4 else { continue }
                return (port: parts[2], key: parts[3])
            }
        }
        return nil
    }
}
