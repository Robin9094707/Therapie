import XCTest

final class TherapieUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    func testNativeViewportAndNavigation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--show-dashboard"]
        app.launch()
        let viewport = app.staticTexts["therapy.viewport"]
        XCTAssertTrue(viewport.waitForExistence(timeout: 15))
        let screen = app.windows.firstMatch.frame
        XCTAssertEqual(viewport.label, "\(Int(screen.width))x\(Int(screen.height))",
                       "The SwiftUI viewport must fill the native iPhone window, including safe areas.")
        XCTAssertGreaterThan(screen.height, 700, "A modern iPhone must not use a legacy 480/568-point viewport.")
        capture("Dashboard portrait")
        for tab in ["Stimmung", "Kalender", "Archiv", "Profil"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 5))
            button.tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: button)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 10), .completed)
            capture(tab)
        }
        app.tabBars.buttons["Heute"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(viewport.waitForExistence(timeout: 5))
        let rotation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.windows.firstMatch.frame.width > app.windows.firstMatch.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotation], timeout: 10), .completed)
        let rotated = app.windows.firstMatch.frame
        XCTAssertTrue(waitForViewport(viewport, width: Int(rotated.width), height: Int(rotated.height)))
        capture("Dashboard landscape")
    }

    @MainActor
    func testOnboardingAndLargeText() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--large-text"]
        app.launch()
        let name = app.textFields["onboarding.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 15))
        let start = app.buttons["Therapiebegleiter starten"]
        XCTAssertFalse(start.isEnabled)
        name.tap()
        name.typeText("Robin")
        for _ in 0..<4 where !start.isHittable { app.swipeUp() }
        XCTAssertTrue(start.isEnabled)
        capture("Onboarding large text")
        start.tap()
        XCTAssertTrue(app.tabBars.buttons["Heute"].waitForExistence(timeout: 10))
        capture("Dashboard large text")
    }

    private func waitForViewport(_ element: XCUIElement, width: Int, height: Int) -> Bool {
        let predicate = NSPredicate(format: "label == %@", "\(width)x\(height)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
