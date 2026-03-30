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

    /// Tracks whether the transport is mosh (needs cursor position fix).
    private var isMoshTransport: Bool {
        transport.needsDeferredStart
    }

    /// Last known cursor position NOT on the status bar (for mosh cursor fix).
    private var lastContentCursorRow: Int = 0
    private var lastContentCursorCol: Int = 0

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

                // Track scroll position before feed to implement auto-scroll.
                // SwiftTerm (UIScrollView) doesn't always update contentOffset
                // after content changes (e.g., erase operations from fish pager).
                let wasAtBottom = self.isScrolledToBottom()

                self.terminalView?.feed(byteArray: bytes[...])

                // Mosh cursor fix: mosh's Display::new_frame may not send
                // the final CUP to reposition the cursor after painting the
                // tmux status bar. Detect this and inject a corrective CUP.
                if self.isMoshTransport {
                    self.fixMoshCursorPosition()
                }

                self.terminalView?.setNeedsDisplay()

                // Snap scroll to bottom if user was already following output.
                // This fixes the blank gap after fish's tab completion pager
                // is dismissed — SwiftTerm's updateScroller isn't called after
                // erase operations, leaving the scroll position stale.
                if wasAtBottom {
                    self.scrollToBottom()
                }
            }
            print("[BRIDGE] stream ended, isCancelled=\(Task.isCancelled)")
            // Stream ended — connection likely dropped
            if !Task.isCancelled {
                self.isDisconnected = true
            }
        }
    }

    // MARK: - Auto-Scroll

    /// Returns true if the terminal scroll view is at (or very near) the bottom.
    private func isScrolledToBottom() -> Bool {
        guard let sv = terminalView else { return true }
        let bottomEdge = sv.contentSize.height - sv.bounds.height
        // Tolerate being within one row of the bottom
        return sv.contentOffset.y >= bottomEdge - 20
    }

    /// Scrolls the terminal to show the latest content (bottom of buffer).
    private func scrollToBottom() {
        guard let sv = terminalView else { return }
        let terminal = sv.getTerminal()
        let rows = terminal.rows
        let optimalSize = sv.getOptimalFrameSize()
        guard rows > 0 else { return }
        let cellHeight = optimalSize.height / CGFloat(rows)

        // Recompute contentSize from the buffer to ensure it's fresh.
        let buffer = terminal.buffer
        // yDisp is the first visible line. For a non-scrolled view, yDisp = yBase.
        // The total line count = yDisp + rows (when at the bottom, yDisp = lines.count - rows).
        // So contentSize.height = (yDisp + rows) * cellHeight is a lower bound.
        // But if there's scrollback above yDisp, the actual line count is larger.
        // Use the existing contentSize (set by SwiftTerm) and just scroll to bottom.
        let bottomOffset = max(0, sv.contentSize.height - sv.bounds.height)
        if abs(sv.contentOffset.y - bottomOffset) > 1 {
            sv.contentOffset = CGPoint(x: 0, y: bottomOffset)
        }
    }

    // MARK: - Mosh Cursor Fix

    /// Detects when mosh leaves the cursor on the tmux status bar (last row)
    /// and repositions it to the last known content position.
    ///
    /// Background: mosh renders the screen by painting cells with CUP commands,
    /// then should send a final CUP to set the cursor at the server's cursor
    /// position. The iOS mosh framework sometimes omits this final CUP,
    /// leaving the cursor wherever the last cell was painted — typically the
    /// tmux status bar on the bottom row.
    func fixMoshCursorPosition() {
        guard let tv = terminalView else { return }
        let terminal = tv.getTerminal()
        let buffer = terminal.buffer
        let rows = terminal.rows
        let cursorY = buffer.y
        let cursorX = buffer.x

        guard rows > 1 else { return }

        let lastRow = rows - 1

        if cursorY == lastRow && isStatusBarRow(buffer: buffer, row: lastRow, cols: terminal.cols) {
            // Cursor is on the status bar — reposition to last known content position.
            // Clamp to valid range (above status bar).
            let fixRow = min(lastContentCursorRow, lastRow - 1)
            let fixCol = lastContentCursorCol

            // Inject CUP escape sequence to move cursor (1-indexed)
            let cup = "\u{1b}[\(fixRow + 1);\(fixCol + 1)H"
            tv.feed(text: cup)
        } else {
            // Cursor is in the content area — remember this position.
            lastContentCursorRow = cursorY
            lastContentCursorCol = cursorX
        }
    }

    /// Heuristic: checks if a given row looks like a tmux status bar.
    /// tmux status bars typically have colored backgrounds (non-default bg attribute)
    /// across most of the row.
    private func isStatusBarRow(buffer: Buffer, row: Int, cols: Int) -> Bool {
        // Use the public getChar(at:) API with screen coordinates.
        var coloredCells = 0
        let checkCols = min(cols, 20)  // check first 20 columns
        for col in 0..<checkCols {
            let cell = buffer.getChar(at: Position(col: col, row: row))
            let attr = cell.attribute
            // Check for non-default background or inverse/reverse attribute.
            let hasColoredBg: Bool
            switch attr.bg {
            case .defaultColor, .defaultInvertedColor:
                hasColoredBg = false
            default:
                hasColoredBg = true
            }
            if hasColoredBg || attr.style.contains(CharacterStyle.inverse) {
                coloredCells += 1
            }
        }
        // If more than half the checked cells have colored backgrounds, it's likely a status bar
        return coloredCells > checkCols / 2
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
