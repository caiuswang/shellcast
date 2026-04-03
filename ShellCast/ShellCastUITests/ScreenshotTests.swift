import XCTest

final class ScreenshotTests: XCTestCase {

    let app = XCUIApplication()
    let screenshotDir = "/Users/taowang/shellcast-website/images"

    override func setUpWithError() throws {
        continueAfterFailure = true
        app.launch()
        sleep(2)
    }

    /// Basic screenshots without connection
    func testTakeAllScreenshots() throws {
        // 1. History tab (default screen)
        saveScreenshot(name: "home")

        // 2. Connections tab
        app.tabBars.buttons["Connections"].tap()
        sleep(1)
        saveScreenshot(name: "connections")

        // 3. Edit connection - tap pencil button
        app.buttons["Edit"].tap()
        sleep(1)
        saveScreenshot(name: "edit-connection")
        if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        // 4. New connection via + button
        app.buttons["Add"].tap()
        sleep(1)
        saveScreenshot(name: "new-connection")
        if app.navigationBars.buttons.firstMatch.exists {
            app.navigationBars.buttons.firstMatch.tap()
            sleep(1)
        }

        // 5. Settings tab
        app.tabBars.buttons["Settings"].tap()
        sleep(1)
        saveScreenshot(name: "settings")
    }

    /// Connect to local server and capture tmux/AI agent browser
    /// Run this after manually saving valid credentials in the app
    func testCaptureConnectedScreenshots() throws {
        // Go to Connections tab
        app.tabBars.buttons["Connections"].tap()
        sleep(1)

        // Tap the connection row to connect
        let connectionRow = app.staticTexts["Local"]
        XCTAssertTrue(connectionRow.exists, "No 'Local' connection found")
        connectionRow.tap()

        // Wait for tmux browser to appear (longer wait for SSH handshake)
        sleep(10)

        // Dismiss error if connection failed
        let okButton = app.buttons["OK"]
        if okButton.exists {
            XCTFail("Connection failed - ensure valid credentials are saved")
            okButton.tap()
            return
        }

        // Capture tmux browser (Tmux tab)
        saveScreenshot(name: "tmux-browser")

        // Dump all visible elements for debugging
        let allButtons = app.buttons.allElementsBoundByIndex
        for (i, btn) in allButtons.enumerated() {
            print("CONNECTED_BUTTON[\(i)]: label='\(btn.label)' id='\(btn.identifier)'")
        }

        // Try Claude tab (dynamic AI agent tab)
        let claudeTab = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] 'Claude'")).firstMatch
        if claudeTab.exists {
            claudeTab.tap()
            sleep(2)
            saveScreenshot(name: "claude-tmux")
        }

        // Try OpenCode tab
        let openCodeTab = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] 'OpenCode'")).firstMatch
        if openCodeTab.exists {
            openCodeTab.tap()
            sleep(2)
            saveScreenshot(name: "opencode-tmux")
        }

        // Try Kimi tab
        let kimiTab = app.buttons.matching(NSPredicate(format: "label CONTAINS[cd] 'Kimi'")).firstMatch
        if kimiTab.exists {
            kimiTab.tap()
            sleep(2)
            saveScreenshot(name: "kimi-tmux")
        }

        // Go back to Tmux tab
        let tmuxTab = app.buttons.matching(NSPredicate(format: "label == 'Tmux'")).firstMatch
        if tmuxTab.exists {
            tmuxTab.tap()
            sleep(1)
        }
    }

    private func saveScreenshot(name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let data = screenshot.pngRepresentation
        try? data.write(to: URL(fileURLWithPath: "\(screenshotDir)/\(name).png"))
    }
}
