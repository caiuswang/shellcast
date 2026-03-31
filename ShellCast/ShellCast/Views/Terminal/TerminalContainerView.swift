import SwiftUI
import SwiftTerm
import SwiftData

struct TerminalContainerView: View {
    let transport: any TransportSession
    let tmuxCommand: String?
    let sessionRecord: SessionRecord?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(ConnectionManager.self) private var connectionManager
    @StateObject private var bridge: TerminalBridge

    @State private var wasBackgrounded = false
    @State private var reconnectError: String?
    @State private var networkMonitorToken: UUID?
    @State private var toastMessage: String?

    private var isSSH: Bool { transport is SSHSession }

    init(transport: any TransportSession, tmuxCommand: String? = nil, sessionRecord: SessionRecord? = nil) {
        self.transport = transport
        self.tmuxCommand = tmuxCommand
        self.sessionRecord = sessionRecord
        self._bridge = StateObject(wrappedValue: TerminalBridge(transport: transport))
    }

    var body: some View {
        ZStack {
            SwiftTermView(bridge: bridge)
                .ignoresSafeArea(.container, edges: .bottom)

            // Top-right buttons: minimize + close
            VStack {
                HStack {
                    Spacer()
                    // Minimize — return to HomeView, keep session alive
                    Button {
                        saveSnapshot()
                        bridge.stop()
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .gray.opacity(0.5))
                    }
                    // Close — disconnect and dismiss
                    Button {
                        saveSnapshot()
                        bridge.stop()
                        Task { await transport.disconnect() }
                        if let sessionRecord {
                            sessionRecord.isActive = false
                            try? modelContext.save()
                        }
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .gray.opacity(0.5))
                    }
                    .padding(.trailing, 12)
                }
                .padding(.top, 12)
                Spacer()
            }

