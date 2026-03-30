import XCTest
@testable import ShellCast

/// Tests for background session persistence behavior.
/// Verifies that ConnectionManager bridge tracking, snapshot capture,
/// and session lifecycle work correctly during background transitions.
@MainActor
final class BackgroundSessionTests: XCTestCase {

    // MARK: - Bridge Registration

    func testRegisterBridge() {
        let manager = ConnectionManager()
        let session = SSHSession(host: "test", port: 22, username: "user")
        let bridge = TerminalBridge(transport: session)
        let sessionId = UUID()

        manager.registerBridge(bridge, for: sessionId)

        XCTAssertEqual(manager.activeBridges.count, 1)
        XCTAssertTrue(manager.activeBridges[sessionId] === bridge)
    }

    func testUnregisterBridge() {
        let manager = ConnectionManager()
        let session = SSHSession(host: "test", port: 22, username: "user")
        let bridge = TerminalBridge(transport: session)
        let sessionId = UUID()

        manager.registerBridge(bridge, for: sessionId)
        manager.unregisterBridge(for: sessionId)

        XCTAssertTrue(manager.activeBridges.isEmpty)
    }

    func testRegisterMultipleBridges() {
        let manager = ConnectionManager()
        let session1 = SSHSession(host: "host1", port: 22, username: "user")
        let session2 = SSHSession(host: "host2", port: 22, username: "user")
        let bridge1 = TerminalBridge(transport: session1)
        let bridge2 = TerminalBridge(transport: session2)
        let id1 = UUID()
        let id2 = UUID()

        manager.registerBridge(bridge1, for: id1)
        manager.registerBridge(bridge2, for: id2)

        XCTAssertEqual(manager.activeBridges.count, 2)
        XCTAssertTrue(manager.activeBridges[id1] === bridge1)
        XCTAssertTrue(manager.activeBridges[id2] === bridge2)
    }

    func testRegisterBridgeOverwritesSameId() {
        let manager = ConnectionManager()
        let session1 = SSHSession(host: "host1", port: 22, username: "user")
        let session2 = SSHSession(host: "host2", port: 22, username: "user")
        let bridge1 = TerminalBridge(transport: session1)
        let bridge2 = TerminalBridge(transport: session2)
        let sessionId = UUID()

        manager.registerBridge(bridge1, for: sessionId)
        manager.registerBridge(bridge2, for: sessionId)

        XCTAssertEqual(manager.activeBridges.count, 1)
        XCTAssertTrue(manager.activeBridges[sessionId] === bridge2)
    }

    func testUnregisterNonexistentIdIsNoOp() {
        let manager = ConnectionManager()
        let randomId = UUID()

        // Should not crash or throw
        manager.unregisterBridge(for: randomId)

        XCTAssertTrue(manager.activeBridges.isEmpty)
    }

    // MARK: - SSHSession State

    func testSSHSessionInitialState() {
        let session = SSHSession(host: "10.0.0.1", port: 22, username: "admin")

        XCTAssertEqual(session.host, "10.0.0.1")
        XCTAssertEqual(session.port, 22)
        XCTAssertEqual(session.username, "admin")
        XCTAssertFalse(session.isConnected)
    }

    func testDisconnectedSessionIsNotConnected() async {
        let session = SSHSession(host: "test", port: 22, username: "user")
        await session.disconnect()
        XCTAssertFalse(session.isConnected)
    }

    // MARK: - TerminalBridge State

    func testBridgeInitialState() {
        let session = SSHSession(host: "test", port: 22, username: "user")
        let bridge = TerminalBridge(transport: session)

        XCTAssertFalse(bridge.isReconnecting)
        XCTAssertFalse(bridge.isDisconnected)
        XCTAssertFalse(bridge.showTmuxSwitcher)
    }

    func testBridgeSnapshotReturnsNilWithoutTerminalView() {
        let session = SSHSession(host: "test", port: 22, username: "user")
        let bridge = TerminalBridge(transport: session)

        // No terminalView attached — snapshot should return nil
        let snapshot = bridge.captureSnapshot()
        XCTAssertNil(snapshot)
    }

    func testBridgeSkipsSnapshotWhenDisconnected() {
        let session = SSHSession(host: "test", port: 22, username: "user")
        let bridge = TerminalBridge(transport: session)
        bridge.isDisconnected = true

        let snapshot = bridge.captureSnapshot()
        XCTAssertNil(snapshot)
    }

    // MARK: - ConnectionManager Active Sessions

    func testActiveSessionsStartEmpty() {
        let manager = ConnectionManager()
        XCTAssertTrue(manager.activeSessions.isEmpty)
        XCTAssertFalse(manager.isConnecting)
        XCTAssertNil(manager.connectionError)
    }

    func testActiveBridgesStartEmpty() {
        let manager = ConnectionManager()
        XCTAssertTrue(manager.activeBridges.isEmpty)
    }

    // MARK: - SessionRecord Model

    func testSessionRecordInitialization() {
        let connectionId = UUID()
        let record = SessionRecord(connectionId: connectionId, tmuxSessionName: "main")

        XCTAssertEqual(record.connectionId, connectionId)
        XCTAssertEqual(record.tmuxSessionName, "main")
        XCTAssertTrue(record.isActive)
        XCTAssertNil(record.snapshotImageData)
        XCTAssertNil(record.snapshotCapturedAt)
    }

    func testSessionRecordDefaultsToActive() {
        let record = SessionRecord(connectionId: UUID())

        XCTAssertTrue(record.isActive)
        XCTAssertNil(record.tmuxSessionName)
    }

    func testSessionRecordCanBeDeactivated() {
        let record = SessionRecord(connectionId: UUID(), tmuxSessionName: "dev")

        record.isActive = false

        XCTAssertFalse(record.isActive)
    }

    func testSessionRecordSnapshotUpdate() {
        let record = SessionRecord(connectionId: UUID())
        let fakeSnapshot = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG magic bytes

        record.snapshotImageData = fakeSnapshot
        record.snapshotCapturedAt = Date()
        record.lastActiveAt = Date()

        XCTAssertNotNil(record.snapshotImageData)
        XCTAssertNotNil(record.snapshotCapturedAt)
        XCTAssertEqual(record.snapshotImageData, fakeSnapshot)
    }

    // MARK: - Background Lifecycle Simulation

    /// Simulates the flow: register bridge → capture would work → unregister on disappear
    func testBridgeLifecycleRegistrationFlow() {
        let manager = ConnectionManager()
        let session = SSHSession(host: "test", port: 22, username: "user")
        let bridge = TerminalBridge(transport: session)
        let sessionId = UUID()

        // onAppear: register
        manager.registerBridge(bridge, for: sessionId)
        XCTAssertEqual(manager.activeBridges.count, 1)

        // Bridge is available for snapshot capture
        XCTAssertNotNil(manager.activeBridges[sessionId])

        // onDisappear: unregister
        manager.unregisterBridge(for: sessionId)
        XCTAssertTrue(manager.activeBridges.isEmpty)
    }

    /// Verifies that disconnected transports are detected correctly
    func testDisconnectedTransportDetection() {
        let manager = ConnectionManager()

        // No active sessions — nothing should be "live"
        let hasLive = manager.activeSessions.contains { session in
            session.transport.isConnected
        }
        XCTAssertFalse(hasLive)
    }
}
