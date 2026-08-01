# Device Acceptance Evidence

## 2026-08-01 — Final review localization and Watch target rerun

- Current tested implementation head:
  `43bc55033e90fb569046d543ee276efd1c317309`
  (`fix: localize system values and Watch red targets`). It adds
  presentation-only mappings; persisted ledger/protocol values and
  accessibility identifiers remain unchanged.
- `swift test` passed 61/61 tests with zero failures: 3 XCTest
  `AppLanguageTests` plus 58 Swift Testing `LedgerStoreTests`.
- The full `RefereePhoneUITests` suite passed 9/9 with zero failures and zero
  skips on `Referee-iPhone` (iPhone 16 Pro simulator, iOS 18.3.1) in 243.688
  seconds. The new Korean regressions verified that a local sync-queue read
  failure does not expose its English protocol message and that a real
  `period_started` timeline row shows `전반`, not `First Half`. Result bundle:
  `/private/tmp/referee-final-phone-full/Logs/Test/Test-RefereePhone-2026.08.01_16-19-13-+0900.xcresult`.
- The full `RefereeWatchUITests` suite passed 3/3 with zero failures and zero
  skips on Apple Watch Series 11 (46 mm), watchOS 26.2, in 35.258 seconds. The
  direct-red regression verified an effective target of at least 44 points, no
  save after a short tap, and a queued save plus return to live after the
  one-second hold. Result bundle:
  `/private/tmp/referee-final-watch-full/Logs/Test/Test-RefereeWatch-2026.08.01_16-23-49-+0900.xcresult`.
- No paired-hardware pilot completion is claimed. Simulator automation does not
  attest physical haptics, representative-motion timing, or physical
  disconnect/reconnect behavior.

## 2026-08-01 — Timeline detail accessibility rerun

- Current tested implementation head:
  `57c8b1d255fd1b3a77c744f4f15eb39f5e39c97c`
  (`fix: make timeline detail rows accessible`).
- `swift test` passed 61/61 tests with zero failures: 3 XCTest
  `AppLanguageTests` plus 58 Swift Testing `LedgerStoreTests`.
- The focused
  `testCompleteMatchSignExportAndPresentShareSheet` passed 1/1 on
  `Referee-iPhone` (iPhone 16 Pro simulator, iOS 18.3.1). The repaired path
  opened event detail from the timeline row, completed signing, generated PDF
  and XLSX exports, and reached the share sheet. Result bundle:
  `/private/tmp/referee-task5-sign-export-57c8b1d.xcresult`.
- The full `RefereePhoneUITests` suite passed 8/8 with zero failures and zero
  skips on the same simulator in 172.309 seconds. Result bundle:
  `/private/tmp/referee-task5-phone-57c8b1d.xcresult`.
- This rerun supersedes the iPhone 7/8 result recorded below for
  `e416e7a`. The earlier failure remains retained as historical evidence; it
  is not the current iPhone gate result.
- The Watch 3/3 result, clean-build/install evidence, language screenshots,
  and their limitations remain documented in the earlier gate record below;
  the Watch suite was not rerun as part of this iPhone accessibility update.
- No paired-hardware pilot completion is claimed. A human referee and observer
  must still complete `docs/FIELD_TEST_PROTOCOL.md`; simulator automation does
  not attest physical haptics, representative-motion timing, or physical
  disconnect/reconnect behavior.

## 2026-08-01 — Localized UI release gate (superseded iPhone status)

- Release candidate implementation head:
  `e416e7a7f9c311caa63dfd80e405a26843875811`. The feature commit range is
  `d222a02684f3c6525df069ca532f09b81b8353e1..e416e7a7f9c311caa63dfd80e405a26843875811`.
- `swift test` passed 61/61 tests with zero failures: 3 XCTest
  `AppLanguageTests` plus 58 Swift Testing `LedgerStoreTests`.
- The full iPhone UI suite ran on `Referee-iPhone` (iPhone 16 Pro simulator,
  iOS 18.3.1): 8 test cases total, 7 passed and 1 failed. The result bundle is
  `/private/tmp/referee-task5-phone-e416e7a.xcresult`.
- The failing iPhone case is the existing
  `testCompleteMatchSignExportAndPresentShareSheet`. It reached the event
  timeline, found and tapped a `timeline.goal_recorded.*` row, but
  `event.details.player` did not appear. XCTest reported two assertions at
  `RefereePhoneUITests.swift:129-130`; the xcresult records one failed test
  case. This run does not hide, waive, or classify that baseline as passing.
- The full Watch UI suite passed 3/3 with zero failures on Apple Watch Series
  11 (46 mm), watchOS 26.2. Coverage included Korean hierarchy/team colors,
  the direct-red hold requirement, and offline foul queue persistence across
  termination and relaunch. The result bundle is
  `/private/tmp/referee-task5-watch-e416e7a.xcresult`.
