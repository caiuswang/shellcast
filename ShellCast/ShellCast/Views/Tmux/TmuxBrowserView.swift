import SwiftUI

struct TmuxBrowserView: View {
    let sessions: [TmuxSession]
    let transport: SSHSession
    let onSelect: (TmuxSession?, Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !sessions.isEmpty {
                        // Terminal icon + title
                        HStack(spacing: 12) {
                            Image(systemName: "terminal")
                                .font(.title)
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text("Tmux Sessions")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.white)
                                Text("\(sessions.count) session\(sessions.count == 1 ? "" : "s") found")
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                        }

                        // Session list
                        VStack(spacing: 0) {
                            ForEach(sessions) { session in
                                Button {
                                    navigationPath.append(session)
                                } label: {
                                    TmuxSessionRow(session: session)
                                }

                                if session.id != sessions.last?.id {
                                    Divider()
                                        .background(Color(white: 0.2))
                                }
                            }
                        }
                        .background(Color(white: 0.1))
                        .cornerRadius(12)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "terminal")
                                .font(.largeTitle)
                                .foregroundStyle(.gray)
                            Text("No tmux sessions found")
                                .font(.headline)
                                .foregroundStyle(.white)
                            Text("Start a new session or connect without tmux")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                    }

                    // New tmux session
                    Button {
                        onSelect(TmuxSession(name: "new", windowCount: 0, lastAttached: nil, attachedClients: 0), nil)
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundStyle(.green)
                            Text("New tmux session")
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(14)
                        .background(Color(white: 0.15))
                        .cornerRadius(12)
                    }

                    // Connect without tmux
                    Button {
                        onSelect(nil, nil)
                    } label: {
                        Text("Connect without tmux")
                            .font(.subheadline)
                            .foregroundStyle(.gray)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(Color(white: 0.08))
                            .cornerRadius(12)
                    }
                }
                .padding(20)
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.white)
                    }
                }
            }
            .navigationDestination(for: TmuxSession.self) { session in
                TmuxWindowBrowserView(
                    session: session,
                    transport: transport,
                    onSelect: onSelect
                )
            }
        }
        .presentationDetents([.medium, .large])
        .preferredColorScheme(.dark)
    }
}

// MARK: - Window Browser

struct TmuxWindowBrowserView: View {
    let session: TmuxSession
    let transport: SSHSession
    let onSelect: (TmuxSession?, Int?) -> Void

    @State private var windows: [TmuxWindow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.title)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text(session.name)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                        Text("\(windows.count) window\(windows.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }

                if isLoading {
                    ProgressView()
                        .tint(.green)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else if let error = errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                } else if !windows.isEmpty {
                    // Window list
                    VStack(spacing: 0) {
                        ForEach(windows) { window in
                            Button {
                                onSelect(session, window.index)
                            } label: {
                                TmuxWindowRow(window: window)
                            }

                            if window.id != windows.last?.id {
                                Divider()
                                    .background(Color(white: 0.2))
                            }
                        }
                    }
                    .background(Color(white: 0.1))
                    .cornerRadius(12)
                }

                // Attach to whole session
                Button {
                    onSelect(session, nil)
                } label: {
                    HStack {
                        Image(systemName: "rectangle.stack")
                            .foregroundStyle(.green)
                        Text("Attach to session")
                            .foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(14)
                    .background(Color(white: 0.15))
                    .cornerRadius(12)
                }
            }
            .padding(20)
        }
        .background(Color.black)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadWindows()
        }
    }

    private func loadWindows() async {
        do {
            windows = try await TmuxParser.listWindows(over: transport, sessionName: session.name)
        } catch {
            errorMessage = "Failed to list windows"
        }
        isLoading = false
    }
}

// MARK: - Row Views

struct TmuxSessionRow: View {
    let session: TmuxSession

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(session.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)

                    if session.attachedClients > 0 {
                        Text("Connected")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                HStack(spacing: 8) {
                    Text("\(session.windowCount) windows")
                        .font(.caption)
                        .foregroundStyle(.gray)

                    if let lastAttached = session.lastAttached {
                        Text(lastAttached.relativeDescription)
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .padding(16)
    }
}

struct TmuxWindowRow: View {
    let window: TmuxWindow

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(window.index): \(window.name)")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)

                    if window.isActive {
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                }

                Text("\(window.paneCount) pane\(window.paneCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }

            Spacer()
        }
        .padding(16)
    }
}
