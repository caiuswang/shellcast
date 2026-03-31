import Foundation

enum MoshError: Error, LocalizedError {
    case bootstrapFailed(String)
    case parseConnectFailed
    case sessionFailed(String)
    case serverNotInstalled
    case frameworkNotAvailable
    case resumeFailed(String)

    var errorDescription: String? {
        switch self {
        case .bootstrapFailed(let reason): return "Mosh bootstrap failed: \(reason)"
        case .parseConnectFailed: return "Failed to parse MOSH CONNECT response"
        case .sessionFailed(let reason): return "Mosh session failed: \(reason)"
        case .serverNotInstalled: return "mosh-server is not installed on the remote host"
        case .frameworkNotAvailable: return "Mosh support is not available in this build"
        case .resumeFailed(let reason): return "Mosh resume failed: \(reason)"
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
    private var moshPthread: pthread_t?
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
        debugLog("[MOSH] start() called: cols=\(cols) rows=\(rows) needsStart=\(needsStart)")
        needsStart = false
        winSize.ws_col = UInt16(cols)
        winSize.ws_row = UInt16(rows)

        guard let continuation = self.continuation else {
            debugLog("[MOSH] ERROR: continuation is nil!")
            return
        }
        debugLog("[MOSH] continuation OK, setting up pipes")

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
            self.moshPthread = pthread_self()

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
        // Signal only the mosh thread to pick up the new window size.
        // Using pthread_kill avoids delivering SIGWINCH to the whole process,
        // which could cause UIKit side-effects (view relayout, etc.).
        if let pt = moshPthread {
            pthread_kill(pt, SIGWINCH)
        }
    }

    func disconnect() async {
        isConnected = false
        inputPipe?.fileHandleForWriting.closeFile()
        inputPipe = nil
        continuation?.finish()
        moshThread?.cancel()
        moshThread = nil
        moshPthread = nil
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
        debugLog("[MOSH] Exec: \(command)")
        let output: String
        do {
            output = try await sshSession.exec(command)
        } catch {
            debugLog("[MOSH] Exec failed: \(error)")
            throw MoshError.bootstrapFailed(error.localizedDescription)
        }
        debugLog("[MOSH] Server output: \(output)")

        // Parse "MOSH CONNECT <port> <key>" from output
        guard let (port, key) = parseMoshConnect(output) else {
            if output.contains("command not found") || output.contains("No such file") {
                throw MoshError.serverNotInstalled
            }
            debugLog("[MOSH] Failed to parse MOSH CONNECT from output")
            throw MoshError.parseConnectFailed
        }
        debugLog("[MOSH] Parsed: port=\(port) key=\(key.prefix(8))...")

        // Close the SSH session — Mosh takes over via UDP
        await sshSession.disconnect()
        debugLog("[MOSH] SSH disconnected, returning MoshSession (not started)")

        return MoshSession(host: host, port: port, key: key)
        #else
        throw MoshError.frameworkNotAvailable
        #endif
    }

    // MARK: - State Persistence

    /// Directory for Mosh session state files.
    private static var stateDirectory: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoshState", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Persisted Mosh session info for resuming after background suspension.
    struct PersistedSession: Codable {
        let host: String
        let port: String
        let key: String
        let serializedState: Data?
        let savedAt: Date
    }

    /// Save a Mosh session's state to disk for later resumption.
    static func saveSessionState(sessionId: UUID, host: String, port: String, key: String, state: Data?) {
        let persisted = PersistedSession(
            host: host, port: port, key: key,
            serializedState: state, savedAt: Date()
        )
        let url = stateDirectory.appendingPathComponent("\(sessionId.uuidString).json")
        if let data = try? JSONEncoder().encode(persisted) {
            try? data.write(to: url, options: .atomic)
            debugLog("[MOSH] Saved session state for \(sessionId) (\(state?.count ?? 0) bytes)")
        }
    }

    /// Load a previously saved Mosh session state.
    static func loadSessionState(sessionId: UUID) -> PersistedSession? {
        let url = stateDirectory.appendingPathComponent("\(sessionId.uuidString).json")
        guard let data = try? Data(contentsOf: url),
              let persisted = try? JSONDecoder().decode(PersistedSession.self, from: data) else {
            return nil
        }
        // Discard state older than 10 minutes — server may have timed out
        if Date().timeIntervalSince(persisted.savedAt) > 600 {
            debugLog("[MOSH] Discarding stale state for \(sessionId) (saved \(persisted.savedAt))")
            removeSessionState(sessionId: sessionId)
            return nil
        }
        return persisted
    }

    /// Remove saved state file.
    static func removeSessionState(sessionId: UUID) {
        let url = stateDirectory.appendingPathComponent("\(sessionId.uuidString).json")
        try? FileManager.default.removeItem(at: url)
    }

    /// Clean up all stale state files (older than 10 minutes).
    static func cleanupStaleStates() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: stateDirectory, includingPropertiesForKeys: nil) else { return }
        let cutoff = Date().addingTimeInterval(-600)
        for file in files where file.pathExtension == "json" {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
               let modified = attrs[.modificationDate] as? Date,
               modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
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