            // Reconnecting overlay
            if bridge.isReconnecting {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.green)
                        .scaleEffect(1.5)
                    Text("Reconnecting...")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }

            // Tmux switcher overlay (SSH only — over Mosh use keyboard shortcuts)
            if bridge.showTmuxSwitcher, isSSH, let sshTransport = transport as? SSHSession {
                TmuxSwitcherOverlay(
                    transport: sshTransport,
                    sendToPTY: { data in
                        Task { try? await transport.send(data) }
                    },
                    isPresented: $bridge.showTmuxSwitcher
                )
                .transition(.opacity)
                .zIndex(10)
            }

            // Toast message (auto-dismiss)
            if let toast = toastMessage {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.8))
                        .cornerRadius(16)
                        .padding(.bottom, 60)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(5)
            }

            // Disconnected overlay
            if bridge.isDisconnected && !bridge.isReconnecting {
                Color.black.opacity(0.7)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 40))
                        .foregroundStyle(.red)
                    Text("Connection Lost")
                        .font(.headline)
                        .foregroundStyle(.white)
                    if let reconnectError {
                        Text(reconnectError)
                            .font(.caption)
                            .foregroundStyle(.red.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    Button {
                        self.reconnectError = nil
                        attemptReconnect()
                    } label: {
                        Text("Reconnect")
                            .fontWeight(.semibold)
                            .foregroundStyle(.black)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                    Button {
                        saveSnapshot()
                        bridge.stop()
                        Task { await transport.disconnect() }
                        dismiss()
                    } label: {
                        Text("Close")
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
        .statusBarHidden()
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .onAppear {
            if let sessionRecord {
                connectionManager.registerBridge(bridge, for: sessionRecord.id)
            }
            // Listen for network changes to trigger proactive SSH reconnection
            if isSSH {
                NetworkMonitor.shared.onNetworkChange = { [weak bridge] isConnected in
                    guard let bridge, isConnected else { return }
                    // Network restored or interface changed — check if SSH is still alive
                    Task { @MainActor in
                        guard !bridge.isDisconnected, !bridge.isReconnecting else { return }
                        debugLog("[NET] Network change detected, checking SSH connection...")
                        checkConnectionOnForeground()
                    }
                }
            }
        }
        .onDisappear {
            if let sessionRecord {
                connectionManager.unregisterBridge(for: sessionRecord.id)
            }
            if isSSH {
                NetworkMonitor.shared.onNetworkChange = nil
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if newPhase == .background || newPhase == .inactive {
                if !wasBackgrounded {
                    saveSnapshot()
                }
                wasBackgrounded = true
            } else if newPhase == .active && wasBackgrounded {
                wasBackgrounded = false
                checkConnectionOnForeground()
            }
        }
    }

    private func saveSnapshot() {
        guard let sessionRecord,
              !bridge.isDisconnected,
              !bridge.isReconnecting,
              let data = bridge.captureSnapshot() else { return }
        sessionRecord.snapshotImageData = data
        sessionRecord.snapshotCapturedAt = Date()
        sessionRecord.lastActiveAt = Date()
        try? modelContext.save()
    }

    private func checkConnectionOnForeground() {
        if isSSH {
            checkSSHConnectionOnForeground()
        } else {
            checkMoshConnectionOnForeground()
        }
    }

    private func checkSSHConnectionOnForeground() {
        Task {
            // Show "Reconnecting..." immediately so user knows what's happening
            bridge.isReconnecting = true

            // Give the system a moment to restore networking
            try? await Task.sleep(for: .milliseconds(500))

            let alive = await (transport as? SSHSession)?.checkAlive() ?? false
            if alive {
                // Connection survived — clear the overlay
                bridge.isReconnecting = false
            } else {
                // Connection dead — reconnect seamlessly
                let terminal = bridge.terminalView?.getTerminal()
                let cols = terminal?.cols ?? 80
                let rows = terminal?.rows ?? 24
                let success = await bridge.reconnect(cols: cols, rows: rows, tmuxCommand: tmuxCommand)
                if success {
                    reconnectError = nil
                    showToast("Reconnected")
                } else {
                    reconnectError = "Reconnection failed. Check your network and try again."
                }
            }
        }
    }

    private func checkMoshConnectionOnForeground() {
        // Mosh uses UDP and handles reconnection internally.
        // After iOS suspension, the client may have been killed.
        // Check if transport is still connected; if not, show status.
        #if canImport(mosh)
        guard let moshSession = transport as? MoshSession else { return }
        if !moshSession.isConnected {
            // Mosh was killed during background — show disconnected overlay
            bridge.isDisconnected = true
        } else {
            // Mosh survived — it will resync automatically via UDP
            showToast("Resumed")
        }
        #endif
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { toastMessage = nil }
        }
    }

    private func attemptReconnect() {
        Task {
            let terminal = bridge.terminalView?.getTerminal()
            let cols = terminal?.cols ?? 80
            let rows = terminal?.rows ?? 24
            let success = await bridge.reconnect(cols: cols, rows: rows, tmuxCommand: tmuxCommand)
            if success {
                reconnectError = nil
                showToast("Reconnected")
            } else {
                reconnectError = "Reconnection failed. Check your network and try again."
            }
        }
    }
}

// MARK: - UIViewRepresentable wrapping SwiftTerm TerminalView

struct SwiftTermView: UIViewControllerRepresentable {
    let bridge: TerminalBridge

    func makeUIViewController(context: Context) -> TerminalViewController {
        let vc = TerminalViewController(bridge: bridge)
        return vc
    }

    func updateUIViewController(_ uiViewController: TerminalViewController, context: Context) {}
}

/// Subclass TerminalView — disables mouse reporting to prevent tap issues.
class ShellCastTerminalView: TerminalView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.pasteConfiguration = nil
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// UIKit view controller hosting SwiftTerm's TerminalView.
/// Using a UIViewController gives better control over keyboard, layout, and first responder.
class TerminalViewController: UIViewController {
    let bridge: TerminalBridge
    private var terminalView: ShellCastTerminalView!

    init(bridge: TerminalBridge) {
        self.bridge = bridge
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var terminalBottomConstraint: NSLayoutConstraint!
    private var toolbarBottomConstraint: NSLayoutConstraint!
    private var toolbarHeightConstraint: NSLayoutConstraint!
    private var toolbar: TerminalKeyboardToolbar!

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        // Create toolbar (always visible — sits at bottom, moves up with keyboard)
        toolbar = TerminalKeyboardToolbar(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 44))
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        toolbarBottomConstraint = toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        toolbarHeightConstraint = toolbar.heightAnchor.constraint(equalToConstant: 44)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbarBottomConstraint,
            toolbarHeightConstraint,
        ])

        toolbar.onPreviewVisibilityChanged = { [weak self] visible in
            guard let self = self else { return }
            self.toolbarHeightConstraint.constant = visible ? 120 : 44
            UIView.animate(withDuration: 0.2) {
                self.view.layoutIfNeeded()
            }
        }

        // Create SwiftTerm TerminalView
        let settings = TerminalSettings.shared
        terminalView = ShellCastTerminalView(frame: view.bounds)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.terminalDelegate = bridge

        // Apply theme colors
        let theme = settings.theme
        terminalView.nativeBackgroundColor = theme.backgroundColor
        terminalView.nativeForegroundColor = theme.foregroundColor
        terminalView.caretColor = theme.caretColor
        view.backgroundColor = theme.backgroundColor

        // Apply font settings
        terminalView.font = settings.font.uiFont(size: CGFloat(settings.fontSize))

        terminalView.keyboardAppearance = .dark
        terminalView.optionAsMetaKey = true
        terminalView.customBlockGlyphs = false
        terminalView.allowMouseReporting = false
        terminalView.autocorrectionType = .no
        terminalView.autocapitalizationType = .none
        terminalView.spellCheckingType = .no

        // Apply cursor style
        let cursorStyle: CursorStyle
        switch (settings.cursorMode, settings.cursorBlink) {
        case (.block, true): cursorStyle = .blinkBlock
        case (.block, false): cursorStyle = .steadyBlock
        case (.underline, true): cursorStyle = .blinkUnderline
        case (.underline, false): cursorStyle = .steadyUnderline
        case (.bar, true): cursorStyle = .blinkBar
        case (.bar, false): cursorStyle = .steadyBar
        }
        terminalView.getTerminal().options.cursorStyle = cursorStyle

        // Apply scrollback size
        terminalView.changeScrollback(settings.scrollbackSize.rawValue)

        view.addSubview(terminalView)

        terminalBottomConstraint = terminalView.bottomAnchor.constraint(equalTo: toolbar.topAnchor)

        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            terminalBottomConstraint,
        ])

        // No inputAccessoryView — we manage toolbar position ourselves
        terminalView.inputView = nil
        terminalView.inputAccessoryView = nil

        // Toolbar must be in front of terminal view
        view.bringSubviewToFront(toolbar)

        // Wire up toolbar and bridge
        toolbar.terminalView = terminalView
        toolbar.onSend = { [weak self] bytes in
            guard let self else { return }
            Task {
                try? await self.bridge.transport.send(Data(bytes))
            }
        }
        toolbar.onTmuxSwitcher = { [weak self] in
            guard let self else { return }
            self.bridge.showTmuxSwitcher = true
        }
        bridge.terminalView = terminalView
        bridge.keyboardToolbar = toolbar

        // Listen for all keyboard frame changes (covers show, hide, and language switch)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }

    private var cellSize: CGSize = .zero
    private var lastServerCols: Int = 0
    private var lastServerRows: Int = 0
    private var resizeWorkItem: DispatchWorkItem?

    private func computeCellSize() {
        let terminal = terminalView.getTerminal()
        let optimalFrame = terminalView.getOptimalFrameSize()
        guard terminal.cols > 0 && terminal.rows > 0 else { return }
        cellSize = CGSize(
            width: optimalFrame.width / CGFloat(terminal.cols),
            height: optimalFrame.height / CGFloat(terminal.rows)
        )
    }

    private func resizeTerminal(availableHeight: CGFloat) {
        guard cellSize.width > 0 && cellSize.height > 0 else { return }

        let newCols = max(1, Int(view.bounds.width / cellSize.width))
        let newRows = max(1, Int(availableHeight / cellSize.height))
        let terminal = terminalView.getTerminal()

        debugLog("[RESIZE] availableHeight=\(availableHeight) cellSize=\(cellSize) newCols=\(newCols) newRows=\(newRows) currentCols=\(terminal.cols) currentRows=\(terminal.rows) lastServer=\(lastServerCols)x\(lastServerRows)")
        debugLog("[RESIZE] view.bounds=\(view.bounds) terminalView.frame=\(terminalView.frame) safeArea.top=\(view.safeAreaInsets.top)")
        debugLog("[RESIZE] terminalView.contentSize=\(terminalView.contentSize) contentOffset=\(terminalView.contentOffset) bounds=\(terminalView.bounds)")

        let terminalNeedsResize = newCols != terminal.cols || newRows != terminal.rows
        let serverNeedsResize = newCols != lastServerCols || newRows != lastServerRows

        if terminalNeedsResize {
            debugLog("[RESIZE] Resizing terminal view: \(terminal.cols)x\(terminal.rows) → \(newCols)x\(newRows)")
            terminalView.resize(cols: newCols, rows: newRows)
        }

        if serverNeedsResize {
            debugLog("[RESIZE] Resizing server: \(lastServerCols)x\(lastServerRows) → \(newCols)x\(newRows)")
            lastServerCols = newCols
            lastServerRows = newRows
            Task {
                do {
                    try await bridge.transport.resize(cols: newCols, rows: newRows)
                    debugLog("[RESIZE] Server resize SUCCESS: \(newCols)x\(newRows)")
                } catch {
                    debugLog("[RESIZE] Server resize FAILED: \(error)")
                }
            }
        }
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let kbFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }

        if cellSize == .zero { computeCellSize() }

        let kbFrameInView = view.convert(kbFrame, from: nil)
        let kbHeight = max(0, view.bounds.maxY - kbFrameInView.origin.y)
        let keyboardVisible = kbHeight > 0

        toolbar.applyLayout(keyboardVisible: keyboardVisible)
        toolbarBottomConstraint.constant = -kbHeight

        debugLog("[KB] kbHeight=\(kbHeight) keyboardVisible=\(keyboardVisible) toolbarConstant=\(toolbarBottomConstraint.constant) viewHeight=\(view.bounds.height) safeTop=\(view.safeAreaInsets.top)")

        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        } completion: { _ in
            // Use the actual terminal view frame after layout — Auto Layout
            // already accounts for safe area, toolbar position, and keyboard.
            let actualHeight = self.terminalView.frame.height
            debugLog("[KB] post-layout terminalFrame=\(self.terminalView.frame) toolbarFrame=\(self.toolbar.frame) actualHeight=\(actualHeight)")

            self.resizeTerminal(availableHeight: actualHeight)
            self.startSessionIfNeeded()
        }
    }

    private var hasStartedSession = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Compute cell dimensions for later use
        computeCellSize()

        // Show keyboard — this triggers keyboardWillChangeFrame which gives us
        // the correct terminal dimensions (viewDidAppear fires before SwiftUI
        // finishes layout, so view.bounds is wrong here).
        terminalView.becomeFirstResponder()

        debugLog("[TERM] viewDidAppear: bounds=\(view.bounds) cellSize=\(cellSize)")
        debugLog("[TERM] needsDeferredStart=\(bridge.transport.needsDeferredStart) isSSH=\(bridge.transport is SSHSession)")

        // Start reading FIRST so the consumer is ready before any data arrives
        bridge.startReading()

        // DON'T resize or start mosh here — view.bounds is not yet correct.
        // The first keyboardWillChangeFrame will provide correct dimensions
        // and start the session there.
    }

    /// Called after layout changes settle. Starts the session with correct dimensions.
    private func startSessionIfNeeded() {
        guard !hasStartedSession else { return }
        hasStartedSession = true

        let terminal = terminalView.getTerminal()
        debugLog("[TERM] Starting session with correct dims: cols=\(terminal.cols) rows=\(terminal.rows)")

        if bridge.transport.needsDeferredStart {
            bridge.transport.startWithDimensions(cols: terminal.cols, rows: terminal.rows)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        // Fallback: if keyboard notification hasn't fired yet (e.g., external keyboard),
        // start the session once the layout stabilizes.
        if !hasStartedSession && terminalView != nil && cellSize != .zero {
            let availableHeight = terminalView.frame.height
            if availableHeight > 0 {
                computeCellSize()
                resizeTerminal(availableHeight: availableHeight)
                startSessionIfNeeded()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        bridge.stop()
    }
}
