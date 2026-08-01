# MVP Screen Inventory and User Flows

## Product boundary

The MVP supports one referee operating an 11-a-side adult or youth match.
The iPhone owns fixture setup, roster data, pitch-map detail, review, reports,
and recovery. Apple Watch owns the match clock and the fastest time-critical
records. Both devices must continue to work offline.

## Shared information architecture

- **Matches**: the iPhone home and the source of all match records.
- **Match hub**: the iPhone control centre for one fixture, grouped by stage:
  setup, live match, review, and report.
- **Timeline**: the immutable chronological event list. Corrections append an
  edit-history entry; they do not silently replace the original record.
- **Sync status**: visible but never blocks match operation. Each event has a
  local-save state and, once applicable, a sync state.

## iPhone screen inventory

The iPhone pre/post-match path uses a bright grouped-card presentation backed
by semantic background, surface, status, spacing, radius, and typography
tokens. Each stage has one visually primary action: create on the match list,
create/save the fixture, open match control after readiness, and sign the
reviewed report. Secondary save, timeline, setup, and export actions remain
available without competing with that stage action. Team names and kit-color
accents, readiness, and sync state stay visible on match control; none relies
on color alone for meaning.

| ID | Screen | Primary purpose | MVP actions |
| --- | --- | --- | --- |
| I-01 | Match list | Find, resume, or create a match | Primary Create match card; open draft/live/completed match; show local/sync status |
| I-02 | Create match | Enter the minimum fixture data | Grouped fixture card for competition, date/time, venue, home and away teams; primary create/save action |
| I-03 | Match setup hub | Complete pre-match requirements | Grouped preparation and readiness cards; visible kit accents; open fixture, crew, teams, rules, venue, and checklist; primary Open match control action |
| I-04 | Teams and lineups | Load or enter participants | Add players/officials; select starters; shirt number; captain; goalkeeper |
| I-05 | Crew and rules | Establish official context | Assign crew roles; set half length, extra time, penalties, substitutions, temporary dismissals, youth options |
| I-06 | Venue and pitch | Store dimensions and prepare location capture | Venue profile; length/width/orientation; grid snap; preview regions |
| I-07 | Pre-match checklist | Confirm readiness | Mark pitch, equipment, crew, lineup, and operational checks; add notes |
| I-08 | Match control | iPhone fallback live operation and Watch companion | Visible readiness, team kit accents, and Watch sync cards; start/hold-to-confirm period controls; score; added time; open timeline and review |
| I-09 | Quick event sheet | Record or enrich an event | Goal, foul, card, substitution, injury, penalty, VAR, restart; timestamp defaults to current clock |
| I-10 | Pitch-map detail | Record spatial foul/event location | Tap snapped location; adjust; confirm accuracy/capture method; show derived pitch region |
| I-11 | Timeline and event detail | Review and correct the match record | Filter; inspect event; complete missing fields; append correction/reversal with reason |
| I-12 | Period transition | Referee-confirmed boundary workflow | Confirm half/full time; enter added-time explanation; start next period or penalties |
| I-13 | Post-match review | Resolve report-readiness issues | Grouped review cards; mandatory-field checklist; timeline warnings; confirm final score and cards |
| I-14 | Reports | Produce official report drafts | Match/referee/incident drafts; edit report fields; primary sign-off action; PDF/spreadsheet export |
| I-15 | History and sync | Audit and recovery support | Per-event edit history; attachment status; retry sync; export/share approved files |

### iPhone navigation

`Match list → Create match → Match setup hub → Match control → Timeline / Period transition → Post-match review → Reports`

The match setup hub remains accessible throughout the match for non-urgent
corrections. During an active period, iPhone actions must not require the
Watch to be connected.

## Apple Watch screen inventory

| ID | Screen | Primary purpose | MVP actions |
| --- | --- | --- | --- |
| W-01 | Match home | One-handed live match operation | Large clock; period; fixed score; Foul, Card, Goal, More; connection/offline indicator |
| W-02 | Start/end confirmation | Prevent accidental clock changes | Hold to start, end, reset, or confirm direct red; success haptic |
| W-03 | Foul flow | Save a foul in two seconds | Choose team, optionally choose quick type; save timestamp immediately; defer location/detail to iPhone |
| W-04 | Card flow | Save a caution or dismissal quickly | Team → player → yellow/red → reason; red requires hold-to-confirm |
| W-05 | Goal flow | Save a goal quickly | Team → scorer; save; update score; scorer may be completed later on iPhone |
| W-06 | More actions | Less-frequent live controls | Added-time marker, injury, VAR, penalty, restart, substitution placeholder, open status |
| W-07 | Match status | Preserve confidence when disconnected | Current period, score, local queue count, iPhone connection, low-battery/sync warnings |

### Watch interaction rules

- W-01 is the default screen throughout a live period; the clock and score
  remain visible after every saved action.
- A quick event saves locally before returning to W-01. It never waits for
  iPhone acknowledgement.
- Team selection uses home/away names or unambiguous short labels, not colour
  alone.
- If player selection would slow a record, the event may be saved without a
  player and is flagged on iPhone review.
- Foul, goal, and ordinary actions receive the defined success haptic; cards
  and goals use the two-short haptic. Disconnection or low battery uses the
  strong repeating warning haptic.

## End-to-end flows

### 1. Create and prepare a fixture

