import UIKit
import SwiftTerm

/// Bridges a TransportSession (SSH or Mosh) with a SwiftTerm TerminalView.
/// Handles piping transport output → terminal display and terminal keystrokes → transport input.
@MainActor
final class TerminalBridge: NSObject, ObservableObject, TerminalViewDelegate {
    var transport: any TransportSession
    weak var terminalView: TerminalView?
    weak var keyboardToolbar: TerminalKeyboardToolbar?

    @Published var isReconnecting = false
    @Published var isDisconnected = false
    @Published var showTmuxSwitcher = false

    private var readTask: Task<Void, Never>?

    init(transport: any TransportSession) {
        self.transport = transport
        super.init()
    }

    /// Start reading from the transport output stream and feeding into the terminal view.
    private var dataReceivedCount = 0

    func startReading() {
        readTask?.cancel()
        dataReceivedCount = 0
        print("[BRIDGE] startReading() called, transport type: \(type(of: transport))")
        readTask = Task { [weak self] in
            guard let self else { return }
            print("[BRIDGE] for-await loop starting")
            for await data in self.transport.outputStream {
                guard !Task.isCancelled else { break }
                self.dataReceivedCount += 1
                if self.dataReceivedCount <= 5 {
                    print("[BRIDGE] data received #\(self.dataReceivedCount): \(data.count) bytes, terminalView=\(self.terminalView != nil)")
                }
                let bytes = Array(data)

                self.terminalView?.feed(byteArray: bytes[...])
                self.terminalView?.setNeedsDisplay()
            }
            print("[BRIDGE] stream ended, isCancelled=\(Task.isCancelled)")
            // Stream ended — connection likely dropped
            if !Task.isCancelled {
                self.isDisconnected = true
            }
        }
    }

    /// Reconnect the SSH session and restart reading. Only works for SSH transport.
    func reconnect(cols: Int, rows: Int, tmuxCommand: String?) async -> Bool {
        guard let sshTransport = transport as? SSHSession else {
            // Mosh handles reconnection internally — no manual reconnect needed
            return false
        }
        isReconnecting = true
        isDisconnected = false
        defer { isReconnecting = false }

        do {
            readTask?.cancel()
            try await sshTransport.reconnect(cols: cols, rows: rows, tmuxCommand: tmuxCommand)
            isDisconnected = false
            startReading()
            return true
        } catch {
            isDisconnected = true
            return false
        }
    }

    func stop() {
        readTask?.cancel()
    }

    /// Capture a thumbnail snapshot of the terminal view as JPEG data.
    func captureSnapshot() -> Data? {
        guard let tv = terminalView, tv.bounds.width > 0, tv.bounds.height > 0 else { return nil }
        let renderer = UIGraphicsImageRenderer(bounds: tv.bounds)
        let fullImage = renderer.image { _ in
            tv.drawHierarchy(in: tv.bounds, afterScreenUpdates: false)
        }
        // Scale down to thumbnail (2x for retina)
        let targetSize = CGSize(width: 360, height: 240)
        let thumbRenderer = UIGraphicsImageRenderer(size: targetSize)
        let thumb = thumbRenderer.image { _ in
            fullImage.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return thumb.jpegData(compressionQuality: 0.5)
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
