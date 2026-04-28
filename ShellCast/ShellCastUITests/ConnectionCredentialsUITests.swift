import XCTest

final class ConnectionCredentialsUITests: XCTestCase {

    func testPasswordPersistsAfterSave() throws {
        let app = XCUIApplication()
        let uniqueHost = "host-\(UUID().uuidString.prefix(8)).local"
        let password = "secret123"

        app.launch()

        app.tabBars.buttons["Connections"].tap()
        app.buttons["Add"].tap()

        let hostField = app.textFields["connection-host-field"]
        XCTAssertTrue(hostField.waitForExistence(timeout: 2))
        hostField.tap()
        hostField.typeText(uniqueHost)

        let usernameField = app.textFields["connection-username-field"]
        usernameField.tap()
        usernameField.typeText("tester")

        let passwordField = app.secureTextFields["connection-password-field"]
        passwordField.tap()
        passwordField.typeText(password)

        app.buttons["connection-save-button"].tap()

        let notNowButton = app.buttons["Not Now"]
        if notNowButton.waitForExistence(timeout: 2) {
            notNowButton.tap()
        }

        XCTAssertTrue(app.staticTexts[uniqueHost].waitForExistence(timeout: 5))

        app.buttons["connection-row-\(uniqueHost)"].tap()

        let reopenedPasswordField = app.secureTextFields["connection-password-field"]
        XCTAssertTrue(reopenedPasswordField.waitForExistence(timeout: 2))

        let persistedValue = reopenedPasswordField.value as? String ?? ""
        XCTAssertFalse(persistedValue.isEmpty)
        XCTAssertNotEqual(persistedValue, "Password")
        XCTAssertTrue(persistedValue.contains("•") || persistedValue.contains("Secure"), "Unexpected secure field value: \(persistedValue)")
    }
}
