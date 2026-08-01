# Referee App Project Context

## Product Goal

Build a football referee application for iPhone and Apple Watch. The first
target users are Korea Football Association (KFA) and regional-association
certified referees. The app must support match operation, official match and
referee reports, and eventually association submission workflows.

Android and Wear OS support will follow after the iPhone and Apple Watch MVP.

## Product Principles

- The referee must be able to record an incident within two seconds.
- Apple Watch is for immediate, one-handed match-time actions.
- iPhone is for setup, detail entry, review, reports, and corrections.
- The app works offline during a match and synchronizes later.
- Official reports retain an auditable event and edit history.

## Match Workflow

### Before the match

- Create or import a fixture: competition, date, venue, home and away teams.
- Configure referee crew: referee, assistant referees, fourth official, and
  match commissioner.
- Load teams, players, officials, and starting lineups.
- Set competition rules: half length, extra time, penalties, substitutions,
  temporary dismissals, and youth formats.
- Select a venue profile and its exact pitch dimensions.
- Complete a pitch and match-operation checklist.

### During the match

- Count-up match timer for each half, extra time, and penalties.
- Score, goalscorer, cautions, dismissals, substitutions, fouls, penalties,
  injuries, VAR, suspensions, and restarts.
- Log severe incidents with a note, voice note, or photo when appropriate.
- Run locally without an iPhone connection; reconcile safely on reconnect.

### After the match

- Review the event timeline and complete missing details.
- Produce match, referee, and incident report drafts.
- Validate mandatory fields, confirm referee sign-off, and keep edit history.
- Export PDF and spreadsheet formats.
- Initial submission approach: approved report files and upload workflow.
- Future submission approach: KFA/regional association partnership and API
  integration.

## Apple Watch Interaction

### Main match screen

- Large current match time.
- Small half/period label.
- Fixed score display.
- Four large actions: foul, card, goal, and more.

### Fast actions

- Foul: team, type, and timestamp. Pitch position may be completed on iPhone.
- Card: team, player, card colour, and reason. Red cards require hold-to-
  confirm.
- Goal: team, scorer, and timestamp.
- Substitution: a later MVP enhancement; choose team, player out, player in.

### Timer rules

- Match clock counts up from 00:00 in every half.
- Do not stop the clock for routine stoppages.
- Track stoppage time separately for injuries, VAR, delayed restarts, or
  suspensions.
- At 45:00 or 90:00 show time as `45+MM:SS` or `90+MM:SS`.
- The referee, not the app, confirms half-time and full-time.
- Start, end, reset, and direct-red-card actions use hold-to-confirm.

### Haptics

- One short haptic: ordinary event saved.
- Two short haptics: goal or card saved.
- One long haptic: period boundary or added-time start.
- Strong repeating haptic: sync failure, disconnected state, or low battery.

## Pitch Size and Event Location

Pitch dimensions matter. Store both representations for every spatial event:

- Physical coordinates in metres from a defined goal line and touchline.
- Normalized coordinates from 0 to 100 on both axes.
- Venue pitch length and width used for the conversion.
- Capture method: pitch tap, GPS-assisted, or later correction.
- Accuracy status: referee-confirmed, estimated, or unconfirmed.

Venue profiles include venue name, address, surface, pitch length, pitch width,
orientation, and optional calibrated pitch corners.

Use a phone pitch diagram with configurable grid snapping for foul locations.
The diagram automatically identifies regions such as penalty area, goal area,
left/centre/right, and attacking/defending half.

GPS must not be treated as official proof of a foul location. It is optional
and only supports referee movement distance, path, and positioning heatmaps.

## Monetization

- Free: basic timer, scores, goals, cards, and a limited basic report.
- Referee Pro: unlimited matches, official templates, PDF/spreadsheet export,
  evidence attachments, backups, advanced reports, foul maps, and heatmaps.
- Association B2B: association templates, referee assignments, administrator
  review, organization controls, and approved direct-submission integration.

