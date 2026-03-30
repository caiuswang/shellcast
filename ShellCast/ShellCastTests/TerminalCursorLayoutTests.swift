import XCTest
import SwiftTerm
@testable import ShellCast

// MARK: - Mock Transport

/// A fake transport that lets tests feed data into the terminal and inspect resize calls.
private final class MockTransportSession: TransportSession {
    private let continuation: AsyncStream<Data>.Continuation
    let outputStream: AsyncStream<Data>

    var isConnected: Bool = true
    var needsDeferredStart: Bool = false

    /// Tracks resize calls so tests can verify dimensions.
    var lastResizeCols: Int?
    var lastResizeRows: Int?

    init() {
        var cont: AsyncStream<Data>.Continuation!
        outputStream = AsyncStream { cont = $0 }
        continuation = cont
    }

    /// Feed raw bytes into the terminal as if they came from a remote server.
    func feedData(_ string: String) {
        continuation.yield(Data(string.utf8))
    }

    func send(_ data: Data) async throws {}

    func resize(cols: Int, rows: Int) async throws {
        lastResizeCols = cols
        lastResizeRows = rows
    }

    func disconnect() async {
        isConnected = false
        continuation.finish()
    }
}

// MARK: - Helper to build a windowed TerminalViewController

/// Embeds a TerminalViewController in a real UIWindow with iPhone-like dimensions
/// and triggers the full lifecycle (viewDidLoad → viewDidAppear).
/// `safeAreaTop` is simulated via an additional container VC with additionalSafeAreaInsets.
@MainActor
private func makeWindowedTerminalVC(
    transport: MockTransportSession,
    width: CGFloat = 393,
    height: CGFloat = 852,
    safeAreaTop: CGFloat = 59
) -> (UIWindow, TerminalViewController, TerminalBridge) {
    let bridge = TerminalBridge(transport: transport)
    let termVC = TerminalViewController(bridge: bridge)

    // Wrap in a container so we can inject safe area insets (simulator windows have 0 insets).
    let container = UIViewController()
    container.addChild(termVC)
    container.view.addSubview(termVC.view)
    termVC.view.frame = container.view.bounds
    termVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    termVC.didMove(toParent: container)
    container.additionalSafeAreaInsets = UIEdgeInsets(top: safeAreaTop, left: 0, bottom: 0, right: 0)

    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: height))
    window.rootViewController = container
    window.makeKeyAndVisible()

    container.view.setNeedsLayout()
    container.view.layoutIfNeeded()
    termVC.view.setNeedsLayout()
    termVC.view.layoutIfNeeded()

    // Trigger viewDidAppear so resizeTerminal runs
    termVC.beginAppearanceTransition(true, animated: false)
    termVC.endAppearanceTransition()

    return (window, termVC, bridge)
}


// MARK: - Tests

/// Tests that the terminal view layout accounts for safe area insets,
/// ensuring the cursor renders at the correct position (not on the tmux status bar).
@MainActor
final class TerminalCursorLayoutTests: XCTestCase {

    // MARK: - Constraint Tests

    /// Verify the terminal view's top is constrained to the safe area, not the raw view top.
    func testTerminalViewTopIsConstrainedToSafeArea() {
        let transport = MockTransportSession()
        let (window, vc, _) = makeWindowedTerminalVC(transport: transport)
        _ = window // keep alive

        let terminalView = vc.view.subviews.first { $0 is ShellCastTerminalView }
        XCTAssertNotNil(terminalView, "Terminal view should exist in the hierarchy")
        guard let terminalView else { return }

        let topConstraints = vc.view.constraints.filter { constraint in
            let involvesTerminalTop =
                (constraint.firstItem as? UIView === terminalView && constraint.firstAttribute == .top) ||
                (constraint.secondItem as? UIView === terminalView && constraint.secondAttribute == .top)
            let involvesSafeArea =
                (constraint.firstItem is UILayoutGuide) ||
                (constraint.secondItem is UILayoutGuide)
            return involvesTerminalTop && involvesSafeArea
        }

        XCTAssertFalse(topConstraints.isEmpty,
                       "Terminal view top must be constrained to safe area layout guide")
    }

    // MARK: - Terminal Dimensions with Safe Area

