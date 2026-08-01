# 11-a-side Field MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a referee-operated 11-a-side football MVP that can prepare, operate, recover, review, and export one complete match with iPhone and Apple Watch, without requiring a network during play.

**Architecture:** RefereeLedger remains the sole source of truth: both apps append immutable local events and synchronize through WatchConnectivity. Add a small derived 11-a-side readiness model to the ledger, present it on iPhone setup/review, and keep Watch interaction focused on immediate one-handed capture. This release excludes a server, accounts, KFA API submission, futsal, and youth-specific flows.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing, XCTest UI tests, SQLite/CSQLite, WatchConnectivity, XcodeGen, iOS 16+, watchOS 9+.

## Global Constraints

- Target a single 11-a-side match, one accountable referee, two 45-minute halves, with existing optional extra time and shoot-out rules.
- Watch events commit locally before connectivity; Watch foul capture returns to match home within two seconds.
- Only iPhone signs and exports reports.
- Preserve append-only event/revision history; never introduce in-place mutation.
- Keep secrets, signing files, device data, and generated products out of Git.
- Use TDD for every behavior: focused test fails, minimal code, focused pass, complete suite.
- Commit and push after each task's verification.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `Sources/RefereeLedger/FieldReadiness.swift` | Pure 11-a-side readiness requirements and derived issues. |
| `Sources/RefereeLedger/LedgerStore.swift` | Builds readiness from persisted fixture, roster, checklist, rules, and period state. |
| `Tests/RefereeLedgerTests/LedgerStoreTests.swift` | Durable readiness and offline-to-signing regression coverage. |
| `Apps/iPhone/RefereePhoneApp.swift` | Pre-match readiness and safe route into live control. |
| `Tests/RefereePhoneUITests/RefereePhoneUITests.swift` | iPhone simulator acceptance. |
| `Apps/Watch/RefereeWatchApp.swift` | Fast labelled capture, confirmation, and sync-recovery feedback. |
| `Tests/RefereeWatchUITests/RefereeWatchUITests.swift` | Watch simulator acceptance. |
| `docs/FIELD_TEST_PROTOCOL.md` | Human-run physical-device field test. |
| `docs/DEVICE_ACCEPTANCE_EVIDENCE.md` | Dated observations and unresolved hardware results. |

## Task 1: Define a deterministic 11-a-side field-readiness contract

**Files:**
- Create: `Sources/RefereeLedger/FieldReadiness.swift`
- Modify: `Sources/RefereeLedger/LedgerStore.swift`
- Test: `Tests/RefereeLedgerTests/LedgerStoreTests.swift`

**Interfaces:**
- Produces `FieldReadiness(blocking:warnings:)`, `FieldReadinessIssue(id:title:detail:severity:)`, and `FieldReadinessSeverity`.
- Produces `LedgerStore.fieldReadiness(matchID: UUID) throws -> FieldReadiness`.
- `FieldReadiness.canStartMatch` is true only when `blocking` is empty.

- [ ] **Step 1: Write the failing test.**

~~~swift
@Test func elevenAsideDraftCannotStartUntilMinimumFieldDataExists() throws {
    let store = try LedgerStore(originDeviceID: deviceID)
    try store.saveFixture(MatchFixture(matchID: matchID, competition: "KFA League", scheduledAt: .now,
                                       venueName: "Main pitch", homeTeamName: "Seoul", awayTeamName: "Busan"))

    let readiness = try store.fieldReadiness(matchID: matchID)

    #expect(!readiness.canStartMatch)
    #expect(readiness.blocking.map(\\.id) == ["roster.home", "roster.away", "referee.accountable"])
}
~~~

- [ ] **Step 2: Verify the test fails.**

Run: `swift test --filter elevenAsideDraftCannotStartUntilMinimumFieldDataExists`

Expected: compile failure because `fieldReadiness(matchID:)` is absent.

- [ ] **Step 3: Implement the smallest public model and query.**

~~~swift
public enum FieldReadinessSeverity: String, Equatable, Sendable { case blocking, warning }

public struct FieldReadinessIssue: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let severity: FieldReadinessSeverity
}