- A focused Korean-to-English UI run passed 1/1. It asserted the Korean
  `경기`/`경기 생성` screen, selected English through `settings.language`, and
  asserted `Matches`/`Create match`. The result bundle is
  `/private/tmp/referee-task5-language-e416e7a.xcresult`.

### Clean build, install, launch, and screenshots

- `RefereePhone` built successfully from an initially absent DerivedData path
  at `/private/tmp/referee-task5-derived-phone-e416e7a`. The build retained one
  Swift concurrency warning at `RefereePhoneApp.swift:1455` about referencing
  actor-isolated `copy` from a `Sendable` closure.
- `RefereeWatch` built successfully from an initially absent DerivedData path
  at `/private/tmp/referee-task5-derived-watch-e416e7a`.
- The clean-built iPhone app installed and launched successfully. The first
  clean-install screenshot showed the Korean default and a full 1206×2622
  device canvas with no letterboxing. The screenshot is
  `/private/tmp/referee-task5-iphone-ko-e416e7a.png` (SHA-256
  `d10fcc1991e12d47792bc2149817eff1d1fa642e51bc86be2c5d46d6f378c34d`).
- The first Watch install attempt immediately after uninstall returned
  `IXErrorDomain` code 24 (`Uninstall requested`). Inspection confirmed the
  old app was absent; after CoreSimulatorService recovered, a sequential
  install of the same clean-built product succeeded and its app container and
  launch were confirmed.
- The Watch Korean screenshot is
  `/private/tmp/referee-task5-watch-ko-e416e7a.png` at 416×496 (SHA-256
  `1627825a1627b3df62c72d7e19d6fcebfccd0a4f736b8257a51f6da623bd39cd`).
  It shows `전반`, the 0–0 score, team names, and localized iPhone/queue status.
- After the in-app English switch test, relaunch preserved English. The
  1206×2622 screenshot shows `Matches`, `Create match`, `Language`, and
  `English` across the full device canvas:
  `/private/tmp/referee-task5-iphone-en-e416e7a.png` (SHA-256
  `318308a3f8fbdc46386b7d329c9084d6c973d6374eef53676f793c7cd8d30af4`).

### Superseded iPhone limitation and continuing human handoff

- The automated iPhone gate was not fully green at
  `e416e7a7f9c311caa63dfd80e405a26843875811`: its sign/export test failed
  before event detail. The 57c8b1d rerun above supersedes that iPhone result
  with focused 1/1 and full-suite 8/8 passing evidence.
- No paired-hardware pilot completion is claimed. A human referee and observer
  must complete `docs/FIELD_TEST_PROTOCOL.md` on the paired iPhone and Apple
  Watch before recording field acceptance.
- Simulator automation cannot attest that a person felt a Watch haptic.
  Physical disconnect/reconnect convergence, tap-to-home timing during
  representative movement, and all haptic patterns remain pending human
  evidence.
- Evidence stored under `/private/tmp` is local and temporary; copy the result
  bundles and screenshots to durable storage before clearing temporary files.

## 2026-07-20 — Simulator acceptance selected as the automated gate

- The user confirmed that physical-device compilation is not required for the
  current automated acceptance gate. Physical Watch evidence remains optional
  hardware coverage rather than a blocker.
- The paired `Referee-iPhone` and Apple Watch Series 11 simulator test passed
  in 11.489 seconds after the navigation and timing fixes.
- The automated Away Foul tap returned to the match home in approximately
  0.60 seconds, displayed `Queue 1`, survived app termination and relaunch,
  and displayed the durable `Queue 1` state again.
- The corresponding result bundle is
  `Test-RefereeWatch-2026.07.20_02-49-42-+0900.xcresult`.

## 2026-07-20 — Physical Watch automation after Mac restart

- Xcode and `devicectl` rediscovered the physical iPhone and Apple Watch as
  available paired devices after the Mac restart. The ipTIME N602E network is
  2.4 GHz-only, so the repeated preparation failures were not caused by the
  Watch being placed on a different Wi-Fi band.
- A physical Watch UI-test run progressed through installation and into the
  test body. It exposed a real small-device navigation race: quick-action
  `NavigationLink` state lived inside the once-per-second `TimelineView`, and
  the Foul link remained disabled during an interrupted transition on the
  slower physical Apple Watch SE.
- Quick actions now use explicit navigation state outside the timeline. The
  next physical run reached Away Foul, saved the event, returned home, showed
  `Queue 1`, terminated and relaunched the app, and again showed `Queue 1`.
  The only assertion failure was the reported 2.661-second duration.
- That duration was not a valid two-second measurement: XCTest's
  `waitForExistence` observed the returned home screen only on its next
  roughly one-second polling boundary. The acceptance test now polls the
  element at 50 ms intervals while retaining the strict two-second limit.
- The refined test passed on the paired Watch simulator in 11.576 seconds;
  its measured Away Foul tap-to-home observation completed in approximately
  0.62 seconds. All 53 ledger tests also passed.
