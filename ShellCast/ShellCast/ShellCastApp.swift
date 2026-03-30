import SwiftUI
import SwiftData
import UIKit

@main
struct ShellCastApp: App {
    @State private var connectionManager = ConnectionManager()
    @Environment(\.scenePhase) private var scenePhase

    let modelContainer: ModelContainer

    /// Track the current background task ID so we don't leak tasks.
    @State private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    init() {
        do {
            modelContainer = try ModelContainer(for: Connection.self, SessionRecord.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        // Start network monitoring for WiFi↔cellular handoff detection
        NetworkMonitor.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(connectionManager)
        }
        .modelContainer(modelContainer)
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                beginBackgroundSessionPersistence()
            case .active:
                endBackgroundTaskIfNeeded()
            default:
                break
            }
        }
    }

    // MARK: - Background Session Persistence

    /// Request extended background time to keep SSH connections alive.
    /// Captures snapshots and updates session records before iOS suspends the app.
    private func beginBackgroundSessionPersistence() {
        // End any existing background task first
        endBackgroundTaskIfNeeded()

        backgroundTaskID = UIApplication.shared.beginBackgroundTask(
            withName: "ShellCast.KeepSSHAlive"
        ) { [self] in
            // Expiration handler — iOS is about to suspend us.
            // Mark sessions that have lost connection as inactive.
            Task { @MainActor in
                markDisconnectedSessionsInactive()
            }
            endBackgroundTaskIfNeeded()
        }

        // Capture snapshots and save Mosh state for all active terminal bridges
        Task { @MainActor in
            captureAllSnapshots()
            saveMoshSessionStates()
        }
    }

    /// Capture terminal snapshots from all registered bridges and update their session records.
    @MainActor
    private func captureAllSnapshots() {
        let context = modelContainer.mainContext

        for (sessionId, bridge) in connectionManager.activeBridges {
            guard !bridge.isDisconnected, !bridge.isReconnecting,
                  let snapshotData = bridge.captureSnapshot() else { continue }

            let predicate = #Predicate<SessionRecord> { $0.id == sessionId }
            let descriptor = FetchDescriptor(predicate: predicate)
            guard let record = try? context.fetch(descriptor).first else { continue }

            record.snapshotImageData = snapshotData
            record.snapshotCapturedAt = Date()
            record.lastActiveAt = Date()
        }
        try? context.save()
    }

    /// Mark sessions as inactive if their transport is no longer connected.
    @MainActor
    private func markDisconnectedSessionsInactive() {
        let context = modelContainer.mainContext

        let activePredicate = #Predicate<SessionRecord> { $0.isActive == true }
        let descriptor = FetchDescriptor(predicate: activePredicate)
        guard let activeSessions = try? context.fetch(descriptor) else { return }

        for record in activeSessions {
            // Check if there's still a live transport for this session
            let hasLiveTransport = connectionManager.activeSessions.contains { activeSession in
                activeSession.connection.id == record.connectionId && activeSession.transport.isConnected
            }
            if !hasLiveTransport {
                record.isActive = false
            }
        }
        try? context.save()
    }

    /// Save Mosh session serialized state to disk so sessions can resume after iOS suspension.
    @MainActor
    private func saveMoshSessionStates() {
        #if canImport(mosh)
        for (sessionId, bridge) in connectionManager.activeBridges {
            guard let moshSession = bridge.transport as? MoshSession,
                  moshSession.isConnected else { continue }
            MoshService.saveSessionState(
                sessionId: sessionId,
                host: moshSession.host,
                port: moshSession.port,
                key: moshSession.key,
                state: moshSession.getSerializedState()
            )
        }
        #endif
    }

    private func endBackgroundTaskIfNeeded() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }
}
