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
        for tab in ["Insights", "Therapie", "Archiv", "Profil"] {
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

    @MainActor
    func testCheckInTaskRemovalWithKeyboardAndMultipleRows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--show-dashboard", "--show-checkin-tasks"]
        app.launch()
        let count = app.staticTexts["checkin.tasks.count"]
        XCTAssertTrue(count.waitForExistence(timeout: 15))
        let add = app.buttons["checkin.task.add"]
        let fields = app.textFields.matching(NSPredicate(format: "identifier BEGINSWITH %@", "checkin.task.title."))
        let removeButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "checkin.task.remove."))
        func tapVisible(_ element: XCUIElement) {
            if !element.isHittable { for _ in 0..<4 { app.swipeDown() } }
            for _ in 0..<10 where !element.isHittable { app.swipeUp() }
            XCTAssertTrue(element.isHittable); element.tap()
        }
        tapVisible(add)
        let first = fields.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 5)); tapVisible(first); first.typeText("Aus Versehen")
        tapVisible(removeButtons.firstMatch)
        XCTAssertTrue(count.waitForExistence(timeout: 5)); XCTAssertEqual(count.label, "0 Aufgaben")
        tapVisible(add)
        let firstID = fields.firstMatch.identifier
        tapVisible(add)
        let twoTasks = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "2 Aufgaben"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [twoTasks], timeout: 5), .completed)
        // Scroll views can omit off-screen accessibility fields; locate rows by identity.
        let second = fields.matching(NSPredicate(format: "identifier != %@", firstID)).firstMatch
        for _ in 0..<8 where !second.exists { app.swipeUp() }
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        let remainingID = second.identifier
        let firstRemovalID = firstID.replacingOccurrences(of: "checkin.task.title.", with: "checkin.task.remove.")
        tapVisible(app.buttons[firstRemovalID])
        XCTAssertEqual(fields.count, 1)
        XCTAssertEqual(fields.firstMatch.identifier, remainingID)
        tapVisible(fields.firstMatch); fields.firstMatch.typeText("Bleibt erhalten")
        tapVisible(removeButtons.firstMatch)
        XCTAssertEqual(count.label, "0 Aufgaben")
        tapVisible(add); tapVisible(removeButtons.firstMatch)
        XCTAssertEqual(count.label, "0 Aufgaben")
        capture("Check-in tasks removed safely")
        app.buttons["Schließen"].tap()
        XCTAssertTrue(app.tabBars.buttons["Heute"].waitForExistence(timeout: 5))
        let resume = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Morgen-Check-in fortsetzen")).firstMatch
        tapVisible(resume)
        XCTAssertTrue(count.waitForExistence(timeout: 5)); XCTAssertEqual(count.label, "0 Aufgaben")
    }

    @MainActor
    func testSavedCheckInOpensReadOnlyAndEditsExplicitly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--show-dashboard", "--show-saved-checkin"]
        app.launch()
        let edit = app.buttons["checkin.detail.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 15))
        XCTAssertEqual(app.textFields.count, 0, "Viewing a saved check-in must not open editable input fields.")
        XCTAssertEqual(app.sliders.count, 0)
        XCTAssertTrue(app.staticTexts["Mein gespeicherter Rückblick"].exists)
        capture("Saved check-in read-only overview")
        edit.tap()
        let text = app.textFields["Ein Gedanke zum Einstieg"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        text.tap(); text.typeText(" Ergänzt")
        let editedText = try XCTUnwrap(text.value as? String)
        XCTAssertNotEqual(editedText, "Mein gespeicherter Rückblick")
        XCTAssertTrue(editedText.contains("Ergänzt"))
        app.buttons["checkin.keyboard.done"].tap()
        let progress = app.staticTexts["checkin.step"]
        for next in 2...8 {
            app.buttons["Weiter"].tap()
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "\(next) / 8"), object: progress)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
        }
        XCTAssertTrue(app.buttons["Check-in speichern"].waitForExistence(timeout: 5))
        app.buttons["Check-in speichern"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[editedText].waitForExistence(timeout: 5), "The exact edited text must appear in the overview, regardless of caret position.")
        XCTAssertEqual(app.textFields.count, 0)
        capture("Updated saved check-in overview")
    }

    @MainActor
    func testNoteAttachmentsKeepParentOpenAndReopenReadOnly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--show-dashboard", "--show-note"]
        app.launch()
        let attach = app.buttons["note.attach.audio"]
        XCTAssertTrue(app.buttons["Speichern"].waitForExistence(timeout: 15))
        reveal(attach, in: app)
        for _ in 0..<3 {
            attach.tap()
            let close = app.buttons["audio.record.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["audio.record.toggle"].exists)
            close.tap()
            XCTAssertTrue(app.buttons["Speichern"].waitForExistence(timeout: 5), "Only the recorder closes; the unsaved parent note stays open.")
            reveal(attach, in: app)
        }
        for id in ["22222222-2222-2222-2222-222222222222", "33333333-3333-3333-3333-333333333333"] {
            let archive = app.buttons["note.attach.archive"]
            reveal(archive, in: app); archive.tap()
            let choose = app.buttons["note.archive.choose." + id]
            XCTAssertTrue(choose.waitForExistence(timeout: 5)); choose.tap()
            let open = app.buttons["note.attachment.open." + id]
            reveal(open, in: app); open.tap()
            let close = app.buttons["media.detail.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            if id.hasPrefix("333") { XCTAssertTrue(app.buttons["media.audio.play"].exists) }
            capture("Note attachment " + id)
            close.tap()
            XCTAssertTrue(app.buttons["Speichern"].waitForExistence(timeout: 5))
        }
        app.buttons["Speichern"].tap()
        XCTAssertTrue(app.staticTexts["therapy.countdown"].waitForExistence(timeout: 10))
        capture("Updated home with therapy countdown")
        XCTAssertTrue(app.tabBars.buttons["Archiv"].waitForExistence(timeout: 10)); app.tabBars.buttons["Archiv"].tap()
        let overview = app.buttons["Übersicht öffnen"].firstMatch
        XCTAssertTrue(overview.waitForExistence(timeout: 5)); overview.tap()
        XCTAssertTrue(app.navigationBars["Deine Notiz"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields.count, 0, "Saved notes first open read-only.")
        for id in ["22222222-2222-2222-2222-222222222222", "33333333-3333-3333-3333-333333333333"] {
            let open = app.buttons["note.detail.attachment." + id]
            reveal(open, in: app); open.tap()
            XCTAssertTrue(app.buttons["media.detail.close"].waitForExistence(timeout: 5)); app.buttons["media.detail.close"].tap()
            XCTAssertTrue(app.navigationBars["Deine Notiz"].waitForExistence(timeout: 5), "Archive media closes back to the saved note.")
        }
        capture("Saved note with photo and playable audio")
    }

    @MainActor
    func testTherapyCancellationAndRestore() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-testing", "--show-dashboard", "--show-appointments"]
        app.launch()
        let cancel = app.buttons["therapy.cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 15)); cancel.tap()
        XCTAssertTrue(app.navigationBars["Termin absagen"].waitForExistence(timeout: 5))
        app.buttons["Speichern"].tap()
        let restore = app.buttons["therapy.restore"].firstMatch
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        capture("Canceled weekly appointment")
        restore.tap()
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "therapy.restore").count, 0)
        capture("Restored weekly appointment")
    }

    @MainActor
    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<7 { if element.exists && element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.exists && element.isHittable, "Expected action is reachable: " + element.identifier)
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
