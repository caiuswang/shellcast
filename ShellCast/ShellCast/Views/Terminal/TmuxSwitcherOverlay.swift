import SwiftUI

/// In-terminal overlay for switching tmux sessions and windows without leaving the terminal.
struct TmuxSwitcherOverlay: View {
    let transport: SSHSession
    /// Send raw bytes through the terminal PTY (for tmux commands that must run in the attached client)
    var sendToPTY: ((Data) -> Void)?
    @Binding var isPresented: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var sessions: [TmuxSession] = []
    @State private var selectedSession: TmuxSession?
    @State private var windows: [TmuxWindow] = []
    @State private var currentSessionName: String?
    @State private var isLoading = true
    @State private var isLoadingWindows = false

    var body: some View {
        ZStack {
            // Dimmed background — tap to dismiss
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: "rectangle.split.3x1")
                        .foregroundStyle(.green)
                    Text(selectedSession?.name ?? "Tmux Sessions")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    if selectedSession != nil {
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedSession = nil
                                windows = []
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        .padding(.trailing, 8)
                    }
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color(white: 0.3))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(white: 0.12))

                Divider().background(Color(white: 0.2))

                // Content
                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(.green)
                    Spacer()
                } else if selectedSession != nil {
                    windowList
                } else {
                    sessionList
                }
            }
            .frame(maxWidth: sizeClass == .regular ? 480 : 360)
            .frame(maxHeight: sizeClass == .regular ? 500 : 400)
            .background(Color(white: 0.08))
            .cornerRadius(16)
            .shadow(color: .black.opacity(0.5), radius: 20)
            .padding(24)
        }
        .task {
            await loadSessions()
        }
    }

    // MARK: - Session List

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sessions) { session in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedSession = session
                        }
                        Task { await loadWindows(for: session) }
                    } label: {
                        sessionRow(session)
                    }

                    if session.id != sessions.last?.id {
                        Divider().background(Color(white: 0.15)).padding(.leading, 16)
                    }
                }
            }
        }
    }

    private func sessionRow(_ session: TmuxSession) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(session.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)

                    if session.name == currentSessionName {
                        Text("Current")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(3)
                    }
                }

                Text("\(session.windowCount) window\(session.windowCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.gray)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Window List

    private var windowList: some View {
        Group {
            if isLoadingWindows {
                VStack {
                    Spacer()
                    ProgressView().tint(.green)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Switch to session (attach to active window)
                        Button {
                            guard let session = selectedSession else { return }
                            switchToSession(session)
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.stack")
                                    .foregroundStyle(.green)
                                Text("Switch to session")
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }

                        Divider().background(Color(white: 0.15)).padding(.leading, 16)

                        ForEach(windows) { window in
                            Button {
                                guard let session = selectedSession else { return }
                                switchToWindow(session, window: window)
                            } label: {
                                windowRow(window)
                            }

                            if window.id != windows.last?.id {
                                Divider().background(Color(white: 0.15)).padding(.leading, 16)
                            }
                        }
                    }
                }
            }
        }
    }

    private func windowRow(_ window: TmuxWindow) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("\(window.index): \(window.name)")
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)

                    if window.isActive {
                        Text("Active")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(3)
                    }
                }

                Text("\(window.paneCount) pane\(window.paneCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func loadSessions() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let sessionsResult = TmuxParser.listSessions(over: transport)
            async let currentResult = TmuxParser.currentSessionName(over: transport)
            sessions = try await sessionsResult
            currentSessionName = try? await currentResult
        } catch {
            sessions = []
        }
    }

    private func loadWindows(for session: TmuxSession) async {
        isLoadingWindows = true
        defer { isLoadingWindows = false }
        do {
            windows = try await TmuxParser.listWindows(over: transport, sessionName: session.name)
        } catch {
            windows = []
        }
    }

    /// Send a tmux command via the PTY using tmux prefix key (Ctrl-B :).
    /// This is the most reliable method because it runs in the actual tmux client context,
    /// regardless of whether the transport is SSH or Mosh.
    private func sendTmuxPrefixCommand(_ tmuxCmd: String) {
        guard let sendToPTY else { return }
        // Ctrl-B (0x02) activates tmux prefix, then ":" enters command mode
        var bytes: [UInt8] = [0x02]  // Ctrl-B
        bytes.append(0x3A)           // ":"
        sendToPTY(Data(bytes))
        // Small delay to let tmux enter command mode, then send the command
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sendToPTY(Data("\(tmuxCmd)\n".utf8))
        }
    }

    private func switchToSession(_ session: TmuxSession) {
        sendTmuxPrefixCommand("switch-client -t \(session.name)")
        isPresented = false
    }

    private func switchToWindow(_ session: TmuxSession, window: TmuxWindow) {
        if session.name != currentSessionName {
            sendTmuxPrefixCommand("switch-client -t \(session.name)")
            // Delay the window select to let session switch complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                sendTmuxPrefixCommand("select-window -t \(session.name):\(window.index)")
            }
        } else {
            sendTmuxPrefixCommand("select-window -t \(session.name):\(window.index)")
        }
        isPresented = false
    }
}
