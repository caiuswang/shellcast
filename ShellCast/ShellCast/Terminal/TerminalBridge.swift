import UIKit
import SwiftTerm

/// Bridges an SSHSession (TransportSession) with a SwiftTerm TerminalView.
/// Handles piping SSH output → terminal display and terminal keystrokes → SSH input.
@MainActor
final class TerminalBridge: NSObject, ObservableObject, TerminalViewDelegate {
    let transport: SSHSession
    weak var terminalView: TerminalView?

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

    /// User typed something — send it over SSH.
    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        Task {
            try? await transport.send(Data(data))
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
