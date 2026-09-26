import XCTest

/// Einmal durch die ganze App: Einrichtung mit Tarnung, Chatliste,
/// Einstellungen, eigener Code, Sperren, Rechner, Entsperren.
///
/// Legt an jeder Station ein Bildschirmfoto ab, wenn KRYPTA_SHOTS gesetzt
/// ist (Verzeichnis auf dem Mac). Läuft gegen einen Server im Speicher
/// (`-KryptaOffline`) — es entsteht keine Kennung in CloudKit.
final class TourUITests: XCTestCase {
    private var app: XCUIApplication!
    private let code = "246810"
    private let deleteCode = "135790"

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

    private func typeCode(_ digits: String) {
        let field = app.textFields["passcode.field"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(digits)
    }

    func testTour() throws {
        app.launchArguments = ["-AppleLanguages", "(de)", "-KryptaOffline", "-KryptaReset"]
        app.launch()
        let next = app.buttons["onboarding.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        shot("01-welcome")
        next.tap()

        let vanish = app.buttons["onboarding.vanish.continue"]
        XCTAssertTrue(vanish.waitForExistence(timeout: 5))
        sleep(3)
        shot("01b-vanish")
        vanish.tap()

        XCTAssertTrue(app.buttons["onboarding.disguise.yes"].waitForExistence(timeout: 5))
        shot("02-disguise")
        app.buttons["onboarding.disguise.yes"].tap()

        typeCode(code)
        sleep(1)
        shot("03-secret-confirm")
        typeCode(code)
        sleep(1)
        shot("04-delete-code")
        typeCode(deleteCode)
        sleep(1)
        typeCode(deleteCode)

        let skip = app.buttons["onboarding.biometrics.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        shot("05-biometrics")
        skip.tap()

        let noPush = app.buttons["onboarding.notifications.skip"]
        XCTAssertTrue(noPush.waitForExistence(timeout: 5))
        shot("05b-notifications")
        noPush.tap()

        XCTAssertTrue(app.navigationBars["Chats"].waitForExistence(timeout: 30))
        sleep(2)
        shot("06-chats-empty")

        app.buttons["chats.new"].tap()
        XCTAssertTrue(app.navigationBars["Neuer Chat"].waitForExistence(timeout: 5))
        shot("07-new-chat")
        app.buttons["Meinen Code zeigen"].tap()
        sleep(1)
        shot("08-my-code")
        app.buttons["Fertig"].tap()
        app.buttons["Abbrechen"].tap()

        app.buttons["Einstellungen"].tap()
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        sleep(1)
        shot("09-settings")
        app.buttons["Fertig"].tap()

        // Sperren: in den Hintergrund und zurück — der Rechner erscheint.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(app.staticTexts["calculator.display"].waitForExistence(timeout: 5))
        for key in ["1", "2", "Plus", "3", "Mal", "4", "Ist gleich"] { app.buttons[key].tap() }
        sleep(1)
        shot("10-calculator")
        XCTAssertEqual(app.staticTexts["calculator.display"].label, "24")

        // Geheimcode + = öffnet Krypta.
        app.buttons["Alles löschen"].tap()
        for d in code { app.buttons[String(d)].tap() }
        app.buttons["Ist gleich"].tap()
        XCTAssertTrue(app.navigationBars["Chats"].waitForExistence(timeout: 15))
        shot("11-unlocked")

        // Geheimcode ändern: danach öffnet nur noch der neue.
        let newCode = "975310"
        app.buttons["Einstellungen"].tap()
        let change = app.buttons["Geheimcode ändern"]
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !change.exists || !change.isHittable { app.swipeUp() }
        XCTAssertTrue(change.waitForExistence(timeout: 5))
        change.tap()
        typeCode(deleteCode)
        typeCode(deleteCode)
        XCTAssertTrue(app.staticTexts["Der Löschcode muss sich vom Geheimcode unterscheiden."].waitForExistence(timeout: 5),
                      "Der Löschcode darf nicht zum Geheimcode werden")
        typeCode(newCode)
        typeCode(newCode)
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        shot("12-code-changed")
        app.buttons["Fertig"].tap()

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(app.staticTexts["calculator.display"].waitForExistence(timeout: 5))
        for d in code { app.buttons[String(d)].tap() }
        app.buttons["Ist gleich"].tap()
        sleep(2)
        XCTAssertFalse(app.navigationBars["Chats"].exists, "Der alte Geheimcode öffnet nicht mehr")
        app.buttons["Alles löschen"].tap()
        for d in newCode { app.buttons[String(d)].tap() }
        app.buttons["Ist gleich"].tap()
        XCTAssertTrue(app.navigationBars["Chats"].waitForExistence(timeout: 15))
    }
}
