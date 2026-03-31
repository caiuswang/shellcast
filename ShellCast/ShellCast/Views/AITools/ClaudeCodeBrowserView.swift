import SwiftUI

struct ClaudeCodeBrowserView: View {
    let sessions: [ClaudeCodeSession]
    let claudePath: String
    let onSelect: (String) -> Void  // Returns the shell command to run

    @State private var settings = TerminalSettings.shared

    private var palette: AppThemePalette { settings.appPalette }

    /// Group sessions by project path
    private var groupedSessions: [(project: String, sessions: [ClaudeCodeSession])] {
        let grouped = Dictionary(grouping: sessions) { $0.projectPath }
        return grouped.map { (project: $0.key, sessions: $0.value) }
            .sorted { ($0.sessions.first?.lastModified ?? .distantPast) > ($1.sessions.first?.lastModified ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // New session button
            Button {
                onSelect(ClaudeCodeParser.newCommand(projectPath: nil, claudePath: claudePath))
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

            if sessions.isEmpty {
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.08))
                            .frame(width: 72, height: 72)
                        Image(systemName: "sparkles")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.purple.opacity(0.4))
                    }
                    Text("No Claude Code Sessions")
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                    Text("Start a new session to get started")
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
            } else {
                // Sessions grouped by project
                ForEach(groupedSessions, id: \.project) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        // Project header
                        HStack(spacing: 6) {
                            Image(systemName: "folder.fill")
                                .font(.caption2)
                                .foregroundStyle(palette.accent)
                            Text(group.project.isEmpty ? "Default" : group.project)
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(palette.secondaryText)
                        }

                        // Session list
                        VStack(spacing: 0) {
                            ForEach(group.sessions) { session in
                                Button {
                                    onSelect(ClaudeCodeParser.resumeCommand(sessionId: session.sessionId, claudePath: claudePath))
                                } label: {
                                    claudeSessionRow(session)
                                }

                                if session.id != group.sessions.last?.id {
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
            }
        }
        .padding(20)
        .iPadContentWidth(600)
    }

    @ViewBuilder
    private func claudeSessionRow(_ session: ClaudeCodeSession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(Color.purple.opacity(0.8))
                .frame(width: 28, height: 28)
                .background(Color.purple.opacity(0.12))
                .cornerRadius(7)

            VStack(alignment: .leading, spacing: 3) {
                Text(session.summary ?? "Session \(session.sessionId.prefix(8))...")
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(session.sessionId.prefix(8) + "...")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(palette.tertiaryText)

                    if let lastModified = session.lastModified {
                        Text(lastModified.relativeDescription)
                            .font(.caption)
                            .foregroundStyle(palette.tertiaryText)
                    }
                }
            }

            Spacer()

            Text("Resume")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.purple)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.purple.opacity(0.12))
                .cornerRadius(6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