public struct FieldReadiness: Equatable, Sendable {
    public let blocking: [FieldReadinessIssue]
    public let warnings: [FieldReadinessIssue]
    public var canStartMatch: Bool { blocking.isEmpty }
}
~~~

Block on missing competition, venue, distinct non-empty teams, one player per team, or accountable referee. Warn, but do not block, for unchecked pitch/equipment/crew/lineup or missing pitch dimensions.

- [ ] **Step 4: Verify focused pass and complete-state regression.**

~~~swift
@Test func completeElevenAsidePreparationIsStartable() throws {
    let store = try preparedElevenAsideStore(matchID: matchID, deviceID: deviceID)
    let readiness = try store.fieldReadiness(matchID: matchID)
    #expect(readiness.blocking.isEmpty)
    #expect(readiness.warnings.isEmpty)
    #expect(readiness.canStartMatch)
}
~~~

Run: `swift test`

Expected: all tests pass.

- [ ] **Step 5: Commit.**

~~~sh
git add Sources/RefereeLedger/FieldReadiness.swift Sources/RefereeLedger/LedgerStore.swift Tests/RefereeLedgerTests/LedgerStoreTests.swift
git commit -m "feat: derive 11-a-side field readiness"
git push
~~~

## Task 2: Make iPhone setup a reliable pre-match control point

**Files:**
- Modify: `Apps/iPhone/RefereePhoneApp.swift`
- Test: `Tests/RefereePhoneUITests/RefereePhoneUITests.swift`
- Regenerate if changed: `Referee.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes `LedgerStore.fieldReadiness(matchID:)`.
- Produces `PhoneMatchStore.fieldReadiness` and `refreshFieldReadiness()`.
- Produces accessibility identifiers `setup.readiness.blocking`, `setup.readiness.warning`, and `setup.openControl`.

- [ ] **Step 1: Write the failing blocked-setup UI test.**

~~~swift
func testIncompleteFixtureShowsBlockingReadinessBeforeLiveControl() throws {
    let app = XCUIApplication()
    app.launchEnvironment["REFEREE_PHONE_UI_TEST_DATABASE"] = UUID().uuidString
    app.launch()
    app.buttons["matches.create"].tap()
    app.buttons["fixture.save"].tap()

    XCTAssertTrue(app.staticTexts["setup.readiness.blocking"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.buttons["setup.openControl"].isEnabled)
}
~~~

- [ ] **Step 2: Run it and confirm it fails at the missing readiness element.**

Run: `xcodebuild -project Referee.xcodeproj -scheme RefereePhone -destination 'platform=iOS Simulator,name=iPhone 16' -only-testing:RefereePhoneUITests/RefereePhoneUITests/testIncompleteFixtureShowsBlockingReadinessBeforeLiveControl test`

- [ ] **Step 3: Implement derived setup presentation.**

Refresh readiness after `load`, `createMatch`, `saveFixture`, and `saveFixtureDraft`. In `PhoneMatchSetupView`, render blocking issue titles in red and warnings separately. Disable only the route to live control when blocks exist; drafts remain savable.

- [ ] **Step 4: Extend the UI test to complete minimum data and prove live control opens.**

~~~swift
XCTAssertTrue(app.buttons["setup.openControl"].isEnabled)
app.buttons["setup.openControl"].tap()
XCTAssertTrue(app.buttons["match.period.start"].waitForExistence(timeout: 3))
~~~

Use visible setup controls to enter fixture data, one player per side, and the accountable referee; do not add test-only production routes.

- [ ] **Step 5: Verify and commit.**

Run: `xcodegen generate`

Run: `xcodebuild -project Referee.xcodeproj -scheme RefereePhone -destination 'platform=iOS Simulator,name=iPhone 16' test`

~~~sh
git add Apps/iPhone/RefereePhoneApp.swift Tests/RefereePhoneUITests/RefereePhoneUITests.swift Referee.xcodeproj/project.pbxproj
git commit -m "feat: gate live control on 11-a-side readiness"
git push
~~~

## Task 3: Harden Watch capture for a moving referee

**Files:**
- Modify: `Apps/Watch/RefereeWatchApp.swift`
- Test: `Tests/RefereeWatchUITests/RefereeWatchUITests.swift`

**Interfaces:**
- Uses `WatchMatchStore.saveGoal`, `saveFoul`, `saveCard`, `pendingSyncCount`, and `syncFailure`.
- Adds published `homeTeamName` and `awayTeamName` loaded from `MatchPackage.fixture`.
- Produces accessibility identifiers `watch.action.card`, `watch.card.red.home`, `watch.card.red.away`, and `watch.save.confirmation`.

- [ ] **Step 1: Write the failing direct-red acceptance.**

~~~swift
@MainActor
func testDirectRedRequiresHoldThenReturnsToLiveClockWithQueuedSave() throws {
    let app = XCUIApplication()
    app.launchEnvironment["REFEREE_WATCH_UI_TEST_DATABASE"] = UUID().uuidString
    app.launchEnvironment["REFEREE_WATCH_UI_TEST_SEED"] = "fixture"
    app.launch()

    app.buttons["watch.action.card"].tap()
    let red = app.staticTexts["watch.card.red.home"]
    XCTAssertTrue(red.waitForExistence(timeout: 2))
    red.press(forDuration: 1.1)

    XCTAssertTrue(app.staticTexts["watch.save.confirmation"].waitForExistence(timeout: 2))
    XCTAssertTrue(app.buttons["watch.action.foul"].waitForExistence(timeout: 2))
}
~~~

- [ ] **Step 2: Run it and confirm the test fails on absent identifiers/return behavior.**

Run: `xcodebuild -project Referee.xcodeproj -scheme RefereeWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' -only-testing:RefereeWatchUITests/RefereeWatchUITests/testDirectRedRequiresHoldThenReturnsToLiveClockWithQueuedSave test`

