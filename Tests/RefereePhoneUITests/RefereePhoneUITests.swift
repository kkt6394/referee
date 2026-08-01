import XCTest

final class RefereePhoneUITests: XCTestCase {
    @MainActor
    func testSwitchesVisibleCopyFromKoreanToEnglish() throws {
        let app = XCUIApplication()
        app.launchEnvironment["REFEREE_UI_TEST_DATABASE"] = UUID().uuidString
        app.launchEnvironment["REFEREE_UI_TEST_LANGUAGE"] = "ko"
        app.launch()

        XCTAssertTrue(app.navigationBars["경기"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["경기 생성"].exists)

        let language = app.buttons["settings.language"]
        XCTAssertTrue(language.waitForExistence(timeout: 3))
        language.tap()
        app.buttons["English"].tap()

        XCTAssertTrue(app.navigationBars["Matches"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Create match"].exists)
    }

    @MainActor
    func testKoreanTimelineLocalizesLiveFollowUpSurface() throws {
        let app = launchSeededFixture(language: "ko")
        saveFixture(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["match.period.start"].waitForExistence(timeout: 3))
        scrollToElement(app.buttons["match.timeline"], in: app).tap()

        XCTAssertTrue(app.navigationBars["경기 기록"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["아직 경기 기록이 없습니다"].exists)
    }

    @MainActor
    func testKoreanLocalizesInactiveWatchSyncFailure() throws {
        let app = launchSeededFixture(language: "ko", syncFailure: "Watch session is not active")
        saveFixture(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["match.period.start"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Watch 세션이 활성 상태가 아닙니다"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Watch session is not active"].exists)
    }

    @MainActor
    func testIncompleteFixtureShowsBlockingReadinessBeforeLiveControl() throws {
        let app = XCUIApplication()
        app.launchEnvironment["REFEREE_UI_TEST_DATABASE"] = UUID().uuidString
        app.launchEnvironment["REFEREE_UI_TEST_LANGUAGE"] = "en"
        app.launch()
        app.buttons["matches.create"].tap()
        app.textFields["fixture.competition"].tap(); app.textFields["fixture.competition"].typeText("KFA League")
        app.textFields["fixture.venue"].tap(); app.textFields["fixture.venue"].typeText("Main pitch")
        app.textFields["fixture.homeTeam"].tap(); app.textFields["fixture.homeTeam"].typeText("Seoul")
        app.textFields["fixture.awayTeam"].tap(); app.textFields["fixture.awayTeam"].typeText("Busan")
        app.buttons["fixture.save"].tap()

        let readiness = scrollToElement(app.staticTexts["setup.readiness.blocking"], in: app)
        XCTAssertTrue(readiness.exists)
        let openControl = scrollToElement(app.buttons["setup.openControl"], in: app)
        XCTAssertFalse(openControl.isEnabled)
    }

    @MainActor
    func testMatchControlShowsReadinessKitAccentsSyncAndReviewEntry() throws {
        let app = launchSeededFixture(language: "en")
        saveFixture(in: app)

        XCTAssertTrue(app.descendants(matching: .any)["match.readiness"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.descendants(matching: .any)["match.homeKitAccent"].label, "Seoul, Red")
        XCTAssertEqual(app.descendants(matching: .any)["match.awayKitAccent"].label, "Busan, Blue")
        XCTAssertTrue(app.descendants(matching: .any)["match.syncStatus"].exists)

        let review = scrollToElement(app.buttons["match.review"], in: app)
        XCTAssertTrue(review.exists)
    }

    @MainActor
    func testCreateFixtureAndRecordLiveActions() throws {
        let app = launchSeededFixture()
        saveFixture(in: app)

        app.descendants(matching: .any)["match.period.start"].press(forDuration: 1.2)
        XCTAssertTrue(app.staticTexts["FIRST HALF"].waitForExistence(timeout: 3))
        app.buttons["GOAL, Seoul"].tap()
        app.buttons["FOUL, Busan"].tap()
        XCTAssertTrue(app.staticTexts["1"].exists)

        app.buttons["match.timeline"].tap()
        XCTAssertTrue(app.navigationBars["Event timeline"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'timeline.goal_recorded.'")).firstMatch
            .waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'timeline.foul_recorded.'")).firstMatch
            .waitForExistence(timeout: 3))
    }

    @MainActor
    func testCompleteMatchSignExportAndPresentShareSheet() throws {
        let app = launchSeededFixture()
        saveFixture(in: app)

        scrollToElement(app.descendants(matching: .any)["match.period.start"], in: app)
            .press(forDuration: 1.2)
        XCTAssertTrue(app.staticTexts["FIRST HALF"].waitForExistence(timeout: 3))
        app.buttons["GOAL, Seoul"].tap()

        scrollToElement(app.buttons["match.timeline"], in: app).tap()
        XCTAssertTrue(app.navigationBars["Event timeline"].waitForExistence(timeout: 3))
        let goal = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'timeline.goal_recorded.'")).firstMatch
        XCTAssertTrue(goal.waitForExistence(timeout: 3))
        goal.tap()

        let playerPicker = app.buttons["event.details.player"]
        XCTAssertTrue(playerPicker.waitForExistence(timeout: 3))
        playerPicker.tap()
        app.buttons["9 · Home 9"].tap()
        let saveDetails = app.buttons["event.details.save"]
        XCTAssertTrue(saveDetails.isEnabled)
        saveDetails.tap()
        XCTAssertTrue(app.navigationBars["Event timeline"].waitForExistence(timeout: 3))
        app.navigationBars["Event timeline"].buttons.firstMatch.tap()

        endCurrentPeriod(in: app)
        XCTAssertTrue(app.staticTexts["HALF TIME"].waitForExistence(timeout: 3))
        scrollToElement(app.descendants(matching: .any)["match.period.start"], in: app)
            .press(forDuration: 1.2)
        XCTAssertTrue(app.staticTexts["SECOND HALF"].waitForExistence(timeout: 3))
        endCurrentPeriod(in: app)
        XCTAssertTrue(app.staticTexts["FULL TIME"].waitForExistence(timeout: 3))

        scrollToElement(app.buttons["match.review"], in: app).tap()
        XCTAssertTrue(app.navigationBars["Post-match review"].waitForExistence(timeout: 3))
        turnOn(app.switches["report.score.confirm"], in: app)
        turnOn(app.switches["report.declaration.accept"], in: app)

        let sign = scrollToElement(app.buttons["report.sign"], in: app)
        expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: sign)
        waitForExpectations(timeout: 3)
        sign.tap()
        // A physical iPhone can expose the SwiftUI button and its labelled
        // child as two matching accessibility elements.
        let confirmSign = app.buttons.matching(identifier: "report.sign.confirm").firstMatch
        XCTAssertTrue(confirmSign.waitForExistence(timeout: 3))
        confirmSign.tap()

        let pdf = scrollToElement(app.buttons["report.export.pdf"], in: app)
        XCTAssertTrue(pdf.waitForExistence(timeout: 3))
        pdf.tap()
        let share = app.buttons["report.export.share"]
        XCTAssertTrue(share.waitForExistence(timeout: 3))
        XCTAssertEqual(share.label, "Share PDF")

        let xlsx = scrollToElement(app.buttons["report.export.xlsx"], in: app)
        xlsx.tap()
        XCTAssertEqual(share.label, "Share XLSX")
        scrollToElement(share, in: app).tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func launchSeededFixture(language: String = "en", syncFailure: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["REFEREE_UI_TEST_DATABASE"] = UUID().uuidString
        app.launchEnvironment["REFEREE_UI_TEST_SEED"] = "fixture"
        app.launchEnvironment["REFEREE_UI_TEST_LANGUAGE"] = language
        if let syncFailure { app.launchEnvironment["REFEREE_UI_TEST_SYNC_FAILURE"] = syncFailure }
        app.launch()
        app.buttons["matches.create"].tap()
        XCTAssertEqual(app.textFields["fixture.competition"].value as? String, "KFA UI League")
        XCTAssertEqual(app.textFields["fixture.venue"].value as? String, "Acceptance Ground")
        XCTAssertEqual(app.textFields["fixture.homeTeam"].value as? String, "Seoul")
        XCTAssertEqual(app.textFields["fixture.awayTeam"].value as? String, "Busan")
        return app
    }

    @MainActor
    private func saveFixture(in app: XCUIApplication) {
        let save = scrollToElement(app.buttons["fixture.save"], in: app)
        XCTAssertTrue(save.isEnabled)
        save.tap()
    }

    @MainActor
    private func endCurrentPeriod(in app: XCUIApplication) {
        scrollToElement(app.descendants(matching: .any)["match.period.end"], in: app)
            .press(forDuration: 1.2)
    }

    @MainActor
    private func turnOn(_ toggle: XCUIElement, in app: XCUIApplication) {
        let toggle = scrollToElement(toggle, in: app)
        if (toggle.value as? String) != "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertEqual(toggle.value as? String, "1")
    }

    @MainActor
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) -> XCUIElement {
        let container: XCUIElement
        if app.collectionViews.firstMatch.exists { container = app.collectionViews.firstMatch }
        else if app.scrollViews.firstMatch.exists { container = app.scrollViews.firstMatch }
        else { container = app }
        for _ in 0..<20 where !element.isHittable { container.swipeUp(velocity: .slow) }
        for _ in 0..<20 where !element.isHittable { container.swipeDown(velocity: .slow) }
        XCTAssertTrue(element.waitForExistence(timeout: 3))
        XCTAssertTrue(element.isHittable)
        return element
    }
}
