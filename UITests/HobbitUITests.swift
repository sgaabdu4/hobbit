import XCTest

final class HobbitUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testVoiceDemo() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HOBBIT_CAPTURE_DEMO"] == "1", "Voice demo is an explicit, billable device check.")
        let app = try launchSignedInApp()
        try reachToday(app)
        if app.buttons["Undo today's completion"].exists { try tap(app.buttons["Undo today's completion"], in: app) }
        try tap(app.buttons["edit-habit"], in: app)
        try tap(app.buttons["mode-unhinged"], in: app)
        if app.alerts["Turn on Unhinged?"].exists { app.alerts.buttons["Use Unhinged"].tap() }
        try tap(app.buttons["Save changes"], in: app)
        XCTAssertTrue(app.buttons["talk-to-pet"].waitForExistence(timeout: 30))
        snapshot("Dark Today with Unhinged", app: app)
        try tap(app.buttons["talk-to-pet"], in: app)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "ringing-status").firstMatch.waitForExistence(timeout: 5))
        snapshot("Ringing Pip", app: app)
        XCTAssertTrue(app.staticTexts["A little push."].waitForExistence(timeout: 40))
        let pet = app.descendants(matching: .any).matching(identifier: "pet-sprite").firstMatch
        let speaking = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == 'speaking'"), object: pet)
        XCTAssertEqual(XCTWaiter.wait(for: [speaking], timeout: 30), .completed, "The mouth should respond to actual received voice audio.")
        snapshot("Angry Pip speaking in live call", app: app)
        Thread.sleep(forTimeInterval: 6)
        try tap(app.buttons["I did it"], in: app)
        XCTAssertTrue(app.staticTexts["You showed up."].waitForExistence(timeout: 10))
        snapshot("Dark completion", app: app)
        try tap(app.buttons["Undo completion"], in: app)
    }

    @MainActor
    func testHabitCompletionAndUndo() throws {
        let app = try launchSignedInApp()
        try reachToday(app)
        let wasCompleted = app.buttons["Undo today's completion"].exists
        if wasCompleted { try tap(app.buttons["Undo today's completion"], in: app) }
        defer {
            if wasCompleted, app.buttons["I did it"].exists {
                try? tap(app.buttons["I did it"], in: app)
                try? tap(app.buttons["Back to today"], in: app)
            }
        }

        snapshot("Today before completion", app: app)
        try tap(app.buttons["I did it"], in: app)
        XCTAssertTrue(app.staticTexts["You showed up."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["day streak"].exists)
        snapshot("Saved completion and streak", app: app)
        try tap(app.buttons["Back to today"], in: app)
        XCTAssertTrue(app.buttons["Undo today's completion"].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Undo today's completion"].waitForExistence(timeout: 10), "Completion must survive relaunch.")
        snapshot("Completion restored after relaunch", app: app)
        try tap(app.buttons["Undo today's completion"], in: app)
        XCTAssertTrue(app.buttons["I did it"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["edit-habit"].exists)
        snapshot("Today after undo", app: app)
    }

    @MainActor
    func testPetChooserKeepsCurrentPet() throws {
        let app = try launchSignedInApp()
        try reachToday(app)
        try tap(app.buttons["Change pet"], in: app)
        XCTAssertTrue(app.buttons["Use Pip"].waitForExistence(timeout: 5))
        snapshot("Pet chooser", app: app)
        try tap(app.buttons["Keep my current pet"], in: app)
        XCTAssertTrue(app.buttons["edit-habit"].waitForExistence(timeout: 5))
        try tap(app.buttons["edit-habit"], in: app)
        XCTAssertTrue(app.buttons["Save changes"].waitForExistence(timeout: 5))
        snapshot("Edit habit and coaching mode", app: app)
        try tap(app.buttons["Cancel"], in: app)
    }

    @MainActor
    private func launchSignedInApp() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15))
        if app.buttons["chatgpt-sign-in"].exists {
            let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.buttons["chatgpt-sign-in"])
            _ = XCTWaiter.wait(for: [restored], timeout: 40)
        }
        if app.buttons["chatgpt-sign-in"].exists {
            snapshot("Sign-in required", app: app)
            XCTFail("This device must already be signed in with ChatGPT. The UI test does not bypass authentication.")
            throw UIStateError.signInRequired
        }
        return app
    }

    @MainActor
    private func reachToday(_ app: XCUIApplication) throws {
        if app.buttons["Back to today"].exists { try tap(app.buttons["Back to today"], in: app) }
        if app.buttons["edit-habit"].waitForExistence(timeout: 3) { return }
        if app.buttons["Use Pip"].exists {
            snapshot("Pet onboarding", app: app)
            try tap(app.buttons["Use Pip"], in: app)
        }
        let input = app.descendants(matching: .any).matching(identifier: "habit-input").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10), "Expected habit setup or an existing daily habit.")
        if app.buttons["Continue"].exists {
            try tap(input, in: app)
            input.typeText("Stretch for two minutes")
            try tap(app.buttons["Continue"], in: app)
        }
        let save = app.buttons["Set my daily call"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        let ready = NSPredicate(format: "isEnabled == true")
        let enabled = XCTNSPredicateExpectation(predicate: ready, object: save)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 40), .completed, "The Mac backend and push registration must be ready.")
        snapshot("Habit and call time confirmation", app: app)
        try tap(save, in: app)
        XCTAssertTrue(app.buttons["edit-habit"].waitForExistence(timeout: 40), "Saving should return to Today.")
    }

    @MainActor
    private func tap(_ element: XCUIElement, in app: XCUIApplication) throws {
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<6 {
            if element.isHittable { element.tap(); return }
            scroll.swipeUp()
        }
        for _ in 0..<6 {
            if element.isHittable { element.tap(); return }
            scroll.swipeDown()
        }
        snapshot("Control could not be reached", app: app)
        XCTFail("Expected control is present but cannot be tapped: \(element.label)")
        throw UIStateError.controlUnreachable
    }

    @MainActor
    private func snapshot(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private enum UIStateError: Error { case signInRequired, controlUnreachable }
}
