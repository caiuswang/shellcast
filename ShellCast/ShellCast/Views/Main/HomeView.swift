import SwiftUI
import SwiftData

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ConnectionManager.self) private var connectionManager
    @Query(sort: \Connection.sortOrder) private var connections: [Connection]
    @Query(filter: #Predicate<SessionRecord> { $0.isActive }, sort: \SessionRecord.lastActiveAt, order: .reverse)
    private var activeSessions: [SessionRecord]

    @State private var showAddConnection = false
    @State private var selectedConnection: Connection?
    @State private var connectingConnection: Connection?
    @State private var activeTransport: SSHSession?
    @State private var showTerminal = false
    @State private var showTmuxBrowser = false
    @State private var tmuxSessions: [TmuxSession] = []
    @State private var errorMessage: String?
    @State private var showError = false

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
                        Button(action: {}) {
                            Image(systemName: "gearshape")
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    showAddConnection = true
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
            .sheet(isPresented: $showAddConnection) {
                EditConnectionView(mode: .add) { connection in
                    connectTo(connection)
                }
            }
            .sheet(item: $selectedConnection) { connection in
                EditConnectionView(mode: .edit(connection))
            }
            .fullScreenCover(isPresented: $showTerminal) {
                if let transport = activeTransport {
                    TerminalContainerView(transport: transport)
                }
            }
            .sheet(isPresented: $showTmuxBrowser) {
                if let transport = activeTransport {
                    TmuxBrowserView(sessions: tmuxSessions) { tmuxSession in
                        showTmuxBrowser = false
                        Task {
                            if let tmuxSession {
                                try await transport.openShell(tmuxCommand: "tmux attach -t \(tmuxSession.name)")
                            } else {
                                try await transport.openShell()
                            }
                            showTerminal = true
                        }
                    }
                }
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

    private func connectTo(_ connection: Connection) {
        Task {
            do {
                let transport = try await connectionManager.connect(connection)
                self.activeTransport = transport

                // Try to list tmux sessions
                do {
                    let sessions = try await TmuxParser.listSessions(over: transport)
                    if sessions.isEmpty {
                        // No tmux sessions, open shell directly
                        try await transport.openShell()
                        showTerminal = true
                    } else {
                        tmuxSessions = sessions
                        showTmuxBrowser = true
                    }
                } catch {
                    // tmux not available or failed, open shell directly
                    try await transport.openShell()
                    showTerminal = true
                }
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
                ConnectionRow(connection: connection)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        connectTo(connection)
                    }
                    .contextMenu {
                        Button("Edit") {
                            selectedConnection = connection
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
