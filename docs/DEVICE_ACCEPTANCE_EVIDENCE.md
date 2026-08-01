# Device Acceptance Evidence

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
