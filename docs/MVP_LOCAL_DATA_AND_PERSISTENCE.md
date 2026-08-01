# MVP Local Data Model and Persistence Boundaries

## Purpose

This document makes the event and sync contract in
[MVP_DOMAIN_AND_SYNC.md](MVP_DOMAIN_AND_SYNC.md) implementable. It is
technology-neutral: SwiftData, Core Data, SQLite, or an equivalent store is
acceptable only if it preserves these transaction boundaries and invariants.

Each device has an independent local database. The iPhone is the long-lived
record and report authority. The Watch is a short-lived independent replica
that can save match actions without connectivity.

## MVP implementation decision

The shared iPhone/Watch persistence layer is implemented as a Swift package
(`RefereeLedger`) backed by SQLite. It uses the platform SQLite library,
Foundation for canonical JSON parsing, and CryptoKit SHA-256. App targets own
their database location and dependency wiring; the package owns ledger
transactions, canonical event hashing, local per-device sequence allocation,
and event outbox creation. This avoids making a SwiftData object graph the
only representation of accepted events and gives both devices identical
transaction semantics.

## Storage boundaries

| Area | Source of truth | Mutability | Retention |
| --- | --- | --- | --- |
| Fixture, roster, rules, venue | Match-owned snapshots | Setup changes create/update snapshots; reports copy them | iPhone: match lifetime; Watch: active package lifetime |
| Event ledger | Event and revision records | Append-only | iPhone: match lifetime; Watch: until acknowledgement and safe retention |
| Match projection | Derived cache | Rebuildable | May be deleted and rebuilt from ledger |
| Report version | Version snapshot | Draft prose versioned; signed versions immutable | iPhone: match lifetime |
| Attachments | Private files plus metadata | Immutable after checksum | Match lifetime / future retention policy |
| Replication | Outbox, receipt, cursor | Delivery state only | Until acknowledgement and retention expiry |

The database must never hold an event's only copy in a projection, report, or
outbox. Attachment bytes live in private filesystem storage; attachment owner,
path, checksum, and transfer status live in the database.

## Identifiers, encoding, and time

- IDs are UUIDs generated before writing. An `event_id` is never regenerated.
- Instants are UTC values with millisecond precision; `match_clock_ms` is a
  separate integer and is never retrospectively derived from wall-clock time.
- Enums are stable lowercase strings. Unknown future values are retained and
  quarantined from official projection, never coerced.
- Payload JSON uses UTF-8 canonical JSON: sorted object keys, no insignificant
  whitespace, invariant number formatting, and explicit nulls only when valid.
- `integrity_hash` is SHA-256 of canonical UTF-8 containing `eventId`,
  `matchId`, `eventType`, `schemaVersion`, `originDeviceId`,
  `originSequence`, `recordedAt`, `matchPeriodId`, `matchClockMs`,
  `effectiveAt`, `supersedesEventId`, and `payload`. Delivery state,
  local row IDs, and received time are excluded.

## Local relational model

### Fixture snapshots

| Table | Key fields | Invariants |
| --- | --- | --- |
| `match` | `id PK`, competition snapshot, scheduled time, lifecycle state, active period | One fixture aggregate; lifecycle is a cache, not authoritative history |
| `match_team` | `id PK`, `match_id FK`, side, display-name snapshot | Unique `(match_id, side)` for home and away |
| `participant_snapshot` | `id PK`, `match_id FK`, source person?, team side?, role, display-name snapshot, shirt number?, starter/captain/goalkeeper flags | Match-local roster and officials |
| `crew_assignment` | `id PK`, `match_id FK`, participant?, crew role, display-name snapshot | Includes the accountable referee |
| `rule_set_snapshot` | `id PK`, `match_id FK UNIQUE`, schema version, rules JSON, canonical hash | Contains time, extra-time, shoot-out, substitutions, youth options |
| `venue_snapshot` | `id PK`, `match_id FK`, venue/address/surface, dimensions, orientation?, corners JSON? | Dimensions are match-owned and immutable report inputs |
| `match_period` | `id PK`, `match_id FK`, kind, ordinal, configured duration?, start/end event?, checkpoint? | Unique `(match_id, ordinal)`; boundaries derive from ledger events |
| `checklist_item` | `id PK`, `match_id FK`, kind, completion time?, note? | Setup aid; only explicit report rules can make it blocking |

