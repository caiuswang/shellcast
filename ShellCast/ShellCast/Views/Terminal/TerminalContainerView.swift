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

/// UIKit view controller hosting SwiftTerm's TerminalView.
/// Using a UIViewController gives better control over keyboard, layout, and first responder.
class TerminalViewController: UIViewController {
    let bridge: TerminalBridge
    private var terminalView: TerminalView!

    init(bridge: TerminalBridge) {
        self.bridge = bridge
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var bottomConstraint: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        // Create SwiftTerm TerminalView
        terminalView = TerminalView(frame: view.bounds)
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        terminalView.terminalDelegate = bridge
        terminalView.nativeBackgroundColor = .black
        terminalView.nativeForegroundColor = UIColor(red: 0.9, green: 0.95, blue: 0.9, alpha: 1.0)
        terminalView.caretColor = .green
        terminalView.font = UIFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        terminalView.keyboardAppearance = .dark
        terminalView.optionAsMetaKey = true
        terminalView.autocorrectionType = .no
        terminalView.autocapitalizationType = .none
        terminalView.spellCheckingType = .no

        view.addSubview(terminalView)

        bottomConstraint = terminalView.bottomAnchor.constraint(equalTo: view.bottomAnchor)

        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: view.topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomConstraint,
        ])

        // Custom keyboard toolbar
        let toolbar = TerminalKeyboardToolbar(
            frame: CGRect(x: 0, y: 0, width: view.bounds.width, height: 44),
            inputViewStyle: .keyboard
        )
        toolbar.terminalView = terminalView
        terminalView.inputView = nil
        terminalView.inputAccessoryView = toolbar

        // Connect bridge to terminal view
        bridge.terminalView = terminalView

        // Listen for keyboard show/hide to resize terminal
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillShow(_:)),
                                               name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)),
                                               name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }

        bottomConstraint.constant = -frame.height
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }

        bottomConstraint.constant = 0
        UIView.animate(withDuration: duration) {
            self.view.layoutIfNeeded()
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        terminalView.reloadInputViews()
        terminalView.becomeFirstResponder()
        // Start reading SSH output
        bridge.startReading()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        bridge.stop()
    }
}
