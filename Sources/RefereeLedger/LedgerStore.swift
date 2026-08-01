import CSQLite
import CryptoKit
import Foundation

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public enum LedgerError: Error, Equatable { case sqlite(String), invalidDraft(String), integrityConflict(UUID) }

/// A transport acknowledgement is legal only for this result.
public enum ReceiveResult: Equatable, Sendable { case committed, alreadyCommitted, quarantined }

public final class LedgerStore: @unchecked Sendable {
    private var database: OpaquePointer?
    public let originDeviceID: UUID
    private let attachmentRoot: URL

    public init(path: String = ":memory:", originDeviceID: UUID, attachmentRoot: URL? = nil) throws {
        self.originDeviceID = originDeviceID
        if let attachmentRoot {
            self.attachmentRoot = attachmentRoot
        } else if path == ":memory:" {
            self.attachmentRoot = FileManager.default.temporaryDirectory
                .appendingPathComponent("RefereeLedger-\(originDeviceID.uuidString)", isDirectory: true)
        } else {
            self.attachmentRoot = URL(fileURLWithPath: path).deletingLastPathComponent()
                .appendingPathComponent("Attachments", isDirectory: true)
        }
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else { throw LedgerError.sqlite("open") }
        try FileManager.default.createDirectory(at: self.attachmentRoot, withIntermediateDirectories: true)
        try execute("PRAGMA foreign_keys = ON;")
        try execute("CREATE TABLE IF NOT EXISTS match_fixture (id TEXT PRIMARY KEY, competition TEXT NOT NULL, scheduled_at TEXT NOT NULL, venue_name TEXT NOT NULL, home_team_name TEXT NOT NULL, away_team_name TEXT NOT NULL, CHECK(home_team_name <> away_team_name));")
        try execute("CREATE TABLE IF NOT EXISTS match_rule_snapshot (match_id TEXT PRIMARY KEY, half_duration_seconds INTEGER NOT NULL, extra_time_enabled INTEGER NOT NULL, penalty_shootout_enabled INTEGER NOT NULL, extra_time_half_duration_seconds INTEGER NOT NULL);")
        try execute("CREATE TABLE IF NOT EXISTS pitch_dimensions (match_id TEXT PRIMARY KEY, length_metres REAL NOT NULL, width_metres REAL NOT NULL);")
        try execute("CREATE TABLE IF NOT EXISTS participant_snapshot (id TEXT PRIMARY KEY, match_id TEXT NOT NULL, team_side TEXT, role TEXT NOT NULL, display_name TEXT NOT NULL, shirt_number INTEGER, UNIQUE(match_id, team_side, shirt_number), CHECK(team_side IS NULL OR team_side IN ('home', 'away')));")
        try execute("CREATE TABLE IF NOT EXISTS pre_match_checklist (match_id TEXT PRIMARY KEY, pitch_checked INTEGER NOT NULL DEFAULT 0, equipment_checked INTEGER NOT NULL DEFAULT 0, crew_checked INTEGER NOT NULL DEFAULT 0, lineup_checked INTEGER NOT NULL DEFAULT 0, notes TEXT NOT NULL DEFAULT '');")
        try execute("CREATE TABLE IF NOT EXISTS device_sequence (match_id TEXT NOT NULL, origin_device_id TEXT NOT NULL, next_sequence INTEGER NOT NULL, PRIMARY KEY(match_id, origin_device_id));")
        try execute("CREATE TABLE IF NOT EXISTS event (event_id TEXT PRIMARY KEY, match_id TEXT NOT NULL, event_type TEXT NOT NULL, schema_version INTEGER NOT NULL, origin_device_id TEXT NOT NULL, origin_sequence INTEGER NOT NULL, recorded_at TEXT NOT NULL, match_period_id TEXT, match_clock_ms INTEGER, effective_at TEXT, supersedes_event_id TEXT, payload_json TEXT NOT NULL, integrity_hash TEXT NOT NULL, UNIQUE(match_id, origin_device_id, origin_sequence));")
        try execute("CREATE TABLE IF NOT EXISTS event_revision (id TEXT PRIMARY KEY, match_id TEXT NOT NULL, target_event_id TEXT NOT NULL, revision_event_id TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, reason TEXT NOT NULL, created_at TEXT NOT NULL);")
        try execute("CREATE TABLE IF NOT EXISTS event_validation (event_id TEXT PRIMARY KEY, schema_status TEXT NOT NULL, hash_status TEXT NOT NULL, projection_status TEXT NOT NULL, diagnostics TEXT NOT NULL, validated_at TEXT NOT NULL);")
        try execute("CREATE TABLE IF NOT EXISTS match_projection (match_id TEXT PRIMARY KEY, projection_cursor TEXT, home_score INTEGER NOT NULL DEFAULT 0, away_score INTEGER NOT NULL DEFAULT 0, projection_json TEXT NOT NULL DEFAULT '{}', rebuilt_at TEXT, dirty INTEGER NOT NULL DEFAULT 1);")
        try execute("CREATE TABLE IF NOT EXISTS outbox (id TEXT PRIMARY KEY, match_id TEXT NOT NULL, message_kind TEXT NOT NULL, object_id TEXT NOT NULL, object_hash TEXT NOT NULL, peer TEXT NOT NULL, state TEXT NOT NULL, UNIQUE(match_id, object_id, object_hash, peer));")
        try execute("CREATE TABLE IF NOT EXISTS inbox_receipt (peer_device_id TEXT NOT NULL, message_id TEXT NOT NULL, object_id TEXT NOT NULL, object_hash TEXT NOT NULL, committed_at TEXT NOT NULL, PRIMARY KEY(peer_device_id, message_id));")
        try execute("CREATE TABLE IF NOT EXISTS sync_cursor (match_id TEXT NOT NULL, peer_device_id TEXT NOT NULL, origin_device_id TEXT NOT NULL, last_contiguous_sequence INTEGER NOT NULL, synced_at TEXT NOT NULL, PRIMARY KEY(match_id, peer_device_id, origin_device_id));")
        try execute("CREATE TABLE IF NOT EXISTS peer_match_package (match_id TEXT NOT NULL, peer_device_id TEXT NOT NULL, package_version INTEGER NOT NULL, package_json BLOB NOT NULL, event_digest TEXT NOT NULL, received_at TEXT NOT NULL, PRIMARY KEY(match_id, peer_device_id));")
        try execute("CREATE TABLE IF NOT EXISTS quarantined_event (event_id TEXT PRIMARY KEY, source_peer TEXT NOT NULL, raw_envelope TEXT NOT NULL, failure_code TEXT NOT NULL, diagnostics TEXT NOT NULL, quarantined_at TEXT NOT NULL);")
        try execute("CREATE TABLE IF NOT EXISTS report_content (match_id TEXT NOT NULL, report_kind TEXT NOT NULL, content_version INTEGER NOT NULL, prose_json TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(match_id, report_kind, content_version));")
        try execute("CREATE TABLE IF NOT EXISTS report_document (id TEXT PRIMARY KEY, match_id TEXT NOT NULL, report_kind TEXT NOT NULL, primary_event_id TEXT, linked_event_ids_json TEXT NOT NULL, created_at TEXT NOT NULL, UNIQUE(match_id, report_kind, primary_event_id));")
        try execute("CREATE TABLE IF NOT EXISTS report_document_content (document_id TEXT NOT NULL, content_version INTEGER NOT NULL, prose_json TEXT NOT NULL, updated_at TEXT NOT NULL, PRIMARY KEY(document_id, content_version));")
        try execute("CREATE TABLE IF NOT EXISTS signed_report_version (id TEXT PRIMARY KEY, match_id TEXT NOT NULL, report_kind TEXT NOT NULL, version INTEGER NOT NULL, content_version INTEGER NOT NULL, template_version TEXT NOT NULL, signer_json TEXT NOT NULL, declaration TEXT NOT NULL, signed_at TEXT NOT NULL, source_fingerprint TEXT NOT NULL, event_ids_json TEXT NOT NULL, validation_json TEXT NOT NULL, UNIQUE(match_id, report_kind, version));")
        // Additive migration for databases created before export snapshots existed.
        try? execute("ALTER TABLE signed_report_version ADD COLUMN fixture_json TEXT;")
        try? execute("ALTER TABLE signed_report_version ADD COLUMN participants_json TEXT;")
        try? execute("ALTER TABLE signed_report_version ADD COLUMN rules_json TEXT;")
        try? execute("ALTER TABLE signed_report_version ADD COLUMN document_id TEXT;")
        try? execute("ALTER TABLE signed_report_version ADD COLUMN attachments_json TEXT;")
        try execute("CREATE TABLE IF NOT EXISTS export_audit (id TEXT PRIMARY KEY, report_id TEXT NOT NULL, format TEXT NOT NULL, file_path TEXT NOT NULL, checksum TEXT NOT NULL, status_label TEXT NOT NULL, generated_at TEXT NOT NULL);")
        try execute("CREATE TABLE IF NOT EXISTS attachment (id TEXT PRIMARY KEY, match_id TEXT NOT NULL, document_id TEXT NOT NULL, media_type TEXT NOT NULL, original_filename TEXT NOT NULL, byte_count INTEGER NOT NULL, checksum TEXT NOT NULL, relative_path TEXT NOT NULL, created_at TEXT NOT NULL, is_required INTEGER NOT NULL DEFAULT 0);")
        try execute("CREATE TABLE IF NOT EXISTS attachment_transfer (id TEXT PRIMARY KEY, attachment_id TEXT NOT NULL, peer TEXT NOT NULL, direction TEXT NOT NULL, state TEXT NOT NULL, bytes_confirmed INTEGER NOT NULL DEFAULT 0, byte_count INTEGER NOT NULL, manifest_json TEXT NOT NULL, staging_path TEXT, error TEXT, updated_at TEXT NOT NULL, UNIQUE(attachment_id, peer, direction));")
        try execute("CREATE INDEX IF NOT EXISTS attachment_document ON attachment(document_id, created_at);")
        try execute("CREATE INDEX IF NOT EXISTS attachment_transfer_peer_state ON attachment_transfer(peer, state, direction);")
        try execute("CREATE INDEX IF NOT EXISTS export_audit_report ON export_audit(report_id, generated_at);")
        try execute("CREATE INDEX IF NOT EXISTS event_match_period_clock ON event(match_id, match_period_id, match_clock_ms);")
        try execute("CREATE INDEX IF NOT EXISTS event_match_recorded_at ON event(match_id, recorded_at);")
        try execute("CREATE INDEX IF NOT EXISTS outbox_peer_state ON outbox(peer, state);")
        try reconcileAttachmentStaging()
    }
    deinit { sqlite3_close(database) }

    /// Atomically allocates a sequence, persists the immutable event, and queues every peer.
    public func create(_ draft: EventDraft, peers: [String]) throws -> LedgerEvent {
        let payload = try CanonicalJSON.canonicalize(draft.payloadJSON)
        try validate(draft: draft, payload: payload)
        try execute("BEGIN IMMEDIATE;")
        do {
            let event = try insertCreatedEvent(draft, canonicalPayload: payload, peers: peers)
            try execute("COMMIT;")
            return event
        } catch { try? execute("ROLLBACK;"); throw error }
    }

