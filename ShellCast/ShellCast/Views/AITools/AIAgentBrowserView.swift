import SwiftUI

// MARK: - AI Agent Browser View

/// Generic browser for AI agent sessions - works with any registered plugin
struct AIAgentBrowserView: View {
    let agentID: String
    let sessions: [AIAgentSession]
    let binaryPath: String
    let onSelect: (String?) -> Void  // nil = new session
    
    @State private var settings = TerminalSettings.shared
    
    private var palette: AppThemePalette { settings.appPalette }
    private var agentColor: Color { AIAgentRegistry.themeColor(for: agentID) }
    private var displayName: String { AIAgentRegistry.displayName(for: agentID) }
    private var iconName: String { AIAgentRegistry.iconName(for: agentID) }
    
    /// Group sessions by project path
    private var groupedSessions: [(project: String, sessions: [AIAgentSession])] {
        let grouped = Dictionary(grouping: sessions) { $0.projectPath }
        return grouped.map { (project: $0.key, sessions: $0.value) }
            .sorted { $0.sessions.count > $1.sessions.count }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if !sessions.isEmpty {
                    ForEach(groupedSessions, id: \.project) { group in
                        VStack(alignment: .leading, spacing: 0) {
                            // Project header
                            HStack(spacing: 8) {
                                Image(systemName: "folder")
                                    .font(.caption)
                                    .foregroundStyle(agentColor)
                                
                                Text(group.project)
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(palette.primaryText)
                                
                                Spacer()
                                
                                Text("\(group.sessions.count) session\(group.sessions.count == 1 ? "" : "s")")
                                    .font(.caption2)
                                    .foregroundStyle(palette.secondaryText)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(palette.surfaceBackground.opacity(0.5))
                            
                            // Session rows
                            VStack(spacing: 0) {
                                ForEach(group.sessions) { session in
                                    Button {
                                        let plugin = AIAgentRegistry.plugin(for: agentID)
                                        let cmd = plugin?.resumeCommand(sessionId: session.sessionId, binaryPath: binaryPath) ?? ""
                                        onSelect(cmd)
                                    } label: {
                                        AIAgentSessionRow(session: session, agentColor: agentColor)
                                    }
                                    
                                    if session.id != group.sessions.last?.id {
                                        Rectangle()
                                            .fill(palette.border)
                                            .frame(height: 0.5)
                                            .padding(.leading, 52)
                                    }
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
                } else {
                    emptyState
                }
                
                // New session button
                Button {
                    onSelect(nil)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(agentColor)
                        Text("New \(displayName) session")
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
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(agentColor.opacity(0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: iconName)
                    .font(.system(size: 28))
                    .foregroundStyle(agentColor.opacity(0.4))
            }
            
            Text("No \(displayName) Sessions")
                .font(.headline)
                .foregroundStyle(palette.primaryText)
            
            Text("Start a new session to begin coding with AI")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - AI Agent Session Row

struct AIAgentSessionRow: View {
    let session: AIAgentSession
    var agentColor: Color = .purple
    
    @State private var settings = TerminalSettings.shared
    
    private var palette: AppThemePalette { settings.appPalette }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bubble.left.fill")
                .font(.caption)
                .foregroundStyle(agentColor.opacity(0.8))
                .frame(width: 28, height: 28)
                .background(agentColor.opacity(0.12))
                .cornerRadius(7)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(session.sessionId.prefix(8))
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(palette.primaryText)
                
                if let summary = session.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                
                if let lastModified = session.lastModified {
                    Text(lastModified.relativeDescription)
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryText)
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

// MARK: - Multi-Agent Browser View

/// Browser that shows sessions from all installed AI agents
struct MultiAgentBrowserView: View {
    let sessions: [AIAgentSession]
    let onSelect: (String, String?) -> Void  // (agentID, command or nil for new)
    
    @State private var settings = TerminalSettings.shared
    @State private var selectedAgent: String? = nil
    
    private var palette: AppThemePalette { settings.appPalette }
    
    /// Sessions grouped by agent
    private var sessionsByAgent: [String: [AIAgentSession]] {
        Dictionary(grouping: sessions) { $0.agentID }
    }
    
    /// Available agent IDs with sessions
    private var availableAgents: [String] {
        Array(sessionsByAgent.keys).sorted()
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if sessions.isEmpty {
                    emptyState
                } else {
                    // Agent filter chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableAgents, id: \.self) { agentID in
                                AgentChip(
                                    agentID: agentID,
                                    isSelected: selectedAgent == agentID,
                                    count: sessionsByAgent[agentID]?.count ?? 0
                                ) {
                                    withAnimation(.spring(duration: 0.2)) {
                                        if selectedAgent == agentID {
                                            selectedAgent = nil
                                        } else {
                                            selectedAgent = agentID
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    
                    // Sessions list
                    let filteredSessions = selectedAgent != nil
                        ? sessionsByAgent[selectedAgent!] ?? []
                        : sessions
                    
                    ForEach(filteredSessions) { session in
                        Button {
                            let plugin = AIAgentRegistry.plugin(for: session.agentID)
                            let binaryPath = plugin?.binaryNames.first ?? session.agentID
                            let cmd = plugin?.resumeCommand(sessionId: session.sessionId, binaryPath: binaryPath)
                            onSelect(session.agentID, cmd)
                        } label: {
                            MultiAgentSessionRow(session: session)
                        }
                        .background(palette.surfaceBackground)
                        .cornerRadius(12)
                    }
                }
            }
            .padding(.vertical, 20)
            .iPadContentWidth(600)
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.08))
                    .frame(width: 72, height: 72)
                Image(systemName: "sparkles")
                    .font(.system(size: 28))
                    .foregroundStyle(palette.accent.opacity(0.4))
            }
            
            Text("No AI Sessions Found")
                .font(.headline)
                .foregroundStyle(palette.primaryText)
            
            Text("No supported AI agents detected on this server")
                .font(.caption)
                .foregroundStyle(palette.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Supporting Views

struct AgentChip: View {
    let agentID: String
    let isSelected: Bool
    let count: Int
    let action: () -> Void
    
    @State private var settings = TerminalSettings.shared
    
    private var palette: AppThemePalette { settings.appPalette }
    private var agentColor: Color { AIAgentRegistry.themeColor(for: agentID) }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: AIAgentRegistry.iconName(for: agentID))
                    .font(.caption)
                Text(AIAgentRegistry.displayName(for: agentID))
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .medium)
                Text("\(count)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(isSelected ? .white : agentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.2) : agentColor.opacity(0.15))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? agentColor : palette.controlBackground)
            .foregroundStyle(isSelected ? .white : palette.primaryText)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
    }
}

struct MultiAgentSessionRow: View {
    let session: AIAgentSession
    
    @State private var settings = TerminalSettings.shared
    
    private var palette: AppThemePalette { settings.appPalette }
    private var agentColor: Color { AIAgentRegistry.themeColor(for: session.agentID) }
    
    var body: some View {
        HStack(spacing: 12) {
            // Agent icon
            Image(systemName: AIAgentRegistry.iconName(for: session.agentID))
                .font(.caption)
                .foregroundStyle(agentColor)
                .frame(width: 28, height: 28)
                .background(agentColor.opacity(0.12))
                .cornerRadius(7)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(session.projectName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(palette.primaryText)
                    
                    Text(session.displayName)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(agentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(agentColor.opacity(0.15))
                        .cornerRadius(4)
                }
                
                if let summary = session.summary {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(1)
                }
                
                if let lastModified = session.lastModified {
                    Text(lastModified.relativeDescription)
                        .font(.caption2)
                        .foregroundStyle(palette.tertiaryText)
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