Use a free download plus in-app purchases/subscriptions. Do not rely on
changing a previously free app into a paid-download app later.

## MVP Scope

1. 11-a-side official adult and youth matches.
2. iPhone setup and review plus Apple Watch match operation.
3. Timer, score, goals, fouls, yellow/red cards, stoppage time, and haptics.
4. Venue dimensions and manual pitch-map foul coordinates.
5. Offline local storage and sync recovery.
6. Match/referee/incident report PDF drafts and edit history.

## Deferred Work

- Direct KFA or regional association submission integration.
- Referee crew real-time collaboration.
- Android and Wear OS apps.
- Futsal, 8-a-side, and 7-a-side rules/templates.
- GPS positioning heatmaps.
- Video synchronization and analysis.

## MVP Report, Validation, and Export Policy

### Report set

The iPhone generates three derived report drafts from the same immutable event
projection. A report draft may contain referee-written prose, but it never
edits event data.

| Report | Purpose | MVP content |
| --- | --- | --- |
| Match report | Official summary of the fixture and result | Fixture and venue snapshots; competition rules; referee crew; confirmed periods; final score; goals; cards; substitutions; penalties; shoot-out result; added-time summary; referee declaration |
| Referee report | Operational record for the referee | Match report summary plus lineup/participant snapshots, disciplinary and foul log, injuries, VAR/restarts when recorded, pitch-location appendix, and operational notes |
| Incident report | Standalone record for serious or disciplinary incidents | One incident per report: linked event(s), match context, people/teams involved, exact match time, narrative, location when available, attachments list, and referee statement |

- A match report is always available after a fixture is created, but only its
  validated version may be signed or exported as official.
- A referee report is generated for every match and may state that a category
  had no recorded events.
- An incident report is created for each direct red and for any event the
  referee explicitly marks as requiring an incident narrative. Yellow cards,
  injuries, VAR, or other events may also create one when the referee chooses.
- Reports show display-name, roster, rule, and venue snapshots from the match,
  never later-edited master data.

### Validation rules

Validation runs in post-match review and again immediately before sign-off.
Warnings may remain in a draft; blocking errors may not.

| Area | Blocking before sign-off | Non-blocking warning |
| --- | --- | --- |
| Fixture | Competition, scheduled date, venue name, home/away display names, and distinct teams | Venue address, orientation, or association identifiers missing |
| Match completion | A valid, unambiguous final `period_ended`; no active period; period sequence permitted by the applied rules | Checklist items or optional crew roles incomplete |
| Timeline integrity | All report-included events have valid hashes/schema; no unresolved correction/reversal chain, duplicate warning, or quarantined event affecting the official projection | Synced state is pending; export remains possible from the local signed version |
| Score and periods | Projected score is confirmed by the referee; goals have a valid team; shoot-out data is complete when used to decide the result | Goal scorer unknown |
| Discipline | Every card has team and colour; every direct red has a player, reason, and incident report with narrative | Yellow-card player/reason missing unless the selected template later requires it |
| Required incidents | Every direct red and referee-marked serious incident has a completed narrative and linked events; referenced attachments, if any, are locally readable | Attachment upload/sync pending |
| Spatial data | A location is required only when the referee marks an incident as location-required; it must include normalized/metre values, pitch dimensions, capture method, and accuracy | Ordinary fouls without a location |
| Signer | A designated accountable referee snapshot, explicit declaration, and current report content version | Missing optional crew confirmation |

- Corrections or reversals used in review require a reason. A correction chain
  that is cyclic, ambiguous, or unresolved blocks every affected report.
- Narrative text is report content, versioned separately from events. It must
  identify the incident and not contradict the linked event projection; any
  mismatch is a blocking review item until resolved by an event correction or
  prose edit.
- No network, iPhone-Watch connection, or completed cloud upload is required
  for sign-off. Local event integrity and local report files are required.

### Sign-off and version policy

1. On the iPhone, the accountable referee reviews the validation result and
   signs an explicit declaration for a selected report version. The app appends
   a `report_signed` event with the report ID, content version, and immutable
   signer snapshot.
