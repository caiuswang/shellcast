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
    @State private var activeConnectionType: ConnectionType = .ssh
    @State private var showTerminal = false
    @State private var activeTmuxCommand: String?
    @State private var activeSessionRecord: SessionRecord?
    @State private var tmuxSessions: [TmuxSession] = []
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var deleteConnectionTarget: Connection?
    @State private var showMoshFallbackNotice = false

    var body: some View {
        TabView(selection: $selectedTab) {
            historyTab
                .tabItem {
                    Image(systemName: "clock.fill")
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
                    Image(systemName: "gearshape.fill")
                    Text("Settings")
                }
                .tag(2)
        }
        .tint(.green)
        .overlay {
            if connectionManager.isConnecting {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .stroke(Color.green.opacity(0.15), lineWidth: 3)
                            .frame(width: 60, height: 60)
                        ProgressView()
                            .controlSize(.large)
                            .tint(.green)
                    }

                    Text("Connecting...")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)

                    Button {
                        connectionManager.cancelConnect()
                    } label: {
                        Text("Cancel")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color(white: 0.15))
                            .cornerRadius(20)
                    }
                }
                .padding(32)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(white: 0.08).opacity(0.95))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        )
                )
            }
        }
        .sheet(item: $activeSheet) { sheet in
            Group {
                switch sheet {
                case .addConnection:
                    EditConnectionView(mode: .add) { connection in
                        connectTo(connection)
                    }
                case .editConnection(let connection):
                    EditConnectionView(mode: .edit(connection))
                case .tmuxBrowser(let sessions):
                    if let transport = activeTransport {
                        TmuxBrowserView(initialSessions: sessions, transport: transport) { tmuxSession, windowIndex in
                            activeSheet = nil
                            openShell(transport: transport, tmuxSession: tmuxSession, windowIndex: windowIndex)
                        }
                    }
                }
            }
            .environment(connectionManager)
        }
        .fullScreenCover(isPresented: $showTerminal) {
            if let transport = connectionManager.activeTerminalTransport {
                let _ = debugLog("[COVER] Rendering TerminalContainerView, transport=\(type(of: transport)), needsDeferredStart=\(transport.needsDeferredStart)")
                TerminalContainerView(transport: transport, tmuxCommand: activeTmuxCommand, sessionRecord: activeSessionRecord)
                    .environment(connectionManager)
            } else {
                let _ = debugLog("[COVER] ERROR: connectionManager.activeTerminalTransport is nil!")
                Color.black
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
        .alert("Mosh Unavailable", isPresented: $showMoshFallbackNotice) {
            Button("OK") {}
        } message: {
            Text("mosh-server is not available on this host. Falling back to SSH.")
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - History Tab

    private var historyTab: some View {
        NavigationStack {
            ScrollView {
                if allSessions.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.gray.opacity(0.25))
                        Text("No Recent Sessions")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.gray.opacity(0.6))
                        Text("Your terminal sessions will appear here")
                            .font(.caption)
                            .foregroundStyle(.gray.opacity(0.35))
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
            .background(Color(white: 0.04))
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
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(.green.opacity(0.08))
                                .frame(width: 80, height: 80)
                            Image(systemName: "server.rack")
                                .font(.system(size: 32))
                                .foregroundStyle(.green.opacity(0.4))
                        }
                        Text("No Connections Yet")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(.gray.opacity(0.6))
                        Text("Tap + to add your first server")
                            .font(.caption)
                            .foregroundStyle(.gray.opacity(0.35))
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
            .background(Color(white: 0.04))
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
                        .background(Color.green.gradient)
                        .clipShape(Circle())
                        .shadow(color: .green.opacity(0.3), radius: 12, y: 6)
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
        .sorted { ($0.sessions.first?.lastActiveAt ?? .distantPast) > ($1.sessions.first?.lastActiveAt ?? .distantPast) }
    }

    // MARK: - Connect

    @MainActor
    private func connectTo(_ connection: Connection) {
        connectionManager.connectingTask = Task { @MainActor in
            do {
                // Always SSH first (for tmux browsing and exec)
                let transport = try await connectionManager.connect(connection)
                try Task.checkCancellation()
                self.activeTransport = transport
                self.activeConnectionId = connection.id
                self.activeConnectionType = connection.connectionType

                // Try to list tmux sessions (non-fatal — tmux may not be installed)
                var sessions: [TmuxSession] = []
                do {
                    sessions = try await TmuxParser.listSessions(over: transport)
                } catch {
                    debugLog("[TMUX] list-sessions failed (tmux may not be installed): \(error)")
                }

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

                // Choose transport based on connection type
                let useMosh = activeConnectionType == .mosh || activeConnectionType == .auto
                if useMosh {
                    do {
                        debugLog("[MOSH] Starting bootstrap, host=\(transport.host)")
                        let moshTransport = try await MoshService.bootstrap(
                            sshSession: transport,
                            host: transport.host,
                            shellCommand: tmuxCommand
                        )
                        debugLog("[MOSH] Bootstrap complete, waiting for sheet dismiss")
                        self.connectionManager.activeTerminalTransport = moshTransport
                        self.activeTmuxCommand = nil
                        // Wait for tmux browser sheet dismissal to complete
                        try? await Task.sleep(for: .milliseconds(600))
                        debugLog("[MOSH] Showing terminal now")
                        showTerminal = true
                        return
                    } catch {
                        debugLog("[MOSH] Bootstrap failed: \(error)")
                        if activeConnectionType == .mosh {
                            throw error
                        }
                        // Auto mode: fall back to SSH with notice
                        showMoshFallbackNotice = true
                    }
                }

                // SSH path
                debugLog("[SSH] Opening shell")
                self.connectionManager.activeTerminalTransport = transport
                try await transport.openShell(tmuxCommand: tmuxCommand)
                showTerminal = true
            } catch {
                debugLog("[CONNECT] Error: \(error)")
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
                self.activeConnectionType = connection.connectionType

                // Build the tmux attach command
                let tmuxCommand: String?
                if let sessionName = session.tmuxSessionName {
                    tmuxCommand = "tmux attach -t \(sessionName)"
                } else {
                    tmuxCommand = nil
                }
                self.activeTmuxCommand = tmuxCommand
                self.activeSessionRecord = session

                // Choose transport based on connection type
                let useMosh = connection.connectionType == .mosh || connection.connectionType == .auto
                if useMosh {
                    do {
                        let moshTransport = try await MoshService.bootstrap(
                            sshSession: transport,
                            host: transport.host,
                            shellCommand: tmuxCommand
                        )
                        self.connectionManager.activeTerminalTransport = moshTransport
                        self.activeTmuxCommand = nil
                        showTerminal = true
                        return
                    } catch {
                        if connection.connectionType == .mosh { throw error }
                        showMoshFallbackNotice = true
                    }
                }

                // SSH fallback
                self.connectionManager.activeTerminalTransport = transport
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
