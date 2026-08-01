# MVP Domain Model and Offline Sync

## Design goals

- Every match-time action is locally durable before the UI confirms success.
- The event timeline is append-only. Corrections and reversals are new events.
- iPhone and Apple Watch may create events independently while disconnected.
- Reports use a derived, reviewable match state rather than mutable event rows.
- The MVP has one accountable referee per match record; crew collaboration is deferred.

## Entity model

| Entity | Purpose | Core fields |
| --- | --- | --- |
| `Match` | Fixture and lifecycle aggregate | `id`, competition, scheduledAt, venueId, homeTeamId, awayTeamId, status, activePeriodId |
| `Team` | Reusable club/team identity | `id`, displayName, shortName, associationId? |
| `MatchTeam` | A team's role in this match | `id`, matchId, teamId, side, displayNameSnapshot, score |
| `Person` | Reusable player or official identity | `id`, displayName, dateOfBirth?, registrationNumber? |
| `MatchParticipant` | Roster/official snapshot for one match | `id`, matchId, personId?, teamSide?, role, shirtNumber?, isStarter, displayNameSnapshot |
| `RefereeCrewAssignment` | Official appointment snapshot | `id`, matchId, participantId?, crewRole, displayNameSnapshot |
| `CompetitionRuleSet` | Rules applied to this fixture | `id`, matchId, halfDurationSeconds, extraTimeEnabled, penaltyShootoutEnabled, substitutionLimit? |
| `VenueProfile` | Reusable venue and pitch definition | `id`, name, pitchLengthMetres, pitchWidthMetres, orientationDegrees?, calibratedCorners? |
| `MatchPeriod` | A referee-confirmed time segment | `id`, matchId, kind, ordinal, durationSeconds?, startedAt?, endedAt?, clockState |
| `MatchEvent` | Immutable operational fact in the timeline | Common event envelope plus type-specific payload |
| `EventRevision` | Auditable correction/reversal relationship | `id`, targetEventId, revisionEventId, reason, createdAt |
| `Attachment` | Optional evidence tied to an event or report | `id`, ownerType, ownerId, localPath, mediaType, checksum, syncState |
| `ReportDraft` | Derived report content and sign-off versions | `id`, matchId, kind, contentVersion, generatedFromEventCursor, status, signedAt? |
| `SyncCursor` | Per-peer replication progress | `id`, matchId, peerDeviceId, lastAcknowledgedSequence, lastSuccessfulSyncAt, state |

`?` means optional in MVP. A match stores snapshots of display names, roster data, rules, and venue dimensions so later master-data edits cannot alter an official historical report.

## Match lifecycle

`draft → ready → live → review → signed_off → exported`

- `draft`: minimum fixture exists.
- `ready`: pre-match work may still be incomplete, but the fixture is ready to start.
- `live`: a period has started. Operational events are accepted.
- `review`: final period is referee-confirmed; event details may be completed and corrected.
- `signed_off`: a validated report version is signed. Subsequent changes create a new report version and require a new sign-off.
- `exported`: an export was created; this is additive and does not prevent a later corrected version.

## Event log

### Common envelope

Every `MatchEvent` has the following fields, independent of its type.

| Field | Description |
| --- | --- |
| `eventId` | UUID generated on the creating device; globally unique and immutable |
| `matchId` | Parent match UUID |
| `eventType` | Type from the catalog below |
| `schemaVersion` | Payload schema version for safe future migration |
| `originDeviceId` | Stable installation/device ID, not a person identifier |
| `originSequence` | Strictly increasing integer allocated by that device for this match |
| `recordedAt` | UTC instant when the referee saved the action |
| `matchPeriodId` | Current period; nullable only for pre/post-match events |
| `matchClockMs` | Count-up time in the current period at capture; nullable outside play |
| `effectiveAt` | Optional corrected match-time placement; never replaces `recordedAt` |
| `payload` | Type-specific, JSON-serializable values |
| `localState` | `saved`, `pending_sync`, `synced`, or `sync_failed` |
| `supersedesEventId` | Target event for a correction or reversal; otherwise null |
| `integrityHash` | Hash of canonical envelope/payload fields for corruption detection |

The ordering key for display is `effectiveAt` when set, otherwise period ordinal plus `matchClockMs`, then `recordedAt`, `originDeviceId`, and `originSequence`. This is a deterministic presentation order, not permission to rewrite history.

### Event catalog

| Event type | Required payload | Notes |
| --- | --- | --- |
| `period_started` | `periodKind`, `ordinal` | Created only after hold-to-confirm |
| `period_ended` | `periodKind`, `ordinal`, `finalClockMs` | Referee-confirmed boundary |
| `goal_recorded` | `teamSide`, `scorerParticipantId?`, `ownGoal?` | Score projection increments unless reversed |
| `foul_recorded` | `teamSide`, `foulType?` | Pitch data is initially optional |
| `card_recorded` | `teamSide`, `playerParticipantId?`, `colour`, `reason?`, `isDirectRed` | Direct red has confirmation metadata |
| `substitution_recorded` | `teamSide`, `playerOutId?`, `playerInId?` | Watch UI remains a later enhancement |
| `penalty_awarded` | `teamSide`, `reason?` | Match incident, not shoot-out kick |
| `injury_recorded` | `teamSide?`, `participantId?`, `severity?` | Narrative follows on iPhone |
| `var_recorded` | `decision`, `reason?` | Available when competition rules permit it |
| `restart_recorded` | `restartType`, `teamSide?` | Optional operational event |
| `stoppage_time_recorded` | `cause`, `durationMs?` | Does not pause the match clock |
| `shootout_kick_recorded` | `teamSide`, `outcome`, `kickOrdinal` | No count-up match-clock requirement |
| `location_added` | `targetEventId`, spatial location payload | Enriches a spatial event such as a foul |
| `detail_added` | `targetEventId`, structured fields/narrative | Completes an event without rewriting it |
| `event_corrected` | `targetEventId`, `replacementEventType`, `replacementPayload`, `reason` | Creates a replacement interpretation; the replacement fields are projected instead of the target |
| `event_reversed` | `targetEventId`, `reason` | Removes target from projected active state |
| `report_signed` | `reportDraftId`, `contentVersion`, signer snapshot | Sign-off is an explicit audit event |

