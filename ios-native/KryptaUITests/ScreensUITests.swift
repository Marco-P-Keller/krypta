import XCTest

/// Bildschirmfotos aller wichtigen Seiten im Demo-Modus, für die Durchsicht
/// des Designs. Der Screenshot-Schutz ist dafür aus (`-shield.off YES`
/// setzt den Schalter nur für diesen Start).
///
/// Ablage: KRYPTA_SHOTS (Verzeichnis auf dem Mac), sonst nur als Anhang.
/// Dunkel: vorher `xcrun simctl ui booted appearance dark` und
/// KRYPTA_SHOT_PREFIX=d setzen.
final class ScreensUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = ProcessInfo.processInfo.environment["KRYPTA_SHOTS"] {
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }

    func testScreens() {
        let p = ProcessInfo.processInfo.environment["KRYPTA_SHOT_PREFIX"] ?? "l"
        app.launchArguments = ["-AppleLanguages", "(de)", "-KryptaDemo", "-shield.off", "YES"]
        app.launch()

        let lena = app.staticTexts["Lena"].firstMatch
        XCTAssertTrue(lena.waitForExistence(timeout: 20))
        sleep(1)
        shot("\(p)01-chats")

        lena.tap()
        XCTAssertTrue(app.textFields["composer.field"].waitForExistence(timeout: 5))
        sleep(1)
        shot("\(p)02-conversation")

        app.buttons["Nachrichtenoptionen"].tap()
        sleep(1)
        shot("\(p)03-options")
        app.buttons["Nach dem Ansehen löschen"].tap()
        let composer = app.textFields["composer.field"]
        composer.tap()
        composer.typeText("Bis gleich!")
        sleep(1)
        shot("\(p)04-composer")
        app.buttons["composer.send"].tap()
        sleep(2)
        app.swipeDown()
        sleep(1)
        shot("\(p)05-sent")

        app.buttons["Kontaktinfo für Lena"].tap()
        sleep(1)
        shot("\(p)06-contact")
        app.swipeUp()
        sleep(1)
        shot("\(p)07-contact-bottom")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)

        app.staticTexts["Kontaktanfragen"].tap()
        sleep(1)
        shot("\(p)08-requests")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        sleep(1)

        app.buttons["Einstellungen"].tap()
        sleep(1)
        shot("\(p)09-settings")
        app.swipeUp()
        sleep(1)
        shot("\(p)10-settings-bottom")
    }
}
