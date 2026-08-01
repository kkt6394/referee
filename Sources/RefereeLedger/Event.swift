import CryptoKit
import Foundation

/// Match-owned fixture snapshot. Reports and event projection reference this
/// snapshot rather than mutable master team or venue profiles.
public struct MatchFixture: Codable, Equatable, Sendable {
    public let matchID: UUID
    public let competition: String
    public let scheduledAt: Date
    public let venueName: String
    public let homeTeamName: String
    public let awayTeamName: String
    public let homeTeamColor: String?
    public let awayTeamColor: String?

    public init(matchID: UUID, competition: String, scheduledAt: Date, venueName: String,
                homeTeamName: String, awayTeamName: String,
                homeTeamColor: String? = nil, awayTeamColor: String? = nil) {
        self.matchID = matchID
        self.competition = competition
        self.scheduledAt = scheduledAt
        self.venueName = venueName
        self.homeTeamName = homeTeamName
        self.awayTeamName = awayTeamName
        self.homeTeamColor = homeTeamColor
        self.awayTeamColor = awayTeamColor
    }
}

/// Persisted, match-owned readiness checks completed before kick-off. These
/// checks are operational guidance rather than a gate on offline match use.
public struct PreMatchChecklist: Codable, Equatable, Sendable {
    public let pitchChecked: Bool
    public let equipmentChecked: Bool
    public let crewChecked: Bool
    public let lineupChecked: Bool
    public let notes: String

    public init(pitchChecked: Bool = false, equipmentChecked: Bool = false,
                crewChecked: Bool = false, lineupChecked: Bool = false,
                notes: String = "") {
        self.pitchChecked = pitchChecked
        self.equipmentChecked = equipmentChecked
        self.crewChecked = crewChecked
        self.lineupChecked = lineupChecked
        self.notes = notes
    }

    public var completedCount: Int {
        [pitchChecked, equipmentChecked, crewChecked, lineupChecked].filter { $0 }.count
    }

    public var isComplete: Bool { completedCount == 4 }
}

public struct EventDraft: Codable, Sendable {
    public let eventID: UUID
    public let matchID: UUID
    public let eventType: String
    public let schemaVersion: Int
    public let recordedAt: Date
    public let matchPeriodID: UUID?
    public let matchClockMs: Int64?
    public let effectiveAt: Date?
    public let supersedesEventID: UUID?
    public let payloadJSON: String

    public init(eventID: UUID = UUID(), matchID: UUID, eventType: String, schemaVersion: Int = 1,
                recordedAt: Date = Date(), matchPeriodID: UUID? = nil, matchClockMs: Int64? = nil,
                effectiveAt: Date? = nil, supersedesEventID: UUID? = nil, payloadJSON: String) {
        self.eventID = eventID; self.matchID = matchID; self.eventType = eventType; self.schemaVersion = schemaVersion
        self.recordedAt = recordedAt; self.matchPeriodID = matchPeriodID; self.matchClockMs = matchClockMs
        self.effectiveAt = effectiveAt; self.supersedesEventID = supersedesEventID; self.payloadJSON = payloadJSON
    }
}

public struct LedgerEvent: Codable, Equatable, Sendable {
    public let draft: EventDraft
    public let originDeviceID: UUID
    public let originSequence: Int64
    public let canonicalPayload: String
    public let integrityHash: String
}

/// Immutable envelope received from a peer. Delivery metadata is deliberately absent.
public struct ReplicatedEvent: Codable, Sendable {
    public let event: LedgerEvent
    public let rawPayloadJSON: String

    public init(event: LedgerEvent, rawPayloadJSON: String? = nil) {
        self.event = event
        self.rawPayloadJSON = rawPayloadJSON ?? event.canonicalPayload
    }
}

/// The small, read-only state the Watch needs while it is disconnected.
public struct CompactMatchProjection: Codable, Equatable, Sendable {
    public let homeScore: Int
    public let awayScore: Int
    public let periodID: UUID?
    public let periodLabel: String
    public let clockAnchor: Date?
    public let clockAnchorMs: Int64