1. On I-01, the referee chooses **Create match**.
2. On I-02, they enter the competition, scheduled time, venue, and teams, then
   save a draft. Only these minimum fields are required to create a record.
3. I-03 shows setup completion by section. The referee adds rosters/lineups
   (I-04), crew and competition rules (I-05), venue dimensions (I-06), and
   pre-match checks (I-07).
4. The app allows the match to start with incomplete optional data, but clearly
   identifies items that will be required before report sign-off.
5. If a Watch is paired, the iPhone sends a compact offline match package:
   match ID, teams, active roster, rules needed in play, period state, and
   event sequence watermark.

### 2. Start and operate a period

1. The referee opens I-08 to verify fixture and device status, then opens
   W-01.
2. On W-02, the referee holds to confirm **Start first half**. The clock starts
   at `00:00`; both devices display the same period state.
3. Routine stoppages do not stop the clock. When necessary, the referee records
   an added-time cause through W-06 or I-09; the main clock keeps counting up.
4. At regulation time, the display changes to `45+MM:SS` (or `90+MM:SS` in the
   second half). The app signals the threshold but never ends play itself.
5. Every action is written to the local event log with a device-generated ID,
   timestamp, period, and sequence. Sync occurs opportunistically.

### 3. Record a goal from the Watch

1. On W-01, tap **Goal**.
2. Select home or away, then select the scorer if immediately known.
3. Save; the event is stored locally, the score increments, and the Watch gives
   two short haptics before returning to W-01.
4. On iPhone, I-11 marks a missing scorer or assist for later completion without
   treating the goal itself as incomplete or unsaved.

### 4. Record a foul and pitch location

1. On W-01, tap **Foul**, select the team and an optional quick type, and save.
2. The Watch records exact match time and gives one short haptic. It does not
   ask for a pitch location.
3. At the next appropriate moment, on I-11 open the foul and choose **Add pitch
   location**.
4. On I-10, tap the pitch diagram. The app stores normalized 0–100 coordinates,
   metre coordinates calculated from the active venue dimensions, capture
   method, accuracy, and derived region.
5. The referee confirms the detail. The original Watch event remains in the
   timeline and its enrichment is auditable.

### 5. Record a card and handle a direct red

1. On W-01, tap **Card**, choose team, player, colour, and reason.
2. A yellow card saves immediately; the Watch gives two short haptics.
3. For a direct red, W-02 requires a hold-to-confirm before saving. This avoids
   an accidental dismissal while preserving the recorded match timestamp.
4. I-11 flags any required incident narrative or missing player detail for
   post-match completion.

### 6. Half-time, full-time, and exceptional periods

1. The referee selects **End period** on W-01 or I-08 and holds to confirm.
2. I-12 records the referee-confirmed boundary, locks the completed period's
   clock value, and asks only for any needed added-time reason.
3. The referee chooses the next configured period, extra time, or penalties.
   Each match-time period starts its own count-up clock at `00:00`.
4. After the final referee-confirmed boundary, the match enters review; it is
   not automatically report-final.

### 7. Offline operation and reconnection

1. If the Watch and iPhone disconnect, W-07 states that events are saving on
   the Watch. Match actions remain available.
2. If the iPhone is offline, it saves its own events locally and presents a
   non-blocking sync indicator.
3. On reconnect, devices exchange event IDs and sequence watermarks, then copy
   missing immutable events in chronological order.
4. A conflict never silently overwrites an event. I-15 shows both records and
   requests the referee's resolution; the resolution is appended to history.
5. The strong repeating haptic is reserved for a sustained sync failure,
   disconnection state, or low battery—not routine offline use.

### 8. Review, sign-off, and export

1. After full time, I-13 evaluates the timeline, score, periods, cards, and
   required incident details.
2. The referee fills missing details in I-11, including pitch locations and
   incident narratives where required by the report type.
3. On I-14, the app generates draft match, referee, and incident reports from
   the event timeline. The referee may edit report-specific prose without
   changing the underlying event record.
4. Validation identifies missing mandatory fields. After they are resolved, the
   referee signs off; the signed report version and its edit history are kept.
5. The referee exports PDF and spreadsheet files for the approved upload
   workflow. Direct association submission remains out of scope for MVP.

## MVP acceptance checks

- A referee can save a Watch foul with team and timestamp in two seconds or
  less, without an iPhone connection.
- A Watch goal and card update the local match record and return to the main
  clock without requiring a modal review.
- The iPhone can add a foul location retaining normalized coordinates, metre
  coordinates, venue dimensions, capture method, and accuracy status.
- Period boundaries and direct reds require hold-to-confirm; routine stoppages
  do not pause the clock.
- A completed match cannot be signed off while report-required data is missing,
  but the underlying match record remains editable through auditable
  corrections.
- Reconnection preserves both devices' locally saved events and exposes, rather
  than silently resolves, conflicts.

## Deliberate MVP decisions

- The Watch does not capture pitch locations, free-form narratives, photos, or
  voice notes; these are iPhone follow-up actions.
- Player selection is optional at live-event capture time, except where an
  immediately known player is needed for operational confidence. Report
  validation handles the required completion later.
- The iPhone is the report-sign-off authority. A Watch can operate a match
  independently for a limited offline interval but cannot finalize reports.
- Penalty shoot-out support records kicks and outcome in the match record; it
  does not use the normal count-up match clock.
