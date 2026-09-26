import XCTest

/// Update von der Flutter-App: ein echter Flutter-Speicher (vom Dart-Code
/// geschrieben, test/interop/flutter_store_fixture_test.dart) liegt im
/// Container und im Schlüsselbund; die native App übernimmt ihn beim Start.
///
/// Läuft gegen einen Server im Speicher (`-KryptaOffline`), damit kein
/// Testkonto in Firebase entsteht.
final class MigrationUITests: XCTestCase {
    private var fixture: String {
        ProcessInfo.processInfo.environment["KRYPTA_FLUTTER_FIXTURE"]
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("KryptaCore/Tests/KryptaMessengerTests/Vectors/flutter_store.json").path
    }

    private func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testFlutterDataIsImported() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-KryptaSeedFlutter", fixture, "-KryptaOffline"]
        app.launch()

        // Der Chat aus der Flutter-App ist da, mit dem vergebenen Namen.
        let chat = app.staticTexts["Mami"].firstMatch
        XCTAssertTrue(chat.waitForExistence(timeout: 20))
        shot("30-migrated-chats")
        chat.tap()
        XCTAssertTrue(app.staticTexts["Nach dem Update"].exists || app.textFields["composer.field"].waitForExistence(timeout: 5))
        shot("31-migrated-chat")
    }

    /// Mitteilungen einschalten und die App verlassen. Die Mitteilung selbst
    /// schickt danach `xcrun simctl push` (siehe README, Abschnitt Push).
    func testEnableNotifications() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-KryptaSeedFlutter", fixture, "-KryptaOffline"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Mami"].firstMatch.waitForExistence(timeout: 20))

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        addUIInterruptionMonitor(withDescription: "Mitteilungen") { alert in
            for label in ["Erlauben", "Allow"] where alert.buttons[label].exists {
                alert.buttons[label].tap()
                return true
            }
            return false
        }

        app.buttons["Einstellungen"].firstMatch.tap()
        let toggle = app.switches["settings.push"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if (toggle.value as? String) != "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }
        for label in ["Erlauben", "Allow"] where springboard.buttons[label].waitForExistence(timeout: 3) {
            springboard.buttons[label].tap()
        }
        app.tap()
        sleep(1)
        shot("32-push-settings")
        XCUIDevice.shared.press(.home)
    }
}

/// Tresor-Passwort: festlegen, App verlassen, falsch, dann richtig.
final class VaultPasswordUITests: XCTestCase {
    func testVaultPasswordGuardsChats() {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KryptaCore/Tests/KryptaMessengerTests/Vectors/flutter_store.json").path
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-KryptaSeedFlutter", fixture, "-KryptaOffline"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Mami"].firstMatch.waitForExistence(timeout: 20))

        app.buttons["Einstellungen"].firstMatch.tap()
        let vault = app.buttons["settings.vault"].firstMatch
        XCTAssertTrue(app.navigationBars["Einstellungen"].waitForExistence(timeout: 5))
        for _ in 0..<4 where !vault.exists || !vault.isHittable { app.swipeUp() }
        vault.tap()
        let new = app.secureTextFields["vault.new"]
        XCTAssertTrue(new.waitForExistence(timeout: 5))
        new.tap()
        new.typeText("geheim123")
        let repeated = app.secureTextFields["vault.repeat"]
        repeated.tap()
        repeated.typeText("geheim123")
        app.buttons["vault.save"].tap()
        XCTAssertTrue(app.staticTexts["An"].waitForExistence(timeout: 10))

        // Verlassen und zurück: jetzt steht das Passwort davor.
        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()
        let field = app.secureTextFields["vault.password"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Mami"].exists)

        field.tap()
        field.typeText("falsch\n")
        XCTAssertTrue(app.staticTexts["Falsches Passwort."].waitForExistence(timeout: 10))

        // Nach dem ersten Fehler zwei Sekunden Pause.
        sleep(3)
        field.tap()
        field.typeText("geheim123\n")
        XCTAssertTrue(app.staticTexts["Mami"].firstMatch.waitForExistence(timeout: 15))
    }
}

/// Notfallknopf: kurzes Tippen löscht nichts, Halten löscht sofort alles.
final class EmergencyWipeUITests: XCTestCase {
    func testHoldingEmergencyButtonWipesEverything() {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("KryptaCore/Tests/KryptaMessengerTests/Vectors/flutter_store.json").path
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-KryptaSeedFlutter", fixture, "-KryptaOffline"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Mami"].firstMatch.waitForExistence(timeout: 20))

        let button = app.descendants(matching: .any)["emergency.wipe"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 5))
        button.tap()
        XCTAssertTrue(app.staticTexts["Gedrückt halten, um sofort alles zu löschen."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Mami"].firstMatch.exists, "Tippen allein löscht nichts")

        button.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.descendants(matching: .any)["emergency.wipe"].exists, "Kein Knopf in der Einrichtung")

        // Auch nach einem Neustart ist nichts mehr da.
        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(de)", "-KryptaOffline"]
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.continue"].waitForExistence(timeout: 20))
    }
}