Reusable team, person, and venue profiles may exist on iPhone for data entry.
Report generation always uses these match-owned snapshots, never a current
master-data join. The Watch receives only the active snapshots it needs.

### Immutable event ledger

| Table | Key fields | Invariants |
| --- | --- | --- |
| `device_sequence` | `match_id FK`, `origin_device_id`, next sequence | PK `(match_id, origin_device_id)`; allocated inside event-save transaction |
| `event` | `event_id PK`, match, type, schema, origin device/sequence, recorded/effective time, period/clock, payload canonical JSON, hash, supersedes?, accepted time | Unique `(match_id, origin_device_id, origin_sequence)`; accepted bytes never update |
| `event_revision` | `id PK`, match, target event, revision event, kind, reason, created time | Revision event unique; correction/reversal reason required |
| `event_validation` | `event_id PK/FK`, schema/hash/projection status, diagnostics, validated time | Derived and recomputable; never part of hash |
| `quarantined_event` | `event_id PK`, source peer, raw envelope, failure code, diagnostics, time, resolved time? | Retained for recovery and excluded from official projection |

Insertions are idempotent. An incoming existing event ID must have identical
canonical bytes and hash. A mismatch is an integrity failure: preserve the
evidence in quarantine, do not overwrite local data, and do not acknowledge
the conflicting copy.

### Projections and review

| Table | Key fields | Invariants |
| --- | --- | --- |
| `match_projection` | `match_id PK`, projection cursor, scores, active period?, lifecycle, projection JSON, rebuilt time | Rebuildable cache; cursor is a deterministic digest, not a row number |
| `projection_event` | match, event, display order, active flag, effective event?, exclusion reason? | Explains whether/how every event affects current state |
| `review_issue` | `id PK`, match, report kind?, severity, code, event/report version?, details, opened/resolved time | Regenerated from ledger and report inputs; never silently resolved |

Projection rebuild includes only hash- and schema-valid accepted events. Cyclic,
ambiguous, missing-target, or quarantined revision chains exclude all affected
events from the official projection and create blocking review issues.

### Report versions and exports

| Table | Key fields | Invariants |
| --- | --- | --- |
| `report` | `id PK`, match, kind, incident key?, current draft/signed IDs | One logical report per kind; incident key identifies its serious incident |
| `report_version` | `id PK`, report, content version, state, template version, event cursor/IDs, fixture snapshot, prose, validation snapshot, generated time, superseded time? | Unique `(report_id, content_version)`; input snapshot is complete |
| `report_signature` | `id PK`, report version, signing event, signer snapshot, declaration, signed time | One signature and sign-off event per signed version |
| `export_audit` | `id PK`, report version, format, file path/checksum, status label, generated/shared time | Additive: re-export creates another row |

Version state is `draft`, `signed_current`, or `signed_superseded`.
Signing freezes every version and signature field. A relevant event/revision or
prose edit supersedes affected current signatures and requires a replacement
draft; it never changes the old event set or validation snapshot.

### Attachments and replication

| Table | Key fields | Invariants |
| --- | --- | --- |
| `attachment` | `id PK`, match, owner kind/ID, media type, byte count, SHA-256, relative path, created/readable time, state | Owner is an event or report version; checksum covers exact file bytes |
| `attachment_transfer` | `id PK`, attachment, peer, direction, state, bytes confirmed, resume token?, error | Independent of event acknowledgement |
| `outbox` | `id PK`, match, message kind, object ID/hash, peer, state, timestamps, retry/error | One open item per target/object/hash; references an already committed object |
| `inbox_receipt` | peer, message ID, object ID/hash, committed time | PK `(peer_device_id, message_id)`; idempotent receive |
| `sync_cursor` | match, peer, origin device, last contiguous sequence, sync time/state | Advances only for committed, verified events |
| `peer_match_package` | match, peer, package version, snapshot, event digest, received/expiry time | Watch cache only; no report/export authority |