Event-specific validation happens on creation when possible and again before report sign-off. A Watch may save `card_recorded` without a player when necessary, but a selected report template may later require that detail.

### Location payload

```text
targetEventId
normalizedX, normalizedY          // 0…100
metresFromGoalLine, metresFromTouchline
pitchLengthMetres, pitchWidthMetres
captureMethod                     // pitch_tap | gps_assisted | later_correction
accuracyStatus                    // referee_confirmed | estimated | unconfirmed
derivedRegion                     // e.g. defending_half, left_penalty_area
```

The pitch dimensions are copied into the payload even though the venue profile also stores them. This preserves the conversion basis if the venue changes. GPS is never official proof of location.

## Projected match state

The app calculates live state from all valid events in deterministic order. It never uses a manually edited score as its authoritative source.

- Score: count active `goal_recorded` events by `teamSide`.
- Cards: count active `card_recorded` events and show associated corrections.
- Period: latest active `period_started` without a later `period_ended`.
- Clock: device monotonic elapsed time while live, anchored by the latest confirmed period start; persist periodic clock checkpoints locally.
- Roster state: initial lineup plus active substitutions.
- Review warnings: incomplete report-required fields, unresolved revision chains, missing required pitch data, or incompatible rule constraints.

Corrections are applied by following `supersedesEventId` chains. If a chain is ambiguous or cyclic, it is excluded from the official projection and surfaced as a blocking review warning.

## Local persistence requirements

- Use a transactional local store on each device. Write event data, outbox entry, and sequence allocation in one transaction before showing success.
- Retain the original encoded event payload, migration version, and integrity hash; never only retain a projected score or timeline.
- Keep attachments as local files with checksums and a separate resumable upload state. Attachment transfer never blocks event replication.
- Store time as UTC instants plus explicit match-clock milliseconds. Do not derive historical clock time from wall-clock time after the fact.
- Back up the iPhone database under the user’s chosen backup policy; Watch data is a short-lived independent replica until acknowledgement by iPhone.

## Replication and reconciliation

### Protocol

1. On pairing/reconnection, each device exchanges `matchId`, `deviceId`, known origin-sequence ranges per device, and a compact event-ID digest.
2. Each side requests missing immutable events by origin device and sequence range, validates schema and integrity hash, then commits them transactionally.
3. The receiver acknowledges only committed events. The sender retains its outbox until acknowledgement.
4. After events, devices exchange attachment manifests. Missing attachments transfer resumably and independently.
5. The iPhone produces the user-facing projection and sync summary. The Watch only needs enough replicated data to show the active match accurately.

### Conflict policy

| Situation | Automatic handling | Referee action |
| --- | --- | --- |
| Same event appears on both devices | Deduplicate by `eventId` and verify matching hash | None unless hashes differ |
| Different events at the same clock time | Keep both; use deterministic display order | Review if they describe the same incident |
| Goal/card entered twice for one incident | Keep both events and flag possible duplicate | Append correction or reversal with a reason |
| Conflicting period boundary | Keep both; mark period state unresolved | Choose authoritative boundary via correction |
| Event lacks player/location detail | Keep event valid operationally | Add a detail/location event on iPhone |
| Event payload/hash invalid | Quarantine from official projection | Retry transfer or resolve from source device |

No sync operation may overwrite an existing event or automatically discard a locally saved event. A redacted/reversed event remains visible in audit history.

### Watch disconnect behavior

- The Watch creates events using its own `originDeviceId` and local sequence.
- It holds an offline match package containing active fixture snapshots, roster, current period, and recent event digest.
- It displays local save success immediately. It does not claim cloud/iPhone sync success until acknowledged.
- If its event queue or storage is at risk, it uses the defined strong warning haptic and directs the referee to reconnect; it must not silently drop data.

## Report versioning and sign-off

1. A report draft records the exact event cursor and event IDs used to generate it, plus template version and structured prose fields.
2. A signed report version is immutable and references the sign-off event.
3. A later event correction leaves the old signed version intact, marks it superseded for operational use, and generates a new draft for validation and sign-off.
4. PDF/spreadsheet exports include report version, generation time, and match identifier so an uploaded file is traceable to its record.

## MVP decisions and open implementation constraints

- `event_corrected` and `event_reversed` require a reason in review and after sign-off. The live iPhone may offer a quick correction, but it must still create the audit event.
- Cloud backup/sync provider selection is intentionally deferred; this contract works for phone–Watch transfer and a future server.
- The clock checkpoint interval, database technology, encryption-at-rest implementation, and attachment size limits are engineering decisions to make before implementation. They do not change the event contract.
- Direct association submission is not modeled as a sync destination in MVP; export/upload remains the handoff.