    public init(homeScore: Int, awayScore: Int, periodID: UUID? = nil,
                periodLabel: String = "NOT STARTED", clockAnchor: Date? = nil,
                clockAnchorMs: Int64 = 0) {
        self.homeScore = homeScore; self.awayScore = awayScore; self.periodID = periodID
        self.periodLabel = periodLabel; self.clockAnchor = clockAnchor; self.clockAnchorMs = clockAnchorMs
    }
}

/// The currently live referee-confirmed period, derived from immutable boundary events.
public struct MatchPeriodContext: Codable, Equatable, Sendable {
    public let periodID: UUID
    public let definition: MatchPeriodDefinition
    public let label: String
    public let startedAt: Date
    public let startClockMs: Int64

    public init(periodID: UUID, definition: MatchPeriodDefinition, startedAt: Date, startClockMs: Int64) {
        self.periodID = periodID; self.definition = definition; self.label = definition.label
        self.startedAt = startedAt; self.startClockMs = startClockMs
    }
}

/// Read-only roster data that may be needed by a Watch quick-action flow.
/// It is match-owned rather than a reference to mutable phone master data.
public struct MatchParticipantSnapshot: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let teamSide: String?
    public let role: String
    public let displayName: String
    public let shirtNumber: Int?

    public init(id: UUID, teamSide: String? = nil, role: String, displayName: String, shirtNumber: Int? = nil) {
        self.id = id; self.teamSide = teamSide; self.role = role
        self.displayName = displayName; self.shirtNumber = shirtNumber
    }
}

/// Details added on iPhone after a fast goal/card capture. Saving this value
/// appends a correction event; it never updates the captured event itself.
public struct EventDetailCompletion: Equatable, Sendable {
    public let participantID: UUID
    public let disciplinaryReason: String?
    public let incidentNarrative: String?
    public let locationRequired: Bool

    public init(participantID: UUID, disciplinaryReason: String? = nil, incidentNarrative: String? = nil,
                locationRequired: Bool = false) {
        self.participantID = participantID
        self.disciplinaryReason = disciplinaryReason
        self.incidentNarrative = incidentNarrative
        self.locationRequired = locationRequired
    }
}

/// Stable vocabulary for live match actions shared by iPhone, Watch, sync,
/// review, and export. Raw values are part of the persisted event contract.
public enum MatchActionType: String, Codable, CaseIterable, Sendable {
    case goal = "goal_recorded"
    case foul = "foul_recorded"
    case card = "card_recorded"
    case substitution = "substitution_recorded"
    case penalty = "penalty_recorded"
    case injury = "injury_recorded"
    case varReview = "var_recorded"
    case suspension = "suspension_recorded"
    case restart = "restart_recorded"
}

public enum PenaltyOutcome: String, Codable, CaseIterable, Sendable {
    case scored, missed, saved, post, retake, pending
}

public enum PenaltyPhase: String, Codable, CaseIterable, Sendable {
    case match, shootout
}

public enum VARReviewType: String, Codable, CaseIterable, Sendable {
    case goal, penalty, directRed = "direct_red", mistakenIdentity = "mistaken_identity", other
}

public enum VAROutcome: String, Codable, CaseIterable, Sendable {
    case confirmed, overturned, noChange = "no_change", pending
}

public enum SuspensionState: String, Codable, CaseIterable, Sendable {
    case started, resumed
}

public enum RestartType: String, Codable, CaseIterable, Sendable {
    case kickoff, freeKick = "free_kick", penaltyKick = "penalty_kick", throwIn = "throw_in"
    case goalKick = "goal_kick", cornerKick = "corner_kick", droppedBall = "dropped_ball"
}

/// Match-owned pitch dimensions used to convert a pitch tap into both official
/// metre coordinates and device-independent normalized coordinates.
public struct PitchDimensions: Codable, Equatable, Sendable {
    public let lengthMetres: Double
    public let widthMetres: Double

