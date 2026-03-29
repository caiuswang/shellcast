import Foundation

protocol TransportSession: AnyObject {
    var outputStream: AsyncStream<Data> { get }
    var isConnected: Bool { get }
    func send(_ data: Data) async throws
    func resize(cols: Int, rows: Int) async throws
    func disconnect() async
}
