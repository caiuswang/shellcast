import UIKit
import SwiftTerm

/// Bridges an SSHSession (TransportSession) with a SwiftTerm TerminalView.
/// Handles piping SSH output → terminal display and terminal keystrokes → SSH input.
@MainActor
final class TerminalBridge: NSObject, ObservableObject, TerminalViewDelegate {
    let transport: SSHSession
    weak var terminalView: TerminalView?
    weak var keyboardToolbar: TerminalKeyboardToolbar?

    private var readTask: Task<Void, Never>?

    init(transport: SSHSession) {
        self.transport = transport
        super.init()
    }

    /// Start reading from the SSH output stream and feeding into the terminal view.
    func startReading() {
        readTask = Task { [weak self] in
            guard let self, let transport = self.transport as SSHSession? else { return }
            for await data in transport.outputStream {
                guard !Task.isCancelled else { break }
                let bytes = Array(data)
                self.terminalView?.feed(byteArray: bytes[...])
            }
        }
    }

    func stop() {
        readTask?.cancel()
    }

    // MARK: - TerminalViewDelegate

    /// User typed something — send it over SSH, applying toolbar modifiers if active.
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        let modifiers = keyboardToolbar?.consumeModifiers()
        let finalData: Data

        if let modifiers, modifiers.ctrl, data.count == 1,
           let byte = data.first {
            // Ctrl+key: convert to control character
            let upper = byte & 0xDF  // uppercase ASCII
            if upper >= 0x40 && upper <= 0x5F {
                finalData = Data([upper - 0x40])
            } else {
                finalData = Data(data)
            }
        } else if let modifiers, modifiers.alt {
            // Alt+key: send ESC prefix
            var bytes: [UInt8] = [0x1B]
            bytes.append(contentsOf: data)
            finalData = Data(bytes)
        } else {
            finalData = Data(data)
        }

        Task {
            try? await transport.send(finalData)
        }
    }

    /// Terminal size changed — notify the SSH server.
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        Task {
            try? await transport.resize(cols: newCols, rows: newRows)
        }
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        // Could update navigation title if needed
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    func scrolled(source: TerminalView, position: Double) {}

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            UIApplication.shared.open(url)
        }
    }

    func bell(source: TerminalView) {}

    func clipboardCopy(source: TerminalView, content: Data) {
        if let str = String(data: content, encoding: .utf8) {
            UIPasteboard.general.string = str
        }
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