    public init(lengthMetres: Double, widthMetres: Double) {
        self.lengthMetres = lengthMetres
        self.widthMetres = widthMetres
    }
}

public enum LocationCaptureMethod: String, Codable, Hashable, Sendable { case pitchTap = "pitch_tap", gpsAssisted = "gps_assisted", laterCorrection = "later_correction" }
public enum LocationAccuracy: String, Codable, Hashable, Sendable { case refereeConfirmed = "referee_confirmed", estimated, unconfirmed }

/// A frozen spatial snapshot derived when `location_added` is appended.
public struct EventLocation: Codable, Equatable, Sendable {
    public let targetEventID: UUID
    public let normalizedX: Double
    public let normalizedY: Double
    public let metresX: Double
    public let metresY: Double
    public let pitchLengthMetres: Double
    public let pitchWidthMetres: Double
    public let captureMethod: LocationCaptureMethod
    public let accuracy: LocationAccuracy
    public let regions: [String]

    public init(targetEventID: UUID, normalizedX: Double, normalizedY: Double,
                metresX: Double, metresY: Double, pitchLengthMetres: Double,
                pitchWidthMetres: Double, captureMethod: LocationCaptureMethod,
                accuracy: LocationAccuracy, regions: [String]) {
        self.targetEventID = targetEventID; self.normalizedX = normalizedX; self.normalizedY = normalizedY
        self.metresX = metresX; self.metresY = metresY
        self.pitchLengthMetres = pitchLengthMetres; self.pitchWidthMetres = pitchWidthMetres
        self.captureMethod = captureMethod; self.accuracy = accuracy; self.regions = regions
    }
}

/// The small subset of the competition rules needed while a Watch is offline.
public struct MatchRuleSnapshot: Codable, Equatable, Sendable {
    public let halfDurationSeconds: Int
    public let extraTimeEnabled: Bool
    public let penaltyShootoutEnabled: Bool
    public let extraTimeHalfDurationSeconds: Int

    public init(halfDurationSeconds: Int = 45 * 60, extraTimeEnabled: Bool = false, penaltyShootoutEnabled: Bool = false,
                extraTimeHalfDurationSeconds: Int = 15 * 60) {
        self.halfDurationSeconds = halfDurationSeconds
        self.extraTimeEnabled = extraTimeEnabled
        self.penaltyShootoutEnabled = penaltyShootoutEnabled
        self.extraTimeHalfDurationSeconds = extraTimeHalfDurationSeconds
    }
}

public struct MatchPeriodDefinition: Codable, Equatable, Sendable {
    public let kind: String
    public let ordinal: Int

    public init(kind: String, ordinal: Int) {
        self.kind = kind
        self.ordinal = ordinal
    }

    public var label: String { kind.replacingOccurrences(of: "_", with: " ").uppercased() }
}

/// Derived lifecycle state. The source of truth remains the append-only period
/// boundary events; this value only tells a client which confirmed transition is legal next.
public struct MatchPeriodState: Codable, Equatable, Sendable {
    public let active: MatchPeriodContext?
    public let next: MatchPeriodDefinition?
    public let isComplete: Bool

    public init(active: MatchPeriodContext?, next: MatchPeriodDefinition?, isComplete: Bool) {
        self.active = active; self.next = next; self.isComplete = isComplete
    }

    public var displayLabel: String {
        if let active { return active.label }
        if isComplete { return "FULL TIME" }
        if let next, next.kind == "second_half" { return "HALF TIME" }
        return next?.label ?? "NOT STARTED"
    }
}

/// A read-only row for the iPhone match timeline. Accepted events remain in
/// the ledger even when a later correction or reversal makes them inactive.
public struct MatchTimelineEntry: Codable, Equatable, Sendable, Identifiable {
    public let eventID: UUID
    public let eventType: String
    public let recordedAt: Date
    public let matchPeriodID: UUID?
    public let matchClockMs: Int64?
    public let payloadJSON: String
    public let supersedesEventID: UUID?
    public let isActive: Bool
    public let hasRevisionIssue: Bool

