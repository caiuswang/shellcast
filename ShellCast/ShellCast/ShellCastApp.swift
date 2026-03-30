import SwiftUI
import SwiftData
import UIKit

@main
struct ShellCastApp: App {
    @State private var connectionManager = ConnectionManager()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(connectionManager)
        }
        .modelContainer(for: [Connection.self, SessionRecord.self])
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                // Request extra background time to keep SSH alive briefly
                let taskID = UIApplication.shared.beginBackgroundTask {
                    // Expiration handler — nothing to clean up
                }
                // End the background task after a short delay
                // This gives iOS a few extra seconds to maintain the connection
                DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                    UIApplication.shared.endBackgroundTask(taskID)
                }
            }
        }
    }
}