- [ ] **Step 3: Implement labelled actions and visible successful-save feedback.**

Render team names, not HOME/AWAY alone, in Goal, Foul, Card, and More actions. Replace direct-red `Text` views with accessible controls that still require one-second long press. After a successful action, return to home, show `Saved locally · Queue N` briefly, and retain the failure screen/status if local save fails.

- [ ] **Step 4: Strengthen the existing foul timing test.**

Before Watch relaunch, assert `watch.save.confirmation` contains `Saved locally`. Run once before implementation to observe failure and again after implementation to observe pass.

- [ ] **Step 5: Verify and commit.**

Run: `xcodebuild -project Referee.xcodeproj -scheme RefereeWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' test`

~~~sh
git add Apps/Watch/RefereeWatchApp.swift Tests/RefereeWatchUITests/RefereeWatchUITests.swift
git commit -m "feat: harden Watch match capture"
git push
~~~

## Task 4: Make offline recovery through report readiness a release gate

**Files:**
- Modify: `Tests/RefereeLedgerTests/LedgerStoreTests.swift`
- Modify only if test exposes defect: `Sources/RefereeLedger/LedgerStore.swift`
- Modify: `Tests/RefereePhoneUITests/RefereePhoneUITests.swift`

**Interfaces:**
- Uses `pendingOutboxEvents(matchID:peer:)`, `receive(_:messageID:from:)`, `acknowledge(eventID:integrityHash:peer:)`, and `rebuildProjection(matchID:)`.
- Produces an automated gate: offline Watch event → Watch relaunch → reconciliation → finished regulation → signable report.

- [ ] **Step 1: Write the failing ledger acceptance.**