    public var id: UUID { eventID }
    public var isRevision: Bool { eventType == "event_corrected" || eventType == "event_reversed" }
    public var canRevise: Bool { isActive && !isRevision && eventType != "period_started" && eventType != "period_ended" }

    public init(eventID: UUID, eventType: String, recordedAt: Date, matchPeriodID: UUID?,
                matchClockMs: Int64?, payloadJSON: String, supersedesEventID: UUID?,
                isActive: Bool, hasRevisionIssue: Bool) {
        self.eventID = eventID; self.eventType = eventType; self.recordedAt = recordedAt
        self.matchPeriodID = matchPeriodID; self.matchClockMs = matchClockMs
        self.payloadJSON = payloadJSON; self.supersedesEventID = supersedesEventID
        self.isActive = isActive; self.hasRevisionIssue = hasRevisionIssue
    }
}

/// The active, iPhone-owned offline context transferred to the Watch.
public struct MatchPackage: Codable, Equatable, Sendable {
    public let version: Int
    /// Repeated explicitly so the transport contract does not depend on a nested field.
    public let activeMatchID: UUID
    public let fixture: MatchFixture
    public let roster: [MatchParticipantSnapshot]
    public let rules: MatchRuleSnapshot
    public let projection: CompactMatchProjection
    public let originWatermarks: [String: Int64]
    public let eventDigest: String

    public init(version: Int = 1, fixture: MatchFixture, roster: [MatchParticipantSnapshot] = [],
                rules: MatchRuleSnapshot = MatchRuleSnapshot(), projection: CompactMatchProjection,
                originWatermarks: [String: Int64], eventDigest: String) {
        self.version = version; self.activeMatchID = fixture.matchID; self.fixture = fixture
        self.roster = roster; self.rules = rules; self.projection = projection
        self.originWatermarks = originWatermarks; self.eventDigest = eventDigest
    }
}

/// Reconciliation state exchanged after activation and whenever connectivity returns.
public struct SyncWatermark: Codable, Equatable, Sendable {
    public let matchID: UUID
    public let deviceID: UUID
    public let originWatermarks: [String: Int64]
    public let eventDigest: String

    public init(matchID: UUID, deviceID: UUID, originWatermarks: [String: Int64], eventDigest: String) {
        self.matchID = matchID; self.deviceID = deviceID; self.originWatermarks = originWatermarks; self.eventDigest = eventDigest
    }
}

public struct EventAcknowledgement: Codable, Equatable, Sendable {
    public let matchID: UUID
    public let eventID: UUID
    public let integrityHash: String

    public init(matchID: UUID, eventID: UUID, integrityHash: String) {
        self.matchID = matchID; self.eventID = eventID; self.integrityHash = integrityHash
    }
}

public enum ReportKind: String, Codable, CaseIterable, Sendable {
    case match
    case referee
    case incident
}

/// Stable identity for one independently editable/signable report. Match and
/// referee reports each have one document per match; incident reports have one
/// document per qualifying incident.
public struct ReportDocument: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let matchID: UUID
    public let kind: ReportKind
    public let primaryEventID: UUID?
    public let linkedEventIDs: [UUID]
    public let contentVersion: Int
    public let content: StructuredReportContent

    public init(id: UUID, matchID: UUID, kind: ReportKind, primaryEventID: UUID? = nil,
                linkedEventIDs: [UUID] = [], contentVersion: Int = 0,
                content: StructuredReportContent = StructuredReportContent()) {
        self.id = id; self.matchID = matchID; self.kind = kind
        self.primaryEventID = primaryEventID; self.linkedEventIDs = linkedEventIDs
        self.contentVersion = contentVersion; self.content = content
    }
}

