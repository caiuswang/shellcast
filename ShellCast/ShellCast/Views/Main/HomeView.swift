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
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(ConnectionManager.self) private var connectionManager
    @Query(sort: \Connection.sortOrder) private var connections: [Connection]
    @Query(sort: \SessionRecord.lastActiveAt, order: .reverse)
    private var allSessions: [SessionRecord]

    @State private var selectedTab = 0
    @State private var activeSheet: ActiveSheet?
    @State private var activeTransport: SSHSession?
    @State private var activeConnectionId: UUID?
    @State private var showTerminal = false
    @State private var activeTmuxCommand: String?
    @State private var activeSessionRecord: SessionRecord?
    @State private var tmuxSessions: [TmuxSession] = []
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var deleteConnectionTarget: Connection?

    var body: some View {
        TabView(selection: $selectedTab) {
            historyTab
                .tabItem {
                    Image(systemName: "clock")
                    Text("History")
                }
                .tag(0)

            connectionsTab
                .tabItem {
                    Image(systemName: "server.rack")
                    Text("Connections")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
                .tag(2)
        }
        .tint(.green)
        .overlay {
            if connectionManager.isConnecting {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView("Connecting...")
                        .tint(.green)
                        .foregroundStyle(.white)
                    Button("Cancel") {
                        connectionManager.cancelConnect()
                    }
                    .foregroundStyle(.gray)
                }
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
                TmuxBrowserView(initialSessions: sessions, transport: activeTransport!) { tmuxSession, windowIndex in
                    activeSheet = nil
                    if let transport = activeTransport {
                        openShell(transport: transport, tmuxSession: tmuxSession, windowIndex: windowIndex)
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showTerminal) {
            if let transport = activeTransport {
                TerminalContainerView(transport: transport, tmuxCommand: activeTmuxCommand, sessionRecord: activeSessionRecord)
            }
        }
        .alert("Connection Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
        .alert("Delete Connection", isPresented: .init(
            get: { deleteConnectionTarget != nil },
            set: { if !$0 { deleteConnectionTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleteConnectionTarget = nil }
            Button("Delete", role: .destructive) {
                if let connection = deleteConnectionTarget {
                    deleteConnectionWithHistory(connection)
                }
            }
        } message: {
            if let connection = deleteConnectionTarget {
                let count = allSessions.filter { $0.connectionId == connection.id }.count
                if count > 0 {
                    Text("This will also delete \(count) session\(count == 1 ? "" : "s") from history.")
                } else {
                    Text("Delete \"\(connection.name)\"?")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - History Tab

    private var historyTab: some View {
        NavigationStack {
            ScrollView {
                if allSessions.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 40))
                            .foregroundStyle(.gray.opacity(0.5))
                        Text("No recent sessions")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(groupedSessions, id: \.connectionId) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.connectionName.uppercased())
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.gray)

                                if sizeClass == .regular {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                                        ForEach(group.sessions) { session in
                                            sessionCard(session)
                                        }
                                    }
                                } else {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 12) {
                                            ForEach(group.sessions) { session in
                                                sessionCard(session)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .background(Color.black)
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func sessionCard(_ session: SessionRecord) -> some View {
        ActiveSessionCard(session: session)
            .contentShape(Rectangle())
            .onTapGesture {
                resumeSession(session)
            }
            .contextMenu {
                if session.isActive {
                    Button("Deactivate") {
                        session.isActive = false
                        try? modelContext.save()
                        if session.connectionId == activeConnectionId,
                           let transport = activeTransport {
                            Task { await transport.disconnect() }
                            activeTransport = nil
                            activeConnectionId = nil
                        }
                    }
                }
                Button("Delete", role: .destructive) {
                    modelContext.delete(session)
                }
            }
    }

    // MARK: - Connections Tab

    private var connectionsTab: some View {
        NavigationStack {
            ScrollView {
                if connections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "server.rack")
                            .font(.system(size: 40))
                            .foregroundStyle(.gray.opacity(0.5))
                        Text("No saved connections")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                        Text("Tap + to add your first server")
                            .font(.caption)
                            .foregroundStyle(.gray.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
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
                                    deleteConnectionTarget = connection
                                }
                            }
                        }
                    }
                    .padding()
                    .iPadContentWidth(700)
                }
            }
            .background(Color.black)
            .navigationTitle("Connections")
            .navigationBarTitleDisplayMode(.inline)
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
        }
    }

    // MARK: - Grouped Sessions

    private struct SessionGroup {
        let connectionId: UUID
        let connectionName: String
        let sessions: [SessionRecord]
    }

    private var groupedSessions: [SessionGroup] {
        let grouped = Dictionary(grouping: allSessions) { $0.connectionId }
        return grouped.map { (connectionId, sessions) in
            let name = connections.first(where: { $0.id == connectionId })?.name ?? "Unknown"
            return SessionGroup(connectionId: connectionId, connectionName: name, sessions: sessions)
        }
        .sorted { $0.sessions.first!.lastActiveAt > $1.sessions.first!.lastActiveAt }
    }

    // MARK: - Connect

    @MainActor
    private func connectTo(_ connection: Connection) {
        connectionManager.connectingTask = Task { @MainActor in
            do {
                let transport = try await connectionManager.connect(connection)
                try Task.checkCancellation()
                self.activeTransport = transport
                self.activeConnectionId = connection.id

                // Try to list tmux sessions
                var sessions: [TmuxSession] = []
                do {
                    sessions = try await TmuxParser.listSessions(over: transport)
                } catch {}

                try Task.checkCancellation()

                // Small delay to ensure any previous sheet has fully dismissed
                try? await Task.sleep(for: .milliseconds(500))

                self.activeSheet = .tmuxBrowser(sessions)
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func openShell(transport: SSHSession, tmuxSession: TmuxSession?, windowIndex: Int? = nil) {
        Task { @MainActor in
            do {
                let tmuxCommand: String?
                if let session = tmuxSession {
                    if session.name == "new" {
                        tmuxCommand = "tmux new-session"
                    } else if let windowIndex {
                        tmuxCommand = "tmux attach -t \(session.name):\(windowIndex)"
                    } else {
                        tmuxCommand = "tmux attach -t \(session.name)"
                    }
                } else {
                    tmuxCommand = nil
                }
                self.activeTmuxCommand = tmuxCommand

                // Create or reuse a SessionRecord for this connection+tmux session
                let connectionId = self.activeConnectionId ?? UUID()
                let sessionName = tmuxSession?.name
                let record = findOrCreateSessionRecord(connectionId: connectionId, tmuxSessionName: sessionName)
                self.activeSessionRecord = record

                try await transport.openShell(tmuxCommand: tmuxCommand)
                showTerminal = true
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
    }

    private func findOrCreateSessionRecord(connectionId: UUID, tmuxSessionName: String?) -> SessionRecord {
        // Look for an existing active session with the same connection and tmux session
        if let existing = allSessions.first(where: {
            $0.connectionId == connectionId && $0.tmuxSessionName == tmuxSessionName
        }) {
            existing.lastActiveAt = Date()
            return existing
        }
        let record = SessionRecord(connectionId: connectionId, tmuxSessionName: tmuxSessionName)
        modelContext.insert(record)
        return record
    }

    // MARK: - Delete Connection

    private func deleteConnectionWithHistory(_ connection: Connection) {
        let relatedSessions = allSessions.filter { $0.connectionId == connection.id }
        for session in relatedSessions {
            modelContext.delete(session)
        }
        try? KeychainService.deletePassword(for: connection.id)
        try? KeychainService.deletePrivateKey(for: connection.id)
        try? KeychainService.deleteKeyPassphrase(for: connection.id)
        modelContext.delete(connection)
    }

    // MARK: - Resume Session

    private func resumeSession(_ session: SessionRecord) {
        // Find the saved connection that matches this session
        guard let connection = connections.first(where: { $0.id == session.connectionId }) else {
            errorMessage = "Connection no longer exists"
            showError = true
            return
        }

        connectionManager.connectingTask = Task { @MainActor in
            do {
                let transport = try await connectionManager.connect(connection)
                try Task.checkCancellation()
                self.activeTransport = transport
                self.activeConnectionId = connection.id

                // Build the tmux attach command
                let tmuxCommand: String?
                if let sessionName = session.tmuxSessionName {
                    tmuxCommand = "tmux attach -t \(sessionName)"
                } else {
                    tmuxCommand = nil
                }
                self.activeTmuxCommand = tmuxCommand
                self.activeSessionRecord = session

                try await transport.openShell(tmuxCommand: tmuxCommand)
                showTerminal = true
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    showError = true
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