- Final physical reruns of the refined test were blocked before the test body
  by intermittent Xcode/CoreDevice transport failures: personalized DDI
  preparation timed out in RemotePairing, the test-runner channel
  disconnected, or the destination remained busy connecting. Restarting the
  user CoreDevice and RemotePairing services temporarily restored access but
  did not keep the transport stable. These failures occurred despite both
  devices remaining listed as available and paired on the same LAN.

### Resume conditions

- Rerun the refined physical UI test only when optional hardware evidence is
  explicitly requested; it is no longer a release blocker for this gate.
- Preserve the current result bundles as evidence of the CoreDevice transport
  issue; do not classify the generic unlock/same-LAN recovery message as an
  SSID failure without additional evidence.
- Haptic sensation still requires a human observer; XCTest can exercise the
  save paths but cannot attest that a person felt the hardware haptic.

## 2026-07-19 — Physical-device acceptance (partial)

- Xcode detected `김기태의 iPhone` (iPhone 16, iOS 26.5.2) and
  `KATIE의 Apple Watch` (Apple Watch SE, watchOS 10.6.2) as available paired
  development devices.
- The `RefereePhone` device build succeeded with the signed `RefereeWatch`
  app embedded. The iPhone app was installed and launched successfully.
- The signed Watch app was also installed directly on the physical Watch and
  launched successfully.
- The physical iPhone end-to-end UI acceptance created a fixture, completed a
  goalscorer, confirmed both period boundaries through full time, signed the
  match report, generated real PDF and XLSX exports, and presented the system
  share sheet. It passed in 143.311 seconds.
- That physical run exposed duplicate parent/child accessibility elements for
  the SwiftUI sign-confirm button. The UI test now selects the first matching
  element and the full acceptance path passes on both simulator and device.
- The physical Watch UI acceptance runner installed twice, including once with
  both devices unlocked, but UI automation stopped before the test body both
  times with `LocalAuthentication` error `-9` (`context dealloc`). No
  foul-speed, persistence, or haptic result is claimed from those runs.
- The Watch app was launched with a dedicated seeded fixture for manual
  physical-device acceptance after the XCTest tooling failure.
- Physical use on the smaller Apple Watch SE exposed that the match home used
  a fixed vertical stack: the sync status was below the visible area but the
  screen could not scroll. The match home now uses a vertical scroll view; the
  signed device build was installed and finger/Crown scrolling to the queue
  status was confirmed on the physical Watch.

### Resume conditions

- Perform the Watch path manually and retain the repeated XCTest
  `LocalAuthentication` failure as a tooling limitation.
- After the connected baseline passes, disconnect the phone, record a Watch
  foul, verify its save haptic, terminate the Watch app immediately, relaunch,
  and confirm the durable queue before restoring connectivity.
- Record the observed short, double-short, long, failure, and repeating haptic
  patterns; these require a person wearing or holding the Watch.

## 2026-07-19 — Paired simulators

- Pair: iOS 18.3.1 `Referee-iPhone` with watchOS 26.2 Apple Watch Series 11
  (46 mm). `simctl list pairs` reported the pair as active and connected.
- Both `RefereePhone` and `RefereeWatch` built, installed, and launched on their
  respective simulators.
- The iPhone UI acceptance created a fixture, started the first half, and
  recorded a goal and foul. The test passed in 24.237 seconds.
- The paired Watch displayed `FIRST HALF`, the running clock, and the projected
  `1–0` score received from the iPhone match package.
- The Watch UI acceptance recorded an away foul, returned to the match home
  within the asserted two-second limit, showed `Queue 1`, terminated the Watch
  app, relaunched it, and again showed `Queue 1`. The test passed in 14.419
  seconds.
- The ledger suite passed all 53 tests, including paired-store restart,
  out-of-order delivery, duplicate delivery, reconnect convergence, and the
  full offline-Watch-to-signed-export acceptance path.

### Reproduction commands

```sh
swift test
xcodebuild -project Referee.xcodeproj -scheme RefereePhone \
  -destination 'platform=iOS Simulator,id=<paired-phone-id>' \
  -only-testing:RefereePhoneUITests/RefereePhoneUITests/testCreateFixtureAndRecordLiveActions test
xcodebuild -project Referee.xcodeproj -scheme RefereeWatch \
  -destination 'platform=watchOS Simulator,id=<paired-watch-id>' test
```

## Remaining hardware evidence

- Verify short, double-short, long, failure, and repeating haptics on a physical
  Apple Watch.
- Record a Watch foul while the phone is disconnected or in airplane mode,
  terminate immediately after the save haptic, and verify the queued event
  after relaunch.
- Restore connectivity and verify both devices converge to the same timeline,
  score, watermarks, and event digest with no duplicate event.
- Repeat the two-second foul capture measurement with a physical referee wearing
  the Watch during representative movement.
