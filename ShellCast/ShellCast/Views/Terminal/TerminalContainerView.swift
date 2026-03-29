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

        view.addSubview(terminalView)

        // Layout: fill the view, respecting keyboard
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Use keyboard layout guide so terminal resizes when keyboard appears
        if #available(iOS 15.0, *) {
            view.keyboardLayoutGuide.topAnchor.constraint(equalTo: terminalView.bottomAnchor).isActive = true
        } else {
            terminalView.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        }

        // Connect bridge to terminal view
        bridge.terminalView = terminalView
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Make terminal first responder to show keyboard
        terminalView.becomeFirstResponder()
        // Start reading SSH output
        bridge.startReading()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        bridge.stop()
    }
}
