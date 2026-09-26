import XCTest

/// Der Chat im Demo-Modus (zweiter Messenger im selben Prozess, kein Netz).
final class ConversationUITests: XCTestCase {
    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["KRYPTA_SHOTS"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    func testDemoConversation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-KryptaDemo"]
        app.launch()

        let lena = app.staticTexts["Lena"].firstMatch
        XCTAssertTrue(lena.waitForExistence(timeout: 20))
        sleep(1)
        shot("20-chats")

        lena.tap()
        XCTAssertTrue(app.textFields["composer.field"].waitForExistence(timeout: 5))
        sleep(1)
        shot("21-conversation")

        // Passwort-Nachricht entsperren.
        app.buttons["Kontakt: Geschützte Nachricht"].tap()
        let field = app.secureTextFields["Passwort"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("blau")
        app.buttons["Entsperren"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["Kontakt: Der Code für die Tür"].waitForExistence(timeout: 5))

        // Schreiben mit Option.
        app.buttons["Nachrichtenoptionen"].tap()
        app.buttons["Nach dem Ansehen löschen"].tap()
        let composer = app.textFields["composer.field"]
        composer.tap()
        composer.typeText("Bis gleich!")
        sleep(1)
        shot("22-composer")
        app.buttons["composer.send"].tap()
        sleep(2)
        shot("23-sent")

        app.buttons["Kontaktinfo für Lena"].tap()
        sleep(1)
        shot("24-contact")
    }
}