2. Signing freezes that report version, its template version, structured prose,
   event-ID set/cursor, validation result, and generation timestamp. It does
   not freeze the match event log.
3. A later event addition, correction, reversal, or report-prose edit marks
   affected signed reports as superseded for operational use. The old version
   remains viewable and may be re-exported only as a clearly labelled
   historical copy; the replacement is a new draft that must validate and be
   signed again.
4. Signing the match report is required before its official export. Signing a
   referee or incident report is independently required before that report's
   official export. A signed match report does not sign its incident reports.
5. Only the iPhone may sign. The Watch may record events but cannot create,
   sign, or export reports.

### Export policy

- An official export is first created only from a signed, current version in
  PDF and spreadsheet (`.xlsx`) formats. A signed superseded version may only
  be re-exported as a historical copy labelled `SIGNED — SUPERSEDED`. The
  basic free report may be previewed but official templates and exports are
  Referee Pro capabilities.
- PDF is the presentation/submission copy. Spreadsheet is a structured event
  appendix: one row per active projected event plus event ID, original and
  effective timing, revision relationship, and relevant location values.
- Every file includes match ID, report kind, report content version, template
  version, signing time, generation time, and a human-readable status such as
  `SIGNED — CURRENT` or `SIGNED — SUPERSEDED`. It must never represent an
  unsigned draft as official.
- Export creates an additive audit record with the file checksum, format,
  generated time, and report version. Re-exporting the same signed version is
  allowed and creates another audit record; it does not alter the signed
  report.
- Files may be shared/uploaded through the operating system only after export.
  Direct KFA or regional-association submission and any claim that an upload
  was accepted are outside the MVP.

## Completed P0 Foundation

- Rules-driven first half, half-time, second half, optional extra-time, and
  full-time lifecycle derived from append-only period boundary events.
- Explicit match list, fresh-ID `Create match`, and state-restoring
  `Resume match` flows with per-match Watch packages.
- iPhone event timeline with append-only correction and reversal actions.
  Revisions require a reason, preserve the original match period and clock,
  and leave the original ledger event visible as revised.
- Match-owned home/away player rosters and accountable-referee snapshots,
  persisted in SQLite and included in the offline Watch match package.
- iPhone goal/card detail completion through append-only corrections. Player
  identity and display snapshots are copied into the replacement payload;
  cards require a disciplinary reason and direct reds additionally require an
  incident narrative flagged for an incident report.
- Derived post-match validation for fixture and period completion, timeline
  integrity, score confirmation, accountable referee, goal/card detail
  warnings, and blocking direct-red details and narratives.
- Independently versioned report prose and immutable signed report versions.
  Signing atomically appends a `report_signed` audit event, freezes the signer,
  validation result, source event IDs, template/content versions, and source
  fingerprint, while later event or prose changes derive a superseded status.
- iPhone post-match review and sign-off UI for match, referee, and incident
  reports. It separates blocking errors from warnings, requires explicit final
  score confirmation and referee declaration, confirms the irreversible sign
  action, and shows current versus superseded immutable version history.
- Signed-version PDF and XLSX export on iPhone. Signing now freezes fixture,
  participant, and rule snapshots for historical rendering; exports use the
  frozen effective event set, label current versus superseded copies, include
  report/version/timing/revision/location metadata, calculate a SHA-256 file
  checksum, append an export audit row, and expose the system share sheet.
- Report-content editing and incident-report identity on iPhone. Match and
  referee reports now have stable document identities, each qualifying serious
  event creates one independently signable incident document, and incident
  documents explicitly retain their primary and linked immutable event IDs.
  Structured summary, description, action-taken, and additional-note fields
  create immutable content versions; changing them visibly supersedes only the
  affected signed document.
