import SwiftUI
import SwiftData

enum ActiveSheet: Identifiable {
    case addConnection
    case editConnection(Connection)
    case tmuxBrowser([TmuxSession])

    var id: String {
        switch self {
        case .addConnection: return "add"
        case .editConnection(let c): return "edit-\(c.id)"
        case .tmuxBrowser: return "tmux"
        }
    }
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ConnectionManager.self) private var connectionManager
    @Query(sort: \Connection.sortOrder) private var connections: [Connection]
    @Query(filter: #Predicate<SessionRecord> { $0.isActive }, sort: \SessionRecord.lastActiveAt, order: .reverse)
    private var activeSessions: [SessionRecord]

    @State private var activeSheet: ActiveSheet?
    @State private var activeTransport: SSHSession?
    @State private var showTerminal = false
    @State private var activeTmuxCommand: String?
    @State private var tmuxSessions: [TmuxSession] = []
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !activeSessions.isEmpty {
                        activeSessionsSection
                    }
                    savedConnectionsSection
                }
                .padding()
            }
            .background(Color.black)
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 12) {
                        Button(action: {}) {
                            Image(systemName: "folder")
                                .foregroundStyle(.white)
                        }
                        Button(action: { showSettings = true }) {
                            Image(systemName: "gearshape")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    activeSheet = .addConnection
                } label: {
                    Image(systemName: "plus")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(Color.green)
                        .clipShape(Circle())
                }
                .padding(24)
            }
            .overlay {
                if connectionManager.isConnecting {
                    Color.black.opacity(0.6)
                        .ignoresSafeArea()
                    ProgressView("Connecting...")
                        .tint(.green)
                        .foregroundStyle(.white)
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .addConnection:
                    EditConnectionView(mode: .add) { connection in
                        connectTo(connection)
                    }
                case .editConnection(let connection):
                    EditConnectionView(mode: .edit(connection))
                case .tmuxBrowser(let sessions):
                    TmuxBrowserView(sessions: sessions) { tmuxSession in
                        activeSheet = nil
                        if let transport = activeTransport {
                            openShell(transport: transport, tmuxSession: tmuxSession)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showTerminal) {
                if let transport = activeTransport {
                    TerminalContainerView(transport: transport, tmuxCommand: activeTmuxCommand)
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("Connection Error", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Connect

    @MainActor
    private func connectTo(_ connection: Connection) {
        Task { @MainActor in
            do {
                let transport = try await connectionManager.connect(connection)
                self.activeTransport = transport

                // Try to list tmux sessions
                var sessions: [TmuxSession] = []
                do {
                    sessions = try await TmuxParser.listSessions(over: transport)

                } catch {

                }

                // Small delay to ensure any previous sheet has fully dismissed
                try? await Task.sleep(for: .milliseconds(500))

                self.activeSheet = .tmuxBrowser(sessions)
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func openShell(transport: SSHSession, tmuxSession: TmuxSession?) {
        Task { @MainActor in
            do {
                let tmuxCommand: String?
                if let session = tmuxSession {
                    if session.name == "new" {
                        tmuxCommand = "tmux new-session"
                    } else {
                        tmuxCommand = "tmux attach -t \(session.name)"
                    }
                } else {
                    tmuxCommand = nil
                }
                self.activeTmuxCommand = tmuxCommand
                try await transport.openShell(tmuxCommand: tmuxCommand)
                showTerminal = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    // MARK: - Active Sessions

    private var activeSessionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIVE SESSIONS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.gray)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(activeSessions) { session in
                        ActiveSessionCard(session: session)
                    }
                }
            }
        }
    }

    // MARK: - Saved Connections

    private var savedConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SAVED CONNECTIONS")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.gray)

            ForEach(connections) { connection in
                ConnectionRow(connection: connection) {
                    activeSheet = .editConnection(connection)
                }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        connectTo(connection)
                    }
                    .contextMenu {
                        Button("Edit") {
                            activeSheet = .editConnection(connection)
                        }
                        Button("Delete", role: .destructive) {
                            modelContext.delete(connection)
                        }
                    }
            }
        }
    }
}

#Preview {
    HomeView()
        .environment(ConnectionManager())
        .modelContainer(for: [Connection.self, SessionRecord.self], inMemory: true)
}
