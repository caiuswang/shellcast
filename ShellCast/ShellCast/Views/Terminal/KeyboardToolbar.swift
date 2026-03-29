import UIKit
import SwiftTerm

/// Custom keyboard accessory toolbar for terminal special keys.
/// Layout: Ctrl Alt | Esc Tab | ↑ ↓ → ← | | / \ ~ - _
class TerminalKeyboardToolbar: UIInputView {

    weak var terminalView: TerminalView?

    private var ctrlActive = false
    private var altActive = false
    private var ctrlButton: UIButton!
    private var altButton: UIButton!

    override init(frame: CGRect, inputViewStyle: UIInputView.Style) {
        super.init(frame: frame, inputViewStyle: inputViewStyle)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        backgroundColor = UIColor(white: 0.1, alpha: 1.0)
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: 44).isActive = true

        let scrollView = UIScrollView()
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

        let stack = UIStackView()
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

        // Group 1: Ctrl, Alt (toggle buttons)
        ctrlButton = makeToggleButton("Ctrl", action: #selector(toggleCtrl))
        altButton = makeToggleButton("Alt", action: #selector(toggleAlt))
        stack.addArrangedSubview(ctrlButton)
        stack.addArrangedSubview(altButton)
        stack.addArrangedSubview(makeSeparator())

        // Group 2: Esc, Tab
        stack.addArrangedSubview(makeButton("Esc", action: #selector(tapEsc)))
        stack.addArrangedSubview(makeButton("Tab", action: #selector(tapTab)))
        stack.addArrangedSubview(makeSeparator())

        // Group 3: Arrow keys + Page Up/Down
        stack.addArrangedSubview(makeButton("↑", action: #selector(tapUp)))
        stack.addArrangedSubview(makeButton("↓", action: #selector(tapDown)))
        stack.addArrangedSubview(makeButton("←", action: #selector(tapLeft)))
        stack.addArrangedSubview(makeButton("→", action: #selector(tapRight)))
        stack.addArrangedSubview(makeButton("PgUp", action: #selector(tapPageUp)))
        stack.addArrangedSubview(makeButton("PgDn", action: #selector(tapPageDown)))
        stack.addArrangedSubview(makeSeparator())

        // Group 4: Special characters
        for (char, sel) in [
            ("|", #selector(tapPipe)),
            ("/", #selector(tapSlash)),
            ("\\", #selector(tapBackslash)),
            ("~", #selector(tapTilde)),
            ("-", #selector(tapDash)),
            ("_", #selector(tapUnderscore)),
        ] {
            stack.addArrangedSubview(makeButton(char, action: sel))
        }

        stack.addArrangedSubview(makeSeparator())

        // Keyboard dismiss button
        let kbButton = makeButton("⌨", action: #selector(tapKeyboard))
        kbButton.titleLabel?.font = .systemFont(ofSize: 18)
        stack.addArrangedSubview(kbButton)
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

    /// Send bytes to terminal view, applying Ctrl/Alt modifiers if active.
    private func sendKey(_ bytes: [UInt8]) {
        terminalView?.send(bytes)
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
    @objc private func tapPageUp()   { sendKey([0x1B, 0x5B, 0x35, 0x7E]) }  // ESC [ 5 ~
    @objc private func tapPageDown() { sendKey([0x1B, 0x5B, 0x36, 0x7E]) }  // ESC [ 6 ~

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
}