    /// After viewDidAppear, the terminal rows should reflect the visible area only (minus safe area).
    func testTerminalRowsAccountForSafeArea() {
        let transport = MockTransportSession()
        let safeAreaTop: CGFloat = 59
        let (window, vc, bridge) = makeWindowedTerminalVC(transport: transport, safeAreaTop: safeAreaTop)
        _ = window

        guard let terminalView = bridge.terminalView else {
            XCTFail("Bridge should have a terminalView after viewDidAppear")
            return
        }

        let terminal = terminalView.getTerminal()
        let rows = terminal.rows
        let cols = terminal.cols

        XCTAssertGreaterThan(rows, 0, "Terminal should have rows")
        XCTAssertGreaterThan(cols, 0, "Terminal should have cols")

        // Verify that the row count fits within the visible area (not the full view height).
        // Visible height = view.height - toolbar(44) - safeAreaTop
        let viewHeight = vc.view.bounds.height
        let visibleHeight = viewHeight - 44 - safeAreaTop

        // Get cell height from the terminal view
        let optimalFrame = terminalView.getOptimalFrameSize()
        guard terminal.cols > 0, terminal.rows > 0 else { return }
        let cellHeight = optimalFrame.height / CGFloat(terminal.rows)

        // rows * cellHeight should fit within visibleHeight
        let totalRowHeight = CGFloat(rows) * cellHeight
        XCTAssertLessThanOrEqual(totalRowHeight, visibleHeight + cellHeight,
                                 "Total row height (\(totalRowHeight)) should not exceed visible area (\(visibleHeight))")

        // The row count should NOT fill the full view height (which would include the safe area)
        let fullHeightRows = Int((viewHeight - 44) / cellHeight)
        XCTAssertLessThan(rows, fullHeightRows,
                          "Terminal rows (\(rows)) must be less than full-height rows (\(fullHeightRows)) due to safe area")
    }

    // MARK: - Cursor Position After Tmux Output

    /// Feed tmux-like terminal output and verify the cursor is in the content area, not on the status bar.
    func testCursorPositionAfterTmuxOutput() {
        let transport = MockTransportSession()
        let (window, vc, bridge) = makeWindowedTerminalVC(transport: transport, safeAreaTop: 59)
        _ = window

        guard let terminalView = bridge.terminalView else {
            XCTFail("Bridge should have a terminalView")
            return
        }

        let terminal = terminalView.getTerminal()
        let rows = terminal.rows
        let cols = terminal.cols
        guard rows > 5 && cols > 10 else {
            XCTFail("Terminal too small: \(cols)x\(rows)")
            return
        }

        // Build tmux-like output:
        // 1. Clear screen
        // 2. Write some content lines (simulating shell output)
        // 3. Write a tmux status bar on the last row
        // 4. Position cursor back at the shell prompt (row rows-2)
        var output = ""

        // Clear screen and home cursor
        output += "\u{1b}[2J\u{1b}[H"

        // Write some shell output lines
        for i in 1...5 {
            output += "output line \(i)\r\n"
        }

        // Shell prompt
        let promptRow = 7  // line after 5 output lines + 1 blank
        output += "user@host:~$ "

        // Save cursor position
        output += "\u{1b}[s"

        // Move to last row and write tmux status bar
        output += "\u{1b}[\(rows);1H"  // move to last row
        output += "\u{1b}[7m"           // reverse video (tmux status bar style)
        let statusBar = "[0] 0:fish  1:vim* 2:logs".padding(toLength: cols, withPad: " ", startingAt: 0)
        output += statusBar
        output += "\u{1b}[0m"           // reset attributes

        // Restore cursor to prompt position
        output += "\u{1b}[u"

        // Feed into the terminal
        terminalView.feed(text: output)
        terminalView.setNeedsDisplay()

        // Now check cursor position
        let cursorRow = terminal.buffer.y    // 0-indexed row in active buffer
        let cursorCol = terminal.buffer.x    // 0-indexed col

        // Cursor should be at the prompt row, NOT on the last row (tmux status bar)
        let lastRow = rows - 1
        XCTAssertNotEqual(cursorRow, lastRow,
                          "Cursor should NOT be on the tmux status bar (last row \(lastRow))")
        XCTAssertLessThan(cursorRow, lastRow,
                          "Cursor row (\(cursorRow)) should be above the status bar row (\(lastRow))")
        XCTAssertGreaterThan(cursorCol, 0,
                             "Cursor should be after the prompt text, not at column 0")

        print("[TEST] Terminal: \(cols)x\(rows), cursor at row=\(cursorRow) col=\(cursorCol), statusBar at row=\(lastRow)")
    }

