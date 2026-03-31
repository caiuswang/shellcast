import SwiftUI

/// Navigation wrapper that carries claudeOnly flag alongside the session
struct WindowNavigation: Hashable {
    let session: TmuxSession
    let claudeOnly: Bool
}

struct TmuxBrowserView: View {
    let initialSessions: [TmuxSession]
    let transport: SSHSession
    let onSelect: (TmuxSession?, Int?, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var navigationPath = NavigationPath()
    @State private var sessions: [TmuxSession] = []
    @State private var renameTarget: TmuxSession?
    @State private var renameText = ""
    @State private var deleteTarget: TmuxSession?
    @State private var operationError: String?
    @State private var showOperationError = false
    @State private var settings = TerminalSettings.shared

    // Claude Code state
    @State private var claudeInstalled = false
    @State private var claudeSessions: [ClaudeCodeSession] = []
    @State private var claudeRunningSessions: Set<String> = []
    @State private var loadingClaude = true
    @State private var claudePath = "claude"
    @State private var selectedTab = 0  // 0 = Tmux, 1 = Claude Tmux, 2 = Claude Code

    private var palette: AppThemePalette { settings.appPalette }

    /// Tmux sessions that are running Claude Code
    private var claudeTmuxSessions: [TmuxSession] {
        sessions.filter { claudeRunningSessions.contains($0.name) }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Tab picker
                if claudeInstalled {
                    Picker("", selection: $selectedTab) {
                        Text("Tmux").tag(0)
                        Text("Claude Tmux").tag(1)
                        Text("Sessions").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                }

                ScrollView {
                    switch selectedTab {
                    case 1:
                        claudeTmuxContent
                    case 2:
                        claudeContent
                    default:
                        tmuxContent
                    }
                }
            }
            .background(palette.screenBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(palette.secondaryText)
                            .font(.title3)
                    }
                }
            }
            .navigationDestination(for: WindowNavigation.self) { nav in
                TmuxWindowBrowserView(
                    session: nav.session,
                    transport: transport,
                    onSelect: onSelect,
                    claudeOnly: nav.claudeOnly
                )
            }
            .alert("Rename Session", isPresented: .init(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Session name", text: $renameText)
                Button("Cancel", role: .cancel) { renameTarget = nil }
                Button("Rename") {
                    if let target = renameTarget {
                        renameSession(target)
                    }
                }
            }
            .alert("Delete Session", isPresented: .init(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            )) {
                Button("Cancel", role: .cancel) { deleteTarget = nil }
                Button("Delete", role: .destructive) {
                    if let target = deleteTarget {
                        deleteSession(target)
                    }
                }
            } message: {
                if let target = deleteTarget {
                    Text("Delete session \"\(target.name)\"? This will kill all windows and processes in it.")
                }
            }
        }
        .alert("Error", isPresented: $showOperationError) {
            Button("OK") {}
        } message: {
            Text(operationError ?? "Unknown error")
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
        .onAppear {
            sessions = initialSessions
        }
        .task {
            debugLog("[CLAUDE-UI] .task started, initialSessions count: \(initialSessions.count)")
            do {
                let installed = try await ClaudeCodeParser.isInstalled(over: transport)
                debugLog("[CLAUDE-UI] isInstalled: \(installed)")
                claudeInstalled = installed
                if claudeInstalled {
                    claudePath = (try? await ClaudeCodeParser.resolveClaudePath(over: transport)) ?? "claude"
                    do {
                        claudeSessions = try await ClaudeCodeParser.listSessions(over: transport)
                        debugLog("[CLAUDE-UI] listSessions returned \(claudeSessions.count) sessions")
                    } catch {
                        debugLog("[CLAUDE-UI] listSessions failed: \(error)")
                    }
                    do {
                        claudeRunningSessions = try await ClaudeCodeParser.detectRunningSessions(over: transport, tmuxSessions: initialSessions)
                        debugLog("[CLAUDE-UI] detectRunningSessions returned: \(claudeRunningSessions)")
                    } catch {
                        debugLog("[CLAUDE-UI] detectRunningSessions failed: \(error)")
                    }
                }
            } catch {
                debugLog("[CLAUDE-UI] isInstalled threw: \(error)")
            }
            loadingClaude = false
        }
    }

    // MARK: - Tmux Tab Content