~~~swift
@Test func fieldMvpRecoversOfflineWatchEventBeforeSignedElevenAsideExport() throws {
    let phone = try preparedElevenAsideStore(matchID: matchID, deviceID: UUID())
    let watch = try LedgerStore(originDeviceID: UUID())
    _ = try watch.create(EventDraft(matchID: matchID, eventType: "foul_recorded",
                                    payloadJSON: #"{"teamSide":"away"}"#), peers: ["iphone"])

    let reopenedWatch = try reopenedCopy(of: watch)
    try reconcile(phone: phone, watch: reopenedWatch, matchID: matchID)

    #expect(try phone.timeline(matchID: matchID).contains { $0.eventType == "foul_recorded" })
    try finishRegulation(phone, matchID: matchID)
    #expect(try signValidMatchReport(phone, matchID: matchID).status == .current)
}
~~~

- [ ] **Step 2: Run focused test and confirm it fails only for new test helpers.**

Run: `swift test --filter fieldMvpRecoversOfflineWatchEventBeforeSignedElevenAsideExport`

- [ ] **Step 3: Add test-only helpers and only the minimum production correction revealed.**

Helpers use public ledger APIs and real SQLite files. Final assertions must verify the two stores converge to the same projection score and event digest; never mock storage or transport ordering.

- [ ] **Step 4: Add iPhone post-match review smoke coverage.**

~~~swift
func testCompletedPreparedMatchCanReachReportReview() throws {
    let app = XCUIApplication()
    app.launchEnvironment["REFEREE_PHONE_UI_TEST_SEED"] = "completed-eleven-aside"
    app.launch()
    app.buttons["match.review"].tap()
    XCTAssertTrue(app.buttons["report.sign"].waitForExistence(timeout: 5))
}
~~~

Add the seed through the existing UI-test setup; the test stops before signing.

- [ ] **Step 5: Verify and commit.**

Run: `swift test`

Run: `xcodebuild -project Referee.xcodeproj -scheme RefereePhone -destination 'platform=iOS Simulator,name=iPhone 16' test`

Run: `xcodebuild -project Referee.xcodeproj -scheme RefereeWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' test`

~~~sh
git add Sources/RefereeLedger/LedgerStore.swift Tests/RefereeLedgerTests/LedgerStoreTests.swift Tests/RefereePhoneUITests/RefereePhoneUITests.swift
git commit -m "test: cover 11-a-side field recovery path"
git push
~~~

## Task 5: Execute and document a physical referee field pilot

**Files:**
- Create: `docs/FIELD_TEST_PROTOCOL.md`
- Modify: `docs/DEVICE_ACCEPTANCE_EVIDENCE.md`

**Interfaces:**
- Consumes a development-signed iPhone app with embedded paired Watch app.
- Produces dated evidence: commit SHA, device/OS, observer, per-step observation, foul elapsed time, sync result, export result, and any unresolved failures.

- [ ] **Step 1: Write the physical protocol before running it.**

The protocol order is fixed: prepare fixture; install paired apps; hold-start first half; record goal, foul, yellow, direct red; disconnect phone; record away foul; immediately relaunch Watch; reconnect until Queue 0; hold-end both halves; complete direct-red incident detail on iPhone; sign; export PDF/XLSX; open both files.

Include a table with `Step`, `Expected`, `Observed`, `Pass`, `Evidence`, and `Notes`. Measure Watch foul tap-to-home with a stopwatch or screen recording and require ≤2.0 seconds. Human observers, not XCTest, attest haptic sensation.

- [ ] **Step 2: Build, install, and run the protocol.**

Run: `xcodebuild -project Referee.xcodeproj -scheme RefereePhone -destination 'platform=iOS,name=<paired iPhone name>' build`

If an action fails, preserve the database, result bundle, and recording; record it as failure and create a separate defect plan rather than reclassifying it.

- [ ] **Step 3: Record factual evidence, commit, and push.**

~~~sh
git add docs/FIELD_TEST_PROTOCOL.md docs/DEVICE_ACCEPTANCE_EVIDENCE.md
git commit -m "docs: record 11-a-side field pilot"
git push
~~~

## Plan Self-Review

- **Coverage:** Tasks 1–2 establish field preparation, Task 3 protects immediate Watch use, Task 4 proves recovery through signing, and Task 5 supplies real-device evidence.
- **Scope:** Futsal, youth templates, accounts, cloud backup, payments, and direct association submission are intentionally excluded so this plan results in a testable 11-a-side release.
- **Consistency:** Task 1 defines `FieldReadiness` before Task 2 consumes it. Tasks 3–4 use existing append-only/sync APIs.
- **Verification:** Each task contains a focused test or field gate, complete suite command, and commit boundary.