    // MARK: - Rows Mismatch Regression

    /// Verifies the old bug: without safe area subtraction, the terminal would report
    /// more rows than visible, causing cursor/content misalignment.
    func testSafeAreaRowsMismatchRegression() {
        let transport1 = MockTransportSession()
        let transport2 = MockTransportSession()

        // Create two terminals: one with safe area = 0, one with safe area = 59
        let (w1, _, bridge1) = makeWindowedTerminalVC(transport: transport1, safeAreaTop: 0)
        let (w2, _, bridge2) = makeWindowedTerminalVC(transport: transport2, safeAreaTop: 59)
        _ = w1; _ = w2

        guard let tv1 = bridge1.terminalView, let tv2 = bridge2.terminalView else {
            XCTFail("Both terminals should have views")
            return
        }

        let rows1 = tv1.getTerminal().rows  // no safe area
        let rows2 = tv2.getTerminal().rows  // with 59pt safe area

        XCTAssertGreaterThan(rows1, rows2,
                             "Terminal with no safe area (\(rows1) rows) should have more rows than one with 59pt safe area (\(rows2) rows)")

        let difference = rows1 - rows2
        XCTAssertGreaterThanOrEqual(difference, 2,
                                    "Safe area of 59pt should remove at least 2-3 rows (got \(difference))")

        print("[TEST] Rows without safe area: \(rows1), with 59pt safe area: \(rows2), difference: \(difference)")
    }

    // MARK: - Full Connection Simulation

    /// Simulates the full flow: create transport → enter terminal → feed data → verify cursor.
    /// This is the closest to a real Mosh/SSH session without network access.
    func testFullSessionFlowCursorNotOnStatusBar() {
        let transport = MockTransportSession()
        transport.needsDeferredStart = true  // simulate Mosh behavior

        let (window, vc, bridge) = makeWindowedTerminalVC(transport: transport, safeAreaTop: 59)
        _ = window

        guard let terminalView = bridge.terminalView else {
            XCTFail("Missing terminalView")
            return
        }

        let terminal = terminalView.getTerminal()
        let rows = terminal.rows
        let cols = terminal.cols

        // Simulate what mosh/tmux would send after connection:
        // 1. tmux fills the screen with pane content
        // 2. tmux draws its status bar on the last line
        // 3. Cursor is placed at the shell prompt in the active pane

        var output = "\u{1b}[2J\u{1b}[H"  // clear + home

        // Fill most of the screen with content (simulating scrollback)
        let contentRows = rows - 2  // leave room for prompt + status bar
        for i in 1...contentRows {
            if i < contentRows {
                output += "content line \(i)\r\n"
            } else {
                // This is the prompt line
                output += "$ "
            }
        }

        // Save cursor at prompt
        let promptRow = contentRows  // 1-indexed
        output += "\u{1b}[s"

        // Draw tmux status bar at the very last row
        output += "\u{1b}[\(rows);1H"
        output += "\u{1b}[30;42m"  // green background (tmux style)
        let bar = "[0] bash".padding(toLength: cols, withPad: " ", startingAt: 0)
        output += bar
        output += "\u{1b}[0m"

        // Restore cursor to prompt
        output += "\u{1b}[u"

        terminalView.feed(text: output)

        // Verify cursor
        let cursorRow = terminal.buffer.y
        let lastRow = rows - 1

        XCTAssertNotEqual(cursorRow, lastRow,
                          "REGRESSION: Cursor is on the tmux status bar row (\(lastRow))! " +
                          "This was the original bug — safe area not accounted for in row calculation.")

        // Verify cursor is in the content area
        XCTAssertLessThan(cursorRow, lastRow,
                          "Cursor (row \(cursorRow)) must be above status bar (row \(lastRow))")

        // Verify the terminal didn't get too many rows (the root cause)
        // With safe area = 59pt, the terminal should have fewer rows than the full height would allow
        let optimalFrame = terminalView.getOptimalFrameSize()
        let cellHeight = optimalFrame.height / CGFloat(rows)
        let fullHeightRows = Int((vc.view.bounds.height - 44) / cellHeight)

        XCTAssertLessThan(rows, fullHeightRows,
                          "Terminal must not use full view height — safe area must be subtracted. " +
                          "Got \(rows) rows but full height would give \(fullHeightRows)")

        print("[TEST] Full session: \(cols)x\(rows), cursor at row \(cursorRow), status bar at row \(lastRow)")
        print("[TEST] Correct rows=\(rows) vs full-height rows=\(fullHeightRows) (diff=\(fullHeightRows - rows))")
    }

