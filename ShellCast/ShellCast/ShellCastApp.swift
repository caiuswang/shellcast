import SwiftUI
import SwiftData

@main
struct ShellCastApp: App {
    @State private var connectionManager = ConnectionManager()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environment(connectionManager)
        }
        .modelContainer(for: [Connection.self, SessionRecord.self])
    }
}