/// Report-owned prose. These fields are versioned independently and never
/// mutate the immutable event ledger.
public struct StructuredReportContent: Codable, Equatable, Sendable {
    public var summary: String
    public var description: String
    public var actionTaken: String
    public var additionalNotes: String

    public init(summary: String = "", description: String = "",
                actionTaken: String = "", additionalNotes: String = "") {
        self.summary = summary; self.description = description
        self.actionTaken = actionTaken; self.additionalNotes = additionalNotes
    }
}

public struct ConfirmedScore: Codable, Equatable, Sendable {
    public let home: Int
    public let away: Int

    public init(home: Int, away: Int) {
        self.home = home
        self.away = away
    }
}

public enum ValidationSeverity: String, Codable, Sendable { case blocking, warning }

public struct ReportValidationIssue: Codable, Equatable, Sendable, Identifiable {
    public let code: String
    public let severity: ValidationSeverity
    public let eventID: UUID?

    public var id: String { "\(code):\(eventID?.uuidString ?? "match")" }

    public init(code: String, severity: ValidationSeverity = .blocking, eventID: UUID? = nil) {
        self.code = code
        self.severity = severity
        self.eventID = eventID
    }
}

/// A reproducible, derived review result. It is persisted inside a signed
/// report snapshot, but it is never a mutable source of match truth.
public struct PostMatchValidationResult: Codable, Equatable, Sendable {
    public let matchID: UUID
    public let projectedScore: ConfirmedScore
    public let confirmedScore: ConfirmedScore?
    public let issues: [ReportValidationIssue]
    public let validatedAt: Date

    public var blockingIssues: [ReportValidationIssue] { issues.filter { $0.severity == .blocking } }
    public var canSign: Bool { blockingIssues.isEmpty }

    public init(matchID: UUID, projectedScore: ConfirmedScore, confirmedScore: ConfirmedScore?,
                issues: [ReportValidationIssue], validatedAt: Date) {
        self.matchID = matchID
        self.projectedScore = projectedScore
        self.confirmedScore = confirmedScore
        self.issues = issues
        self.validatedAt = validatedAt
    }
}

public enum SignedReportStatus: String, Codable, Sendable { case current, superseded }

public enum ReportExportFormat: String, Codable, CaseIterable, Sendable { case pdf, xlsx }

/// Immutable metadata for bytes stored in the app's private attachment area.
/// `relativePath` is never an external URL and the checksum covers the exact bytes.
public struct ReportAttachment: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let matchID: UUID
    public let documentID: UUID
    public let mediaType: String
    public let originalFilename: String
    public let byteCount: Int64
    public let checksum: String
    public let relativePath: String
    public let createdAt: Date
    public let isRequired: Bool
    public let isReadable: Bool

    public init(id: UUID, matchID: UUID, documentID: UUID, mediaType: String,
                originalFilename: String, byteCount: Int64, checksum: String,
                relativePath: String, createdAt: Date, isRequired: Bool,
                isReadable: Bool) {
        self.id = id; self.matchID = matchID; self.documentID = documentID
        self.mediaType = mediaType; self.originalFilename = originalFilename
        self.byteCount = byteCount; self.checksum = checksum; self.relativePath = relativePath
        self.createdAt = createdAt; self.isRequired = isRequired; self.isReadable = isReadable
    }
}

public enum AttachmentTransferDirection: String, Codable, Sendable { case outgoing, incoming }
public enum AttachmentTransferState: String, Codable, Sendable { case pending, transferring, failed, completed }

/// Transport-safe attachment metadata. File-system paths and readability are
/// deliberately excluded; receivers derive their own private final path.
public struct AttachmentManifest: Codable, Equatable, Sendable {
    public let attachmentID: UUID
    public let matchID: UUID
    public let documentID: UUID
    public let mediaType: String
    public let originalFilename: String
    public let byteCount: Int64
    public let checksum: String
    public let createdAt: Date
    public let isRequired: Bool

