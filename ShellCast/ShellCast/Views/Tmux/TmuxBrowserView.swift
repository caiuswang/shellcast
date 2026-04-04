import SwiftUI

/// Navigation wrapper that carries agent filter alongside the session
struct WindowNavigation: Hashable {
    let session: TmuxSession
    let agentFilter: String?  // nil = no filter, "claude" = only Claude, "opencode" = only OpenCode, etc.
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

    // AI Agent state
    @State private var installedAgents: [AIAgentPlugin.Type] = []
    @State private var agentSessions: [AIAgentSession] = []
    @State private var runningSessionsByAgent: [String: Set<String>] = [:]
    @State private var loadingAgents = true
    @State private var agentBinaryPaths: [String: String] = [:]  // agentID -> path
    @State private var selectedTab = 0  // 0 = Tmux, 1+ = AI Agent tabs

    private var palette: AppThemePalette { settings.appPalette }

    /// All tmux sessions running any AI agent
    private var allAITmuxSessions: [TmuxSession] {
        let allRunning = runningSessionsByAgent.values.flatMap { $0 }
        return sessions.filter { allRunning.contains($0.name) }
    }
    
    /// Get tmux sessions running a specific agent
    private func tmuxSessionsRunning(agentID: String) -> [TmuxSession] {
        guard let running = runningSessionsByAgent[agentID] else { return [] }
        return sessions.filter { running.contains($0.name) }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack(spacing: 0) {
                // Tab picker
                if !installedAgents.isEmpty {
                    agentTabPicker
                }

                ScrollView {
                    tabContent
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
                    agentFilter: nav.agentFilter
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
            await loadAIAgents()
        }
    }

    // MARK: - Tab Picker
    
    private var agentTabPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // All Tmux tab
                TabButton(title: "Tmux", icon: "terminal", isSelected: selectedTab == 0) {
                    withAnimation(.spring(duration: 0.2)) {
                        selectedTab = 0
                    }
                }
                
                // AI Agent tabs - use indexed access to avoid complex ForEach
                agentTabButtons
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
        }
    }
    
    private var agentTabButtons: some View {
        ForEach(0..<installedAgents.count, id: \.self) { index in
            let plugin = installedAgents[index]
            let tabIndex = index + 1
            TabButton(
                title: plugin.displayName,
                icon: plugin.iconName,
                isSelected: selectedTab == tabIndex,
                color: colorFromName(plugin.themeColor)
            ) {
                withAnimation(.spring(duration: 0.2)) {
                    selectedTab = tabIndex
                }
            }
        }
    }
    
    @ViewBuilder
    private var tabContent: some View {
        if selectedTab == 0 {
            tmuxContent
        } else if selectedTab <= installedAgents.count {
            aiTmuxContent(for: installedAgents[selectedTab - 1])
        }
    }
    
    // MARK: - AI Agent Loading
    
    private func loadAIAgents() async {
        debugLog("[AI-AGENTS] Loading AI agents for \(initialSessions.count) tmux sessions")

        // Step 1: Detect installed agents (must complete first)
        installedAgents = await AIAgentRegistry.detectInstalledAgents(over: transport)
        debugLog("[AI-AGENTS] Installed agents: \(installedAgents.map { $0.agentID })")

        guard !installedAgents.isEmpty else {
            loadingAgents = false
            return
        }

        // Step 2: Run binary paths, session listing, and running detection in parallel
        // These are all independent of each other.
        await withTaskGroup(of: Void.self) { group in
            // Binary paths
            group.addTask { @MainActor in
                var paths: [String: String] = [:]
                await withTaskGroup(of: (String, String).self) { inner in
                    for plugin in installedAgents {
                        inner.addTask {
                            let path = (try? await plugin.resolveBinaryPath(over: transport)) ?? plugin.binaryNames.first ?? plugin.agentID
                            return (plugin.agentID, path)
                        }
                    }
                    for await (agentID, path) in inner {
                        paths[agentID] = path
                    }
                }
                agentBinaryPaths = paths
            }

            // List resumable sessions (pass installed agents to skip redundant isInstalled checks)
            group.addTask { @MainActor in
                let sessions = await AIAgentRegistry.listAllSessions(over: transport, installedAgents: installedAgents)
                debugLog("[AI-AGENTS] Total sessions from all agents: \(sessions.count)")
                agentSessions = sessions
            }

            // Detect running sessions
            group.addTask { @MainActor in
                let running = await AIAgentRegistry.detectAllRunningSessions(
                    over: transport,
                    tmuxSessions: initialSessions
                )
                debugLog("[AI-AGENTS] Running sessions by agent: \(running)")
                runningSessionsByAgent = running
            }
        }

        loadingAgents = false
    }
    
    private func colorFromName(_ name: String) -> Color {
        switch name.lowercased() {
        case "purple": return .purple
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "red": return .red
        case "pink": return .pink
        case "cyan", "teal": return .cyan
        case "indigo": return .indigo
        case "mint": return .mint
        case "yellow": return .yellow
        default: return .purple
        }
    }
    
    // MARK: - AI Agents Status
    
    private var aiAgentsStatusHeader: some View {
        aiAgentStatusCards
            .padding(.horizontal, 4)
    }
    
    private var aiAgentStatusCards: some View {
        HStack(spacing: 12) {
            ForEach(0..<installedAgents.count, id: \.self) { index in
                let plugin = installedAgents[index]
                let tabIndex = index + 1
                let runningCount = runningSessionsByAgent[plugin.agentID]?.count ?? 0
                let agentColor = colorFromName(plugin.themeColor)
                let isSelected = selectedTab == tabIndex
                
                Button {
                    withAnimation(.spring(duration: 0.2)) {
                        selectedTab = tabIndex
                    }
                } label: {
                    HStack(spacing: 6) {
                        if AIAgentRegistry.isCustomIcon(plugin.iconName) {
                            Image(plugin.iconName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 12, height: 12)
                                .foregroundStyle(isSelected ? .white : agentColor)
                        } else {
                            Image(systemName: plugin.iconName)
                                .font(.caption)
                                .foregroundStyle(isSelected ? .white : agentColor)
                        }
                        
                        VStack(alignment: .leading, spacing: 1) {
                            Text(plugin.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(isSelected ? .white : palette.primaryText)
                            
                            Text(runningCount > 0 ? "\(runningCount) running" : "idle")
                                .font(.caption2)
                                .foregroundStyle(isSelected ? .white.opacity(0.8) : (runningCount > 0 ? agentColor : palette.tertiaryText))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(isSelected ? agentColor : palette.surfaceBackground)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(isSelected ? agentColor : (runningCount > 0 ? agentColor.opacity(0.3) : palette.border), lineWidth: runningCount > 0 || isSelected ? 1 : 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    // MARK: - Tmux Tab Content

    @ViewBuilder
    private var tmuxContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            // AI Agents Status Header
            if !installedAgents.isEmpty {
                aiAgentsStatusHeader
            }
            
            if !sessions.isEmpty {
                // Session list
                VStack(spacing: 0) {
                    ForEach(sessions) { session in
                        Button {
                            navigationPath.append(WindowNavigation(session: session, agentFilter: nil))
                        } label: {
                            let runningAgentID = firstRunningAgentID(in: session.name)
                            TmuxSessionRow(session: session, aiAgentID: runningAgentID)
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
    
    /// Get the first running agent ID for a tmux session
    private func firstRunningAgentID(in sessionName: String) -> String? {
        for (agentID, sessions) in runningSessionsByAgent {
            if sessions.contains(sessionName) {
                return agentID
            }
        }
        return nil
    }

    // MARK: - AI Agent Tmux Tab Content

    @ViewBuilder
    private func aiTmuxContent(for agent: AIAgentPlugin.Type) -> some View {
        let runningTmuxSessions = tmuxSessionsRunning(agentID: agent.agentID)
        let agentColor = colorFromName(agent.themeColor)
        let binaryPath = agentBinaryPaths[agent.agentID] ?? agent.binaryNames.first ?? agent.agentID
        let resumableSessions = agentSessions.filter { $0.agentID == agent.agentID }

        VStack(alignment: .leading, spacing: 20) {
            // Loading indicator
            if loadingAgents {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(agentColor)
                    Text("Detecting \(agent.displayName) sessions...")
                        .font(.subheadline)
                        .foregroundStyle(palette.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            }

            // AI Tmux Sessions
            if !runningTmuxSessions.isEmpty {
                VStack(spacing: 0) {
                    ForEach(runningTmuxSessions) { session in
                        Button {
                            navigationPath.append(WindowNavigation(session: session, agentFilter: agent.agentID))
                        } label: {
                            TmuxSessionRow(session: session, aiAgentID: agent.agentID)
                        }

                        if session.id != runningTmuxSessions.last?.id {
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
            } else if !loadingAgents {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(agentColor.opacity(0.08))
                            .frame(width: 72, height: 72)
                        if AIAgentRegistry.isCustomIcon(agent.iconName) {
                            Image(agent.iconName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 28, height: 28)
                                .foregroundStyle(agentColor.opacity(0.4))
                        } else {
                            Image(systemName: agent.iconName)
                                .font(.system(size: 28))
                                .foregroundStyle(agentColor.opacity(0.4))
                        }
                    }
                    Text("No Active \(agent.displayName) Sessions")
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                    Text("No tmux sessions are currently running \(agent.displayName)")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            }

            // Resumable sessions from this agent
            if !resumableSessions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Resume Session")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(palette.secondaryText)
                        .padding(.horizontal, 4)
                    
                    VStack(spacing: 0) {
                        ForEach(resumableSessions) { session in
                            Button {
                                let cmd = agent.resumeCommand(sessionId: session.sessionId, binaryPath: binaryPath)
                                let tmux = TmuxSession(name: "\(agent.agentID)-\(Int(Date().timeIntervalSince1970))", windowCount: 0, lastAttached: nil, attachedClients: 0)
                                onSelect(tmux, nil, cmd)
                            } label: {
                                AIAgentSessionRow(session: session, agentColor: agentColor)
                            }
                            
                            if session.id != resumableSessions.last?.id {
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
            }

            // New session button
            Button {
                let cmd = agent.newCommand(projectPath: nil, binaryPath: binaryPath)
                let tmux = TmuxSession(name: "\(agent.agentID)-\(Int(Date().timeIntervalSince1970))", windowCount: 0, lastAttached: nil, attachedClients: 0)
                onSelect(tmux, nil, cmd)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(agentColor)
                    Text("New \(agent.displayName) session")
                        .fontWeight(.medium)
                        .foregroundStyle(palette.primaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(14)
                .background(palette.controlBackground)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(agentColor.opacity(0.2), lineWidth: 0.5)
                )
            }
        }
        .padding(20)
        .iPadContentWidth(600)
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
    var agentFilter: String? = nil  // nil = no filter, "claude" = only windows running Claude, etc.

    @State private var windows: [TmuxWindow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var renameTarget: TmuxWindow?
    @State private var renameText = ""
    @State private var deleteTarget: TmuxWindow?
    @State private var operationError: String?
    @State private var showOperationError = false
    @State private var settings = TerminalSettings.shared
    @State private var runningWindowsByAgent: [String: Set<Int>] = [:]

    private var displayedWindows: [TmuxWindow] {
        if let agentFilter = agentFilter {
            // When filtering by agent, only show windows after detection completes
            guard let runningWindows = runningWindowsByAgent[agentFilter] else {
                // Detection not yet complete, return empty
                return []
            }
            return windows.filter { runningWindows.contains($0.index) }
        }
        // No filter, show all windows
        return windows
    }
    
    // Track if we're still detecting agent windows
    private var isDetectingAgentWindows: Bool {
        agentFilter != nil && runningWindowsByAgent[agentFilter!] == nil
    }

    private var palette: AppThemePalette { settings.appPalette }
    
    private var filterAgentInfo: AgentDisplayInfo? { AgentDisplayInfo(agentID: agentFilter) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(spacing: 12) {
                    // Show agent icon if filtered, otherwise session icon
                    Group {
                        if let icon = filterAgentInfo?.icon, AIAgentRegistry.isCustomIcon(icon) {
                            Image(icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 20, height: 20)
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background((filterAgentInfo?.color ?? palette.accent).gradient)
                                .cornerRadius(10)
                        } else {
                            Image(systemName: filterAgentInfo?.icon ?? "rectangle.split.3x1")
                                .font(.callout)
                                .fontWeight(.medium)
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background((filterAgentInfo?.color ?? palette.accent).gradient)
                                .cornerRadius(10)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.name)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        
                        HStack(spacing: 6) {
                            Text("\(displayedWindows.count) window\(displayedWindows.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                            
                            // Show filter badge if agent filter is active
                            if let agent = filterAgentInfo {
                                HStack(spacing: 4) {
                                    if AIAgentRegistry.isCustomIcon(agent.icon) {
                                        Image(agent.icon)
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 8, height: 8)
                                    } else {
                                        Image(systemName: agent.icon)
                                            .font(.system(size: 8))
                                    }
                                    Text(agent.name)
                                }
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(agent.color)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(agent.color.opacity(0.15))
                                .cornerRadius(4)
                            }
                        }
                    }
                }

                if isLoading || isDetectingAgentWindows {
                    ProgressView()
                        .tint(filterAgentInfo?.color ?? .green)
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
                                let agentID = runningWindowsByAgent.first { $0.value.contains(window.index) }?.key
                                TmuxWindowRow(window: window, aiAgentID: agentID)
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
                } else if agentFilter != nil {
                    // Empty state when filtering by agent but no windows match
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill((filterAgentInfo?.color ?? palette.accent).opacity(0.08))
                                .frame(width: 72, height: 72)
                            if let icon = filterAgentInfo?.icon, AIAgentRegistry.isCustomIcon(icon) {
                                Image(icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 28, height: 28)
                                    .foregroundStyle((filterAgentInfo?.color ?? palette.accent).opacity(0.4))
                            } else {
                                Image(systemName: filterAgentInfo?.icon ?? "sparkles")
                                    .font(.system(size: 28))
                                    .foregroundStyle((filterAgentInfo?.color ?? palette.accent).opacity(0.4))
                            }
                        }
                        Text("No \(filterAgentInfo?.name ?? "AI Agent") Windows")
                            .font(.headline)
                            .foregroundStyle(palette.primaryText)
                        Text("No windows in this session are running \(filterAgentInfo?.name ?? "the AI agent")")
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
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
        
        // Detect which windows are running each AI agent
        var allRunningWindows: [String: Set<Int>] = [:]
        for plugin in AIAgentRegistry.allPlugins {
            if let windows = try? await plugin.detectRunningWindows(over: transport, tmuxSessionName: session.name) {
                if !windows.isEmpty {
                    allRunningWindows[plugin.agentID] = windows
                }
            }
        }
        runningWindowsByAgent = allRunningWindows
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

// MARK: - Agent Info Helper

/// Helper to get agent display info from agent ID
struct AgentDisplayInfo {
    let name: String
    let icon: String
    let color: Color
    
    init?(agentID: String?) {
        guard let agentID = agentID, !agentID.isEmpty else { return nil }
        self.name = AIAgentRegistry.displayName(for: agentID)
        self.icon = AIAgentRegistry.iconName(for: agentID)
        self.color = AIAgentRegistry.themeColor(for: agentID)
    }
}

// MARK: - Row Views

struct TmuxSessionRow: View {
    let session: TmuxSession
    var aiAgentID: String? = nil  // e.g., "claude", "opencode"
    @State private var settings = TerminalSettings.shared

    private var palette: AppThemePalette { settings.appPalette }
    private var agentInfo: AgentDisplayInfo? { AgentDisplayInfo(agentID: aiAgentID) }

    var body: some View {
        HStack(spacing: 12) {
            // Icon shows agent-specific icon if running, otherwise terminal icon
            if let icon = agentInfo?.icon, AIAgentRegistry.isCustomIcon(icon) {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(agentInfo?.color.opacity(0.8) ?? palette.accent.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background((agentInfo?.color ?? palette.accent).opacity(0.12))
                    .cornerRadius(7)
            } else {
                Image(systemName: agentInfo?.icon ?? "terminal")
                    .font(.caption)
                    .foregroundStyle(agentInfo?.color.opacity(0.8) ?? palette.accent.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background((agentInfo?.color ?? palette.accent).opacity(0.12))
                    .cornerRadius(7)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(session.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)

                    // AI Agent badge with agent-specific color
                    if let agent = agentInfo {
                        HStack(spacing: 4) {
                            if AIAgentRegistry.isCustomIcon(agent.icon) {
                                Image(agent.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 8, height: 8)
                            } else {
                                Image(systemName: agent.icon)
                                    .font(.system(size: 8))
                            }
                            Text(agent.name)
                        }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(agent.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(agent.color.opacity(0.15))
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

// MARK: - Supporting Views

struct TabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var color: Color = .accentColor
    let action: () -> Void
    
    @State private var settings = TerminalSettings.shared
    
    private var palette: AppThemePalette { settings.appPalette }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if AIAgentRegistry.isCustomIcon(icon) {
                    Image(icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 12, height: 12)
                } else {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .medium)
            }
            .frame(minWidth: 80)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(isSelected ? color : palette.controlBackground)
            .foregroundStyle(isSelected ? .white : palette.primaryText)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

struct TmuxWindowRow: View {
    let window: TmuxWindow
    var aiAgentID: String? = nil  // e.g., "claude", "opencode"
    @State private var settings = TerminalSettings.shared

    private var palette: AppThemePalette { settings.appPalette }
    private var agentInfo: AgentDisplayInfo? { AgentDisplayInfo(agentID: aiAgentID) }

    var body: some View {
        HStack(spacing: 12) {
            // Icon shows agent-specific icon if running, otherwise window icon
            if let icon = agentInfo?.icon, AIAgentRegistry.isCustomIcon(icon) {
                Image(icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 14, height: 14)
                    .foregroundStyle(agentInfo?.color.opacity(0.8) ?? palette.accent.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background((agentInfo?.color ?? palette.accent).opacity(0.12))
                    .cornerRadius(7)
            } else {
                Image(systemName: agentInfo?.icon ?? "macwindow")
                    .font(.caption)
                    .foregroundStyle(agentInfo?.color.opacity(0.8) ?? palette.accent.opacity(0.8))
                    .frame(width: 28, height: 28)
                    .background((agentInfo?.color ?? palette.accent).opacity(0.12))
                    .cornerRadius(7)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("\(window.index): \(window.name)")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)

                    // AI Agent badge with agent-specific color
                    if let agent = agentInfo {
                        HStack(spacing: 4) {
                            if AIAgentRegistry.isCustomIcon(agent.icon) {
                                Image(agent.icon)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 8, height: 8)
                            } else {
                                Image(systemName: agent.icon)
                                    .font(.system(size: 8))
                            }
                            Text(agent.name)
                        }
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(agent.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(agent.color.opacity(0.15))
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

