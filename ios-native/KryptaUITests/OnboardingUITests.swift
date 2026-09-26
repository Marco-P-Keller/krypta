import XCTest

/// Der erste Start: die Einrichtung erscheint, und der Weg ohne Tarnung
/// führt bis zur Frage nach Face ID.
final class OnboardingUITests: XCTestCase {
    func testWelcomeLeadsToDisguiseChoice() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(de)", "-KryptaOffline", "-KryptaReset"]
        app.launch()
        let next = app.buttons["onboarding.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        next.tap()
        XCTAssertTrue(app.buttons["onboarding.disguise.yes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["onboarding.disguise.no"].exists)
    }
}
