import SwiftUI
import SwiftTerm

struct TerminalContainerView: View {
    let transport: SSHSession

    @Environment(\.dismiss) private var dismiss
    @StateObject private var bridge: TerminalBridge

    init(transport: SSHSession) {
        self.transport = transport
        self._bridge = StateObject(wrappedValue: TerminalBridge(transport: transport))
    }

    var body: some View {
        ZStack {
            SwiftTermView(bridge: bridge)
                .ignoresSafeArea(.container, edges: .bottom)

            // Close button
            VStack {
                HStack {
                    Spacer()
                    Button {
                        bridge.stop()
                        Task { await transport.disconnect() }
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .gray.opacity(0.5))
                    }
                    .padding(12)
                }
                Spacer()
            }
        }
        .statusBarHidden()
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
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
    private var toolbar: TerminalKeyboardToolbar!

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        // Create toolbar (always visible — sits at bottom, moves up with keyboard)
        toolbar = TerminalKeyboardToolbar(frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 44))
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toolbar)

        toolbarBottomConstraint = toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbarBottomConstraint,
            toolbar.heightAnchor.constraint(equalToConstant: 44),
        ])

        // Create SwiftTerm TerminalView
        terminalView = ShellCastTerminalView(frame: view.bounds)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.terminalDelegate = bridge
        terminalView.nativeBackgroundColor = .black
        terminalView.nativeForegroundColor = UIColor(red: 0.9, green: 0.95, blue: 0.9, alpha: 1.0)
        terminalView.caretColor = .green
        if let nerdFont = UIFont(name: "JetBrainsMonoNF-Regular", size: 12) {
            terminalView.font = nerdFont
        } else {
            terminalView.font = UIFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        }
        terminalView.keyboardAppearance = .dark
        terminalView.optionAsMetaKey = true
        terminalView.customBlockGlyphs = false
        terminalView.allowMouseReporting = false
        terminalView.autocorrectionType = .no
        terminalView.autocapitalizationType = .none
        terminalView.spellCheckingType = .no

        view.addSubview(terminalView)

        terminalBottomConstraint = terminalView.bottomAnchor.constraint(equalTo: toolbar.topAnchor)

        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: view.topAnchor),
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
            print("[Toolbar] onSend called, bytes=\(bytes), self=\(self != nil)")
            guard let self else { return }
            Task {
                do {
                    try await self.bridge.transport.send(Data(bytes))
                    print("[Toolbar] send succeeded")
                } catch {
                    print("[Toolbar] send error: \(error)")
                }
            }
        }
        bridge.terminalView = terminalView
        bridge.keyboardToolbar = toolbar

        // Listen for keyboard show/hide to reposition toolbar
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    private var cellSize: CGSize = .zero

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

        if newCols != terminal.cols || newRows != terminal.rows {
            terminalView.resize(cols: newCols, rows: newRows)
            Task {
                try? await bridge.transport.resize(cols: newCols, rows: newRows)
            }
        }
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let kbFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }

        if cellSize == .zero { computeCellSize() }

        toolbar.applyLayout(keyboardVisible: true)

        // Move toolbar to sit on top of keyboard
        let kbFrameInView = view.convert(kbFrame, from: nil)
        let kbHeight = view.bounds.maxY - kbFrameInView.origin.y

        // toolbar.bottom = view.bottom - kbHeight
        toolbarBottomConstraint.constant = -kbHeight

        // Terminal available height = above toolbar
        let availableHeight = view.bounds.height - kbHeight - 44

        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.resizeTerminal(availableHeight: availableHeight)
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        print("[KB] keyboardWillHide called")
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }

        toolbar.applyLayout(keyboardVisible: false)

        // Move toolbar back to bottom of screen
        toolbarBottomConstraint.constant = 0

        let availableHeight = view.bounds.height - 44

        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.resizeTerminal(availableHeight: availableHeight)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Compute cell dimensions and resize for toolbar
        computeCellSize()
        resizeTerminal(availableHeight: view.bounds.height - 44)

        terminalView.becomeFirstResponder()
        // Start reading SSH output
        bridge.startReading()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        bridge.stop()
    }
}