    // MARK: - Mosh-Style Rendering Tests

    /// Mosh does NOT use cursor save/restore (DECSC/DECRC or CSI s/u).
    /// Instead it: hides cursor → paints cells with CUP → sets cursor via CUP → shows cursor.
    /// Test that SwiftTerm handles this correctly.
    func testMoshStyleRendering_CursorAfterStatusBar() {
        let transport = MockTransportSession()
        let (window, _, bridge) = makeWindowedTerminalVC(transport: transport, safeAreaTop: 59)
        _ = window

        guard let terminalView = bridge.terminalView else {
            XCTFail("Missing terminalView"); return
        }

        let terminal = terminalView.getTerminal()
        let rows = terminal.rows
        let cols = terminal.cols
        guard rows > 5, cols > 10 else {
            XCTFail("Terminal too small"); return
        }

        // Simulate mosh Display::new_frame rendering:
        // 1. Hide cursor
        // 2. Paint content with CUP (last thing painted is status bar on last row)
        // 3. Move cursor to prompt position with CUP
        // 4. Show cursor
        var output = ""

        // Step 1: Hide cursor (CSI ?25l)
        output += "\u{1b}[?25l"

        // Step 2: Paint the screen using CUP for each row
        // Paint shell content
        for row in 1...5 {
            output += "\u{1b}[\(row);1H"  // CUP to row
            output += "content line \(row)"
        }

        // Paint prompt on row 7
        let promptRow = 7
        output += "\u{1b}[\(promptRow);1H"
        output += "user@host:~$ "

        // Paint tmux status bar on LAST row (this is painted LAST by mosh)
        output += "\u{1b}[\(rows);1H"
        output += "\u{1b}[30;42m"  // green bg
        let bar = "[0] 0:fish  1:vim*".padding(toLength: cols, withPad: " ", startingAt: 0)
        output += bar
        output += "\u{1b}[0m"

        // Step 3: Move cursor to prompt position (CUP) — THIS IS THE KEY
        output += "\u{1b}[\(promptRow);14H"  // after "user@host:~$ "

        // Step 4: Show cursor (CSI ?25h)
        output += "\u{1b}[?25h"

        terminalView.feed(text: output)

        let cursorRow = terminal.buffer.y
        let cursorCol = terminal.buffer.x
        let lastRow = rows - 1

        XCTAssertEqual(cursorRow, promptRow - 1,  // 0-indexed
                       "Cursor should be at prompt row \(promptRow-1) but is at \(cursorRow)")
        XCTAssertNotEqual(cursorRow, lastRow,
                          "Cursor should NOT be on status bar (row \(lastRow))")

        print("[TEST-MOSH] cursor=(\(cursorCol),\(cursorRow)) expected prompt row=\(promptRow-1) statusBar=\(lastRow)")
    }