    /// Writes the minimum iPhone-owned fixture snapshot used by a live match.
    public func saveFixture(_ fixture: MatchFixture) throws {
        guard !fixture.competition.isEmpty, !fixture.venueName.isEmpty,
              !fixture.homeTeamName.isEmpty, !fixture.awayTeamName.isEmpty,
              fixture.homeTeamName != fixture.awayTeamName else {
            throw LedgerError.invalidDraft("fixture requires competition, venue, and distinct team names")
        }
        let stmt = try prepare("INSERT INTO match_fixture VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET competition = excluded.competition, scheduled_at = excluded.scheduled_at, venue_name = excluded.venue_name, home_team_name = excluded.home_team_name, away_team_name = excluded.away_team_name")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, fixture.matchID.uuidString.lowercased()); bind(stmt, 2, fixture.competition)
        bind(stmt, 3, EventIntegrity.instant(fixture.scheduledAt)); bind(stmt, 4, fixture.venueName)
        bind(stmt, 5, fixture.homeTeamName); bind(stmt, 6, fixture.awayTeamName)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }

    public func savePitchDimensions(_ dimensions: PitchDimensions, matchID: UUID) throws {
        guard dimensions.lengthMetres >= 90, dimensions.lengthMetres <= 120,
              dimensions.widthMetres >= 45, dimensions.widthMetres <= 90 else {
            throw LedgerError.invalidDraft("pitch dimensions must be 90–120 m by 45–90 m")
        }
        let statement = try prepare("INSERT INTO pitch_dimensions VALUES (?, ?, ?) ON CONFLICT(match_id) DO UPDATE SET length_metres = excluded.length_metres, width_metres = excluded.width_metres")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, matchID.uuidString.lowercased())
        sqlite3_bind_double(statement, 2, dimensions.lengthMetres)
        sqlite3_bind_double(statement, 3, dimensions.widthMetres)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }

    public func pitchDimensions(matchID: UUID) throws -> PitchDimensions? {
        let statement = try prepare("SELECT length_metres, width_metres FROM pitch_dimensions WHERE match_id = ?")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, matchID.uuidString.lowercased())
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return PitchDimensions(lengthMetres: sqlite3_column_double(statement, 0),
                               widthMetres: sqlite3_column_double(statement, 1))
    }

    public func fixture(matchID: UUID) throws -> MatchFixture? {
        let stmt = try prepare("SELECT competition, scheduled_at, venue_name, home_team_name, away_team_name FROM match_fixture WHERE id = ?")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, matchID.uuidString.lowercased())
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let competition = columnText(stmt, 0), let scheduled = columnText(stmt, 1),
              let venue = columnText(stmt, 2), let home = columnText(stmt, 3), let away = columnText(stmt, 4) else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: scheduled) else { return nil }
        return MatchFixture(matchID: matchID, competition: competition, scheduledAt: date, venueName: venue, homeTeamName: home, awayTeamName: away)
    }

    public func saveRules(_ rules: MatchRuleSnapshot, matchID: UUID) throws {
        guard rules.halfDurationSeconds > 0, rules.extraTimeHalfDurationSeconds > 0 else {
            throw LedgerError.invalidDraft("period durations must be positive")
        }
        let stmt = try prepare("INSERT INTO match_rule_snapshot VALUES (?, ?, ?, ?, ?) ON CONFLICT(match_id) DO UPDATE SET half_duration_seconds = excluded.half_duration_seconds, extra_time_enabled = excluded.extra_time_enabled, penalty_shootout_enabled = excluded.penalty_shootout_enabled, extra_time_half_duration_seconds = excluded.extra_time_half_duration_seconds")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, matchID.uuidString.lowercased()); bind(stmt, 2, String(rules.halfDurationSeconds))
        bind(stmt, 3, rules.extraTimeEnabled ? "1" : "0"); bind(stmt, 4, rules.penaltyShootoutEnabled ? "1" : "0")
        bind(stmt, 5, String(rules.extraTimeHalfDurationSeconds))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }

    public func rules(matchID: UUID) throws -> MatchRuleSnapshot {
        let stmt = try prepare("SELECT half_duration_seconds, extra_time_enabled, penalty_shootout_enabled, extra_time_half_duration_seconds FROM match_rule_snapshot WHERE match_id = ?")
        defer { sqlite3_finalize(stmt) }; bind(stmt, 1, matchID.uuidString.lowercased())
        guard sqlite3_step(stmt) == SQLITE_ROW else { return MatchRuleSnapshot() }
        return MatchRuleSnapshot(halfDurationSeconds: Int(sqlite3_column_int64(stmt, 0)),
                                 extraTimeEnabled: sqlite3_column_int(stmt, 1) != 0,
                                 penaltyShootoutEnabled: sqlite3_column_int(stmt, 2) != 0,
                                 extraTimeHalfDurationSeconds: Int(sqlite3_column_int64(stmt, 3)))
    }

    public func fixtures() throws -> [MatchFixture] {
        let stmt = try prepare("SELECT id, competition, scheduled_at, venue_name, home_team_name, away_team_name FROM match_fixture ORDER BY scheduled_at DESC")
        defer { sqlite3_finalize(stmt) }
        var result: [MatchFixture] = []
        while sqlite3_step(stmt) == SQLITE_ROW,
              let id = columnText(stmt, 0).flatMap(UUID.init(uuidString:)),
              let competition = columnText(stmt, 1), let scheduled = columnText(stmt, 2).flatMap(date),
              let venue = columnText(stmt, 3), let home = columnText(stmt, 4), let away = columnText(stmt, 5) {
            result.append(MatchFixture(matchID: id, competition: competition, scheduledAt: scheduled, venueName: venue, homeTeamName: home, awayTeamName: away))
        }
        return result
    }

    public func savePreMatchChecklist(_ checklist: PreMatchChecklist, matchID: UUID) throws {
        let stmt = try prepare("INSERT INTO pre_match_checklist VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(match_id) DO UPDATE SET pitch_checked = excluded.pitch_checked, equipment_checked = excluded.equipment_checked, crew_checked = excluded.crew_checked, lineup_checked = excluded.lineup_checked, notes = excluded.notes")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, matchID.uuidString.lowercased())
        bind(stmt, 2, checklist.pitchChecked ? "1" : "0")
        bind(stmt, 3, checklist.equipmentChecked ? "1" : "0")
        bind(stmt, 4, checklist.crewChecked ? "1" : "0")
        bind(stmt, 5, checklist.lineupChecked ? "1" : "0")
        bind(stmt, 6, checklist.notes)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }

    public func preMatchChecklist(matchID: UUID) throws -> PreMatchChecklist {
        let stmt = try prepare("SELECT pitch_checked, equipment_checked, crew_checked, lineup_checked, notes FROM pre_match_checklist WHERE match_id = ?")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, matchID.uuidString.lowercased())
        guard sqlite3_step(stmt) == SQLITE_ROW else { return PreMatchChecklist() }
        return PreMatchChecklist(pitchChecked: sqlite3_column_int(stmt, 0) != 0,
                                 equipmentChecked: sqlite3_column_int(stmt, 1) != 0,
                                 crewChecked: sqlite3_column_int(stmt, 2) != 0,
                                 lineupChecked: sqlite3_column_int(stmt, 3) != 0,
                                 notes: columnText(stmt, 4) ?? "")
    }

    /// Replaces setup-time participant snapshots for one match. Accepted match
    /// events remain immutable and continue to carry their copied display data.
    public func saveParticipants(_ participants: [MatchParticipantSnapshot], matchID: UUID) throws {
        let homePlayers = participants.filter { $0.role == "player" && $0.teamSide == "home" }
        let awayPlayers = participants.filter { $0.role == "player" && $0.teamSide == "away" }
        let homeNumbers = homePlayers.compactMap(\.shirtNumber)
        let awayNumbers = awayPlayers.compactMap(\.shirtNumber)
        guard Set(participants.map(\.id)).count == participants.count else {
            throw LedgerError.invalidDraft("participant IDs must be unique")
        }
        guard participants.allSatisfy({
            !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            ($0.teamSide == nil || $0.teamSide == "home" || $0.teamSide == "away") &&
            ($0.role == "player" || ($0.role == "accountable_referee" && $0.teamSide == nil)) &&
            ($0.role != "player" || ($0.teamSide != nil && $0.shirtNumber.map { $0 > 0 && $0 <= 99 } == true))
        }), participants.filter({ $0.role == "accountable_referee" }).count == 1,
           !homePlayers.isEmpty, !awayPlayers.isEmpty,
           Set(homeNumbers).count == homeNumbers.count, Set(awayNumbers).count == awayNumbers.count else {
            throw LedgerError.invalidDraft("roster requires valid players and exactly one accountable referee")
        }
        try replaceParticipants(participants, matchID: matchID)
    }

    /// Persists an incomplete setup draft without claiming that the roster is
    /// report-ready. The strict `saveParticipants` API remains the finalization
    /// boundary used by complete fixture setup.
    public func saveParticipantDrafts(_ participants: [MatchParticipantSnapshot], matchID: UUID) throws {
        let playerNumbersBySide = Dictionary(grouping: participants.filter { $0.role == "player" }, by: { $0.teamSide })
            .mapValues { $0.compactMap(\.shirtNumber) }
        guard Set(participants.map(\.id)).count == participants.count,
              participants.allSatisfy({
                  !$0.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                  ($0.teamSide == nil || $0.teamSide == "home" || $0.teamSide == "away") &&
                  ($0.role == "player" || ($0.role == "accountable_referee" && $0.teamSide == nil)) &&
                  ($0.role != "player" || ($0.teamSide != nil && $0.shirtNumber.map { (1...99).contains($0) } == true))
              }), participants.filter({ $0.role == "accountable_referee" }).count <= 1,
              playerNumbersBySide.values.allSatisfy({ Set($0).count == $0.count }) else {
            throw LedgerError.invalidDraft("participant draft contains invalid or duplicate values")
        }
        try replaceParticipants(participants, matchID: matchID)
    }

    private func replaceParticipants(_ participants: [MatchParticipantSnapshot], matchID: UUID) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            let delete = try prepare("DELETE FROM participant_snapshot WHERE match_id = ?")
            bind(delete, 1, matchID.uuidString.lowercased())
            guard sqlite3_step(delete) == SQLITE_DONE else { sqlite3_finalize(delete); throw LedgerError.sqlite(lastError) }
            sqlite3_finalize(delete)
            for participant in participants {
                let statement = try prepare("INSERT INTO participant_snapshot VALUES (?, ?, ?, ?, ?, ?)")
                defer { sqlite3_finalize(statement) }
                bind(statement, 1, participant.id.uuidString.lowercased())
                bind(statement, 2, matchID.uuidString.lowercased())
                bind(statement, 3, participant.teamSide)
                bind(statement, 4, participant.role)
                bind(statement, 5, participant.displayName.trimmingCharacters(in: .whitespacesAndNewlines))
                bind(statement, 6, participant.shirtNumber.map(String.init))
                guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
            }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }

    public func participants(matchID: UUID) throws -> [MatchParticipantSnapshot] {
        let statement = try prepare("SELECT id, team_side, role, display_name, shirt_number FROM participant_snapshot WHERE match_id = ? ORDER BY CASE team_side WHEN 'home' THEN 0 WHEN 'away' THEN 1 ELSE 2 END, shirt_number, display_name")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, matchID.uuidString.lowercased())
        var result: [MatchParticipantSnapshot] = []
        while sqlite3_step(statement) == SQLITE_ROW,
              let id = columnText(statement, 0).flatMap(UUID.init(uuidString:)),
              let role = columnText(statement, 2), let name = columnText(statement, 3) {
            let number = sqlite3_column_type(statement, 4) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 4))
            result.append(MatchParticipantSnapshot(id: id, teamSide: columnText(statement, 1), role: role,
                                                   displayName: name, shirtNumber: number))
        }
        return result
    }

    /// Completes a fast-captured goal or card by appending a correction whose
    /// replacement payload contains match-owned participant display data.
    @discardableResult
    public func completeEventDetails(eventID: UUID, completion: EventDetailCompletion,
                                     peers: [String]) throws -> LedgerEvent {
        guard try !hasRevision(targetEventID: eventID) else {
            throw LedgerError.invalidDraft("event already has a correction or reversal")
        }
        guard let target = try event(eventID: eventID),
              target.draft.eventType == "goal_recorded" || target.draft.eventType == "card_recorded",
              let payload = try? JSONSerialization.jsonObject(with: Data(target.canonicalPayload.utf8)) as? [String: Any],
              let side = payload["teamSide"] as? String else {
            throw LedgerError.invalidDraft("only captured goals and cards can be completed")
        }
        guard let participant = try participants(matchID: target.draft.matchID).first(where: {
            $0.id == completion.participantID && $0.role == "player" && $0.teamSide == side
        }) else { throw LedgerError.invalidDraft("selected player is not in the event team's match roster") }
        var replacement = payload
        replacement["participantId"] = participant.id.uuidString.lowercased()
        replacement["participantDisplayName"] = participant.displayName
        replacement["shirtNumber"] = participant.shirtNumber
        if target.draft.eventType == "card_recorded" {
            let reason = completion.disciplinaryReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !reason.isEmpty else { throw LedgerError.invalidDraft("cards require a disciplinary reason") }
            replacement["disciplinaryReason"] = reason
            if payload["isDirectRed"] as? Bool == true {
                let narrative = completion.incidentNarrative?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !narrative.isEmpty else { throw LedgerError.invalidDraft("direct red cards require an incident narrative") }
                replacement["incidentNarrative"] = narrative
                replacement["requiresIncidentReport"] = true
                replacement["locationRequired"] = completion.locationRequired
            }
        }
        let envelope: [String: Any] = ["reason": "Completed event details",
                                       "replacementEventType": target.draft.eventType,
                                       "replacementPayload": replacement]
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else { throw LedgerError.invalidDraft("invalid event details") }
        return try create(EventDraft(matchID: target.draft.matchID, eventType: "event_corrected",
                                     matchPeriodID: target.draft.matchPeriodID, matchClockMs: target.draft.matchClockMs,
                                     supersedesEventID: target.draft.eventID, payloadJSON: json), peers: peers)
    }

    /// Completes deferred participants or outcomes for the extended action
    /// vocabulary by appending an immutable correction.
    @discardableResult
    public func completeMatchAction(eventID: UUID, primaryParticipantID: UUID? = nil,
                                    secondaryParticipantID: UUID? = nil, outcome: String? = nil,
                                    peers: [String]) throws -> LedgerEvent {
        guard try !hasRevision(targetEventID: eventID) else {
            throw LedgerError.invalidDraft("event already has a correction or reversal")
        }
        guard let target = try event(eventID: eventID),
              let action = MatchActionType(rawValue: target.draft.eventType),
              [.substitution, .penalty, .injury, .varReview].contains(action),
              var replacement = try? JSONSerialization.jsonObject(with: Data(target.canonicalPayload.utf8)) as? [String: Any] else {
            throw LedgerError.invalidDraft("this match action has no deferred details")
        }
        let side = replacement["teamSide"] as? String
        let roster = try participants(matchID: target.draft.matchID)
        func player(_ id: UUID?) throws -> MatchParticipantSnapshot? {
            guard let id else { return nil }
            guard let participant = roster.first(where: {
                $0.id == id && $0.role == "player" && (side == nil || $0.teamSide == side)
            }) else { throw LedgerError.invalidDraft("selected player is not in the event team's match roster") }
            return participant
        }
        switch action {
        case .substitution:
            guard let outgoing = try player(primaryParticipantID),
                  let incoming = try player(secondaryParticipantID), outgoing.id != incoming.id else {
                throw LedgerError.invalidDraft("substitutions require distinct outgoing and incoming players")
            }
            replacement["playerOutId"] = outgoing.id.uuidString.lowercased()
            replacement["playerOutDisplayName"] = outgoing.displayName
            replacement["playerOutShirtNumber"] = outgoing.shirtNumber
            replacement["playerInId"] = incoming.id.uuidString.lowercased()
            replacement["playerInDisplayName"] = incoming.displayName
            replacement["playerInShirtNumber"] = incoming.shirtNumber
        case .penalty:
            if let kicker = try player(primaryParticipantID) {
                replacement["participantId"] = kicker.id.uuidString.lowercased()
                replacement["participantDisplayName"] = kicker.displayName
                replacement["shirtNumber"] = kicker.shirtNumber
            }
            if let outcome, PenaltyOutcome(rawValue: outcome) != nil { replacement["outcome"] = outcome }
        case .injury:
            if let injured = try player(primaryParticipantID) {
                replacement["teamSide"] = injured.teamSide
                replacement["participantId"] = injured.id.uuidString.lowercased()
                replacement["participantDisplayName"] = injured.displayName
                replacement["shirtNumber"] = injured.shirtNumber
            }
        case .varReview:
            guard let outcome, VAROutcome(rawValue: outcome) != nil else {
                throw LedgerError.invalidDraft("VAR completion requires an outcome")
            }
            replacement["outcome"] = outcome
        default: break
        }
        let envelope: [String: Any] = ["reason": "Completed match action details",
                                       "replacementEventType": target.draft.eventType,
                                       "replacementPayload": replacement]
        let data = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw LedgerError.invalidDraft("invalid match action details")
        }
        return try create(EventDraft(matchID: target.draft.matchID, eventType: "event_corrected",
                                     matchPeriodID: target.draft.matchPeriodID, matchClockMs: target.draft.matchClockMs,
                                     supersedesEventID: target.draft.eventID, payloadJSON: json), peers: peers)
    }

    /// Appends a spatial enrichment without changing the captured incident.
    @discardableResult
    public func addLocation(to eventID: UUID, normalizedX: Double, normalizedY: Double,
                            captureMethod: LocationCaptureMethod = .pitchTap,
                            accuracy: LocationAccuracy = .refereeConfirmed,
                            peers: [String]) throws -> LedgerEvent {
        guard normalizedX.isFinite, normalizedY.isFinite,
              (0...100).contains(normalizedX), (0...100).contains(normalizedY) else {
            throw LedgerError.invalidDraft("normalized pitch coordinates must be between 0 and 100")
        }
        guard let target = try event(eventID: eventID) else { throw LedgerError.invalidDraft("location target does not exist") }
        let effective = effectiveTypeAndPayload(target)
        guard effective.type == "foul_recorded" || locationRequired(in: effective.payload) else {
            throw LedgerError.invalidDraft("locations may be added only to fouls or location-required incidents")
        }
        guard let pitch = try pitchDimensions(matchID: target.draft.matchID) else {
            throw LedgerError.invalidDraft("pitch dimensions are required before adding a location")
        }
        let metresX = normalizedX * pitch.lengthMetres / 100
        let metresY = normalizedY * pitch.widthMetres / 100
        let location = EventLocation(targetEventID: eventID, normalizedX: normalizedX, normalizedY: normalizedY,
                                     metresX: metresX, metresY: metresY,
                                     pitchLengthMetres: pitch.lengthMetres, pitchWidthMetres: pitch.widthMetres,
                                     captureMethod: captureMethod, accuracy: accuracy,
                                     regions: pitchRegions(x: metresX, y: metresY, pitch: pitch))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding: try encoder.encode(location), as: UTF8.self)
        return try create(EventDraft(matchID: target.draft.matchID, eventType: "location_added",
                                     matchPeriodID: target.draft.matchPeriodID,
                                     matchClockMs: target.draft.matchClockMs, payloadJSON: json), peers: peers)
    }

    public func location(for eventID: UUID) throws -> EventLocation? {
        let statement = try prepare("SELECT payload_json FROM event WHERE event_type = 'location_added' AND lower(json_extract(payload_json, '$.targetEventID')) = lower(?) ORDER BY recorded_at DESC, origin_sequence DESC LIMIT 1")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, eventID.uuidString.lowercased())
        guard sqlite3_step(statement) == SQLITE_ROW, let json = columnText(statement, 0) else { return nil }
        return try? JSONDecoder().decode(EventLocation.self, from: Data(json.utf8))
    }

    /// Returns every accepted event, including revisions and their immutable
    /// targets. Newest rows appear first for field-side review.
    public func timeline(matchID: UUID) throws -> [MatchTimelineEntry] {
        let stmt = try prepare("SELECT event_id, event_type, schema_version, origin_device_id, origin_sequence, recorded_at, match_period_id, match_clock_ms, effective_at, supersedes_event_id, payload_json, integrity_hash, match_id FROM event WHERE match_id = ? ORDER BY recorded_at, origin_device_id, origin_sequence")
        defer { sqlite3_finalize(stmt) }; bind(stmt, 1, matchID.uuidString.lowercased())
        var events: [LedgerEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW, let event = eventFromRow(stmt) { events.append(event) }
        let rows = events.map { event in
            (id: event.draft.eventID.uuidString.lowercased(), type: event.draft.eventType,
             payload: event.canonicalPayload, target: event.draft.supersedesEventID?.uuidString.lowercased(),
             hash: event.integrityHash)
        }
        let validation = revisionValidation(rows)
        let activeRevisions = rows.filter {
            ($0.type == "event_reversed" || $0.type == "event_corrected") && !validation.invalidRevisionIDs.contains($0.id)
        }
        let superseded = Set(activeRevisions.compactMap(\.target))
        return events.reversed().map { event in
            let id = event.draft.eventID.uuidString.lowercased()
            let hasIssue = validation.invalidRevisionIDs.contains(id)
            return MatchTimelineEntry(eventID: event.draft.eventID, eventType: event.draft.eventType,
                                      recordedAt: event.draft.recordedAt, matchPeriodID: event.draft.matchPeriodID,
                                      matchClockMs: event.draft.matchClockMs, payloadJSON: event.canonicalPayload,
                                      supersedesEventID: event.draft.supersedesEventID,
                                      isActive: !superseded.contains(id) && !hasIssue,
                                      hasRevisionIssue: hasIssue)
        }
    }

    public func rebuildProjection(matchID: UUID) throws -> MatchProjection {
        let statement = try prepare("SELECT event_id, event_type, payload_json, supersedes_event_id, integrity_hash FROM event WHERE match_id = ? ORDER BY recorded_at, origin_device_id, origin_sequence")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, matchID.uuidString.lowercased())
        var rows: [(id: String, type: String, payload: String, target: String?, hash: String)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let id = columnText(statement, 0), let type = columnText(statement, 1), let payload = columnText(statement, 2) else { continue }
            guard let hash = columnText(statement, 4) else { continue }
            rows.append((id, type, payload, columnText(statement, 3), hash))
        }
        let validation = revisionValidation(rows)
        let activeRevisions = rows.filter { ($0.type == "event_reversed" || $0.type == "event_corrected") && !validation.invalidRevisionIDs.contains($0.id) }
        let superseded = Set(activeRevisions.compactMap(\.target))
        var home = 0, away = 0
        for row in rows where !superseded.contains(row.id) && !validation.invalidRevisionIDs.contains(row.id) {
            let projected: (type: String, payload: String)
            if row.type == "event_corrected" {
                guard let replacement = correctionReplacement(row.payload) else { continue }
                projected = replacement
            } else {
                projected = (row.type, row.payload)
            }
            guard projected.type == "goal_recorded",
                  let side = (try? JSONSerialization.jsonObject(with: Data(projected.payload.utf8))) as? [String: Any],
                  let teamSide = side["teamSide"] as? String else { continue }
            if teamSide == "home" { home += 1 }; if teamSide == "away" { away += 1 }
        }
        let projection = MatchProjection(homeScore: home, awayScore: away, issues: validation.issues)
        try cacheProjection(matchID: matchID, projection: projection, eventHashes: rows.map(\.hash))
        return projection
    }

    /// Builds the offline context owned by the iPhone. Callers may supply live
    /// clock context because it is a runtime concern rather than a mutable event.
    public func matchPackage(matchID: UUID, periodID: UUID? = nil, periodLabel: String = "NOT STARTED",
                             clockAnchor: Date? = nil, clockAnchorMs: Int64 = 0) throws -> MatchPackage? {
        guard let fixture = try fixture(matchID: matchID) else { return nil }
        let projection = try rebuildProjection(matchID: matchID)
        let derivedPeriod = try activePeriodContext(matchID: matchID)
        let packagePeriodID = periodID ?? derivedPeriod?.periodID
        let packagePeriodLabel = periodID == nil ? (derivedPeriod?.label ?? periodLabel) : periodLabel
        let packageClockAnchor = clockAnchor ?? derivedPeriod?.startedAt
        let packageClockAnchorMs = clockAnchor == nil ? (derivedPeriod?.startClockMs ?? clockAnchorMs) : clockAnchorMs
        return MatchPackage(fixture: fixture,
                            roster: try participants(matchID: matchID),
                            rules: try rules(matchID: matchID),
                            projection: CompactMatchProjection(homeScore: projection.homeScore, awayScore: projection.awayScore,
                                                               periodID: packagePeriodID, periodLabel: packagePeriodLabel,
                                                               clockAnchor: packageClockAnchor, clockAnchorMs: packageClockAnchorMs),
                            originWatermarks: try originWatermarks(matchID: matchID),
                            eventDigest: try eventDigest(matchID: matchID))
    }

    /// Finds the latest valid period start that has not yet been ended. The
    /// result is derived only from ledger events, never from a mutable timer.
    public func activePeriodContext(matchID: UUID) throws -> MatchPeriodContext? {
        try periodState(matchID: matchID).active
    }

    public func periodState(matchID: UUID) throws -> MatchPeriodState {
        try periodState(matchID: matchID, rules: rules(matchID: matchID))
    }

    private func periodState(matchID: UUID, rules: MatchRuleSnapshot) throws -> MatchPeriodState {
        let stmt = try prepare("SELECT event_id, event_type, schema_version, origin_device_id, origin_sequence, recorded_at, match_period_id, match_clock_ms, effective_at, supersedes_event_id, payload_json, integrity_hash, match_id FROM event WHERE match_id = ? ORDER BY recorded_at, origin_device_id, origin_sequence")
        defer { sqlite3_finalize(stmt) }; bind(stmt, 1, matchID.uuidString.lowercased())
        var active: MatchPeriodContext?
        var completed: [MatchPeriodDefinition] = []
        while sqlite3_step(stmt) == SQLITE_ROW, let event = eventFromRow(stmt) {
            switch event.draft.eventType {
            case "period_started":
                guard active == nil, let periodID = event.draft.matchPeriodID,
                      let definition = periodDefinition(payload: event.canonicalPayload),
                      definition == nextPeriod(after: completed, rules: rules) else { continue }
                active = MatchPeriodContext(periodID: periodID, definition: definition, startedAt: event.draft.recordedAt,
                                             startClockMs: event.draft.matchClockMs ?? 0)
            case "period_ended":
                guard let current = active, event.draft.matchPeriodID == current.periodID,
                      let definition = periodDefinition(payload: event.canonicalPayload),
                      definition == current.definition,
                      definition == nextPeriod(after: completed, rules: rules) else { continue }
                completed.append(definition); active = nil
            default:
                continue
            }
        }
        if let active { return MatchPeriodState(active: active, next: nil, isComplete: false) }
        let next = nextPeriod(after: completed, rules: rules)
        return MatchPeriodState(active: nil, next: next, isComplete: next == nil && !completed.isEmpty)
    }

    /// Persists the Watch's active offline context before its UI treats the package as ready.
    /// The fixture and raw package snapshot are written in the same transaction.
    public func installMatchPackage(_ package: MatchPackage, from peerDeviceID: UUID) throws {
        guard package.activeMatchID == package.fixture.matchID, package.version > 0 else {
            throw LedgerError.invalidDraft("match package has an invalid active match ID or version")
        }
        let encoded = try JSONEncoder().encode(package)
        try execute("BEGIN IMMEDIATE;")
        do {
            try upsertFixture(package.fixture)
            try saveRules(package.rules, matchID: package.activeMatchID)
            let stmt = try prepare("INSERT INTO peer_match_package VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(match_id, peer_device_id) DO UPDATE SET package_version = excluded.package_version, package_json = excluded.package_json, event_digest = excluded.event_digest, received_at = excluded.received_at")
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, package.activeMatchID.uuidString.lowercased())
            bind(stmt, 2, peerDeviceID.uuidString.lowercased())
            bind(stmt, 3, String(package.version))
            sqlite3_bind_blob(stmt, 4, (encoded as NSData).bytes, Int32(encoded.count), sqliteTransient)
            bind(stmt, 5, package.eventDigest); bind(stmt, 6, EventIntegrity.instant(Date()))
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }

    public func installedMatchPackage(matchID: UUID, from peerDeviceID: UUID) throws -> MatchPackage? {
        let stmt = try prepare("SELECT package_json FROM peer_match_package WHERE match_id = ? AND peer_device_id = ?")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, matchID.uuidString.lowercased()); bind(stmt, 2, peerDeviceID.uuidString.lowercased())
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let bytes = sqlite3_column_blob(stmt, 0) else { return nil }
        let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(stmt, 0)))
        return try? JSONDecoder().decode(MatchPackage.self, from: data)
    }

    /// Highest contiguous sequence retained for every origin in this match.
    public func originWatermarks(matchID: UUID) throws -> [String: Int64] {
        let stmt = try prepare("SELECT DISTINCT origin_device_id FROM event WHERE match_id = ?")
        defer { sqlite3_finalize(stmt) }; bind(stmt, 1, matchID.uuidString.lowercased())
        var result: [String: Int64] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW, let origin = columnText(stmt, 0) {
            let sequence = try contiguousSequence(matchID: matchID, originDeviceID: origin)
            result[origin] = sequence
        }
        return result
    }

    public func syncWatermark(matchID: UUID) throws -> SyncWatermark {
        SyncWatermark(matchID: matchID, deviceID: originDeviceID,
                      originWatermarks: try originWatermarks(matchID: matchID), eventDigest: try eventDigest(matchID: matchID))
    }

    /// Returns immutable events absent from a peer according to its contiguous watermarks.
    public func eventsMissing(from peerWatermarks: [String: Int64], matchID: UUID) throws -> [ReplicatedEvent] {
        let stmt = try prepare("SELECT event_id, event_type, schema_version, origin_device_id, origin_sequence, recorded_at, match_period_id, match_clock_ms, effective_at, supersedes_event_id, payload_json, integrity_hash, match_id FROM event WHERE match_id = ? ORDER BY origin_device_id, origin_sequence")
        defer { sqlite3_finalize(stmt) }; bind(stmt, 1, matchID.uuidString.lowercased())
        var result: [ReplicatedEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let event = eventFromRow(stmt), event.originSequence > (peerWatermarks[event.originDeviceID.uuidString.lowercased()] ?? 0) else { continue }
            result.append(ReplicatedEvent(event: event))
        }
        return result
    }

    /// Pending rows are deliberately not removed on send. They remain available
    /// for WatchConnectivity retries until an acknowledgement is committed.
    public func pendingOutboxEvents(matchID: UUID, peer: String) throws -> [ReplicatedEvent] {
        let stmt = try prepare("SELECT e.event_id, e.event_type, e.schema_version, e.origin_device_id, e.origin_sequence, e.recorded_at, e.match_period_id, e.match_clock_ms, e.effective_at, e.supersedes_event_id, e.payload_json, e.integrity_hash, e.match_id FROM event e JOIN outbox o ON o.object_id = e.event_id AND o.object_hash = e.integrity_hash WHERE o.match_id = ? AND o.peer = ? AND o.message_kind = 'event' AND o.state = 'pending' ORDER BY e.origin_device_id, e.origin_sequence")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, matchID.uuidString.lowercased()); bind(stmt, 2, peer)
        var events: [ReplicatedEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW, let event = eventFromRow(stmt) { events.append(ReplicatedEvent(event: event)) }
        return events
    }

    public func outboxCount() throws -> Int { try scalarInt("SELECT COUNT(*) FROM outbox") }
    public func pendingOutboxCount() throws -> Int { try scalarInt("SELECT COUNT(*) FROM outbox WHERE state = 'pending'") }
    public func pendingOutboxCount(matchID: UUID, peer: String) throws -> Int {
        let stmt = try prepare("SELECT COUNT(*) FROM outbox WHERE match_id = ? AND peer = ? AND state = 'pending'")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, matchID.uuidString.lowercased()); bind(stmt, 2, peer)
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw LedgerError.sqlite(lastError) }
        return Int(sqlite3_column_int64(stmt, 0))
    }
    public func eventCount() throws -> Int { try scalarInt("SELECT COUNT(*) FROM event") }
    public func quarantineCount() throws -> Int { try scalarInt("SELECT COUNT(*) FROM quarantined_event") }
    public func projectionIsDirty(matchID: UUID) throws -> Bool {
        let stmt = try prepare("SELECT dirty FROM match_projection WHERE match_id = ?")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, matchID.uuidString.lowercased())
        return sqlite3_step(stmt) != SQLITE_ROW || sqlite3_column_int(stmt, 0) != 0
    }
    public func syncCursor(matchID: UUID, peerDeviceID: UUID, originDeviceID: UUID) throws -> Int64 {
        let stmt = try prepare("SELECT last_contiguous_sequence FROM sync_cursor WHERE match_id = ? AND peer_device_id = ? AND origin_device_id = ?")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, matchID.uuidString.lowercased()); bind(stmt, 2, peerDeviceID.uuidString.lowercased())
        bind(stmt, 3, originDeviceID.uuidString.lowercased())
        return sqlite3_step(stmt) == SQLITE_ROW ? sqlite3_column_int64(stmt, 0) : 0
    }

    /// Marks an already-committed event delivery as acknowledged. The immutable event remains stored.
    public func acknowledge(eventID: UUID, integrityHash: String, peer: String) throws {
        let stmt = try prepare("UPDATE outbox SET state = 'acknowledged' WHERE object_id = ? AND object_hash = ? AND peer = ?")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, eventID.uuidString.lowercased()); bind(stmt, 2, integrityHash); bind(stmt, 3, peer)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }

    /// Stores attachment bytes privately, then commits immutable metadata only
    /// after the checksum-derived final file is in place.
    @discardableResult
    public func addAttachment(documentID: UUID, data: Data, mediaType: String,
                              originalFilename: String, isRequired: Bool = false,
                              peers: [String] = []) throws -> ReportAttachment {
        guard !data.isEmpty else { throw LedgerError.invalidDraft("attachment must not be empty") }
        guard let identity = try reportDocumentIdentity(documentID: documentID) else {
            throw LedgerError.invalidDraft("report document does not exist")
        }
        let type = mediaType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !type.isEmpty else { throw LedgerError.invalidDraft("attachment media type is required") }
        let safeName = URL(fileURLWithPath: originalFilename).lastPathComponent
        guard !safeName.isEmpty else { throw LedgerError.invalidDraft("attachment filename is required") }

        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let relativePath = "\(identity.matchID.uuidString.lowercased())/\(checksum.prefix(2))/\(checksum)"
        let finalURL = attachmentRoot.appendingPathComponent(relativePath)
        let stagingDirectory = attachmentRoot.appendingPathComponent("Staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let stagingURL = stagingDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: stagingURL, options: [.atomic, .completeFileProtection])
        do {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                let existing = try Data(contentsOf: finalURL, options: .mappedIfSafe)
                guard SHA256.hash(data: existing).map({ String(format: "%02x", $0) }).joined() == checksum else {
                    throw LedgerError.invalidDraft("attachment checksum path contains different bytes")
                }
                try FileManager.default.removeItem(at: stagingURL)
            } else {
                try FileManager.default.moveItem(at: stagingURL, to: finalURL)
            }
            // JSONEncoder's ISO-8601 strategy is second-precise on supported
            // deployment targets; normalize so live and frozen metadata compare exactly.
            let createdAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
            let attachment = ReportAttachment(id: UUID(), matchID: identity.matchID, documentID: documentID,
                                              mediaType: type, originalFilename: safeName,
                                              byteCount: Int64(data.count), checksum: checksum,
                                              relativePath: relativePath, createdAt: createdAt,
                                              isRequired: isRequired, isReadable: true)
            let stmt = try prepare("INSERT INTO attachment VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
            defer { sqlite3_finalize(stmt) }
            bind(stmt, 1, attachment.id.uuidString.lowercased()); bind(stmt, 2, identity.matchID.uuidString.lowercased())
            bind(stmt, 3, documentID.uuidString.lowercased()); bind(stmt, 4, type); bind(stmt, 5, safeName)
            bind(stmt, 6, String(data.count)); bind(stmt, 7, checksum); bind(stmt, 8, relativePath)
            bind(stmt, 9, EventIntegrity.instant(attachment.createdAt)); bind(stmt, 10, isRequired ? "1" : "0")
            guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
            for peer in Set(peers) { try queueAttachmentTransfer(attachmentID: attachment.id, peer: peer) }
            return attachment
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            throw error
        }
    }

    public func attachments(documentID: UUID) throws -> [ReportAttachment] {
        let stmt = try prepare("SELECT id, match_id, media_type, original_filename, byte_count, checksum, relative_path, created_at, is_required FROM attachment WHERE document_id = ? ORDER BY created_at, id")
        defer { sqlite3_finalize(stmt) }; bind(stmt, 1, documentID.uuidString.lowercased())
        var result: [ReportAttachment] = []
        while sqlite3_step(stmt) == SQLITE_ROW,
              let id = columnText(stmt, 0).flatMap(UUID.init(uuidString:)),
              let matchID = columnText(stmt, 1).flatMap(UUID.init(uuidString:)),
              let mediaType = columnText(stmt, 2), let name = columnText(stmt, 3),
              let checksum = columnText(stmt, 5), let path = columnText(stmt, 6),
              let createdAt = columnText(stmt, 7).flatMap(date) {
            let readable = attachmentIsValid(relativePath: path, checksum: checksum,
                                             byteCount: sqlite3_column_int64(stmt, 4))
            result.append(ReportAttachment(id: id, matchID: matchID, documentID: documentID,
                                           mediaType: mediaType, originalFilename: name,
                                           byteCount: sqlite3_column_int64(stmt, 4), checksum: checksum,
                                           relativePath: path, createdAt: createdAt,
                                           isRequired: sqlite3_column_int(stmt, 8) != 0,
                                           isReadable: readable))
        }
        return result
    }

    /// Adds an independently retryable attachment delivery. This never changes
    /// event outbox rows or their acknowledgement state.
    public func queueAttachmentTransfer(attachmentID: UUID, peer: String) throws {
        let peer = peer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !peer.isEmpty else { throw LedgerError.invalidDraft("attachment peer is required") }
        guard let attachment = try attachment(id: attachmentID), attachment.isReadable else {
            throw LedgerError.invalidDraft("attachment bytes are unavailable or invalid")
        }
        let manifest = AttachmentManifest(attachment: attachment)
        let manifestJSON = String(decoding: try JSONEncoder().encode(manifest), as: UTF8.self)
        let now = EventIntegrity.instant(Date())
        try execute("BEGIN IMMEDIATE;")
        do {
            let transfer = try prepare("INSERT INTO attachment_transfer (id, attachment_id, peer, direction, state, bytes_confirmed, byte_count, manifest_json, staging_path, error, updated_at) VALUES (?, ?, ?, 'outgoing', 'pending', 0, ?, ?, NULL, NULL, ?) ON CONFLICT(attachment_id, peer, direction) DO UPDATE SET state = CASE WHEN state = 'completed' THEN state ELSE 'pending' END, error = NULL, updated_at = excluded.updated_at")
            defer { sqlite3_finalize(transfer) }
            bind(transfer, 1, UUID().uuidString.lowercased()); bind(transfer, 2, attachmentID.uuidString.lowercased())
            bind(transfer, 3, peer); bind(transfer, 4, String(attachment.byteCount)); bind(transfer, 5, manifestJSON); bind(transfer, 6, now)
            guard sqlite3_step(transfer) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
            let outbox = try prepare("INSERT OR IGNORE INTO outbox VALUES (?, ?, 'attachment', ?, ?, ?, 'pending')")
            defer { sqlite3_finalize(outbox) }
            bind(outbox, 1, UUID().uuidString.lowercased()); bind(outbox, 2, attachment.matchID.uuidString.lowercased())
            bind(outbox, 3, attachmentID.uuidString.lowercased()); bind(outbox, 4, attachment.checksum); bind(outbox, 5, peer)
            guard sqlite3_step(outbox) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
    }

    public func attachmentTransfers(documentID: UUID) throws -> [AttachmentTransfer] {
        let statement = try prepare("SELECT t.id, t.attachment_id, t.peer, t.direction, t.state, t.bytes_confirmed, t.byte_count, t.error, t.updated_at FROM attachment_transfer t JOIN attachment a ON a.id = t.attachment_id WHERE a.document_id = ? ORDER BY t.updated_at, t.id")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, documentID.uuidString.lowercased())
        var transfers: [AttachmentTransfer] = []
        while sqlite3_step(statement) == SQLITE_ROW, let transfer = attachmentTransferFromRow(statement) { transfers.append(transfer) }
        return transfers
    }

    public func attachmentTransfer(attachmentID: UUID, peer: String,
                                   direction: AttachmentTransferDirection) throws -> AttachmentTransfer? {
        let statement = try prepare("SELECT id, attachment_id, peer, direction, state, bytes_confirmed, byte_count, error, updated_at FROM attachment_transfer WHERE attachment_id = ? AND peer = ? AND direction = ?")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, attachmentID.uuidString.lowercased())
        bind(statement, 2, peer); bind(statement, 3, direction.rawValue)
        return sqlite3_step(statement) == SQLITE_ROW ? attachmentTransferFromRow(statement) : nil
    }

    public func pendingAttachmentManifests(matchID: UUID, peer: String) throws -> [AttachmentManifest] {
        let statement = try prepare("SELECT t.manifest_json FROM attachment_transfer t JOIN attachment a ON a.id = t.attachment_id JOIN outbox o ON o.object_id = a.id AND o.object_hash = a.checksum WHERE a.match_id = ? AND t.peer = ? AND t.direction = 'outgoing' AND t.state IN ('pending', 'transferring', 'failed') AND o.message_kind = 'attachment' AND o.state = 'pending' ORDER BY t.updated_at")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, matchID.uuidString.lowercased()); bind(statement, 2, peer)
        var manifests: [AttachmentManifest] = []
        while sqlite3_step(statement) == SQLITE_ROW, let json = columnText(statement, 0),
              let manifest = try? JSONDecoder().decode(AttachmentManifest.self, from: Data(json.utf8)) { manifests.append(manifest) }
        return manifests
    }

    /// Produces the next chunk from the last receiver-confirmed offset.
    public func nextAttachmentChunk(attachmentID: UUID, peer: String,
                                    maximumBytes: Int = 256 * 1024) throws -> AttachmentChunk? {
        guard maximumBytes > 0 else { throw LedgerError.invalidDraft("chunk size must be positive") }
        let statement = try prepare("SELECT manifest_json, bytes_confirmed, state FROM attachment_transfer WHERE attachment_id = ? AND peer = ? AND direction = 'outgoing'")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, attachmentID.uuidString.lowercased()); bind(statement, 2, peer)
        guard sqlite3_step(statement) == SQLITE_ROW, let json = columnText(statement, 0),
              let manifest = try? JSONDecoder().decode(AttachmentManifest.self, from: Data(json.utf8)) else {
            throw LedgerError.invalidDraft("attachment transfer is not queued")
        }
        if columnText(statement, 2) == AttachmentTransferState.completed.rawValue { return nil }
        let offset = sqlite3_column_int64(statement, 1)
        guard let attachment = try attachment(id: attachmentID), attachment.isReadable else {
            try markAttachmentTransferFailed(attachmentID: attachmentID, peer: peer, error: "local attachment failed integrity validation")
            throw LedgerError.invalidDraft("attachment bytes are unavailable or invalid")
        }
        let data = try Data(contentsOf: attachmentRoot.appendingPathComponent(attachment.relativePath), options: .mappedIfSafe)
        guard offset >= 0, offset <= data.count else { throw LedgerError.invalidDraft("invalid attachment resume offset") }
        if offset == data.count { return nil }
        let end = min(data.count, Int(offset) + maximumBytes)
        return AttachmentChunk(manifest: manifest, offset: offset, bytes: data.subdata(in: Int(offset)..<end))
    }

    /// Commits a received chunk to a private staging file. Only a complete file
    /// with the declared byte count and SHA-256 is promoted into attachment storage.
    @discardableResult
    public func receiveAttachmentChunk(_ chunk: AttachmentChunk, from peer: String) throws -> AttachmentTransferAcknowledgement {
        let manifest = chunk.manifest
        try validate(manifest: manifest)
        guard chunk.offset >= 0, !chunk.bytes.isEmpty else { throw LedgerError.invalidDraft("attachment chunk is empty or has an invalid offset") }
        let stagingDirectory = attachmentRoot.appendingPathComponent("Staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let existing = try incomingTransfer(attachmentID: manifest.attachmentID, peer: peer)
        if let existing, existing.state == .completed {
            guard let attachment = try attachment(id: manifest.attachmentID), attachment.checksum == manifest.checksum,
                  attachment.isReadable else { throw LedgerError.integrityConflict(manifest.attachmentID) }
            return AttachmentTransferAcknowledgement(attachmentID: manifest.attachmentID, checksum: manifest.checksum,
                                                     nextOffset: manifest.byteCount, isComplete: true)
        }
        let transferID = existing?.id ?? UUID()
        let relativeStagingPath = "Staging/\(transferID.uuidString.lowercased()).part"
        let stagingURL = attachmentRoot.appendingPathComponent(relativeStagingPath)
        let currentSize = (try? stagingURL.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        if chunk.offset < currentSize {
            let saved = try Data(contentsOf: stagingURL, options: .mappedIfSafe)
            let end = chunk.offset + Int64(chunk.bytes.count)
            guard end <= currentSize,
                  saved.subdata(in: Int(chunk.offset)..<Int(end)) == chunk.bytes else {
                throw LedgerError.integrityConflict(manifest.attachmentID)
            }
            return AttachmentTransferAcknowledgement(attachmentID: manifest.attachmentID, checksum: manifest.checksum,
                                                     nextOffset: currentSize, isComplete: false)
        }
        guard chunk.offset == currentSize, currentSize + Int64(chunk.bytes.count) <= manifest.byteCount else {
            throw LedgerError.invalidDraft("attachment chunk is not contiguous or exceeds declared size")
        }
        if currentSize == 0 { try chunk.bytes.write(to: stagingURL, options: [.atomic, .completeFileProtection]) }
        else {
            let handle = try FileHandle(forWritingTo: stagingURL)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: chunk.bytes)
        }
        let nextOffset = currentSize + Int64(chunk.bytes.count)
        try upsertIncomingTransfer(id: transferID, manifest: manifest, peer: peer, state: .transferring,
                                   bytesConfirmed: nextOffset, stagingPath: relativeStagingPath, error: nil)
        guard nextOffset == manifest.byteCount else {
            return AttachmentTransferAcknowledgement(attachmentID: manifest.attachmentID, checksum: manifest.checksum,
                                                     nextOffset: nextOffset, isComplete: false)
        }
        do {
            try finalizeIncomingAttachment(manifest: manifest, stagingURL: stagingURL)
            try upsertIncomingTransfer(id: transferID, manifest: manifest, peer: peer, state: .completed,
                                       bytesConfirmed: nextOffset, stagingPath: nil, error: nil)
            return AttachmentTransferAcknowledgement(attachmentID: manifest.attachmentID, checksum: manifest.checksum,
                                                     nextOffset: nextOffset, isComplete: true)
        } catch {
            try? FileManager.default.removeItem(at: stagingURL)
            try? upsertIncomingTransfer(id: transferID, manifest: manifest, peer: peer, state: .failed,
                                        bytesConfirmed: 0, stagingPath: nil, error: String(describing: error))
            throw error
        }
    }

    public func acknowledgeAttachment(_ acknowledgement: AttachmentTransferAcknowledgement, peer: String) throws {
        let statement = try prepare("SELECT byte_count, manifest_json FROM attachment_transfer WHERE attachment_id = ? AND peer = ? AND direction = 'outgoing'")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, acknowledgement.attachmentID.uuidString.lowercased()); bind(statement, 2, peer)
        guard sqlite3_step(statement) == SQLITE_ROW, let json = columnText(statement, 1),
              let manifest = try? JSONDecoder().decode(AttachmentManifest.self, from: Data(json.utf8)),
              manifest.checksum == acknowledgement.checksum,
              acknowledgement.nextOffset >= 0, acknowledgement.nextOffset <= sqlite3_column_int64(statement, 0),
              acknowledgement.isComplete || acknowledgement.nextOffset < manifest.byteCount,
              !acknowledgement.isComplete || acknowledgement.nextOffset == manifest.byteCount else {
            throw LedgerError.invalidDraft("invalid attachment acknowledgement")
        }
        let state = acknowledgement.isComplete ? AttachmentTransferState.completed : .transferring
        let update = try prepare("UPDATE attachment_transfer SET state = ?, bytes_confirmed = MAX(bytes_confirmed, ?), error = NULL, updated_at = ? WHERE attachment_id = ? AND peer = ? AND direction = 'outgoing'")
        defer { sqlite3_finalize(update) }; bind(update, 1, state.rawValue); bind(update, 2, String(acknowledgement.nextOffset))
        bind(update, 3, EventIntegrity.instant(Date())); bind(update, 4, acknowledgement.attachmentID.uuidString.lowercased()); bind(update, 5, peer)
        guard sqlite3_step(update) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
        if acknowledgement.isComplete {
            let outbox = try prepare("UPDATE outbox SET state = 'acknowledged' WHERE object_id = ? AND object_hash = ? AND peer = ? AND message_kind = 'attachment'")
            defer { sqlite3_finalize(outbox) }; bind(outbox, 1, acknowledgement.attachmentID.uuidString.lowercased())
            bind(outbox, 2, acknowledgement.checksum); bind(outbox, 3, peer)
            guard sqlite3_step(outbox) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
        }
    }

    public func markAttachmentTransferFailed(attachmentID: UUID, peer: String, error: String) throws {
        let statement = try prepare("UPDATE attachment_transfer SET state = 'failed', error = ?, updated_at = ? WHERE attachment_id = ? AND peer = ? AND direction = 'outgoing'")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, error); bind(statement, 2, EventIntegrity.instant(Date()))
        bind(statement, 3, attachmentID.uuidString.lowercased()); bind(statement, 4, peer)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }

    private func attachment(id: UUID) throws -> ReportAttachment? {
        let statement = try prepare("SELECT match_id, document_id, media_type, original_filename, byte_count, checksum, relative_path, created_at, is_required FROM attachment WHERE id = ?")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, id.uuidString.lowercased())
        guard sqlite3_step(statement) == SQLITE_ROW,
              let matchID = columnText(statement, 0).flatMap(UUID.init(uuidString:)),
              let documentID = columnText(statement, 1).flatMap(UUID.init(uuidString:)),
              let mediaType = columnText(statement, 2), let filename = columnText(statement, 3),
              let checksum = columnText(statement, 5), let path = columnText(statement, 6),
              let createdAt = columnText(statement, 7).flatMap(date) else { return nil }
        let byteCount = sqlite3_column_int64(statement, 4)
        return ReportAttachment(id: id, matchID: matchID, documentID: documentID,
                                mediaType: mediaType, originalFilename: filename,
                                byteCount: byteCount, checksum: checksum, relativePath: path,
                                createdAt: createdAt, isRequired: sqlite3_column_int(statement, 8) != 0,
                                isReadable: attachmentIsValid(relativePath: path, checksum: checksum, byteCount: byteCount))
    }

    private func validate(manifest: AttachmentManifest) throws {
        let safeName = URL(fileURLWithPath: manifest.originalFilename).lastPathComponent
        let checksumCharacters = CharacterSet(charactersIn: "0123456789abcdef")
        guard manifest.byteCount > 0, manifest.checksum.count == 64,
              manifest.checksum.unicodeScalars.allSatisfy(checksumCharacters.contains),
              !manifest.mediaType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !safeName.isEmpty, safeName == manifest.originalFilename else {
            throw LedgerError.invalidDraft("invalid attachment manifest")
        }
    }

    private func incomingTransfer(attachmentID: UUID, peer: String) throws -> AttachmentTransfer? {
        let statement = try prepare("SELECT id, attachment_id, peer, direction, state, bytes_confirmed, byte_count, error, updated_at FROM attachment_transfer WHERE attachment_id = ? AND peer = ? AND direction = 'incoming'")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, attachmentID.uuidString.lowercased()); bind(statement, 2, peer)
        return sqlite3_step(statement) == SQLITE_ROW ? attachmentTransferFromRow(statement) : nil
    }

    private func attachmentTransferFromRow(_ statement: OpaquePointer?) -> AttachmentTransfer? {
        guard let id = columnText(statement, 0).flatMap(UUID.init(uuidString:)),
              let attachmentID = columnText(statement, 1).flatMap(UUID.init(uuidString:)),
              let peer = columnText(statement, 2),
              let direction = columnText(statement, 3).flatMap(AttachmentTransferDirection.init(rawValue:)),
              let state = columnText(statement, 4).flatMap(AttachmentTransferState.init(rawValue:)),
              let updatedAt = columnText(statement, 8).flatMap(date) else { return nil }
        return AttachmentTransfer(id: id, attachmentID: attachmentID, peer: peer,
                                  direction: direction, state: state,
                                  bytesConfirmed: sqlite3_column_int64(statement, 5),
                                  byteCount: sqlite3_column_int64(statement, 6),
                                  error: columnText(statement, 7), updatedAt: updatedAt)
    }

    private func upsertIncomingTransfer(id: UUID, manifest: AttachmentManifest, peer: String,
                                        state: AttachmentTransferState, bytesConfirmed: Int64,
                                        stagingPath: String?, error: String?) throws {
        let manifestJSON = String(decoding: try JSONEncoder().encode(manifest), as: UTF8.self)
        let statement = try prepare("INSERT INTO attachment_transfer (id, attachment_id, peer, direction, state, bytes_confirmed, byte_count, manifest_json, staging_path, error, updated_at) VALUES (?, ?, ?, 'incoming', ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(attachment_id, peer, direction) DO UPDATE SET state = excluded.state, bytes_confirmed = excluded.bytes_confirmed, byte_count = excluded.byte_count, manifest_json = excluded.manifest_json, staging_path = excluded.staging_path, error = excluded.error, updated_at = excluded.updated_at")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, id.uuidString.lowercased())
        bind(statement, 2, manifest.attachmentID.uuidString.lowercased()); bind(statement, 3, peer)
        bind(statement, 4, state.rawValue); bind(statement, 5, String(bytesConfirmed)); bind(statement, 6, String(manifest.byteCount))
        bind(statement, 7, manifestJSON); bind(statement, 8, stagingPath); bind(statement, 9, error)
        bind(statement, 10, EventIntegrity.instant(Date()))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }

    private func finalizeIncomingAttachment(manifest: AttachmentManifest, stagingURL: URL) throws {
        let data = try Data(contentsOf: stagingURL, options: .mappedIfSafe)
        guard data.count == manifest.byteCount,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == manifest.checksum else {
            throw LedgerError.integrityConflict(manifest.attachmentID)
        }
        if let existing = try attachment(id: manifest.attachmentID) {
            guard existing.matchID == manifest.matchID, existing.documentID == manifest.documentID,
                  existing.checksum == manifest.checksum, existing.byteCount == manifest.byteCount else {
                throw LedgerError.integrityConflict(manifest.attachmentID)
            }
            if stagingURL.standardizedFileURL != attachmentRoot.appendingPathComponent(existing.relativePath).standardizedFileURL {
                try? FileManager.default.removeItem(at: stagingURL)
            }
            return
        }
        let relativePath = "\(manifest.matchID.uuidString.lowercased())/\(manifest.checksum.prefix(2))/\(manifest.checksum)"
        let finalURL = attachmentRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            guard attachmentIsValid(relativePath: relativePath, checksum: manifest.checksum, byteCount: manifest.byteCount) else {
                throw LedgerError.integrityConflict(manifest.attachmentID)
            }
            try FileManager.default.removeItem(at: stagingURL)
        } else {
            try FileManager.default.moveItem(at: stagingURL, to: finalURL)
        }
        let statement = try prepare("INSERT INTO attachment VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, manifest.attachmentID.uuidString.lowercased()); bind(statement, 2, manifest.matchID.uuidString.lowercased())
        bind(statement, 3, manifest.documentID.uuidString.lowercased()); bind(statement, 4, manifest.mediaType)
        bind(statement, 5, manifest.originalFilename); bind(statement, 6, String(manifest.byteCount)); bind(statement, 7, manifest.checksum)
        bind(statement, 8, relativePath); bind(statement, 9, EventIntegrity.instant(manifest.createdAt)); bind(statement, 10, manifest.isRequired ? "1" : "0")
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }

    /// Restores resumable offsets and promotes only complete, verified staging
    /// files. Unreferenced staging files are safe to remove because no metadata
    /// or active transfer points to them.
    private func reconcileAttachmentStaging() throws {
        let stagingDirectory = attachmentRoot.appendingPathComponent("Staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let statement = try prepare("SELECT id, peer, manifest_json, staging_path FROM attachment_transfer WHERE direction = 'incoming' AND state != 'completed'")
        defer { sqlite3_finalize(statement) }
        var referenced = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW,
              let id = columnText(statement, 0).flatMap(UUID.init(uuidString:)),
              let peer = columnText(statement, 1), let json = columnText(statement, 2),
              let manifest = try? JSONDecoder().decode(AttachmentManifest.self, from: Data(json.utf8)) {
            let relativePath = columnText(statement, 3) ?? "Staging/\(id.uuidString.lowercased()).part"
            referenced.insert(relativePath)
            let url = attachmentRoot.appendingPathComponent(relativePath)
            guard FileManager.default.fileExists(atPath: url.path) else {
                try upsertIncomingTransfer(id: id, manifest: manifest, peer: peer, state: .pending,
                                           bytesConfirmed: 0, stagingPath: relativePath, error: nil)
                continue
            }
            let size = Int64((try url.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0)
            if size < manifest.byteCount {
                try upsertIncomingTransfer(id: id, manifest: manifest, peer: peer, state: .transferring,
                                           bytesConfirmed: size, stagingPath: relativePath, error: nil)
            } else if size == manifest.byteCount {
                do {
                    try finalizeIncomingAttachment(manifest: manifest, stagingURL: url)
                    try upsertIncomingTransfer(id: id, manifest: manifest, peer: peer, state: .completed,
                                               bytesConfirmed: size, stagingPath: nil, error: nil)
                    referenced.remove(relativePath)
                } catch {
                    try? FileManager.default.removeItem(at: url)
                    try upsertIncomingTransfer(id: id, manifest: manifest, peer: peer, state: .failed,
                                               bytesConfirmed: 0, stagingPath: nil, error: String(describing: error))
                    referenced.remove(relativePath)
                }
            } else {
                try? FileManager.default.removeItem(at: url)
                try upsertIncomingTransfer(id: id, manifest: manifest, peer: peer, state: .failed,
                                           bytesConfirmed: 0, stagingPath: nil, error: "staging file exceeds declared byte count")
                referenced.remove(relativePath)
            }
        }
        for url in (try? FileManager.default.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: nil)) ?? [] {
            let relativePath = "Staging/\(url.lastPathComponent)"
            if !referenced.contains(relativePath) { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func attachmentIsValid(relativePath: String, checksum: String, byteCount: Int64) -> Bool {
        let url = attachmentRoot.appendingPathComponent(relativePath)
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe), data.count == byteCount else { return false }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == checksum
    }

    private func attachmentIssues(documentID: UUID) throws -> [ReportValidationIssue] {
        try attachments(documentID: documentID).filter { $0.isRequired && !$0.isReadable }.map { _ in
            ReportValidationIssue(code: "required_attachment_unreadable")
        }
    }

    /// Re-runs all blocking MVP checks from immutable events and match-owned snapshots.
    public func validatePostMatch(matchID: UUID, confirmedScore: ConfirmedScore?) throws -> PostMatchValidationResult {
        var issues: [ReportValidationIssue] = []
        if try fixture(matchID: matchID) == nil {
            issues.append(ReportValidationIssue(code: "fixture_missing"))
        }
        let state = try periodState(matchID: matchID)
        if state.active != nil { issues.append(ReportValidationIssue(code: "period_still_active")) }
        else if !state.isComplete { issues.append(ReportValidationIssue(code: "match_not_complete")) }

        let projection = try rebuildProjection(matchID: matchID)
        issues += projection.issues.map {
            ReportValidationIssue(code: $0.code, eventID: UUID(uuidString: $0.eventID))
        }
        if try invalidEventValidationCount(matchID: matchID) > 0 {
            issues.append(ReportValidationIssue(code: "timeline_integrity_invalid"))
        }
        let projectedScore = ConfirmedScore(home: projection.homeScore, away: projection.awayScore)
        if confirmedScore == nil { issues.append(ReportValidationIssue(code: "score_not_confirmed")) }
        else if confirmedScore != projectedScore { issues.append(ReportValidationIssue(code: "score_confirmation_mismatch")) }

        let roster = try participants(matchID: matchID)
        if roster.filter({ $0.role == "accountable_referee" }).count != 1 {
            issues.append(ReportValidationIssue(code: "accountable_referee_missing"))
        }
        for item in try activeReportEvents(matchID: matchID) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(item.payload.utf8)) as? [String: Any] else {
                issues.append(ReportValidationIssue(code: "event_payload_invalid", eventID: item.id)); continue
            }
            if item.type == "goal_recorded", object["participantId"] as? String == nil {
                issues.append(ReportValidationIssue(code: "goal_player_missing", severity: .warning, eventID: item.id))
            }
            if item.type == "card_recorded" {
                let isDirectRed = object["isDirectRed"] as? Bool == true
                if object["participantId"] as? String == nil {
                    issues.append(ReportValidationIssue(code: "card_player_missing", severity: isDirectRed ? .blocking : .warning, eventID: item.id))
                }
                if (object["disciplinaryReason"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    issues.append(ReportValidationIssue(code: "card_reason_missing", severity: isDirectRed ? .blocking : .warning, eventID: item.id))
                }
                if isDirectRed,
                   (object["incidentNarrative"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    issues.append(ReportValidationIssue(code: "direct_red_narrative_missing", eventID: item.id))
                }
            }
            if item.type == MatchActionType.substitution.rawValue,
               (object["playerOutId"] as? String == nil || object["playerInId"] as? String == nil) {
                issues.append(ReportValidationIssue(code: "substitution_players_missing", eventID: item.id))
            }
            if item.type == MatchActionType.penalty.rawValue,
               object["outcome"] as? String == PenaltyOutcome.pending.rawValue {
                let phase = object["phase"] as? String
                issues.append(ReportValidationIssue(code: "penalty_outcome_pending",
                                                    severity: phase == PenaltyPhase.shootout.rawValue ? .blocking : .warning,
                                                    eventID: item.id))
            }
            if item.type == MatchActionType.injury.rawValue,
               object["participantId"] as? String == nil {
                issues.append(ReportValidationIssue(code: "injury_player_missing", severity: .warning, eventID: item.id))
            }
            if item.type == MatchActionType.varReview.rawValue,
               object["outcome"] as? String == VAROutcome.pending.rawValue {
                issues.append(ReportValidationIssue(code: "var_outcome_pending", severity: .warning, eventID: item.id))
            }
            if object["locationRequired"] as? Bool == true, try location(for: item.id) == nil {
                issues.append(ReportValidationIssue(code: "required_location_missing", eventID: item.id))
            }
        }
        return PostMatchValidationResult(matchID: matchID, projectedScore: projectedScore,
                                         confirmedScore: confirmedScore,
                                         issues: issues.sorted { $0.id < $1.id }, validatedAt: Date())
    }

    /// Returns stable report identities and derives one incident document for
    /// each active event that explicitly requires an incident report.
    public func reportDocuments(matchID: UUID) throws -> [ReportDocument] {
        _ = try ensureStandardDocument(matchID: matchID, kind: .match)
        _ = try ensureStandardDocument(matchID: matchID, kind: .referee)
        try reconcileIncidentDocuments(matchID: matchID)
        let statement = try prepare("SELECT id, report_kind, primary_event_id, linked_event_ids_json FROM report_document WHERE match_id = ? ORDER BY CASE report_kind WHEN 'match' THEN 0 WHEN 'referee' THEN 1 ELSE 2 END, created_at")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, matchID.uuidString.lowercased())
        let decoder = JSONDecoder()
        var result: [ReportDocument] = []
        while sqlite3_step(statement) == SQLITE_ROW,
              let id = columnText(statement, 0).flatMap(UUID.init(uuidString:)),
              let kindText = columnText(statement, 1), let kind = ReportKind(rawValue: kindText),
              let linksText = columnText(statement, 3),
              let links = try? decoder.decode([UUID].self, from: Data(linksText.utf8)) {
            let version = try latestDocumentContentVersion(documentID: id)
            let content = try documentContent(documentID: id, version: version) ?? StructuredReportContent()
            result.append(ReportDocument(id: id, matchID: matchID, kind: kind,
                                         primaryEventID: columnText(statement, 2).flatMap(UUID.init(uuidString:)),
                                         linkedEventIDs: links, contentVersion: version, content: content))
        }
        return result
    }

    /// Saves typed, report-owned prose as a new immutable content version.
    @discardableResult
    public func saveReportContent(documentID: UUID, content: StructuredReportContent) throws -> Int {
        guard try reportDocumentIdentity(documentID: documentID) != nil else {
            throw LedgerError.invalidDraft("report document does not exist")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let prose = try CanonicalJSON.canonicalize(String(decoding: encoder.encode(content), as: UTF8.self))
        let version = try latestDocumentContentVersion(documentID: documentID) + 1
        let statement = try prepare("INSERT INTO report_document_content VALUES (?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, documentID.uuidString.lowercased()); bind(statement, 2, String(version))
        bind(statement, 3, prose); bind(statement, 4, EventIntegrity.instant(Date()))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
        return version
    }

    /// Compatibility entry point for callers that still provide a JSON object.
    @discardableResult
    public func saveReportContent(matchID: UUID, kind: ReportKind, proseJSON: String) throws -> Int {
        let prose = try CanonicalJSON.canonicalize(proseJSON)
        guard let object = try? JSONSerialization.jsonObject(with: Data(prose.utf8)) as? [String: Any] else {
            throw LedgerError.invalidDraft("report prose must be a JSON object")
        }
        let content = StructuredReportContent(summary: object["summary"] as? String ?? "",
                                              description: object["description"] as? String ?? object["incidentNarrative"] as? String ?? "",
                                              actionTaken: object["actionTaken"] as? String ?? "",
                                              additionalNotes: object["additionalNotes"] as? String ?? object["operationalNotes"] as? String ?? "")
        let document = kind == .incident
            ? try reportDocuments(matchID: matchID).first(where: { $0.kind == .incident })
            : try ensureStandardDocument(matchID: matchID, kind: kind)
        guard let document else { throw LedgerError.invalidDraft("incident report does not exist") }
        return try saveReportContent(documentID: document.id, content: content)
    }

    /// Freezes one independently signed version and appends its audit event.
    @discardableResult
    public func signReport(matchID: UUID, kind: ReportKind, documentID requestedDocumentID: UUID? = nil,
                           confirmedScore: ConfirmedScore,
                           declaration: String, templateVersion: String = "mvp-1",
                           peers: [String] = []) throws -> SignedReportVersion {
        let declaration = declaration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !declaration.isEmpty else { throw LedgerError.invalidDraft("report signing requires a declaration") }
        guard !templateVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LedgerError.invalidDraft("report signing requires a template version")
        }
        let documents = try reportDocuments(matchID: matchID)
        guard let document = requestedDocumentID.flatMap({ id in documents.first { $0.id == id && $0.kind == kind } })
                ?? documents.first(where: { $0.kind == kind }) else {
            throw LedgerError.invalidDraft("report document does not exist")
        }
        let baseValidation = try validatePostMatch(matchID: matchID, confirmedScore: confirmedScore)
        let validation = PostMatchValidationResult(matchID: baseValidation.matchID,
                                                   projectedScore: baseValidation.projectedScore,
                                                   confirmedScore: baseValidation.confirmedScore,
                                                   issues: (baseValidation.issues + (try attachmentIssues(documentID: document.id))).sorted { $0.id < $1.id },
                                                   validatedAt: baseValidation.validatedAt)
        guard validation.canSign else { throw LedgerError.invalidDraft("report has blocking validation issues") }
        let signer = try participants(matchID: matchID).first { $0.role == "accountable_referee" }!
        var contentVersion = try latestDocumentContentVersion(documentID: document.id)
        if contentVersion == 0 { contentVersion = try saveReportContent(documentID: document.id, content: StructuredReportContent()) }
        if kind == .incident {
            let content = try documentContent(documentID: document.id, version: contentVersion)
            guard content?.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                throw LedgerError.invalidDraft("incident report requires a narrative description")
            }
        }
        let version = try latestSignedVersion(matchID: matchID, kind: kind) + 1
        let fingerprint = try reportSourceFingerprint(matchID: matchID, documentID: document.id, contentVersion: contentVersion)
        let eventIDs = kind == .incident ? document.linkedEventIDs : try reportEventIDs(matchID: matchID)
        let reportID = UUID(), signedAt = Date()
        let payloadObject: [String: Any] = [
            "reportId": reportID.uuidString.lowercased(), "reportKind": kind.rawValue,
            "documentId": document.id.uuidString.lowercased(),
            "reportVersion": version, "contentVersion": contentVersion,
            "templateVersion": templateVersion, "signerId": signer.id.uuidString.lowercased(),
            "signerDisplayName": signer.displayName, "declaration": declaration,
            "sourceFingerprint": fingerprint
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payloadObject, options: [.sortedKeys])
        let signDraft = EventDraft(matchID: matchID, eventType: "report_signed", recordedAt: signedAt,
                                   payloadJSON: String(decoding: payloadData, as: UTF8.self))
        let signPayload = try CanonicalJSON.canonicalize(signDraft.payloadJSON)
        try validate(draft: signDraft, payload: signPayload)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let signerJSON = String(decoding: try encoder.encode(signer), as: UTF8.self)
        let validationJSON = String(decoding: try encoder.encode(validation), as: UTF8.self)
        let eventIDsJSON = String(decoding: try encoder.encode(eventIDs), as: UTF8.self)
        guard let fixture = try fixture(matchID: matchID) else { throw LedgerError.invalidDraft("fixture does not exist") }
        let fixtureJSON = String(decoding: try encoder.encode(fixture), as: UTF8.self)
        let participantsJSON = String(decoding: try encoder.encode(try participants(matchID: matchID)), as: UTF8.self)
        let rulesJSON = String(decoding: try encoder.encode(try rules(matchID: matchID)), as: UTF8.self)
        let attachmentsJSON = String(decoding: try encoder.encode(try attachments(documentID: document.id)), as: UTF8.self)
        try execute("BEGIN IMMEDIATE;")
        do {
            _ = try insertCreatedEvent(signDraft, canonicalPayload: signPayload, peers: peers)
            let statement = try prepare("INSERT INTO signed_report_version (id, match_id, report_kind, version, content_version, template_version, signer_json, declaration, signed_at, source_fingerprint, event_ids_json, validation_json, fixture_json, participants_json, rules_json, document_id, attachments_json) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")
            defer { sqlite3_finalize(statement) }
            bind(statement, 1, reportID.uuidString.lowercased()); bind(statement, 2, matchID.uuidString.lowercased())
            bind(statement, 3, kind.rawValue); bind(statement, 4, String(version)); bind(statement, 5, String(contentVersion))
            bind(statement, 6, templateVersion); bind(statement, 7, signerJSON); bind(statement, 8, declaration)
            bind(statement, 9, EventIntegrity.instant(signedAt)); bind(statement, 10, fingerprint)
            bind(statement, 11, eventIDsJSON); bind(statement, 12, validationJSON)
            bind(statement, 13, fixtureJSON); bind(statement, 14, participantsJSON); bind(statement, 15, rulesJSON)
            bind(statement, 16, document.id.uuidString.lowercased())
            bind(statement, 17, attachmentsJSON)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
            try execute("COMMIT;")
        } catch { try? execute("ROLLBACK;"); throw error }
        return SignedReportVersion(id: reportID, matchID: matchID, kind: kind, documentID: document.id, version: version,
                                   contentVersion: contentVersion, templateVersion: templateVersion,
                                   signer: signer, declaration: declaration, signedAt: signedAt,
                                   sourceFingerprint: fingerprint, eventIDs: eventIDs,
                                   validation: validation, status: .current)
    }

    public func signedReports(matchID: UUID, kind: ReportKind) throws -> [SignedReportVersion] {
        let documents = try reportDocuments(matchID: matchID)
        let statement = try prepare("SELECT id, version, content_version, template_version, signer_json, declaration, signed_at, source_fingerprint, event_ids_json, validation_json, document_id FROM signed_report_version WHERE match_id = ? AND report_kind = ? ORDER BY version DESC")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, matchID.uuidString.lowercased()); bind(statement, 2, kind.rawValue)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        var result: [SignedReportVersion] = []
        while sqlite3_step(statement) == SQLITE_ROW,
              let id = columnText(statement, 0).flatMap(UUID.init(uuidString:)),
              let template = columnText(statement, 3), let signerText = columnText(statement, 4),
              let declaration = columnText(statement, 5), let signedText = columnText(statement, 6),
              let fingerprint = columnText(statement, 7), let idsText = columnText(statement, 8),
              let validationText = columnText(statement, 9), let signedAt = date(signedText),
              let signer = try? decoder.decode(MatchParticipantSnapshot.self, from: Data(signerText.utf8)),
              let eventIDs = try? decoder.decode([UUID].self, from: Data(idsText.utf8)),
              let validation = try? decoder.decode(PostMatchValidationResult.self, from: Data(validationText.utf8)) {
            let contentVersion = Int(sqlite3_column_int64(statement, 2))
            let documentID = columnText(statement, 10).flatMap(UUID.init(uuidString:))
            let currentDocument = documentID.flatMap { id in documents.first { $0.id == id } }
            let currentFingerprint = try documentID.map {
                try reportSourceFingerprint(matchID: matchID, documentID: $0,
                                            contentVersion: currentDocument?.contentVersion ?? 0)
            }
            let status: SignedReportStatus = currentDocument?.contentVersion == contentVersion && fingerprint == currentFingerprint ? .current : .superseded
            result.append(SignedReportVersion(id: id, matchID: matchID, kind: kind, documentID: documentID,
                                              version: Int(sqlite3_column_int64(statement, 1)), contentVersion: contentVersion,
                                              templateVersion: template, signer: signer, declaration: declaration,
                                              signedAt: signedAt, sourceFingerprint: fingerprint,
                                              eventIDs: eventIDs, validation: validation, status: status))
        }
        return result
    }

    /// Loads only the immutable inputs frozen when this report version was signed.
    public func exportSnapshot(reportID: UUID) throws -> SignedReportExportSnapshot {
        guard let report = try signedReportForLookup(reportID: reportID) else {
            throw LedgerError.invalidDraft("signed report does not exist")
        }

        let statement = try prepare("SELECT fixture_json, participants_json, rules_json, attachments_json FROM signed_report_version WHERE id = ?")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, reportID.uuidString.lowercased())
        guard sqlite3_step(statement) == SQLITE_ROW,
              let fixtureText = columnText(statement, 0),
              let participantsText = columnText(statement, 1),
              let rulesText = columnText(statement, 2) else {
            throw LedgerError.invalidDraft("signed report predates immutable export snapshots and must be signed again")
        }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        guard let fixture = try? decoder.decode(MatchFixture.self, from: Data(fixtureText.utf8)),
              let participants = try? decoder.decode([MatchParticipantSnapshot].self, from: Data(participantsText.utf8)),
              let rules = try? decoder.decode(MatchRuleSnapshot.self, from: Data(rulesText.utf8)) else {
            throw LedgerError.invalidDraft("signed report export snapshot is unreadable")
        }
        let frozenAttachments: [ReportAttachment]
        if let attachmentsText = columnText(statement, 3) {
            guard let decoded = try? decoder.decode([ReportAttachment].self, from: Data(attachmentsText.utf8)) else {
                throw LedgerError.invalidDraft("signed report attachment snapshot is unreadable")
            }
            frozenAttachments = decoded
        } else {
            frozenAttachments = []
        }
        guard let documentID = report.documentID else {
            throw LedgerError.invalidDraft("signed report predates report identities and must be signed again")
        }
        let proseStatement = try prepare("SELECT prose_json FROM report_document_content WHERE document_id = ? AND content_version = ?")
        defer { sqlite3_finalize(proseStatement) }
        bind(proseStatement, 1, documentID.uuidString.lowercased())
        bind(proseStatement, 2, String(report.contentVersion))
        guard sqlite3_step(proseStatement) == SQLITE_ROW, let prose = columnText(proseStatement, 0) else {
            throw LedgerError.invalidDraft("signed report content is missing")
        }
        return SignedReportExportSnapshot(report: report, fixture: fixture, participants: participants,
                                          rules: rules, proseJSON: prose,
                                          events: try exportEvents(matchID: report.matchID, eventIDs: Set(report.eventIDs)),
                                          attachments: frozenAttachments)
    }

    /// Adds an immutable audit row after the caller has successfully moved a generated file.
    @discardableResult
    public func recordExport(reportID: UUID, format: ReportExportFormat,
                             filePath: String, checksum: String,
                             generatedAt: Date = Date()) throws -> ReportExportAudit {
        let normalizedChecksum = checksum.lowercased()
        guard !filePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              normalizedChecksum.count == 64,
              normalizedChecksum.allSatisfy({ $0.isHexDigit }) else {
            throw LedgerError.invalidDraft("export requires a file path and SHA-256 checksum")
        }
        guard let report = try signedReportForLookup(reportID: reportID) else {
            throw LedgerError.invalidDraft("signed report does not exist")
        }
        let audit = ReportExportAudit(id: UUID(), reportID: reportID, format: format,
                                      filePath: filePath, checksum: normalizedChecksum,
                                      statusLabel: report.status == .current ? "SIGNED — CURRENT" : "SIGNED — SUPERSEDED",
                                      generatedAt: generatedAt)
        let statement = try prepare("INSERT INTO export_audit VALUES (?, ?, ?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, audit.id.uuidString.lowercased()); bind(statement, 2, reportID.uuidString.lowercased())
        bind(statement, 3, format.rawValue); bind(statement, 4, filePath); bind(statement, 5, audit.checksum)
        bind(statement, 6, audit.statusLabel); bind(statement, 7, EventIntegrity.instant(audit.generatedAt))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
        return audit
    }

    public func exportAudits(reportID: UUID) throws -> [ReportExportAudit] {
        let statement = try prepare("SELECT id, format, file_path, checksum, status_label, generated_at FROM export_audit WHERE report_id = ? ORDER BY generated_at DESC")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, reportID.uuidString.lowercased())
        var result: [ReportExportAudit] = []
        while sqlite3_step(statement) == SQLITE_ROW,
              let id = columnText(statement, 0).flatMap(UUID.init(uuidString:)),
              let formatText = columnText(statement, 1), let format = ReportExportFormat(rawValue: formatText),
              let path = columnText(statement, 2), let checksum = columnText(statement, 3),
              let status = columnText(statement, 4), let generatedText = columnText(statement, 5),
              let generatedAt = date(generatedText) {
            result.append(ReportExportAudit(id: id, reportID: reportID, format: format,
                                            filePath: path, checksum: checksum,
                                            statusLabel: status, generatedAt: generatedAt))
        }
        return result
    }

    private func signedReportForLookup(reportID: UUID) throws -> SignedReportVersion? {
        let statement = try prepare("SELECT match_id, report_kind FROM signed_report_version WHERE id = ?")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, reportID.uuidString.lowercased())
        guard sqlite3_step(statement) == SQLITE_ROW,
              let matchID = columnText(statement, 0).flatMap(UUID.init(uuidString:)),
              let kindText = columnText(statement, 1), let kind = ReportKind(rawValue: kindText) else { return nil }
        return try signedReports(matchID: matchID, kind: kind).first { $0.id == reportID }
    }

    private func exportEvents(matchID: UUID, eventIDs: Set<UUID>) throws -> [ReportExportEvent] {
        let stmt = try prepare("SELECT event_id, event_type, schema_version, origin_device_id, origin_sequence, recorded_at, match_period_id, match_clock_ms, effective_at, supersedes_event_id, payload_json, integrity_hash, match_id FROM event WHERE match_id = ? ORDER BY recorded_at, origin_device_id, origin_sequence")
        defer { sqlite3_finalize(stmt) }; bind(stmt, 1, matchID.uuidString.lowercased())
        var events: [LedgerEvent] = []
        while sqlite3_step(stmt) == SQLITE_ROW, let event = eventFromRow(stmt), eventIDs.contains(event.draft.eventID) {
            events.append(event)
        }
        let rows = events.map { event in
            (id: event.draft.eventID.uuidString.lowercased(), type: event.draft.eventType,
             payload: event.canonicalPayload, target: event.draft.supersedesEventID?.uuidString.lowercased(),
             hash: event.integrityHash)
        }
        let validation = revisionValidation(rows)
        let activeRevisions = rows.filter {
            ($0.type == "event_reversed" || $0.type == "event_corrected") && !validation.invalidRevisionIDs.contains($0.id)
        }
        let superseded = Set(activeRevisions.compactMap(\.target))
        let byID = Dictionary(uniqueKeysWithValues: events.map { ($0.draft.eventID, $0) })
        return events.compactMap { event in
            let id = event.draft.eventID.uuidString.lowercased()
            guard !superseded.contains(id), !validation.invalidRevisionIDs.contains(id),
                  event.draft.eventType != "event_reversed", event.draft.eventType != "report_signed" else { return nil }
            if event.draft.eventType == "event_corrected" {
                guard let replacement = correctionReplacement(event.canonicalPayload) else { return nil }
                let original = event.draft.supersedesEventID.flatMap { byID[$0] }
                return ReportExportEvent(id: event.draft.eventID, sourceEventType: event.draft.eventType,
                                         effectiveEventType: replacement.type, recordedAt: event.draft.recordedAt,
                                         originalMatchClockMs: original?.draft.matchClockMs,
                                         effectiveMatchClockMs: event.draft.matchClockMs,
                                         revisionOfEventID: event.draft.supersedesEventID,
                                         payloadJSON: replacement.payload)
            }
            return ReportExportEvent(id: event.draft.eventID, sourceEventType: event.draft.eventType,
                                     effectiveEventType: event.draft.eventType, recordedAt: event.draft.recordedAt,
                                     originalMatchClockMs: event.draft.matchClockMs,
                                     effectiveMatchClockMs: event.draft.matchClockMs,
                                     revisionOfEventID: nil, payloadJSON: event.canonicalPayload)
        }
    }

    /// Commits a verified inbound event once. Identical redelivery is acknowledged idempotently;
    /// mismatched canonical bytes or hashes are preserved in quarantine and never overwrite data.
    @discardableResult
    public func receive(_ replicated: ReplicatedEvent, messageID: UUID, from peerDeviceID: UUID) throws -> ReceiveResult {
        let event = replicated.event
        let canonical: String
        do { canonical = try CanonicalJSON.canonicalize(replicated.rawPayloadJSON) }
        catch { try quarantine(event, peer: peerDeviceID, raw: replicated.rawPayloadJSON, code: "invalid_payload", diagnostic: "Payload is not canonical JSON"); return .quarantined }
        do { try validate(draft: event.draft, payload: canonical, originSequence: event.originSequence) }
        catch { try quarantine(event, peer: peerDeviceID, raw: replicated.rawPayloadJSON, code: "invalid_event", diagnostic: "Event does not meet capture-time invariants"); return .quarantined }
        let expectedHash = EventIntegrity.hash(draft: event.draft, deviceID: event.originDeviceID, sequence: event.originSequence, payload: canonical)
        guard canonical == event.canonicalPayload, expectedHash == event.integrityHash else {
            try quarantine(event, peer: peerDeviceID, raw: replicated.rawPayloadJSON, code: "integrity_mismatch", diagnostic: "Canonical payload or SHA-256 hash differs"); return .quarantined
        }
        try execute("BEGIN IMMEDIATE;")
        do {
            if let receipt = try receipt(peer: peerDeviceID, messageID: messageID) {
                guard receipt.objectID == event.draft.eventID.uuidString.lowercased(), receipt.hash == event.integrityHash else {
                    try execute("ROLLBACK;")
                    try quarantine(event, peer: peerDeviceID, raw: replicated.rawPayloadJSON, code: "receipt_conflict", diagnostic: "Message ID was already committed for another object"); return .quarantined
                }
                try execute("COMMIT;")
                return .alreadyCommitted
            }
            if let existingHash = try eventHash(eventID: event.draft.eventID) {
                guard existingHash == event.integrityHash else {
                    try execute("ROLLBACK;")
                    try quarantine(event, peer: peerDeviceID, raw: replicated.rawPayloadJSON, code: "event_id_conflict", diagnostic: "Existing event ID has another hash"); return .quarantined
                }
            } else if try originSequenceExists(for: event) {
                try execute("ROLLBACK;")
                try quarantine(event, peer: peerDeviceID, raw: replicated.rawPayloadJSON, code: "origin_sequence_conflict", diagnostic: "Origin device sequence belongs to another event"); return .quarantined
            } else {
                try insert(event)
                try insertRevisionIfNeeded(event)
                try insertValidation(event)
                try markProjectionDirty(matchID: event.draft.matchID)
            }
            try insertReceipt(peer: peerDeviceID, messageID: messageID, event: event)
            try advanceContiguousCursor(for: event, peer: peerDeviceID)
            try execute("COMMIT;")
            return .committed
        } catch { try? execute("ROLLBACK;"); throw error }
    }

    private func eventDigest(matchID: UUID) throws -> String {
        let stmt = try prepare("SELECT integrity_hash FROM event WHERE match_id = ? ORDER BY integrity_hash")
        defer { sqlite3_finalize(stmt) }; bind(stmt, 1, matchID.uuidString.lowercased())
        var hashes: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW, let hash = columnText(stmt, 0) { hashes.append(hash) }
        return SHA256.hash(data: Data(hashes.joined(separator: "\\n").utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func invalidEventValidationCount(matchID: UUID) throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM event_validation v JOIN event e ON e.event_id = v.event_id WHERE e.match_id = ? AND (v.schema_status <> 'valid' OR v.hash_status <> 'valid')")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, matchID.uuidString.lowercased())
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.sqlite(lastError) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func activeReportEvents(matchID: UUID) throws -> [(id: UUID, type: String, payload: String)] {
        try timeline(matchID: matchID).compactMap { entry in
            guard entry.isActive else { return nil }
            if entry.eventType == "event_reversed" || entry.eventType == "report_signed" { return nil }
            if entry.eventType == "event_corrected" {
                guard let replacement = correctionReplacement(entry.payloadJSON) else { return nil }
                return (entry.eventID, replacement.type, replacement.payload)
            }
            return (entry.eventID, entry.eventType, entry.payloadJSON)
        }
    }

    private func ensureStandardDocument(matchID: UUID, kind: ReportKind) throws -> ReportDocument? {
        guard kind != .incident else { return nil }
        let lookup = try prepare("SELECT id FROM report_document WHERE match_id = ? AND report_kind = ? AND primary_event_id IS NULL LIMIT 1")
        defer { sqlite3_finalize(lookup) }
        bind(lookup, 1, matchID.uuidString.lowercased()); bind(lookup, 2, kind.rawValue)
        let id: UUID
        if sqlite3_step(lookup) == SQLITE_ROW, let existing = columnText(lookup, 0).flatMap(UUID.init(uuidString:)) {
            id = existing
        } else {
            id = UUID()
            let insert = try prepare("INSERT INTO report_document VALUES (?, ?, ?, NULL, '[]', ?)")
            defer { sqlite3_finalize(insert) }
            bind(insert, 1, id.uuidString.lowercased()); bind(insert, 2, matchID.uuidString.lowercased())
            bind(insert, 3, kind.rawValue); bind(insert, 4, EventIntegrity.instant(Date()))
            guard sqlite3_step(insert) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
        }
        let version = try latestDocumentContentVersion(documentID: id)
        return ReportDocument(id: id, matchID: matchID, kind: kind, contentVersion: version,
                              content: try documentContent(documentID: id, version: version) ?? StructuredReportContent())
    }

    private func reconcileIncidentDocuments(matchID: UUID) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        for item in try activeReportEvents(matchID: matchID) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(item.payload.utf8)) as? [String: Any],
                  object["requiresIncidentReport"] as? Bool == true else { continue }
            let activeEntry = try timeline(matchID: matchID).first { $0.eventID == item.id }
            let primary = activeEntry?.supersedesEventID ?? item.id
            var linked = [primary]
            if item.id != primary { linked.append(item.id) }
            if let locationID = try latestLocationEventID(targets: linked) { linked.append(locationID) }
            let links = String(decoding: try encoder.encode(linked), as: UTF8.self)
            let lookup = try prepare("SELECT id FROM report_document WHERE match_id = ? AND report_kind = 'incident' AND primary_event_id = ?")
            bind(lookup, 1, matchID.uuidString.lowercased()); bind(lookup, 2, primary.uuidString.lowercased())
            if sqlite3_step(lookup) == SQLITE_ROW, let id = columnText(lookup, 0) {
                sqlite3_finalize(lookup)
                let update = try prepare("UPDATE report_document SET linked_event_ids_json = ? WHERE id = ?")
                bind(update, 1, links); bind(update, 2, id)
                guard sqlite3_step(update) == SQLITE_DONE else { sqlite3_finalize(update); throw LedgerError.sqlite(lastError) }
                sqlite3_finalize(update)
            } else {
                sqlite3_finalize(lookup)
                let id = UUID()
                let insert = try prepare("INSERT INTO report_document VALUES (?, ?, 'incident', ?, ?, ?)")
                bind(insert, 1, id.uuidString.lowercased()); bind(insert, 2, matchID.uuidString.lowercased())
                bind(insert, 3, primary.uuidString.lowercased()); bind(insert, 4, links); bind(insert, 5, EventIntegrity.instant(Date()))
                guard sqlite3_step(insert) == SQLITE_DONE else { sqlite3_finalize(insert); throw LedgerError.sqlite(lastError) }
                sqlite3_finalize(insert)
                let initial = StructuredReportContent(summary: object["disciplinaryReason"] as? String ?? "Serious incident",
                                                      description: object["incidentNarrative"] as? String ?? "",
                                                      actionTaken: "", additionalNotes: "")
                _ = try saveReportContent(documentID: id, content: initial)
            }
        }
    }

    private func reportDocumentIdentity(documentID: UUID) throws -> (matchID: UUID, kind: ReportKind)? {
        let statement = try prepare("SELECT match_id, report_kind FROM report_document WHERE id = ?")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, documentID.uuidString.lowercased())
        guard sqlite3_step(statement) == SQLITE_ROW,
              let matchID = columnText(statement, 0).flatMap(UUID.init(uuidString:)),
              let kindText = columnText(statement, 1), let kind = ReportKind(rawValue: kindText) else { return nil }
        return (matchID, kind)
    }

    private func latestLocationEventID(targets: [UUID]) throws -> UUID? {
        for target in targets.reversed() {
            let statement = try prepare("SELECT event_id FROM event WHERE event_type = 'location_added' AND lower(json_extract(payload_json, '$.targetEventID')) = lower(?) ORDER BY recorded_at DESC, origin_sequence DESC LIMIT 1")
            bind(statement, 1, target.uuidString)
            if sqlite3_step(statement) == SQLITE_ROW, let id = columnText(statement, 0).flatMap(UUID.init(uuidString:)) {
                sqlite3_finalize(statement); return id
            }
            sqlite3_finalize(statement)
        }
        return nil
    }

    private func latestDocumentContentVersion(documentID: UUID) throws -> Int {
        let statement = try prepare("SELECT COALESCE(MAX(content_version), 0) FROM report_document_content WHERE document_id = ?")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, documentID.uuidString.lowercased())
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.sqlite(lastError) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func documentContent(documentID: UUID, version: Int) throws -> StructuredReportContent? {
        guard version > 0 else { return nil }
        let statement = try prepare("SELECT prose_json FROM report_document_content WHERE document_id = ? AND content_version = ?")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, documentID.uuidString.lowercased()); bind(statement, 2, String(version))
        guard sqlite3_step(statement) == SQLITE_ROW, let prose = columnText(statement, 0) else { return nil }
        return try JSONDecoder().decode(StructuredReportContent.self, from: Data(prose.utf8))
    }

    private func latestContentVersion(matchID: UUID, kind: ReportKind) throws -> Int {
        let statement = try prepare("SELECT COALESCE(MAX(content_version), 0) FROM report_content WHERE match_id = ? AND report_kind = ?")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, matchID.uuidString.lowercased()); bind(statement, 2, kind.rawValue)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.sqlite(lastError) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func latestSignedVersion(matchID: UUID, kind: ReportKind) throws -> Int {
        let statement = try prepare("SELECT COALESCE(MAX(version), 0) FROM signed_report_version WHERE match_id = ? AND report_kind = ?")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, matchID.uuidString.lowercased()); bind(statement, 2, kind.rawValue)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw LedgerError.sqlite(lastError) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func reportEventIDs(matchID: UUID) throws -> [UUID] {
        let statement = try prepare("SELECT event_id FROM event WHERE match_id = ? AND event_type <> 'report_signed' ORDER BY recorded_at, origin_device_id, origin_sequence")
        defer { sqlite3_finalize(statement) }; bind(statement, 1, matchID.uuidString.lowercased())
        var result: [UUID] = []
        while sqlite3_step(statement) == SQLITE_ROW,
              let id = columnText(statement, 0).flatMap(UUID.init(uuidString:)) { result.append(id) }
        return result
    }

    private func reportSourceFingerprint(matchID: UUID, documentID: UUID, contentVersion: Int) throws -> String {
        let contentStatement = try prepare("SELECT prose_json FROM report_document_content WHERE document_id = ? AND content_version = ?")
        defer { sqlite3_finalize(contentStatement) }
        bind(contentStatement, 1, documentID.uuidString.lowercased()); bind(contentStatement, 2, String(contentVersion))
        guard sqlite3_step(contentStatement) == SQLITE_ROW, let prose = columnText(contentStatement, 0) else {
            throw LedgerError.invalidDraft("report content version does not exist")
        }

        let identityStatement = try prepare("SELECT report_kind, linked_event_ids_json FROM report_document WHERE id = ?")
        defer { sqlite3_finalize(identityStatement) }; bind(identityStatement, 1, documentID.uuidString.lowercased())
        guard sqlite3_step(identityStatement) == SQLITE_ROW,
              let kindText = columnText(identityStatement, 0), let kind = ReportKind(rawValue: kindText),
              let linksText = columnText(identityStatement, 1) else {
            throw LedgerError.invalidDraft("report document does not exist")
        }
        let linkedIDs = Set((try? JSONDecoder().decode([UUID].self, from: Data(linksText.utf8))) ?? [])
        let eventStatement = try prepare("SELECT event_id, integrity_hash FROM event WHERE match_id = ? AND event_type <> 'report_signed' ORDER BY recorded_at, origin_device_id, origin_sequence")
        defer { sqlite3_finalize(eventStatement) }; bind(eventStatement, 1, matchID.uuidString.lowercased())
        var eventIdentity: [String] = []
        while sqlite3_step(eventStatement) == SQLITE_ROW,
              let id = columnText(eventStatement, 0), let hash = columnText(eventStatement, 1) {
            if kind == .incident, UUID(uuidString: id).map({ !linkedIDs.contains($0) }) == true { continue }
            eventIdentity.append("\(id):\(hash)")
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let fixtureData = try encoder.encode(try fixture(matchID: matchID))
        let rosterData = try encoder.encode(try participants(matchID: matchID))
        let rulesData = try encoder.encode(try rules(matchID: matchID))
        var source = Data()
        source.append(fixtureData); source.append(0)
        source.append(rosterData); source.append(0)
        source.append(rulesData); source.append(0)
        source.append(Data(eventIdentity.joined(separator: "\n").utf8)); source.append(0)
        source.append(Data(documentID.uuidString.lowercased().utf8)); source.append(0)
        source.append(Data(prose.utf8)); source.append(0)
        let attachmentIdentity = try attachments(documentID: documentID).map {
            "\($0.id.uuidString.lowercased()):\($0.checksum):\($0.byteCount):\($0.isRequired)"
        }.joined(separator: "\n")
        source.append(Data(attachmentIdentity.utf8))
        return SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined()
    }

    private func contiguousSequence(matchID: UUID, originDeviceID: String) throws -> Int64 {
        let stmt = try prepare("SELECT origin_sequence FROM event WHERE match_id = ? AND origin_device_id = ? ORDER BY origin_sequence")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, matchID.uuidString.lowercased()); bind(stmt, 2, originDeviceID)
        var expected: Int64 = 1
        while sqlite3_step(stmt) == SQLITE_ROW {
            let found = sqlite3_column_int64(stmt, 0)
            guard found == expected else { break }
            expected += 1
        }
        return expected - 1
    }

    private func eventFromRow(_ stmt: OpaquePointer?) -> LedgerEvent? {
        guard let eventIDText = columnText(stmt, 0), let eventID = UUID(uuidString: eventIDText),
              let eventType = columnText(stmt, 1), let originText = columnText(stmt, 3), let origin = UUID(uuidString: originText),
              let recordedText = columnText(stmt, 5), let recordedAt = date(recordedText),
              let payload = columnText(stmt, 10), let hash = columnText(stmt, 11) else { return nil }
        guard let constrainedMatchID = currentMatchIDForRow(stmt) else { return nil }
        let draft = EventDraft(eventID: eventID, matchID: constrainedMatchID, eventType: eventType,
                               schemaVersion: Int(sqlite3_column_int64(stmt, 2)), recordedAt: recordedAt,
                               matchPeriodID: columnText(stmt, 6).flatMap(UUID.init(uuidString:)),
                               matchClockMs: sqlite3_column_type(stmt, 7) == SQLITE_NULL ? nil : sqlite3_column_int64(stmt, 7),
                               effectiveAt: columnText(stmt, 8).flatMap(date),
                               supersedesEventID: columnText(stmt, 9).flatMap(UUID.init(uuidString:)), payloadJSON: payload)
        return LedgerEvent(draft: draft, originDeviceID: origin, originSequence: sqlite3_column_int64(stmt, 4), canonicalPayload: payload, integrityHash: hash)
    }

    private func event(eventID: UUID) throws -> LedgerEvent? {
        let statement = try prepare("SELECT event_id, event_type, schema_version, origin_device_id, origin_sequence, recorded_at, match_period_id, match_clock_ms, effective_at, supersedes_event_id, payload_json, integrity_hash, match_id FROM event WHERE event_id = ?")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, eventID.uuidString.lowercased())
        return sqlite3_step(statement) == SQLITE_ROW ? eventFromRow(statement) : nil
    }

    private func hasRevision(targetEventID: UUID) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM event_revision WHERE target_event_id = ? LIMIT 1")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, targetEventID.uuidString.lowercased())
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func currentMatchIDForRow(_ stmt: OpaquePointer?) -> UUID? {
        // eventsMissing selects the constrained match ID as column 0 in its own wrapper query below.
        columnText(stmt, 12).flatMap(UUID.init(uuidString:))
    }

    private func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    private func allocateSequence(matchID: UUID) throws -> Int64 {
        let id = matchID.uuidString.lowercased(), device = originDeviceID.uuidString.lowercased()
        let select = try prepare("SELECT next_sequence FROM device_sequence WHERE match_id = ? AND origin_device_id = ?")
        bind(select, 1, id); bind(select, 2, device); defer { sqlite3_finalize(select) }
        let sequence: Int64 = sqlite3_step(select) == SQLITE_ROW ? sqlite3_column_int64(select, 0) : 1
        try execute("INSERT INTO device_sequence(match_id, origin_device_id, next_sequence) VALUES('\(id)', '\(device)', \(sequence + 1)) ON CONFLICT(match_id, origin_device_id) DO UPDATE SET next_sequence = excluded.next_sequence;")
        return sequence
    }
    private func insertCreatedEvent(_ draft: EventDraft, canonicalPayload payload: String,
                                    peers: [String]) throws -> LedgerEvent {
        let sequence = try allocateSequence(matchID: draft.matchID)
        let hash = EventIntegrity.hash(draft: draft, deviceID: originDeviceID, sequence: sequence, payload: payload)
        let event = LedgerEvent(draft: draft, originDeviceID: originDeviceID, originSequence: sequence,
                                canonicalPayload: payload, integrityHash: hash)
        try insert(event)
        try insertRevisionIfNeeded(event)
        try insertValidation(event)
        try markProjectionDirty(matchID: draft.matchID)
        for peer in Set(peers) { try insertOutbox(event, peer: peer) }
        return event
    }
    private func upsertFixture(_ fixture: MatchFixture) throws {
        let stmt = try prepare("INSERT INTO match_fixture VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET competition = excluded.competition, scheduled_at = excluded.scheduled_at, venue_name = excluded.venue_name, home_team_name = excluded.home_team_name, away_team_name = excluded.away_team_name")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, fixture.matchID.uuidString.lowercased()); bind(stmt, 2, fixture.competition)
        bind(stmt, 3, EventIntegrity.instant(fixture.scheduledAt)); bind(stmt, 4, fixture.venueName)
        bind(stmt, 5, fixture.homeTeamName); bind(stmt, 6, fixture.awayTeamName)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }
    private func validate(draft: EventDraft, payload: String, originSequence: Int64? = nil) throws {
        guard !draft.eventType.isEmpty, draft.schemaVersion > 0 else {
            throw LedgerError.invalidDraft("event type and schema version are required")
        }
        if let matchClockMs = draft.matchClockMs, matchClockMs < 0 {
            throw LedgerError.invalidDraft("match clock cannot be negative")
        }
        if let originSequence, originSequence < 1 {
            throw LedgerError.invalidDraft("origin sequence must be positive")
        }
        if draft.eventType == "event_corrected" || draft.eventType == "event_reversed" {
            guard draft.supersedesEventID != nil, let reason = revisionReason(payload), !reason.isEmpty else {
                throw LedgerError.invalidDraft("corrections and reversals require a target and reason")
            }
        }
        guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else {
            throw LedgerError.invalidDraft("event payload must be a JSON object")
        }
        if draft.eventType == "event_corrected",
           let replacement = correctionReplacement(payload),
           let replacementObject = try? JSONSerialization.jsonObject(with: Data(replacement.payload.utf8)) as? [String: Any] {
            try validateMatchAction(type: replacement.type, object: replacementObject)
        }
        try validateMatchAction(type: draft.eventType, object: object)
        switch draft.eventType {
        case "location_added":
            guard let targetText = object["targetEventID"] as? String,
                  let targetID = UUID(uuidString: targetText),
                  let x = object["normalizedX"] as? NSNumber, let y = object["normalizedY"] as? NSNumber,
                  (0...100).contains(x.doubleValue), (0...100).contains(y.doubleValue),
                  let metresX = object["metresX"] as? NSNumber, let metresY = object["metresY"] as? NSNumber,
                  metresX.doubleValue >= 0, metresY.doubleValue >= 0,
                  object["pitchLengthMetres"] is NSNumber, object["pitchWidthMetres"] is NSNumber,
                  LocationCaptureMethod(rawValue: object["captureMethod"] as? String ?? "") != nil,
                  LocationAccuracy(rawValue: object["accuracy"] as? String ?? "") != nil,
                  object["regions"] is [String] else {
                throw LedgerError.invalidDraft("location events require a valid target and complete spatial snapshot")
            }
            let target = try event(eventID: targetID)
            // A local enrichment must point at an existing event. A replicated
            // enrichment may legally arrive first; its target is reconciled by
            // the same contiguous-cursor flow used for revisions.
            if originSequence == nil, target == nil {
                throw LedgerError.invalidDraft("location events require a valid target and complete spatial snapshot")
            }
            if let target, target.draft.matchID != draft.matchID {
                throw LedgerError.invalidDraft("location events require a valid target and complete spatial snapshot")
            }
        case "period_started":
            guard draft.matchPeriodID != nil, validPeriodPayload(object) else {
                throw LedgerError.invalidDraft("period start requires period ID, kind, and ordinal")
            }
            let state = try periodState(matchID: draft.matchID)
            guard state.active == nil, let expected = state.next,
                  periodDefinition(object) == expected else {
                throw LedgerError.invalidDraft("period start is not the next permitted transition")
            }
        case "period_ended":
            guard draft.matchPeriodID != nil, validPeriodPayload(object),
                  let finalClock = object["finalClockMs"] as? NSNumber, finalClock.int64Value >= 0 else {
                throw LedgerError.invalidDraft("period end requires period ID, kind, ordinal, and final clock")
            }
            let state = try periodState(matchID: draft.matchID)
            guard let active = state.active, active.periodID == draft.matchPeriodID,
                  periodDefinition(object) == active.definition else {
                throw LedgerError.invalidDraft("period end must close the active period")
            }
        default:
            break
        }
    }

    private func validateMatchAction(type: String, object: [String: Any]) throws {
        switch type {
        case MatchActionType.goal.rawValue, MatchActionType.foul.rawValue:
            guard validTeamSide(object["teamSide"]) else {
                throw LedgerError.invalidDraft("goals and fouls require a home or away team")
            }
        case MatchActionType.card.rawValue:
            guard validTeamSide(object["teamSide"]), let colour = object["colour"] as? String,
                  ["yellow", "red"].contains(colour), object["isDirectRed"] is Bool else {
                throw LedgerError.invalidDraft("cards require team, yellow or red colour, and direct-red state")
            }
        case MatchActionType.substitution.rawValue:
            guard validTeamSide(object["teamSide"]) else {
                throw LedgerError.invalidDraft("substitutions require a home or away team")
            }
            let out = object["playerOutId"] as? String
            let incoming = object["playerInId"] as? String
            guard (out == nil && incoming == nil) ||
                    (out.flatMap(UUID.init(uuidString:)) != nil && incoming.flatMap(UUID.init(uuidString:)) != nil && out != incoming) else {
                throw LedgerError.invalidDraft("substitution players must be distinct valid IDs or both deferred")
            }
        case MatchActionType.penalty.rawValue:
            guard validTeamSide(object["teamSide"]),
                  PenaltyOutcome(rawValue: object["outcome"] as? String ?? "") != nil,
                  PenaltyPhase(rawValue: object["phase"] as? String ?? "") != nil else {
                throw LedgerError.invalidDraft("penalties require team, phase, and outcome")
            }
        case MatchActionType.injury.rawValue:
            guard object["teamSide"] == nil || validTeamSide(object["teamSide"]) else {
                throw LedgerError.invalidDraft("injuries require a valid team when one is supplied")
            }
        case MatchActionType.varReview.rawValue:
            guard VARReviewType(rawValue: object["reviewType"] as? String ?? "") != nil,
                  VAROutcome(rawValue: object["outcome"] as? String ?? "") != nil else {
                throw LedgerError.invalidDraft("VAR reviews require review type and outcome")
            }
        case MatchActionType.suspension.rawValue:
            guard SuspensionState(rawValue: object["state"] as? String ?? "") != nil,
                  let reason = object["reason"] as? String,
                  !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LedgerError.invalidDraft("suspensions require state and reason")
            }
        case MatchActionType.restart.rawValue:
            guard RestartType(rawValue: object["restartType"] as? String ?? "") != nil,
                  object["teamSide"] == nil || validTeamSide(object["teamSide"]) else {
                throw LedgerError.invalidDraft("restarts require a valid type and optional team")
            }
        default:
            break
        }
    }
    private func validTeamSide(_ value: Any?) -> Bool {
        guard let side = value as? String else { return false }
        return side == "home" || side == "away"
    }
    private func effectiveTypeAndPayload(_ event: LedgerEvent) -> (type: String, payload: String) {
        if event.draft.eventType == "event_corrected", let replacement = correctionReplacement(event.canonicalPayload) {
            return replacement
        }
        return (event.draft.eventType, event.canonicalPayload)
    }
    private func locationRequired(in payload: String) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { return false }
        return object["locationRequired"] as? Bool == true
    }
    private func pitchRegions(x: Double, y: Double, pitch: PitchDimensions) -> [String] {
        var regions: [String] = []
        regions.append(x < pitch.lengthMetres / 3 ? "defending_third" : (x > pitch.lengthMetres * 2 / 3 ? "attacking_third" : "middle_third"))
        regions.append(y < pitch.widthMetres / 3 ? "left_channel" : (y > pitch.widthMetres * 2 / 3 ? "right_channel" : "centre_channel"))
        let centred = abs(y - pitch.widthMetres / 2)
        if (x <= 16.5 || x >= pitch.lengthMetres - 16.5), centred <= 20.16 { regions.append("penalty_area") }
        if (x <= 5.5 || x >= pitch.lengthMetres - 5.5), centred <= 9.16 { regions.append("goal_area") }
        return regions
    }
    private func validPeriodPayload(_ object: [String: Any]) -> Bool { periodDefinition(object) != nil }
    private func periodDefinition(_ object: [String: Any]) -> MatchPeriodDefinition? {
        guard let kind = object["periodKind"] as? String, !kind.isEmpty,
              let ordinal = object["ordinal"] as? NSNumber, ordinal.intValue > 0 else { return nil }
        return MatchPeriodDefinition(kind: kind, ordinal: ordinal.intValue)
    }
    private func periodDefinition(payload: String) -> MatchPeriodDefinition? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { return nil }
        return periodDefinition(object)
    }
    private func nextPeriod(after completed: [MatchPeriodDefinition], rules: MatchRuleSnapshot) -> MatchPeriodDefinition? {
        let sequence = [
            MatchPeriodDefinition(kind: "first_half", ordinal: 1),
            MatchPeriodDefinition(kind: "second_half", ordinal: 2)
        ] + (rules.extraTimeEnabled ? [
            MatchPeriodDefinition(kind: "extra_time_first_half", ordinal: 3),
            MatchPeriodDefinition(kind: "extra_time_second_half", ordinal: 4)
        ] : [])
        guard completed.count < sequence.count else { return nil }
        return sequence[completed.count]
    }
    private func insert(_ event: LedgerEvent) throws {
        let sql = "INSERT INTO event VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        let stmt = try prepare(sql); defer { sqlite3_finalize(stmt) }
        let d = event.draft
        bind(stmt, 1, d.eventID.uuidString.lowercased()); bind(stmt, 2, d.matchID.uuidString.lowercased())
        bind(stmt, 3, d.eventType); bind(stmt, 4, String(d.schemaVersion))
        bind(stmt, 5, event.originDeviceID.uuidString.lowercased()); bind(stmt, 6, String(event.originSequence))
        bind(stmt, 7, EventIntegrity.instant(d.recordedAt)); bind(stmt, 8, d.matchPeriodID?.uuidString.lowercased())
        bind(stmt, 9, d.matchClockMs.map(String.init)); bind(stmt, 10, d.effectiveAt.map(EventIntegrity.instant))
        bind(stmt, 11, d.supersedesEventID?.uuidString.lowercased()); bind(stmt, 12, event.canonicalPayload)
        bind(stmt, 13, event.integrityHash)
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }
    private func insertValidation(_ event: LedgerEvent) throws {
        let stmt = try prepare("INSERT INTO event_validation VALUES (?, 'valid', 'valid', 'pending', '', ?)")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, event.draft.eventID.uuidString.lowercased())
        bind(stmt, 2, EventIntegrity.instant(Date()))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }
    private func markProjectionDirty(matchID: UUID) throws {
        let stmt = try prepare("INSERT INTO match_projection(match_id, dirty) VALUES (?, 1) ON CONFLICT(match_id) DO UPDATE SET dirty = 1")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, matchID.uuidString.lowercased())
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }
    private func cacheProjection(matchID: UUID, projection: MatchProjection, eventHashes: [String]) throws {
        let cursorData = Data(eventHashes.sorted().joined(separator: "\\n").utf8)
        let cursor = SHA256.hash(data: cursorData).map { String(format: "%02x", $0) }.joined()
        let snapshot = "{\"homeScore\":\(projection.homeScore),\"awayScore\":\(projection.awayScore),\"issueCount\":\(projection.issues.count)}"
        let stmt = try prepare("INSERT INTO match_projection(match_id, projection_cursor, home_score, away_score, projection_json, rebuilt_at, dirty) VALUES (?, ?, ?, ?, ?, ?, 0) ON CONFLICT(match_id) DO UPDATE SET projection_cursor = excluded.projection_cursor, home_score = excluded.home_score, away_score = excluded.away_score, projection_json = excluded.projection_json, rebuilt_at = excluded.rebuilt_at, dirty = 0")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, matchID.uuidString.lowercased()); bind(stmt, 2, cursor)
        bind(stmt, 3, String(projection.homeScore)); bind(stmt, 4, String(projection.awayScore))
        bind(stmt, 5, snapshot); bind(stmt, 6, EventIntegrity.instant(Date()))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }
    private func insertOutbox(_ event: LedgerEvent, peer: String) throws { try execute("INSERT INTO outbox VALUES ('\(UUID().uuidString.lowercased())', '\(event.draft.matchID.uuidString.lowercased())', 'event', '\(event.draft.eventID.uuidString.lowercased())', '\(event.integrityHash)', '\(peer.replacingOccurrences(of: "'", with: "''"))', 'pending')") }
    private func insertRevisionIfNeeded(_ event: LedgerEvent) throws {
        let draft = event.draft
        guard (draft.eventType == "event_corrected" || draft.eventType == "event_reversed"),
              let target = draft.supersedesEventID,
              let reason = revisionReason(event.canonicalPayload) else { return }
        let statement = try prepare("INSERT INTO event_revision VALUES (?, ?, ?, ?, ?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        bind(statement, 1, UUID().uuidString.lowercased()); bind(statement, 2, draft.matchID.uuidString.lowercased())
        bind(statement, 3, target.uuidString.lowercased()); bind(statement, 4, draft.eventID.uuidString.lowercased())
        bind(statement, 5, draft.eventType == "event_reversed" ? "reversal" : "correction")
        bind(statement, 6, reason); bind(statement, 7, EventIntegrity.instant(draft.recordedAt))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }
    private func revisionReason(_ payload: String) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { return nil }
        return object["reason"] as? String
    }
    private func correctionReplacement(_ payload: String) -> (type: String, payload: String)? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let type = object["replacementEventType"] as? String,
              let replacement = object["replacementPayload"] else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: replacement),
              let replacementJSON = String(data: data, encoding: .utf8),
              let canonical = try? CanonicalJSON.canonicalize(replacementJSON) else { return nil }
        return (type, canonical)
    }
    private func revisionValidation(_ rows: [(id: String, type: String, payload: String, target: String?, hash: String)]) -> (invalidRevisionIDs: Set<String>, issues: [ProjectionIssue]) {
        let revisions = rows.filter { $0.type == "event_corrected" || $0.type == "event_reversed" }
        let knownIDs = Set(rows.map(\.id))
        var invalid = Set<String>(), issues: [ProjectionIssue] = []
        for revision in revisions where revision.target == nil || !knownIDs.contains(revision.target!) {
            invalid.insert(revision.id)
            issues.append(ProjectionIssue(code: "missing_revision_target", eventID: revision.id))
        }
        let groups = Dictionary(grouping: revisions.compactMap { revision in revision.target.map { ($0, revision) } }, by: \.0)
        for (target, candidates) in groups where candidates.count > 1 {
            invalid.formUnion(candidates.map { $0.1.id })
            issues.append(ProjectionIssue(code: "ambiguous_revision", eventID: target))
        }
        let targetByRevision = Dictionary(uniqueKeysWithValues: revisions.compactMap { revision in revision.target.map { (revision.id, $0) } })
        for revision in revisions {
            var visited = Set<String>(), cursor: String? = revision.id
            while let current = cursor, let next = targetByRevision[current] {
                if !visited.insert(current).inserted { break }
                if next == revision.id || visited.contains(next) {
                    invalid.formUnion(visited)
                    issues.append(ProjectionIssue(code: "cyclic_revision", eventID: revision.id))
                    break
                }
                cursor = next
            }
        }
        return (invalid, Array(Set(issues)).sorted { $0.code < $1.code || ($0.code == $1.code && $0.eventID < $1.eventID) })
    }
    private func insertReceipt(peer: UUID, messageID: UUID, event: LedgerEvent) throws {
        try execute("INSERT OR IGNORE INTO inbox_receipt VALUES ('\(peer.uuidString.lowercased())', '\(messageID.uuidString.lowercased())', '\(event.draft.eventID.uuidString.lowercased())', '\(event.integrityHash)', '\(EventIntegrity.instant(Date()))')")
    }
    private func eventHash(eventID: UUID) throws -> String? {
        let stmt = try prepare("SELECT integrity_hash FROM event WHERE event_id = ?"); defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, eventID.uuidString.lowercased())
        return sqlite3_step(stmt) == SQLITE_ROW ? columnText(stmt, 0) : nil
    }
    private func originSequenceExists(for event: LedgerEvent) throws -> Bool {
        let stmt = try prepare("SELECT 1 FROM event WHERE match_id = ? AND origin_device_id = ? AND origin_sequence = ?")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, event.draft.matchID.uuidString.lowercased())
        bind(stmt, 2, event.originDeviceID.uuidString.lowercased())
        bind(stmt, 3, String(event.originSequence))
        return sqlite3_step(stmt) == SQLITE_ROW
    }
    private func receipt(peer: UUID, messageID: UUID) throws -> (objectID: String, hash: String)? {
        let stmt = try prepare("SELECT object_id, object_hash FROM inbox_receipt WHERE peer_device_id = ? AND message_id = ?")
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, peer.uuidString.lowercased())
        bind(stmt, 2, messageID.uuidString.lowercased())
        guard sqlite3_step(stmt) == SQLITE_ROW,
              let objectID = columnText(stmt, 0), let hash = columnText(stmt, 1) else { return nil }
        return (objectID, hash)
    }
    private func advanceContiguousCursor(for event: LedgerEvent, peer: UUID) throws {
        let matchID = event.draft.matchID.uuidString.lowercased()
        let originID = event.originDeviceID.uuidString.lowercased()
        let peerID = peer.uuidString.lowercased()
        var cursor = try syncCursor(matchID: event.draft.matchID, peerDeviceID: peer, originDeviceID: event.originDeviceID)
        let statement = try prepare("SELECT 1 FROM event WHERE match_id = ? AND origin_device_id = ? AND origin_sequence = ?")
        defer { sqlite3_finalize(statement) }
        while true {
            sqlite3_reset(statement); sqlite3_clear_bindings(statement)
            bind(statement, 1, matchID); bind(statement, 2, originID); bind(statement, 3, String(cursor + 1))
            guard sqlite3_step(statement) == SQLITE_ROW else { break }
            cursor += 1
        }
        let upsert = try prepare("INSERT INTO sync_cursor VALUES (?, ?, ?, ?, ?) ON CONFLICT(match_id, peer_device_id, origin_device_id) DO UPDATE SET last_contiguous_sequence = excluded.last_contiguous_sequence, synced_at = excluded.synced_at")
        defer { sqlite3_finalize(upsert) }
        bind(upsert, 1, matchID); bind(upsert, 2, peerID); bind(upsert, 3, originID)
        bind(upsert, 4, String(cursor)); bind(upsert, 5, EventIntegrity.instant(Date()))
        guard sqlite3_step(upsert) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }
    private func quarantine(_ event: LedgerEvent, peer: UUID, raw: String, code: String, diagnostic: String) throws {
        let stmt = try prepare("INSERT OR IGNORE INTO quarantined_event VALUES (?, ?, ?, ?, ?, ?)"); defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, event.draft.eventID.uuidString.lowercased()); bind(stmt, 2, peer.uuidString.lowercased())
        bind(stmt, 3, raw); bind(stmt, 4, code); bind(stmt, 5, diagnostic); bind(stmt, 6, EventIntegrity.instant(Date()))
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw LedgerError.sqlite(lastError) }
    }
    private func execute(_ sql: String) throws { guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw LedgerError.sqlite(lastError) } }
    private func prepare(_ sql: String) throws -> OpaquePointer? { var statement: OpaquePointer?; guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else { throw LedgerError.sqlite(lastError) }; return statement }
    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String) { sqlite3_bind_text(stmt, index, value, -1, sqliteTransient) }
    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value else { sqlite3_bind_null(stmt, index); return }
        bind(stmt, index, value)
    }
    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String? { sqlite3_column_text(stmt, index).map { String(cString: $0) } }
    private func scalarInt(_ sql: String) throws -> Int { let stmt = try prepare(sql); defer { sqlite3_finalize(stmt) }; guard sqlite3_step(stmt) == SQLITE_ROW else { throw LedgerError.sqlite(lastError) }; return Int(sqlite3_column_int64(stmt, 0)) }
    private var lastError: String { database.map { String(cString: sqlite3_errmsg($0)) } ?? "database unavailable" }
}

public struct ProjectionIssue: Hashable, Sendable { public let code: String; public let eventID: String }

public struct MatchProjection: Equatable, Sendable {
    public let homeScore: Int
    public let awayScore: Int
    public let issues: [ProjectionIssue]
    public init(homeScore: Int, awayScore: Int, issues: [ProjectionIssue] = []) {
        self.homeScore = homeScore; self.awayScore = awayScore; self.issues = issues
    }
}