    public init(attachmentID: UUID, matchID: UUID, documentID: UUID, mediaType: String,
                originalFilename: String, byteCount: Int64, checksum: String,
                createdAt: Date, isRequired: Bool) {
        self.attachmentID = attachmentID; self.matchID = matchID; self.documentID = documentID
        self.mediaType = mediaType; self.originalFilename = originalFilename
        self.byteCount = byteCount; self.checksum = checksum; self.createdAt = createdAt
        self.isRequired = isRequired
    }

    public init(attachment: ReportAttachment) {
        self.init(attachmentID: attachment.id, matchID: attachment.matchID,
                  documentID: attachment.documentID, mediaType: attachment.mediaType,
                  originalFilename: attachment.originalFilename, byteCount: attachment.byteCount,
                  checksum: attachment.checksum, createdAt: attachment.createdAt,
                  isRequired: attachment.isRequired)
    }
}

public struct AttachmentChunk: Codable, Equatable, Sendable {
    public let manifest: AttachmentManifest
    public let offset: Int64
    public let bytes: Data

    public init(manifest: AttachmentManifest, offset: Int64, bytes: Data) {
        self.manifest = manifest; self.offset = offset; self.bytes = bytes
    }
}

public struct AttachmentTransferAcknowledgement: Codable, Equatable, Sendable {
    public let attachmentID: UUID
    public let checksum: String
    public let nextOffset: Int64
    public let isComplete: Bool

    public init(attachmentID: UUID, checksum: String, nextOffset: Int64, isComplete: Bool) {
        self.attachmentID = attachmentID; self.checksum = checksum
        self.nextOffset = nextOffset; self.isComplete = isComplete
    }
}

public struct AttachmentTransfer: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let attachmentID: UUID
    public let peer: String
    public let direction: AttachmentTransferDirection
    public let state: AttachmentTransferState
    public let bytesConfirmed: Int64
    public let byteCount: Int64
    public let error: String?
    public let updatedAt: Date

    public init(id: UUID, attachmentID: UUID, peer: String,
                direction: AttachmentTransferDirection, state: AttachmentTransferState,
                bytesConfirmed: Int64, byteCount: Int64, error: String?, updatedAt: Date) {
        self.id = id; self.attachmentID = attachmentID; self.peer = peer
        self.direction = direction; self.state = state; self.bytesConfirmed = bytesConfirmed
        self.byteCount = byteCount; self.error = error; self.updatedAt = updatedAt
    }
}

/// Immutable metadata for one signed report version. Current/superseded state
/// is derived by comparing its frozen source fingerprint with current content.
public struct SignedReportVersion: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let matchID: UUID
    public let kind: ReportKind
    public let documentID: UUID?
    public let version: Int
    public let contentVersion: Int
    public let templateVersion: String
    public let signer: MatchParticipantSnapshot
    public let declaration: String
    public let signedAt: Date
    public let sourceFingerprint: String
    public let eventIDs: [UUID]
    public let validation: PostMatchValidationResult
    public let status: SignedReportStatus

    public init(id: UUID, matchID: UUID, kind: ReportKind, documentID: UUID? = nil,
                version: Int, contentVersion: Int,
                templateVersion: String, signer: MatchParticipantSnapshot, declaration: String,
                signedAt: Date, sourceFingerprint: String, eventIDs: [UUID],
                validation: PostMatchValidationResult, status: SignedReportStatus) {
        self.id = id; self.matchID = matchID; self.kind = kind; self.documentID = documentID; self.version = version
        self.contentVersion = contentVersion; self.templateVersion = templateVersion
        self.signer = signer; self.declaration = declaration; self.signedAt = signedAt
        self.sourceFingerprint = sourceFingerprint; self.eventIDs = eventIDs
        self.validation = validation; self.status = status
    }
}

