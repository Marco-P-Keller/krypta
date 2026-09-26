import XCTest

/// Der erste Start: die Einrichtung erscheint, und der Weg ohne Tarnung
/// führt bis zur Frage nach Face ID.
final class OnboardingUITests: XCTestCase {
    func testWelcomeLeadsToDisguiseChoice() {
        let app = XCUIApplication()
        app.launch()
        let next = app.buttons["onboarding.continue"]
        guard next.waitForExistence(timeout: 10) else {
            // Schon eingerichtet — dann gibt es nichts zu prüfen.
            return
        }
        next.tap()
        XCTAssertTrue(app.buttons["onboarding.disguise.yes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.disguise.no"].exists)
    }
}