    /// Test the mosh cursor fix: when mosh omits the final CUP, the bridge
    /// should detect the cursor on the status bar and reposition it.
    func testMoshCursorFix_RepositionFromStatusBar() {
        let transport = MockTransportSession()
        transport.needsDeferredStart = true  // mark as mosh

        let (window, _, bridge) = makeWindowedTerminalVC(transport: transport, safeAreaTop: 59)
        _ = window

        guard let terminalView = bridge.terminalView else {
            XCTFail("Missing terminalView"); return
        }

        let terminal = terminalView.getTerminal()
        let rows = terminal.rows
        let cols = terminal.cols
        guard rows > 5, cols > 10 else {
            XCTFail("Terminal too small"); return
        }

        // Step 1: Feed initial content where cursor is at the prompt (row 7, after "$ ")
        var setup = "\u{1b}[2J\u{1b}[H"
        for row in 1...5 {
            setup += "\u{1b}[\(row);1H"
            setup += "content line \(row)"
        }
        setup += "\u{1b}[7;1H"
        setup += "user@host:~$ "

        // Also paint a status bar with colored bg on last row
        setup += "\u{1b}[\(rows);1H"
        setup += "\u{1b}[30;42m"  // green bg (tmux style)
        let bar = "[0] 0:fish  1:vim*".padding(toLength: cols, withPad: " ", startingAt: 0)
        setup += bar
        setup += "\u{1b}[0m"

        // Position cursor at prompt (this is the "good" state)
        setup += "\u{1b}[7;14H"
        terminalView.feed(text: setup)

        // Verify cursor is at prompt
        XCTAssertEqual(terminal.buffer.y, 6, "Cursor should be at prompt row")
        let savedRow = terminal.buffer.y
        let savedCol = terminal.buffer.x

        // Register this as the "good" cursor position via the bridge's fix logic
        bridge.fixMoshCursorPosition()

        // Step 2: Simulate mosh update that paints status bar LAST without final CUP.
        // The bridge's fixMoshCursorPosition should detect and fix this.
        var buggyUpdate = ""
        buggyUpdate += "\u{1b}[?25l"

        // Repaint the status bar (cursor ends up here)
        buggyUpdate += "\u{1b}[\(rows);1H"
        buggyUpdate += "\u{1b}[30;42m"
        buggyUpdate += bar
        buggyUpdate += "\u{1b}[0m"

        // NO final CUP — this is the mosh bug
        buggyUpdate += "\u{1b}[?25h"

        // Feed through the bridge's data path (which includes the cursor fix)
        // We simulate what startReading does: feed + fixMoshCursorPosition
        terminalView.feed(text: buggyUpdate)

        // Without the fix, cursor would be on lastRow.
        // Verify it's on the status bar before fix
        let beforeFix = terminal.buffer.y
        print("[TEST-FIX] Before fix: cursor row=\(beforeFix) (status bar=\(rows-1))")

        // Now apply the fix (same logic as in startReading)
        bridge.fixMoshCursorPosition()

        let afterFix = terminal.buffer.y
        let afterFixCol = terminal.buffer.x

        print("[TEST-FIX] After fix: cursor row=\(afterFix) col=\(afterFixCol)")
        print("[TEST-FIX] Expected: row=\(savedRow) col=\(savedCol)")

        XCTAssertNotEqual(afterFix, rows - 1,
                          "After fix, cursor should NOT be on status bar")
        XCTAssertEqual(afterFix, savedRow,
                       "Cursor should be restored to last known content row (\(savedRow))")
    }

    /// Test mosh output split across multiple chunks (simulating pipe reads).
    /// Cursor positioning command might be in a separate chunk.
    func testMoshStyleRendering_SplitChunks() {
        let transport = MockTransportSession()
        let (window, _, bridge) = makeWindowedTerminalVC(transport: transport, safeAreaTop: 59)
        _ = window

        guard let terminalView = bridge.terminalView else {
            XCTFail("Missing terminalView"); return
        }

        let terminal = terminalView.getTerminal()
        let rows = terminal.rows
        let cols = terminal.cols
        guard rows > 5, cols > 10 else {
            XCTFail("Terminal too small"); return
        }

        // Chunk 1: hide cursor + paint content + paint status bar
        var chunk1 = ""
        chunk1 += "\u{1b}[?25l"
        for row in 1...5 {
            chunk1 += "\u{1b}[\(row);1H"
            chunk1 += "content line \(row)"
        }
        chunk1 += "\u{1b}[7;1H"
        chunk1 += "user@host:~$ "
        chunk1 += "\u{1b}[\(rows);1H"
        let bar = "[0] bash".padding(toLength: cols, withPad: " ", startingAt: 0)
        chunk1 += bar

        // Feed chunk 1 — cursor is now on status bar
        terminalView.feed(text: chunk1)
        let afterChunk1 = terminal.buffer.y
        print("[TEST-SPLIT] After chunk1: cursor row=\(afterChunk1) (should be on status bar \(rows-1))")

        // Chunk 2: reposition cursor + show cursor
        var chunk2 = ""
        chunk2 += "\u{1b}[7;14H"   // CUP to prompt position
        chunk2 += "\u{1b}[?25h"    // show cursor

        // Feed chunk 2 — cursor should now be at prompt
        terminalView.feed(text: chunk2)
        let afterChunk2 = terminal.buffer.y

        XCTAssertEqual(afterChunk2, 6,  // row 7 is 0-indexed as 6
                       "After chunk2, cursor should be at prompt row 6 but is at \(afterChunk2)")
        XCTAssertNotEqual(afterChunk2, rows - 1,
                          "Cursor should NOT still be on status bar after repositioning")

        print("[TEST-SPLIT] After chunk2: cursor row=\(afterChunk2) (should be at prompt row 6)")
    }
}