/// One effective event row frozen to the event set used by a signed report.
public struct ReportExportEvent: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let sourceEventType: String
    public let effectiveEventType: String
    public let recordedAt: Date
    public let originalMatchClockMs: Int64?
    public let effectiveMatchClockMs: Int64?
    public let revisionOfEventID: UUID?
    public let payloadJSON: String

    public init(id: UUID, sourceEventType: String, effectiveEventType: String, recordedAt: Date,
                originalMatchClockMs: Int64?, effectiveMatchClockMs: Int64?,
                revisionOfEventID: UUID?, payloadJSON: String) {
        self.id = id; self.sourceEventType = sourceEventType; self.effectiveEventType = effectiveEventType
        self.recordedAt = recordedAt; self.originalMatchClockMs = originalMatchClockMs
        self.effectiveMatchClockMs = effectiveMatchClockMs; self.revisionOfEventID = revisionOfEventID
        self.payloadJSON = payloadJSON
    }
}

/// Complete immutable input for rendering a historical or current signed report.
public struct SignedReportExportSnapshot: Codable, Equatable, Sendable {
    public let report: SignedReportVersion
    public let fixture: MatchFixture
    public let participants: [MatchParticipantSnapshot]
    public let rules: MatchRuleSnapshot
    public let proseJSON: String
    public let events: [ReportExportEvent]
    public let attachments: [ReportAttachment]

    public init(report: SignedReportVersion, fixture: MatchFixture,
                participants: [MatchParticipantSnapshot], rules: MatchRuleSnapshot,
                proseJSON: String, events: [ReportExportEvent], attachments: [ReportAttachment] = []) {
        self.report = report; self.fixture = fixture; self.participants = participants
        self.rules = rules; self.proseJSON = proseJSON; self.events = events; self.attachments = attachments
    }
}

public struct ReportExportAudit: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let reportID: UUID
    public let format: ReportExportFormat
    public let filePath: String
    public let checksum: String
    public let statusLabel: String
    public let generatedAt: Date

    public init(id: UUID, reportID: UUID, format: ReportExportFormat, filePath: String,
                checksum: String, statusLabel: String, generatedAt: Date) {
        self.id = id; self.reportID = reportID; self.format = format; self.filePath = filePath
        self.checksum = checksum; self.statusLabel = statusLabel; self.generatedAt = generatedAt
    }
}

extension EventDraft: Equatable {
    public static func == (lhs: EventDraft, rhs: EventDraft) -> Bool { lhs.eventID == rhs.eventID }
}

enum EventIntegrity {
    static func hash(draft: EventDraft, deviceID: UUID, sequence: Int64, payload: String) -> String {
        // Field order is intentionally fixed and mirrors MVP_LOCAL_DATA_AND_PERSISTENCE.md.
        let object = "{\"eventId\":\"\(draft.eventID.uuidString.lowercased())\",\"matchId\":\"\(draft.matchID.uuidString.lowercased())\",\"eventType\":\(jsonString(draft.eventType)),\"schemaVersion\":\(draft.schemaVersion),\"originDeviceId\":\"\(deviceID.uuidString.lowercased())\",\"originSequence\":\(sequence),\"recordedAt\":\(jsonString(instant(draft.recordedAt))),\"matchPeriodId\":\(optionalUUID(draft.matchPeriodID)),\"matchClockMs\":\(optionalInt(draft.matchClockMs)),\"effectiveAt\":\(optionalDate(draft.effectiveAt)),\"supersedesEventId\":\(optionalUUID(draft.supersedesEventID)),\"payload\":\(payload)}"
        return SHA256.hash(data: Data(object.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func instant(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Dates are normalized at millisecond precision before persistence.
        return formatter.string(from: Date(timeIntervalSince1970: (date.timeIntervalSince1970 * 1000).rounded() / 1000))
    }
    private static func jsonString(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
    private static func optionalUUID(_ value: UUID?) -> String { value.map { "\"\($0.uuidString.lowercased())\"" } ?? "null" }
    private static func optionalInt(_ value: Int64?) -> String { value.map(String.init) ?? "null" }
    private static func optionalDate(_ value: Date?) -> String { value.map { jsonString(instant($0)) } ?? "null" }
}
