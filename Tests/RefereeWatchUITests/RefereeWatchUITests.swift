import XCTest

final class RefereeWatchUITests: XCTestCase {
    @MainActor
    func testDirectRedRequiresHoldThenReturnsToLiveClockWithQueuedSave() throws {
        let app = XCUIApplication()
        app.launchEnvironment["REFEREE_WATCH_UI_TEST_DATABASE"] = UUID().uuidString
        app.launchEnvironment["REFEREE_WATCH_UI_TEST_SEED"] = "fixture"
        app.launch()

        let foul = app.buttons["watch.action.foul"]
        XCTAssertTrue(foul.waitForExistence(timeout: 5))
        app.buttons["watch.action.card"].tap()
        let red = app.staticTexts["watch.card.red.home"]
        XCTAssertTrue(red.waitForExistence(timeout: 2))
        red.press(forDuration: 1.1)

        XCTAssertTrue(app.staticTexts["watch.save.confirmation"].waitForExistence(timeout: 2))
        XCTAssertTrue(foul.waitForExistence(timeout: 2))
    }

    @MainActor
    func testOfflineFoulReturnsHomeWithinTwoSecondsAndSurvivesRelaunch() throws {
        let app = XCUIApplication()
        app.launchEnvironment["REFEREE_WATCH_UI_TEST_DATABASE"] = UUID().uuidString
        app.launchEnvironment["REFEREE_WATCH_UI_TEST_SEED"] = "fixture"
        app.launch()

        let foul = app.buttons["watch.action.foul"]
        XCTAssertTrue(foul.waitForExistence(timeout: 5))
        foul.tap()
        let awayFoul = app.buttons["watch.foul.away"]
        XCTAssertTrue(awayFoul.waitForExistence(timeout: 2))

        let startedAt = Date()
        awayFoul.tap()
        XCTAssertTrue(waitForExistence(foul, timeout: 2))
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 2,
                          "Foul capture must return home within two seconds")
        XCTAssertTrue(app.staticTexts["watch.save.confirmation"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["watch.sync.status"].label.contains("Queue 1"))

        app.terminate()
        app.launch()
        XCTAssertTrue(foul.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["watch.sync.status"].label.contains("Queue 1"))
    }

    @MainActor
    private func waitForExistence(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return element.exists
    }
}