    @ViewBuilder
    private var tmuxContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !sessions.isEmpty {
                // Session list
                VStack(spacing: 0) {
                    ForEach(sessions) { session in
                        Button {
                            navigationPath.append(WindowNavigation(session: session, claudeOnly: false))
                        } label: {
                            TmuxSessionRow(session: session, aiToolRunning: claudeRunningSessions.contains(session.name) ? "Claude Code" : nil)
                        }
                        .contextMenu {
                            Button {
                                renameText = session.name
                                renameTarget = session
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                deleteTarget = session
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }

                        if session.id != sessions.last?.id {
                            Rectangle()
                                .fill(palette.border)
                                .frame(height: 0.5)
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(palette.surfaceBackground)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(palette.border, lineWidth: 0.5)
                )
            } else {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(palette.accent.opacity(0.08))
                            .frame(width: 72, height: 72)
                        Image(systemName: "terminal")
                            .font(.system(size: 28))
                            .foregroundStyle(palette.accent.opacity(0.4))
                    }
                    Text("No Tmux Sessions")
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                    Text("Start a new session or connect without tmux")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }

            // Action buttons
            VStack(spacing: 10) {
                Button {
                    onSelect(TmuxSession(name: "new", windowCount: 0, lastAttached: nil, attachedClients: 0), nil, nil)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(palette.accent)
                        Text("New tmux session")
                            .fontWeight(.medium)
                            .foregroundStyle(palette.primaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(palette.controlBackground)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(palette.accent.opacity(0.2), lineWidth: 0.5)
                    )
                }

                Button {
                    onSelect(nil, nil, nil)
                } label: {
                    Text("Connect without tmux")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(palette.elevatedSurfaceBackground)
                        .cornerRadius(12)
                }
            }
        }
        .padding(20)
        .iPadContentWidth(600)
    }

    // MARK: - Claude Tmux Tab Content (only sessions running Claude)

    @ViewBuilder
    private var claudeTmuxContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !claudeTmuxSessions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(claudeTmuxSessions) { session in
                        Button {
                            navigationPath.append(WindowNavigation(session: session, claudeOnly: true))
                        } label: {
                            TmuxSessionRow(session: session, aiToolRunning: "Claude Code")
                        }

                        if session.id != claudeTmuxSessions.last?.id {
                            Rectangle()
                                .fill(palette.border)
                                .frame(height: 0.5)
                                .padding(.leading, 52)
                        }
                    }
                }
                .background(palette.surfaceBackground)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(palette.border, lineWidth: 0.5)
                )
            } else {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.08))
                            .frame(width: 72, height: 72)
                        Image(systemName: "sparkles")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.purple.opacity(0.4))
                    }
                    Text("No Active Claude Sessions")
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                    Text("No tmux sessions are currently running Claude Code")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }

            // New Claude session in tmux
            Button {
                let cmd = ClaudeCodeParser.newCommand(projectPath: nil, claudePath: claudePath)
                let tmux = TmuxSession(name: "claude-\(Int(Date().timeIntervalSince1970))", windowCount: 0, lastAttached: nil, attachedClients: 0)
                onSelect(tmux, nil, cmd)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.purple)
                    Text("New Claude Code session")
                        .fontWeight(.medium)
                        .foregroundStyle(palette.primaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(palette.controlBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.purple.opacity(0.2), lineWidth: 0.5)
                )
            }
        }
        .padding(20)
        .iPadContentWidth(600)
    }

    // MARK: - Claude Code Sessions Tab Content

    @ViewBuilder
    private var claudeContent: some View {
        ClaudeCodeBrowserView(sessions: claudeSessions, claudePath: claudePath) { shellCommand in
            let tmux = TmuxSession(name: "claude-\(Int(Date().timeIntervalSince1970))", windowCount: 0, lastAttached: nil, attachedClients: 0)
            onSelect(tmux, nil, shellCommand)
        }
    }

    private func renameSession(_ session: TmuxSession) {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != session.name else { return }
        Task {
            do {
                try await TmuxParser.renameSession(over: transport, oldName: session.name, newName: newName)
            } catch {
                operationError = "Failed to rename session: \(error.localizedDescription)"
                showOperationError = true
            }
            sessions = (try? await TmuxParser.listSessions(over: transport)) ?? sessions
        }
    }

    private func deleteSession(_ session: TmuxSession) {
        Task {
            do {
                try await TmuxParser.killSession(over: transport, sessionName: session.name)
            } catch {
                operationError = "Failed to delete session: \(error.localizedDescription)"
                showOperationError = true
            }
            sessions = (try? await TmuxParser.listSessions(over: transport)) ?? sessions
        }
    }
}

// MARK: - Window Browser

struct TmuxWindowBrowserView: View {
    let session: TmuxSession
    let transport: SSHSession
    let onSelect: (TmuxSession?, Int?, String?) -> Void
    var claudeOnly: Bool = false

