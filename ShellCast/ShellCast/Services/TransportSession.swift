import Foundation

protocol TransportSession: AnyObject {
    var outputStream: AsyncStream<Data> { get }
    var isConnected: Bool { get }
    /// Whether this session needs an explicit start with terminal dimensions (e.g. Mosh).
    /// SSH sessions return false since they're started before the terminal view exists.
    var needsDeferredStart: Bool { get }
    func send(_ data: Data) async throws
    func resize(cols: Int, rows: Int) async throws
    func disconnect() async
    /// Start the session with exact terminal dimensions. Only meaningful if needsDeferredStart is true.
    func startWithDimensions(cols: Int, rows: Int)
}

extension TransportSession {
    var needsDeferredStart: Bool { false }
    func startWithDimensions(cols: Int, rows: Int) {}
}
