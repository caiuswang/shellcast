import UIKit
import SwiftTerm
import Speech

/// Custom keyboard accessory toolbar for terminal special keys.
/// Layout: Ctrl Alt | Esc Tab | ↑ ↓ → ← | | / \ ~ - _
class TerminalKeyboardToolbar: UIView {

    weak var terminalView: TerminalView?
    /// Direct send callback — sends bytes over SSH regardless of first responder state.
    var onSend: (([UInt8]) -> Void)?

    private(set) var ctrlActive = false
    private(set) var altActive = false
    private var ctrlButton: UIButton!
    private var altButton: UIButton!

    // Button groups for reordering
    private var pageGroup: [UIView] = []
    private var modifierGroup: [UIView] = []
    private var escTabGroup: [UIView] = []
    private var arrowGroup: [UIView] = []
    private var symbolGroup: [UIView] = []
    private var kbGroup: [UIView] = []
    private var micGroup: [UIView] = []
    private var stack: UIStackView!
    private var scrollView: UIScrollView!

    // Speech recognition
    private var micButton: UIButton!
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var isListening = false
    private var lastTranscript = ""

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = UIColor(white: 0.1, alpha: 1.0)

        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -4),
            stack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor, constant: -8),
            stack.heightAnchor.constraint(equalTo: scrollView.heightAnchor, constant: -8),
        ])

        // Create button groups (no separators — those are added fresh each time)
        pageGroup = [
            makeButton("PgUp", action: #selector(tapPageUp)),
            makeButton("PgDn", action: #selector(tapPageDown)),
        ]

        ctrlButton = makeToggleButton("Ctrl", action: #selector(toggleCtrl))
        altButton = makeToggleButton("Alt", action: #selector(toggleAlt))
        modifierGroup = [ctrlButton, altButton]

        escTabGroup = [
            makeButton("Esc", action: #selector(tapEsc)),
            makeButton("Tab", action: #selector(tapTab)),
        ]

        arrowGroup = [
            makeButton("↑", action: #selector(tapUp)),
            makeButton("↓", action: #selector(tapDown)),
            makeButton("←", action: #selector(tapLeft)),
            makeButton("→", action: #selector(tapRight)),
        ]

        var symbols: [UIView] = []
        for (char, sel) in [
            ("|", #selector(tapPipe)),
            ("/", #selector(tapSlash)),
            ("\\", #selector(tapBackslash)),
            ("~", #selector(tapTilde)),
            ("-", #selector(tapDash)),
            ("_", #selector(tapUnderscore)),
        ] {
            symbols.append(makeButton(char, action: sel))
        }
        symbolGroup = symbols

        let kbButton = makeButton("⌨", action: #selector(tapKeyboard))
        kbButton.titleLabel?.font = .systemFont(ofSize: 18)
        kbGroup = [kbButton]

        micButton = UIButton(type: .system)
        micButton.setImage(UIImage(systemName: "mic"), for: .normal)
        micButton.tintColor = .white
        micButton.backgroundColor = UIColor(white: 0.22, alpha: 1.0)
        micButton.layer.cornerRadius = 6
        micButton.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        micButton.addTarget(self, action: #selector(tapMic), for: .touchUpInside)
        micGroup = [micButton]

        // Default: no-keyboard layout (PgUp/PgDn first)
        applyLayout(keyboardVisible: false)
    }

    /// Reorder buttons based on keyboard visibility.
    func applyLayout(keyboardVisible: Bool) {
        // Remove all arranged subviews
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // Reset scroll to start so first group is visible
        scrollView.setContentOffset(.zero, animated: false)

        let groups: [[UIView]]
        if keyboardVisible {
            groups = [modifierGroup, escTabGroup, arrowGroup, pageGroup, symbolGroup, micGroup, kbGroup]
        } else {
            groups = [pageGroup, modifierGroup, escTabGroup, arrowGroup, symbolGroup, micGroup, kbGroup]
        }

        for (i, group) in groups.enumerated() {
            for view in group {
                stack.addArrangedSubview(view)
            }
            // Add separator between groups (not after last)
            if i < groups.count - 1 {
                stack.addArrangedSubview(makeSeparator())
            }
        }
    }

    // MARK: - Button Factory

    private func makeButton(_ title: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.titleLabel?.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor(white: 0.22, alpha: 1.0)
        button.layer.cornerRadius = 6
        button.contentEdgeInsets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func makeToggleButton(_ title: String, action: Selector) -> UIButton {
        let button = makeButton(title, action: action)
        button.backgroundColor = UIColor(white: 0.22, alpha: 1.0)
        return button
    }

    private func makeSeparator() -> UIView {
        let sep = UIView()
        sep.translatesAutoresizingMaskIntoConstraints = false
        sep.backgroundColor = UIColor(white: 0.3, alpha: 1.0)
        sep.widthAnchor.constraint(equalToConstant: 1).isActive = true
        sep.heightAnchor.constraint(equalToConstant: 20).isActive = true
        return sep
    }

    private func updateToggleAppearance(_ button: UIButton, active: Bool) {
        button.backgroundColor = active
            ? UIColor(red: 0.2, green: 0.5, blue: 0.2, alpha: 1.0)
            : UIColor(white: 0.22, alpha: 1.0)
    }

    // MARK: - Modifier Toggles

    @objc private func toggleCtrl() {
        ctrlActive.toggle()
        updateToggleAppearance(ctrlButton, active: ctrlActive)
    }

    @objc private func toggleAlt() {
        altActive.toggle()
        updateToggleAppearance(altButton, active: altActive)
    }

    /// Consume and reset modifier state. Returns (ctrl, alt) flags.
    func consumeModifiers() -> (ctrl: Bool, alt: Bool) {
        let result = (ctrl: ctrlActive, alt: altActive)
        if ctrlActive {
            ctrlActive = false
            updateToggleAppearance(ctrlButton, active: false)
        }
        if altActive {
            altActive = false
            updateToggleAppearance(altButton, active: false)
        }
        return result
    }

    /// Send bytes — always uses onSend to go directly to SSH.
    private func sendKey(_ bytes: [UInt8]) {
        onSend?(bytes)
        // Auto-deactivate modifiers after use
        if ctrlActive {
            ctrlActive = false
            updateToggleAppearance(ctrlButton, active: false)
        }
        if altActive {
            altActive = false
            updateToggleAppearance(altButton, active: false)
        }
    }

    private func sendChar(_ char: String) {
        if ctrlActive, let ascii = char.uppercased().unicodeScalars.first?.value,
           ascii >= 0x40 && ascii <= 0x5F {
            // Ctrl+letter: send control character (ASCII value - 0x40)
            sendKey([UInt8(ascii - 0x40)])
        } else if altActive {
            // Alt+key: send ESC prefix followed by the character
            var bytes: [UInt8] = [0x1B]  // ESC
            bytes.append(contentsOf: Array(char.utf8))
            sendKey(bytes)
        } else {
            sendKey(Array(char.utf8))
        }
    }

    // MARK: - Key Actions

    @objc private func tapEsc() { sendKey([0x1B]) }
    @objc private func tapTab() { sendKey([0x09]) }

    // Arrow keys: send ANSI escape sequences
    @objc private func tapUp()       { sendKey([0x1B, 0x5B, 0x41]) }  // ESC [ A
    @objc private func tapDown()     { sendKey([0x1B, 0x5B, 0x42]) }  // ESC [ B
    @objc private func tapRight()    { sendKey([0x1B, 0x5B, 0x43]) }  // ESC [ C
    @objc private func tapLeft()     { sendKey([0x1B, 0x5B, 0x44]) }  // ESC [ D
    // Send Ctrl+B [ to enter tmux copy mode, then PgUp/PgDn to scroll
    @objc private func tapPageUp() {
        // Ctrl+B (tmux prefix) + PgUp — tmux default binds PgUp in copy mode
        sendKey([0x02, 0x1B, 0x5B, 0x35, 0x7E])
    }
    @objc private func tapPageDown() {
        sendKey([0x1B, 0x5B, 0x36, 0x7E])  // PgDn (works once already in copy mode)
    }

    // Special characters
    @objc private func tapPipe()       { sendChar("|") }
    @objc private func tapSlash()      { sendChar("/") }
    @objc private func tapBackslash()  { sendChar("\\") }
    @objc private func tapTilde()      { sendChar("~") }
    @objc private func tapDash()       { sendChar("-") }
    @objc private func tapUnderscore() { sendChar("_") }

    @objc private func tapKeyboard() {
        if terminalView?.isFirstResponder == true {
            terminalView?.resignFirstResponder()
        } else {
            terminalView?.becomeFirstResponder()
        }
    }

    // MARK: - Speech Recognition

    @objc private func tapMic() {
        if isListening {
            stopListening()
        } else {
            startListening()
        }
    }

    private func startListening() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self, status == .authorized else { return }
                self.requestMicAndStart()
            }
        }
    }

    private func requestMicAndStart() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, granted else { return }
                self.beginRecognition()
            }
        }
    }

    private func beginRecognition() {
        // Stop any existing task
        recognitionTask?.cancel()
        recognitionTask = nil

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest, let speechRecognizer, speechRecognizer.isAvailable else { return }
        recognitionRequest.shouldReportPartialResults = false

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            recognitionRequest.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self else { return }
            if let result {
                let text = result.bestTranscription.formattedString
                if result.isFinal {
                    self.sendKey(Array(text.utf8))
                }
            }
            if error != nil || (result?.isFinal ?? false) {
                self.stopListening()
            }
        }

        do {
            try audioEngine.start()
            isListening = true
            micButton.tintColor = .red
            micButton.backgroundColor = UIColor(red: 0.4, green: 0.15, blue: 0.15, alpha: 1.0)
        } catch {
            stopListening()
        }
    }

    private func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        micButton.tintColor = .white
        micButton.backgroundColor = UIColor(white: 0.22, alpha: 1.0)
    }
}