    @State private var windows: [TmuxWindow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var renameTarget: TmuxWindow?
    @State private var renameText = ""
    @State private var deleteTarget: TmuxWindow?
    @State private var operationError: String?
    @State private var showOperationError = false
    @State private var settings = TerminalSettings.shared
    @State private var claudeRunningWindows: Set<Int> = []

    private var displayedWindows: [TmuxWindow] {
        if claudeOnly {
            return windows.filter { claudeRunningWindows.contains($0.index) }
        }
        return windows
    }

    private var palette: AppThemePalette { settings.appPalette }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.callout)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(palette.accent.gradient)
                        .cornerRadius(10)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        Text("\(displayedWindows.count) window\(displayedWindows.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                }

                if isLoading {
                    ProgressView()
                        .tint(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else if let error = errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else if !displayedWindows.isEmpty {
                    // Window list
                    VStack(spacing: 0) {
                        ForEach(displayedWindows) { window in
                            Button {
                                onSelect(session, window.index, nil)
                            } label: {
                                TmuxWindowRow(window: window, aiToolRunning: claudeRunningWindows.contains(window.index) ? "Claude Code" : nil)
                            }
                            .contextMenu {
                                Button {
                                    renameText = window.name
                                    renameTarget = window
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    deleteTarget = window
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }

                            if window.id != displayedWindows.last?.id {
                                Rectangle()
                                    .fill(palette.border)
                                    .frame(height: 0.5)
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .background(palette.surfaceBackground)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(palette.border, lineWidth: 0.5)
                    )
                }

                // Attach to whole session
                Button {
                    onSelect(session, nil, nil)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.stack")
                            .foregroundStyle(.green)
                        Text("Attach to session")
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(Color(white: 0.12))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(palette.accent.opacity(0.2), lineWidth: 0.5)
                    )
                }
            }
            .padding(20)
            .iPadContentWidth(600)
        }
        .background(palette.screenBackground)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Error", isPresented: $showOperationError) {
            Button("OK") {}
        } message: {
            Text(operationError ?? "Unknown error")
        }
        .task {
            await loadWindows()
        }
        .alert("Rename Window", isPresented: .init(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Window name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Rename") {
                if let target = renameTarget {
                    renameWindow(target)
                }
            }
        }
        .alert("Delete Window", isPresented: .init(
            get: { deleteTarget != nil },
            set: { if !$0 { deleteTarget = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleteTarget = nil }
            Button("Delete", role: .destructive) {
                if let target = deleteTarget {
                    deleteWindow(target)
                }
            }
        } message: {
            if let target = deleteTarget {
                Text("Delete window \"\(target.index): \(target.name)\"? This will kill all processes in it.")
            }
        }
    }

    private func loadWindows() async {
        do {
            windows = try await TmuxParser.listWindows(over: transport, sessionName: session.name)
        } catch {
            errorMessage = "Failed to list windows: \(error.localizedDescription)"
        }
        isLoading = false
        // Detect which windows are running Claude Code
        claudeRunningWindows = (try? await ClaudeCodeParser.detectRunningWindows(over: transport, tmuxSessionName: session.name)) ?? []
    }

    private func renameWindow(_ window: TmuxWindow) {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty, newName != window.name else { return }
        Task {
            do {
                try await TmuxParser.renameWindow(over: transport, sessionName: session.name, windowIndex: window.index, newName: newName)
            } catch {
                operationError = "Failed to rename window: \(error.localizedDescription)"
                showOperationError = true
            }
            windows = (try? await TmuxParser.listWindows(over: transport, sessionName: session.name)) ?? windows
        }
    }

    private func deleteWindow(_ window: TmuxWindow) {
        Task {
            do {
                try await TmuxParser.killWindow(over: transport, sessionName: session.name, windowIndex: window.index)
            } catch {
                operationError = "Failed to delete window: \(error.localizedDescription)"
                showOperationError = true
            }
            windows = (try? await TmuxParser.listWindows(over: transport, sessionName: session.name)) ?? windows
        }
    }
}

// MARK: - Row Views

struct TmuxSessionRow: View {
    let session: TmuxSession
    var aiToolRunning: String? = nil
    @State private var settings = TerminalSettings.shared

    private var palette: AppThemePalette { settings.appPalette }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: aiToolRunning != nil ? "sparkles" : "terminal")
                .font(.caption)
                .foregroundStyle(aiToolRunning != nil ? Color.purple.opacity(0.8) : palette.accent.opacity(0.8))
                .frame(width: 28, height: 28)
                .background(aiToolRunning != nil ? Color.purple.opacity(0.12) : palette.accent.opacity(0.12))
                .cornerRadius(7)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(session.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)

                    if let toolName = aiToolRunning {
                        Text(toolName)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .cornerRadius(4)
                    }

                    if session.attachedClients > 0 {
                        Text("Connected")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(palette.accent.opacity(0.15))
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 8) {
                    Text("\(session.windowCount) windows")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)

                    if let lastAttached = session.lastAttached {
                        Text(lastAttached.relativeDescription)
                            .font(.caption)
                            .foregroundStyle(palette.tertiaryText)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2)
                .foregroundStyle(palette.tertiaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

struct TmuxWindowRow: View {
    let window: TmuxWindow
    var aiToolRunning: String? = nil
    @State private var settings = TerminalSettings.shared

    private var palette: AppThemePalette { settings.appPalette }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: aiToolRunning != nil ? "sparkles" : "macwindow")
                .font(.caption)
                .foregroundStyle(aiToolRunning != nil ? Color.purple.opacity(0.8) : palette.accent.opacity(0.8))
                .frame(width: 28, height: 28)
                .background(aiToolRunning != nil ? Color.purple.opacity(0.12) : palette.accent.opacity(0.12))
                .cornerRadius(7)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("\(window.index): \(window.name)")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)

                    if let toolName = aiToolRunning {
                        Text(toolName)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.15))
                            .cornerRadius(4)
                    }

                    if window.isActive {
                        Text("Active")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(palette.accent.opacity(0.15))
                            .cornerRadius(4)
                    }
                }

                Text("\(window.paneCount) pane\(window.paneCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
