# Referee UI and Localization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task with review checkpoints.

**Goal:** Deliver a Korean-first, English-switchable referee experience with a polished pre/post-match iPhone UI and high-contrast live-match Watch UI.

**Architecture:** Keep the append-only ledger, package transfer, offline queue, and sign-off rules unchanged. Add a small shared localization service and semantic SwiftUI style tokens, then migrate user-facing strings and update the two platform surfaces independently.

**Tech Stack:** Swift 6, SwiftUI, Swift Package Manager, XCTest/XCUITest, XcodeGen.

## Global Constraints

- iPhone is the primary surface before and after a match; Watch is primary during live play.
- Korean (`ko`) is default; English (`en`) is selectable and persisted locally.
- Event identifiers, database values, accessibility identifiers, and sync protocol fields remain language-neutral.
- Watch actions remain offline-first, use large touch targets, and preserve long-press red-card confirmation.
- Preserve current 11-a-side readiness gates, team kit colors, queue behavior, signing, and exports.
- Run `swift test`, full iPhone UI tests, and full Watch UI tests before integration.

---

### Task 1: Add locale selection and string catalog boundary

**Files:**
- Create: `Sources/RefereeLedger/AppLanguage.swift`
- Modify: `Apps/iPhone/RefereePhoneApp.swift`
- Modify: `Apps/Watch/RefereeWatchApp.swift`
- Test: `Tests/RefereeLedgerTests/AppLanguageTests.swift`

**Interfaces:**
- Produce `public enum AppLanguage: String, CaseIterable { case korean = "ko"; case english = "en" }`.
- Produce `public struct AppLanguageStore` with `init(userDefaults:)`, `language`, and `set(_:)`.
- Keep persistence key `referee.app.language` and default to `.korean`.

- [ ] Write tests proving default Korean, persisted English, and invalid stored values falling back to Korean.
- [ ] Run `swift test --filter AppLanguageTests` and verify the new tests fail before implementation.
- [ ] Implement the enum and UserDefaults-backed store without touching ledger schemas.
- [ ] Run the focused test, then full `swift test`.
- [ ] Commit `feat: add persisted app language selection`.

### Task 2: Introduce localized copy and language setting

**Files:**
- Create: `Apps/Shared/RefereeCopy.swift`
- Modify: `Apps/iPhone/RefereePhoneApp.swift`
- Modify: `Apps/Watch/RefereeWatchApp.swift`
- Test: `Tests/RefereePhoneUITests/RefereePhoneUITests.swift`

**Interfaces:**
- Produce `struct RefereeCopy` with `init(language:)` and typed properties for navigation, readiness, match actions, sync status, and setup labels.
- Produce a language setting in the iPhone setup/settings flow with accessibility identifier `settings.language`.
- Watch reads the same persisted language when its package is installed, while protocol payloads remain English-neutral identifiers.

- [ ] Add a UI test that launches with Korean, asserts `경기`/`경기 생성`, switches to English, and asserts `Matches`/`Create match`.
- [ ] Run the focused UI test and capture the expected pre-implementation failure.
- [ ] Replace hard-coded visible strings in the root, setup, readiness, and live action surfaces with `RefereeCopy` values.
- [ ] Implement the setting and persistence refresh path for both platforms.
- [ ] Run full iPhone and Watch UI suites and commit `feat: localize referee surfaces`.

### Task 3: Polish the iPhone pre/post-match experience

**Files:**
- Create: `Apps/iPhone/RefereeTheme.swift`
- Modify: `Apps/iPhone/RefereePhoneApp.swift`
- Modify: `docs/MVP_SCREEN_INVENTORY.md`
- Test: `Tests/RefereePhoneUITests/RefereePhoneUITests.swift`

**Interfaces:**
- Produce semantic colors, spacing, corner radius, and typography tokens in `RefereeTheme`.
- Keep existing accessibility identifiers and add `match.readiness`, `match.syncStatus`, and `match.review` where missing.

- [ ] Add UI assertions for visible readiness status, team kit accent labels, and post-match review entry.
- [ ] Refactor the Matches, Create match, setup hub, readiness, and review surfaces into bright grouped cards with one primary action per screen.
- [ ] Preserve all existing form fields, validation, navigation, and save behavior.
- [ ] Run iPhone UI tests and inspect Korean and English screenshots on the simulator.
- [ ] Commit `feat: polish iPhone referee workflow`.

### Task 4: Polish the Watch live-match experience

**Files:**
- Create: `Apps/Watch/RefereeWatchTheme.swift`
- Modify: `Apps/Watch/RefereeWatchApp.swift`
- Test: `Tests/RefereeWatchUITests/RefereeWatchUITests.swift`

**Interfaces:**
- Produce dark semantic tokens and minimum live-action target sizes in `RefereeWatchTheme`.
- Preserve existing identifiers `watch.card.red.home`, `watch.card.red.away`, and queue/status labels.

- [ ] Add UI assertions for localized period, score, team colors, `saved locally`, and Queue count.
- [ ] Rework the Watch home into a dark high-contrast hierarchy: period/clock, score, connection status, then goal/foul/card actions.
- [ ] Keep goal/card save-and-return behavior and the red-card long-press confirmation unchanged.
- [ ] Run the full Watch UI suite on the current watchOS simulator and inspect a screenshot.
- [ ] Commit `feat: polish watch live match controls`.

### Task 5: End-to-end verification and pilot handoff

**Files:**
- Modify: `docs/FIELD_TEST_PROTOCOL.md`
- Modify: `docs/DEVICE_ACCEPTANCE_EVIDENCE.md`

- [ ] Run `swift test` and record the test count.
- [ ] Run iPhone UI tests on `Referee-iPhone` and Watch UI tests on the current Series 11 simulator.
- [ ] Build/install both apps with a clean DerivedData path and confirm the iPhone app fills the screen.
- [ ] Verify Korean default and English switch manually on simulator screenshots.
- [ ] Update the field protocol with the release commit and language checks.
- [ ] Commit `docs: record localized UI acceptance gate` and push `main`.

## Checkpoints

- After Task 2: localization must be complete before visual refactoring continues.
- After Task 3: iPhone pre/post-match flow must remain fully operable.
- After Task 4: Watch offline actions and red-card safety must remain fully operable.
- Task 5 is the release gate; no physical pilot claim is made until a human completes the protocol on paired hardware.