Attachment capture writes to a private staging path, hashes bytes, atomically
moves to its checksum-derived final path, then commits metadata. Startup may
remove only unreferenced staging files; it may recreate metadata only after
checksum verification. Required attachments must be locally readable and
checksum-valid before the affected report can be signed.

## Required transaction boundaries

### Local event creation (iPhone or Watch)

One transaction must allocate the device sequence, validate capture-time
minimums, build canonical bytes/hash, insert `event` plus optional revision
and initial validation, update or dirty the projection, and insert an event
outbox row for each eligible peer. Only after commit may the UI show success or
play a haptic. It never waits for Bluetooth, network, or attachment transfer.

### Receiving replicated events

For each bounded batch, one transaction checks receipts/idempotency; verifies
package availability, schema, canonical bytes, hash, and sequence constraints;
inserts valid events or quarantine evidence; rebuilds/marks projection dirty;
writes receipts; and advances only contiguous cursors. Acknowledge only after
commit. Quarantined or conflicting events are not successfully acknowledged.

### Draft, sign, and supersede reports (iPhone only)

Draft generation reads one consistent database snapshot and records exact event
IDs/cursor, fixture and participant snapshots, template version, prose, and
validation result in a new report version. Signing revalidates in one
transaction, confirms inputs remain current, appends `report_signed`, writes
the signature, marks the version current, and queues its event. Any relevant
later event or prose transaction supersedes old current versions and opens
replacement review work.

### Export a signed report (iPhone only)

Render only from the signed version snapshot. Write a staging file, checksum
it, atomically move it to the export location, then add an `export_audit`
row. A failure has no successful audit row. Status is `SIGNED — CURRENT` or
`SIGNED — SUPERSEDED`; unsigned drafts are never official exports.

## Device ownership and recovery

| Capability | iPhone | Apple Watch |
| --- | --- | --- |
| Fixture/master data | Owns | Read-only active package |
| Event creation and sequence | Own device ID | Own device ID |
| Projection | Full, user-facing | Compact active match |
| Reports/sign/export | Owns | Not permitted |
| Attachments | MVP capture/storage owner | Not captured in MVP |
| Retention | Long-lived and backup eligible | Unacknowledged events plus active context |

At Watch package install, iPhone transfers fixture snapshots, active roster,
rules, periods, event digest, and required compact projection. The Watch must
raise its strong warning state if it cannot safely retain a local event or
outbox item; it must not silently discard data.

On startup: migrate schema; reconcile attachment staging/final files; validate
event hashes; rebuild dirty projections; requeue unacknowledged outbox records;
and recompute review issues. Recovery never repairs an event by editing it.

## Minimum indexes and acceptance checks

- Primary `event(event_id)`; unique
  `(match_id, origin_device_id, origin_sequence)`; indexes on
  `(match_id, match_period_id, match_clock_ms)` and `(match_id, recorded_at)`.
- Unique `event_revision(revision_event_id)` and
  `report_version(report_id, content_version)`; indexes on outbox peer/state
  and sync-cursor match/peer/origin.
- No cascade delete may remove accepted events, signed reports/signatures,
  export audits, or their attachment metadata.
- Killing the app immediately after a Watch goal haptic leaves its event,
  sequence allocation, and outbox item after restart.
- Duplicate delivery creates one event; same ID with a different hash fails
  safely without overwrite.
- Attachment transfer failure does not block event acknowledgement, while a
  required unreadable attachment blocks the affected sign-off.
- Changing master team/person/rules/venue data after setup does not alter a
  historical projection or report version.
- Rebuilding from the event ledger produces the same score, periods, active
  events, and review issues as cached projection data.