- iPhone report attachments and local integrity. Photos and arbitrary files
  are copied into private, file-protected storage under checksum-derived paths;
  immutable SQLite metadata links each attachment to its report document.
  Required unreadable or checksum-invalid files block that document's sign-off,
  attachment changes supersede only the affected signed document, and every
  signed version freezes its attachment list for PDF and XLSX export metadata.
- Independent resumable attachment transfer and startup recovery. Attachment
  manifests and chunk acknowledgements use their own transfer rows and outbox
  messages, so event acknowledgement never waits for file delivery. Receivers
  persist contiguous staging progress, resume after restart, verify declared
  byte count and SHA-256 before promotion, retain pending/failed/completed
  status for the UI, and remove only staging files not referenced by an active
  transfer.
- Manual pitch-map location enrichment. Match setup persists regulation-range
  pitch dimensions; iPhone timeline actions can append immutable
  `location_added` events for fouls and location-required incidents. Every
  event freezes normalized and metre coordinates, the dimensions used for
  conversion, capture and accuracy metadata, and derived pitch regions.
  Location-required incident review now blocks sign-off until the spatial
  snapshot exists, and incident documents link the location event into their
  signed source fingerprint.
- Visible iPhone–Watch reconciliation. Both apps surface reachability, durable
  outbox counts, last peer contact, and actionable immediate-delivery errors
  without blocking local match actions. Activation and reachability recovery
  automatically exchange watermarks and retry pending immutable events; users
  can also retry explicitly. Paired persistent-store coverage proves offline
  durability, restart recovery, out-of-order and duplicate idempotency, and
  bidirectional reconnect convergence to the same event digest.
- Remaining match-action vocabulary and report projection. Substitutions,
  penalties, injuries, VAR reviews, match suspensions/resumptions, and restarts
  now use stable shared event types with capture-time payload validation on
  local and replicated writes. Watch quick capture can defer player/outcome
  details; iPhone appends those details as immutable corrections and surfaces
  blocking or warning review issues. Every active effective action is retained
  by signed report fingerprints and the generic PDF/XLSX event appendix.
- Match-operation acceptance hardening. A paired-store end-to-end regression
  now covers fixture packaging, disconnected Watch period/goal/foul capture,
  reconnect convergence, scorer and pitch-location completion, full time,
  validation, signing, immutable export snapshots, and PDF/XLSX audit rows.
  An iPhone UI test exercises fixture creation, hold-to-start, live goal/foul
  actions, score projection, and timeline visibility on a simulator. Explicit
  Phone and Watch schemes keep platform builds isolated. This work also fixed
  an iPhone lifecycle gap where locally saved quick actions updated the score
  but did not refresh the in-memory timeline until relaunch or peer sync.
- Full iPhone UI acceptance automation. A simulator regression now creates a
  seeded fixture, records and completes a goalscorer detail, confirms both
  period boundaries through full time, validates and signs the match report,
  generates real PDF and XLSX exports, and verifies system share-sheet
  presentation. Stable accessibility identifiers cover every report action.
- Watch durability and speed acceptance automation. A dedicated watchOS UI
  regression seeds an offline fixture, records a foul, verifies the quick flow
  returns to the match home inside two seconds, and confirms the durable queue
  survives app termination and relaunch. Goal and foul saves now dismiss their
  quick-action screens as required by the Watch interaction contract. A
  genuinely paired simulator run also confirmed that the Watch received the
  iPhone fixture, active first-half state, and projected 1–0 score.
- Small-screen Watch usability hardening. Physical Apple Watch SE acceptance
  found that the fixed match-home stack clipped sync/queue status below the
  visible area. The home is now vertically scrollable, and finger/Crown access
  to the queue status was verified on the physical device.

## Next Task

The current automated Watch acceptance gate is complete on the paired
iPhone–Watch simulators. The refined test passes foul capture in approximately
0.60 seconds, durable Queue 1 persistence across termination and relaunch, and
the strict two-second assertion. Physical Watch compilation and XCTest are
optional hardware evidence rather than a blocker; only return to the unstable
CoreDevice/RemotePairing path when explicitly requested. Select the next MVP
product increment before implementation.
