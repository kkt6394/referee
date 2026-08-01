import SwiftUI
import WatchConnectivity
import RefereeLedger
import PhotosUI
import UniformTypeIdentifiers
import UIKit

private extension Color {
    init(hex: String) {
        let value = UInt64(hex.dropFirst(hex.hasPrefix("#") ? 1 : 0), radix: 16) ?? 0x1565C0
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        var red: CGFloat = 0; var green: CGFloat = 0; var blue: CGFloat = 0; var alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

struct PlayerDraft: Identifiable, Equatable {
    let id: UUID
    var name: String
    var shirtNumber: Int

    init(id: UUID = UUID(), name: String = "", shirtNumber: Int = 1) {
        self.id = id; self.name = name; self.shirtNumber = shirtNumber
    }
}

private struct TeamKitPalette: Identifiable {
    let id: String
    let name: String
    let color: Color
    static let all: [TeamKitPalette] = [
        .init(id: "#D32F2F", name: "Red", color: .red), .init(id: "#F57C00", name: "Orange", color: .orange),
        .init(id: "#FBC02D", name: "Yellow", color: .yellow), .init(id: "#388E3C", name: "Green", color: .green),
        .init(id: "#00838F", name: "Teal", color: .teal), .init(id: "#1565C0", name: "Blue", color: .blue),
        .init(id: "#283593", name: "Navy", color: .indigo), .init(id: "#7B1FA2", name: "Purple", color: .purple),
        .init(id: "#C2185B", name: "Pink", color: .pink), .init(id: "#212121", name: "Black", color: .black)
    ]
}

@main
struct RefereePhoneApp: App {
    @StateObject private var match = PhoneMatchStore()
    @AppStorage("referee.app.language") private var languageCode = AppLanguage.korean.rawValue

    init() {
#if DEBUG
        if let rawValue = ProcessInfo.processInfo.environment["REFEREE_UI_TEST_LANGUAGE"],
           let language = AppLanguage(rawValue: rawValue) {
            AppLanguageStore(userDefaults: .standard).set(language)
        }
#endif
    }

    var body: some Scene {
        WindowGroup {
            PhoneRootView()
                .environmentObject(match)
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.refereeCopy, RefereeCopy(language: language))
        }
    }

    private var language: AppLanguage { AppLanguage(rawValue: languageCode) ?? .korean }
}

@MainActor
final class PhoneMatchStore: NSObject, ObservableObject, WCSessionDelegate {
    @Published var competition = "Friendly"
    @Published var venue = ""
    @Published var pitchLengthMetres = 105.0
    @Published var pitchWidthMetres = 68.0
    @Published var homeTeam = "Home"
    @Published var awayTeam = "Away"
    @Published var homeTeamColor = "#D32F2F"
    @Published var awayTeamColor = "#1565C0"
    @Published var scheduledAt = Date()
    @Published var extraTimeEnabled = false
    @Published var accountableReferee = ""
    @Published var homePlayers: [PlayerDraft] = [PlayerDraft()]
    @Published var awayPlayers: [PlayerDraft] = [PlayerDraft()]
    @Published var pitchChecked = false
    @Published var equipmentChecked = false
    @Published var crewChecked = false
    @Published var lineupChecked = false
    @Published var checklistNotes = ""
    @Published private(set) var matches: [MatchFixture] = []
    @Published private(set) var homeScore = 0
    @Published private(set) var awayScore = 0
    @Published private(set) var saveMessage: String?
    @Published private(set) var activePeriodID: UUID?
    @Published private(set) var periodLabel = "NOT STARTED"
    @Published private(set) var clockAnchor: Date?
    @Published private(set) var clockAnchorMs: Int64 = 0
    @Published private(set) var timeline: [MatchTimelineEntry] = []
    @Published private(set) var postMatchValidation: PostMatchValidationResult?
    @Published private(set) var reportDocuments: [ReportDocument] = []
    @Published private(set) var signedReportHistory: [ReportKind: [SignedReportVersion]] = [:]
    @Published private(set) var lastExportedFile: URL?
    @Published private(set) var lastExportedReportID: UUID?
    @Published private(set) var lastExportedFormat: ReportExportFormat?
    @Published private(set) var pendingSyncCount = 0
    @Published private(set) var isWatchReachable = false
    @Published private(set) var syncStatus = "Watch unavailable · saved locally"
    @Published private(set) var syncFailure: String?
    @Published private(set) var lastPeerSyncAt: Date?
    @Published private(set) var fieldReadiness: FieldReadiness?

    @Published private(set) var matchID: UUID = UUID()
    private var ledger: LedgerStore?
    private var accountableRefereeID = UUID()

    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    override init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Referee", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let databaseName = ProcessInfo.processInfo.environment["REFEREE_UI_TEST_DATABASE"]
            .map { "phone-ledger-\($0).sqlite" } ?? "phone-ledger.sqlite"
        let path = directory.appendingPathComponent(databaseName).path
        do {
            ledger = try LedgerStore(path: path, originDeviceID: UIDevice.current.identifierForVendor ?? UUID())
        } catch {
            ledger = nil
            saveMessage = "Local database is unavailable"
        }
        super.init()
        if let savedID = UserDefaults.standard.string(forKey: "activeMatchID").flatMap(UUID.init(uuidString:)),
           let ledger, let fixture = try? ledger.fixture(matchID: savedID) { matchID = savedID; load(fixture, ledger: ledger) }
        reloadMatches()
        refreshProjection()
        session?.delegate = self
        session?.activate()
        refreshSyncState()
    }

    @discardableResult
    func saveFixture() -> Bool {
        do {
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            try saveFixtureCore(using: ledger)
            try ledger.saveParticipants(participantDrafts(includeEmpty: true), matchID: matchID)
            try saveChecklist(using: ledger)
            finishFixtureSave()
            saveMessage = "Fixture saved locally"
            return true
        } catch {
            saveMessage = "Could not save fixture: \(error.localizedDescription)"
            return false
        }
    }

    /// Saves the minimum fixture and any valid preparation entered so far.
    /// Incomplete preparation remains visible after relaunch and does not block
    /// opening match control.
    @discardableResult
    func saveFixtureDraft() -> Bool {
        do {
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            try saveFixtureCore(using: ledger)
            try ledger.saveParticipantDrafts(participantDrafts(includeEmpty: false), matchID: matchID)
            try saveChecklist(using: ledger)
            finishFixtureSave()
            saveMessage = "Match draft saved locally"
            return true
        } catch {
            saveMessage = "Could not save match draft: \(error.localizedDescription)"
            return false
        }
    }

    var fixtureDetailsValid: Bool {
        !competition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !homeTeam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !awayTeam.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        homeTeam.trimmingCharacters(in: .whitespacesAndNewlines) != awayTeam.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var pitchSetupValid: Bool { (90...120).contains(pitchLengthMetres) && (45...90).contains(pitchWidthMetres) }

    var participantSetupComplete: Bool {
        let home = homePlayers.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let away = awayPlayers.filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return !accountableReferee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !home.isEmpty && !away.isEmpty &&
            (home + away).allSatisfy { (1...99).contains($0.shirtNumber) } &&
            Set(home.map(\.shirtNumber)).count == home.count && Set(away.map(\.shirtNumber)).count == away.count
    }

    var checklist: PreMatchChecklist {
        PreMatchChecklist(pitchChecked: pitchChecked, equipmentChecked: equipmentChecked,
                          crewChecked: crewChecked, lineupChecked: lineupChecked, notes: checklistNotes)
    }

    private func saveFixtureCore(using ledger: LedgerStore) throws {
        try ledger.saveFixture(MatchFixture(matchID: matchID, competition: competition.trimmingCharacters(in: .whitespacesAndNewlines),
                                            scheduledAt: scheduledAt, venueName: venue.trimmingCharacters(in: .whitespacesAndNewlines),
                                            homeTeamName: homeTeam.trimmingCharacters(in: .whitespacesAndNewlines),
                                            awayTeamName: awayTeam.trimmingCharacters(in: .whitespacesAndNewlines),
                                            homeTeamColor: homeTeamColor, awayTeamColor: awayTeamColor))
        try ledger.saveRules(MatchRuleSnapshot(extraTimeEnabled: extraTimeEnabled), matchID: matchID)
        try ledger.savePitchDimensions(PitchDimensions(lengthMetres: pitchLengthMetres,
                                                       widthMetres: pitchWidthMetres), matchID: matchID)
    }

    private func participantDrafts(includeEmpty: Bool) -> [MatchParticipantSnapshot] {
        let home = homePlayers.filter { includeEmpty || !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map {
            MatchParticipantSnapshot(id: $0.id, teamSide: "home", role: "player",
                                     displayName: $0.name, shirtNumber: $0.shirtNumber)
        }
        let away = awayPlayers.filter { includeEmpty || !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map {
            MatchParticipantSnapshot(id: $0.id, teamSide: "away", role: "player",
                                     displayName: $0.name, shirtNumber: $0.shirtNumber)
        }
        let referee = accountableReferee.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? [] :
            [MatchParticipantSnapshot(id: accountableRefereeID, role: "accountable_referee", displayName: accountableReferee)]
        return home + away + referee
    }

    private func saveChecklist(using ledger: LedgerStore) throws {
        try ledger.savePreMatchChecklist(checklist, matchID: matchID)
    }

    private func finishFixtureSave() {
        UserDefaults.standard.set(matchID.uuidString, forKey: "activeMatchID")
        reloadMatches(); refreshProjection(); refreshFieldReadiness(); publishMatchPackage()
    }

    func refreshFieldReadiness() {
        fieldReadiness = try? ledger?.fieldReadiness(matchID: matchID)
    }

    func createMatch() {
        matchID = UUID(); competition = "Friendly"; venue = ""; homeTeam = ""; awayTeam = ""
        homeTeamColor = "#D32F2F"; awayTeamColor = "#1565C0"
        pitchLengthMetres = 105; pitchWidthMetres = 68
        scheduledAt = Date(); extraTimeEnabled = false; homeScore = 0; awayScore = 0
        accountableReferee = ""; accountableRefereeID = UUID(); homePlayers = [PlayerDraft()]; awayPlayers = [PlayerDraft()]
        pitchChecked = false; equipmentChecked = false; crewChecked = false; lineupChecked = false; checklistNotes = ""
        activePeriodID = nil; periodLabel = "NOT STARTED"; clockAnchor = nil; clockAnchorMs = 0
        timeline = []
        postMatchValidation = nil; reportDocuments = []; signedReportHistory = [:]
        lastExportedFile = nil; lastExportedReportID = nil; lastExportedFormat = nil
        pendingSyncCount = 0; syncFailure = nil; lastPeerSyncAt = nil
        saveMessage = nil
#if DEBUG
        if ProcessInfo.processInfo.environment["REFEREE_UI_TEST_SEED"] == "fixture" {
            competition = "KFA UI League"; venue = "Acceptance Ground"
            homeTeam = "Seoul"; awayTeam = "Busan"; accountableReferee = "Referee Kim"
            homePlayers = [PlayerDraft(name: "Home 9", shirtNumber: 9)]
            awayPlayers = [PlayerDraft(name: "Away 10", shirtNumber: 10)]
        }
#endif
    }

    func resumeMatch(_ fixture: MatchFixture) {
        guard let ledger else { return }
        matchID = fixture.matchID; load(fixture, ledger: ledger)
        UserDefaults.standard.set(matchID.uuidString, forKey: "activeMatchID")
        refreshProjection(); refreshFieldReadiness(); publishMatchPackage(); synchronize()
    }

    private func reloadMatches() { matches = (try? ledger?.fixtures()) ?? [] }
    private func load(_ fixture: MatchFixture, ledger: LedgerStore) {
        competition = fixture.competition; scheduledAt = fixture.scheduledAt; venue = fixture.venueName
        homeTeam = fixture.homeTeamName; awayTeam = fixture.awayTeamName
        homeTeamColor = fixture.homeTeamColor ?? "#D32F2F"
        awayTeamColor = fixture.awayTeamColor ?? "#1565C0"
        extraTimeEnabled = (try? ledger.rules(matchID: fixture.matchID).extraTimeEnabled) ?? false
        let pitch = try? ledger.pitchDimensions(matchID: fixture.matchID)
        pitchLengthMetres = pitch?.lengthMetres ?? 105
        pitchWidthMetres = pitch?.widthMetres ?? 68
        let snapshots = (try? ledger.participants(matchID: fixture.matchID)) ?? []
        if let referee = snapshots.first(where: { $0.role == "accountable_referee" }) {
            accountableRefereeID = referee.id; accountableReferee = referee.displayName
        } else { accountableRefereeID = UUID(); accountableReferee = "" }
        homePlayers = snapshots.filter { $0.role == "player" && $0.teamSide == "home" }
            .map { PlayerDraft(id: $0.id, name: $0.displayName, shirtNumber: $0.shirtNumber ?? 1) }
        awayPlayers = snapshots.filter { $0.role == "player" && $0.teamSide == "away" }
            .map { PlayerDraft(id: $0.id, name: $0.displayName, shirtNumber: $0.shirtNumber ?? 1) }
        if homePlayers.isEmpty { homePlayers = [PlayerDraft()] }
        if awayPlayers.isEmpty { awayPlayers = [PlayerDraft()] }
        let checklist = (try? ledger.preMatchChecklist(matchID: fixture.matchID)) ?? PreMatchChecklist()
        pitchChecked = checklist.pitchChecked; equipmentChecked = checklist.equipmentChecked
        crewChecked = checklist.crewChecked; lineupChecked = checklist.lineupChecked; checklistNotes = checklist.notes
    }

    func roster(for side: String) -> [MatchParticipantSnapshot] {
        let drafts = side == "home" ? homePlayers : awayPlayers
        return drafts.map { MatchParticipantSnapshot(id: $0.id, teamSide: side, role: "player",
                                                       displayName: $0.name, shirtNumber: $0.shirtNumber) }
    }

    func addPlayer(to side: String) {
        if side == "home" { homePlayers.append(PlayerDraft(shirtNumber: nextNumber(homePlayers))) }
        else { awayPlayers.append(PlayerDraft(shirtNumber: nextNumber(awayPlayers))) }
    }

    func removePlayers(at offsets: IndexSet, from side: String) {
        if side == "home" { homePlayers.remove(atOffsets: offsets) }
        else { awayPlayers.remove(atOffsets: offsets) }
    }

    private func nextNumber(_ players: [PlayerDraft]) -> Int { min(99, (players.map(\.shirtNumber).max() ?? 0) + 1) }

    func completeDetails(for entry: MatchTimelineEntry, playerID: UUID, disciplinaryReason: String?,
                         incidentNarrative: String?, locationRequired: Bool = false) {
        do {
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            _ = try ledger.completeEventDetails(eventID: entry.eventID,
                                                completion: EventDetailCompletion(participantID: playerID,
                                                                                  disciplinaryReason: disciplinaryReason,
                                                                                  incidentNarrative: incidentNarrative,
                                                                                  locationRequired: locationRequired),
                                                peers: ["watch"])
            refreshProjection(); saveMessage = "Event details completed"; synchronize()
        } catch { saveMessage = "Could not complete details: \(error.localizedDescription)" }
    }

    func addLocation(to entry: MatchTimelineEntry, normalizedX: Double, normalizedY: Double,
                     accuracy: LocationAccuracy) -> Bool {
        do {
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            _ = try ledger.addLocation(to: entry.eventID, normalizedX: normalizedX, normalizedY: normalizedY,
                                       captureMethod: .pitchTap, accuracy: accuracy, peers: ["watch"])
            refreshProjection(); saveMessage = "Pitch location appended"; synchronize()
            return true
        } catch {
            saveMessage = "Could not add location: \(error.localizedDescription)"
            return false
        }
    }

    func recordGoal(for side: String, matchClockMs: Int64) {
        record(type: "goal_recorded", payloadJSON: #"{"teamSide":"\#(side)"}"#, matchClockMs: matchClockMs, message: "Goal saved locally")
    }

    func recordFoul(for side: String, matchClockMs: Int64) {
        record(type: "foul_recorded", payloadJSON: #"{"teamSide":"\#(side)"}"#, matchClockMs: matchClockMs, message: "Foul saved locally")
    }

    func recordCard(for side: String, colour: String, matchClockMs: Int64) {
        let directRed = colour == "red"
        record(type: "card_recorded", payloadJSON: "{\"colour\":\"\(colour)\",\"isDirectRed\":\(directRed),\"teamSide\":\"\(side)\"}", matchClockMs: matchClockMs, message: "\(colour.capitalized) card saved locally")
    }

    func recordStoppage(cause: String, matchClockMs: Int64) {
        record(type: "stoppage_time_recorded", payloadJSON: #"{"cause":"\#(cause)"}"#, matchClockMs: matchClockMs, message: "Added-time marker saved")
    }

    func recordSubstitution(for side: String, playerOut: UUID, playerIn: UUID, matchClockMs: Int64) {
        let roster = roster(for: side)
        guard let outgoing = roster.first(where: { $0.id == playerOut }),
              let incoming = roster.first(where: { $0.id == playerIn }), outgoing.id != incoming.id else {
            saveMessage = "Choose two distinct roster players"; return
        }
        var payload: [String: Any] = ["teamSide": side,
            "playerOutId": outgoing.id.uuidString.lowercased(), "playerOutDisplayName": outgoing.displayName,
            "playerInId": incoming.id.uuidString.lowercased(), "playerInDisplayName": incoming.displayName,
        ]
        if let number = outgoing.shirtNumber { payload["playerOutShirtNumber"] = number }
        if let number = incoming.shirtNumber { payload["playerInShirtNumber"] = number }
        recordAction(.substitution, payload: payload, matchClockMs: matchClockMs,
                     message: "Substitution saved locally")
    }

    func recordPenalty(for side: String, outcome: PenaltyOutcome, phase: PenaltyPhase = .match, matchClockMs: Int64) {
        recordAction(.penalty, payload: ["teamSide": side, "outcome": outcome.rawValue, "phase": phase.rawValue],
                     matchClockMs: matchClockMs, message: "Penalty saved locally")
    }

    func recordInjury(for side: String?, matchClockMs: Int64) {
        var payload: [String: Any] = [:]; if let side { payload["teamSide"] = side }
        recordAction(.injury, payload: payload, matchClockMs: matchClockMs, message: "Injury saved locally")
    }

    func recordVAR(type: VARReviewType, outcome: VAROutcome = .pending, matchClockMs: Int64) {
        recordAction(.varReview, payload: ["reviewType": type.rawValue, "outcome": outcome.rawValue],
                     matchClockMs: matchClockMs, message: "VAR review saved locally")
    }

    func recordSuspension(state: SuspensionState, reason: String, matchClockMs: Int64) {
        recordAction(.suspension, payload: ["state": state.rawValue, "reason": reason],
                     matchClockMs: matchClockMs, message: "Suspension state saved locally")
    }

    func recordRestart(type: RestartType, side: String? = nil, matchClockMs: Int64) {
        var payload: [String: Any] = ["restartType": type.rawValue]; if let side { payload["teamSide"] = side }
        recordAction(.restart, payload: payload, matchClockMs: matchClockMs, message: "Restart saved locally")
    }

    func completeMatchAction(_ entry: MatchTimelineEntry, primary: UUID? = nil,
                             secondary: UUID? = nil, outcome: String? = nil) {
        do {
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            _ = try ledger.completeMatchAction(eventID: entry.eventID, primaryParticipantID: primary,
                                               secondaryParticipantID: secondary, outcome: outcome,
                                               peers: ["watch"])
            refreshProjection(); saveMessage = "Match action details completed"; synchronize()
        } catch { saveMessage = "Could not complete action: \(error.localizedDescription)" }
    }

    func reverse(_ entry: MatchTimelineEntry, reason: String) {
        saveRevision(entry: entry, type: "event_reversed", payload: ["reason": reason], message: "Event reversed")
    }

    func correct(_ entry: MatchTimelineEntry, teamSide: String, colour: String?, reason: String) {
        guard var replacement = Self.payloadObject(entry.payloadJSON) else {
            saveMessage = "Could not read the original event"; return
        }
        replacement["teamSide"] = teamSide
        if entry.eventType == "card_recorded", let colour {
            replacement["colour"] = colour
            replacement["isDirectRed"] = colour == "red"
        }
        saveRevision(entry: entry, type: "event_corrected",
                     payload: ["reason": reason, "replacementEventType": entry.eventType,
                               "replacementPayload": replacement], message: "Event corrected")
    }

    private func saveRevision(entry: MatchTimelineEntry, type: String, payload: [String: Any], message: String) {
        do {
            guard entry.canRevise else { throw LedgerError.invalidDraft("only active match actions can be revised") }
            guard !((payload["reason"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw LedgerError.invalidDraft("a revision reason is required")
            }
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            guard let payloadJSON = String(data: data, encoding: .utf8) else { throw LedgerError.invalidDraft("invalid revision payload") }
            _ = try ledger.create(EventDraft(matchID: matchID, eventType: type,
                                             matchPeriodID: entry.matchPeriodID, matchClockMs: entry.matchClockMs,
                                             supersedesEventID: entry.eventID, payloadJSON: payloadJSON), peers: ["watch"])
            refreshProjection()
            saveMessage = message
            synchronize()
        } catch {
            saveMessage = "Could not revise event: \(error.localizedDescription)"
        }
    }

    private static func payloadObject(_ payloadJSON: String) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: Data(payloadJSON.utf8)) as? [String: Any]
    }

    private func recordAction(_ type: MatchActionType, payload: [String: Any], matchClockMs: Int64, message: String) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            saveMessage = "Could not encode match action"; return
        }
        record(type: type.rawValue, payloadJSON: json, matchClockMs: matchClockMs, message: message)
    }

    private func record(type: String, payloadJSON: String, matchClockMs: Int64, message: String) {
        do {
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            _ = try ledger.create(
                EventDraft(matchID: matchID, eventType: type, matchPeriodID: activePeriodID, matchClockMs: matchClockMs,
                           payloadJSON: payloadJSON),
                peers: ["watch"]
            )
            refreshProjection()
            saveMessage = message
            synchronize()
        } catch {
            saveMessage = "Could not save event: \(error.localizedDescription)"
        }
    }

    func elapsed(at date: Date) -> Int64 {
        guard let clockAnchor else { return clockAnchorMs }
        return clockAnchorMs + max(0, Int64(date.timeIntervalSince(clockAnchor) * 1_000))
    }

    func startNextPeriod() {
        guard activePeriodID == nil else { return }
        do {
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            guard let definition = try ledger.periodState(matchID: matchID).next else {
                saveMessage = "Match is already complete"; return
            }
            let periodID = UUID()
            _ = try ledger.create(
                EventDraft(matchID: matchID, eventType: "period_started", matchPeriodID: periodID,
                           matchClockMs: 0, payloadJSON: "{\"ordinal\":\(definition.ordinal),\"periodKind\":\"\(definition.kind)\"}"),
                peers: ["watch"]
            )
            refreshProjection()
            saveMessage = "\(definition.label.capitalized) started"
            synchronize()
        } catch {
            saveMessage = "Could not start first half: \(error.localizedDescription)"
        }
    }

    func endCurrentPeriod(at date: Date) {
        guard let activePeriodID else { return }
        let elapsed = elapsed(at: date)
        do {
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            guard let active = try ledger.periodState(matchID: matchID).active else { return }
            _ = try ledger.create(
                EventDraft(matchID: matchID, eventType: "period_ended", matchPeriodID: activePeriodID,
                           matchClockMs: elapsed,
                           payloadJSON: "{\"finalClockMs\":\(elapsed),\"ordinal\":\(active.definition.ordinal),\"periodKind\":\"\(active.definition.kind)\"}"),
                peers: ["watch"]
            )
            refreshProjection()
            saveMessage = "\(active.definition.label.capitalized) ended"
            synchronize()
        } catch {
            saveMessage = "Could not end period: \(error.localizedDescription)"
        }
    }

    func refreshPostMatchReview(confirmedScore: ConfirmedScore?) {
        do {
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            postMatchValidation = try ledger.validatePostMatch(matchID: matchID, confirmedScore: confirmedScore)
            reportDocuments = try ledger.reportDocuments(matchID: matchID)
            signedReportHistory = try Dictionary(uniqueKeysWithValues: ReportKind.allCases.map {
                ($0, try ledger.signedReports(matchID: matchID, kind: $0))
            })
        } catch {
            postMatchValidation = nil
            saveMessage = "Could not review report: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func saveReportContent(documentID: UUID, content: StructuredReportContent,
                           confirmedScore: ConfirmedScore?) -> Bool {
        do {
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            let version = try ledger.saveReportContent(documentID: documentID, content: content)
            refreshPostMatchReview(confirmedScore: confirmedScore)
            saveMessage = "Report content version \(version) saved"
            return true
        } catch {
            saveMessage = "Could not save report content: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func signReport(kind: ReportKind, documentID: UUID, confirmedScore: ConfirmedScore, declaration: String) -> Bool {
        do {
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            let signed = try ledger.signReport(matchID: matchID, kind: kind, documentID: documentID,
                                               confirmedScore: confirmedScore,
                                               declaration: declaration,
                                               peers: ["watch"])
            refreshProjection()
            refreshPostMatchReview(confirmedScore: confirmedScore)
            saveMessage = "\(kind.displayName) version \(signed.version) signed"
            synchronize()
            return true
        } catch {
            saveMessage = "Could not sign report: \(error.localizedDescription)"
            refreshPostMatchReview(confirmedScore: confirmedScore)
            return false
        }
    }

    func exportReport(_ version: SignedReportVersion, format: ReportExportFormat) {
        do {
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            let snapshot = try ledger.exportSnapshot(reportID: version.id)
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Referee/Exports", isDirectory: true)
            let result = try SignedReportFileExporter.export(snapshot, format: format, directory: directory)
            do {
                _ = try ledger.recordExport(reportID: version.id, format: format,
                                            filePath: result.url.path, checksum: result.checksum,
                                            generatedAt: result.generatedAt)
            } catch {
                try? FileManager.default.removeItem(at: result.url)
                throw error
            }
            lastExportedFile = result.url; lastExportedReportID = version.id; lastExportedFormat = format
            saveMessage = "\(format.rawValue.uppercased()) export ready to share"
        } catch {
            lastExportedFile = nil; lastExportedReportID = nil; lastExportedFormat = nil
            saveMessage = "Could not export report: \(error.localizedDescription)"
        }
    }

    func attachments(documentID: UUID) -> [ReportAttachment] {
        (try? ledger?.attachments(documentID: documentID)) ?? []
    }

    func attachmentTransfers(documentID: UUID) -> [AttachmentTransfer] {
        (try? ledger?.attachmentTransfers(documentID: documentID)) ?? []
    }

    @discardableResult
    func addAttachment(documentID: UUID, data: Data, mediaType: String,
                       filename: String, required: Bool) -> Bool {
        do {
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            _ = try ledger.addAttachment(documentID: documentID, data: data, mediaType: mediaType,
                                         originalFilename: filename, isRequired: required)
            refreshPostMatchReview(confirmedScore: postMatchValidation?.confirmedScore)
            saveMessage = "Attachment stored and checksum verified"
            return true
        } catch {
            saveMessage = "Could not store attachment: \(error.localizedDescription)"
            return false
        }
    }

    func addAttachment(documentID: UUID, url: URL, required: Bool) -> Bool {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier)
                ?? "application/octet-stream"
            return addAttachment(documentID: documentID, data: data, mediaType: type,
                                 filename: url.lastPathComponent, required: required)
        } catch {
            saveMessage = "Could not read attachment: \(error.localizedDescription)"
            return false
        }
    }

    private func publishMatchPackage() {
        guard let ledger, let package = try? ledger.matchPackage(matchID: matchID), let data = try? JSONEncoder().encode(package) else { return }
        try? session?.updateApplicationContext([
            "referee.matchPackage": data,
            "referee.app.language": AppLanguageStore(userDefaults: .standard).language.rawValue
        ])
        send(kind: "package", payload: data)
    }

    func updateAppLanguage(_ language: AppLanguage) {
        AppLanguageStore(userDefaults: .standard).set(language)
        publishMatchPackage()
    }

    func retrySynchronization() {
        syncFailure = nil
        publishMatchPackage()
        synchronize()
    }

    private func synchronize() {
        refreshSyncState()
        guard let ledger, let watermark = try? ledger.syncWatermark(matchID: matchID), let data = try? JSONEncoder().encode(watermark) else {
            noteSyncFailure("Could not read the local sync queue")
            return
        }
        syncStatus = isWatchReachable ? "Reconciling with Watch" : queuedSyncStatus
        send(kind: "watermark", payload: data)
        sendPendingEvents()
    }

    private func sendPendingEvents() {
        guard let ledger, let events = try? ledger.pendingOutboxEvents(matchID: matchID, peer: "watch") else {
            noteSyncFailure("Could not read pending Watch events")
            return
        }
        for event in events {
            if let data = try? JSONEncoder().encode(event) { send(kind: "event", payload: data) }
        }
        refreshSyncState()
    }

    private func send(kind: String, payload: Data) {
        guard let session, let data = try? JSONEncoder().encode(WatchTransportMessage(kind: kind, senderDeviceID: ledger?.originDeviceID ?? UUID(), payload: payload)) else { return }
        // transferUserInfo survives a disconnect. The immediate copy only reduces latency;
        // duplicate delivery is safe because LedgerStore receipts are idempotent.
        session.transferUserInfo(["referee.sync": data])
        if session.isReachable {
            session.sendMessage(["referee.sync": data], replyHandler: nil) { [weak self] error in
                Task { @MainActor in self?.noteSyncFailure("Immediate Watch delivery failed: \(error.localizedDescription)") }
            }
        }
    }

    private func receiveTransport(_ data: Data) {
        guard let message = try? JSONDecoder().decode(WatchTransportMessage.self, from: data), let ledger else { return }
        lastPeerSyncAt = Date()
        syncFailure = nil
        switch message.kind {
        case "watermark":
            guard let watermark = try? JSONDecoder().decode(SyncWatermark.self, from: message.payload), watermark.matchID == matchID,
                  let missing = try? ledger.eventsMissing(from: watermark.originWatermarks, matchID: matchID) else { return }
            for event in missing { if let data = try? JSONEncoder().encode(event) { send(kind: "event", payload: data) } }
            sendPendingEvents()
            if missing.isEmpty, let local = try? ledger.syncWatermark(matchID: matchID), local.eventDigest == watermark.eventDigest {
                syncStatus = "Watch is up to date"
            }
        case "event":
            guard let event = try? JSONDecoder().decode(ReplicatedEvent.self, from: message.payload) else { return }
            let result = try? ledger.receive(event, messageID: message.messageID, from: message.senderDeviceID)
            guard result == .committed || result == .alreadyCommitted else { return }
            let acknowledgement = EventAcknowledgement(matchID: event.event.draft.matchID, eventID: event.event.draft.eventID, integrityHash: event.event.integrityHash)
            if let data = try? JSONEncoder().encode(acknowledgement) { send(kind: "ack", payload: data) }
            refreshProjection()
            synchronize()
        case "ack":
            guard let acknowledgement = try? JSONDecoder().decode(EventAcknowledgement.self, from: message.payload) else { return }
            try? ledger.acknowledge(eventID: acknowledgement.eventID, integrityHash: acknowledgement.integrityHash, peer: "watch")
            refreshSyncState()
            if pendingSyncCount == 0 { syncStatus = "Watch is up to date" }
        default: break
        }
    }

    private var queuedSyncStatus: String {
        pendingSyncCount == 0 ? "Saved locally · Watch offline" : "\(pendingSyncCount) event\(pendingSyncCount == 1 ? "" : "s") queued safely"
    }

    private func refreshSyncState() {
        isWatchReachable = session?.isReachable ?? false
        pendingSyncCount = (try? ledger?.pendingOutboxCount(matchID: matchID, peer: "watch")) ?? 0
        guard syncFailure == nil else { syncStatus = "Sync needs attention · events remain local"; return }
        if isWatchReachable {
            syncStatus = pendingSyncCount == 0 ? "Watch connected" : "Syncing \(pendingSyncCount) queued event\(pendingSyncCount == 1 ? "" : "s")"
        } else {
            syncStatus = queuedSyncStatus
        }
    }

    private func noteSyncFailure(_ message: String) {
        syncFailure = message
        refreshSyncState()
    }

    private func refreshProjection() {
        guard let ledger, let projection = try? ledger.rebuildProjection(matchID: matchID) else { return }
        homeScore = projection.homeScore; awayScore = projection.awayScore
        timeline = (try? ledger.timeline(matchID: matchID)) ?? []
        refreshClockContext()
        // A Watch-created period boundary becomes the next durable package context.
        publishMatchPackage()
    }

    private func refreshClockContext() {
        guard let ledger else { return }
        guard let state = try? ledger.periodState(matchID: matchID), let context = state.active else {
            activePeriodID = nil
            periodLabel = (try? ledger.periodState(matchID: matchID).displayLabel) ?? "NOT STARTED"
            clockAnchor = nil
            clockAnchorMs = 0
            return
        }
        activePeriodID = context.periodID
        periodLabel = context.label
        clockAnchor = context.startedAt
        clockAnchorMs = context.startClockMs
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error { self.noteSyncFailure("Watch session activation failed: \(error.localizedDescription)"); return }
            guard activationState == .activated else { self.noteSyncFailure("Watch session is not active"); return }
            self.publishMatchPackage(); self.synchronize()
        }
    }
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated func sessionDidDeactivate(_ session: WCSession) { session.activate() }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.syncFailure = nil
            self.refreshSyncState()
            if reachable { self.publishMatchPackage(); self.synchronize() }
        }
    }
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshSyncState() }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) { if let data = message["referee.sync"] as? Data { Task { @MainActor in self.receiveTransport(data) } } }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) { if let data = userInfo["referee.sync"] as? Data { Task { @MainActor in self.receiveTransport(data) } } }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) { if let data = applicationContext["referee.matchPackage"] as? Data { Task { @MainActor in self.receiveTransportPackage(data) } } }

    private func receiveTransportPackage(_ data: Data) {
        // The phone owns fixtures; context is accepted only as a harmless reconnect hint.
        if let package = try? JSONDecoder().decode(MatchPackage.self, from: data), package.fixture.matchID == matchID { synchronize() }
    }
}

private struct WatchTransportMessage: Codable {
    let kind: String
    let senderDeviceID: UUID
    let messageID: UUID
    let payload: Data
    init(kind: String, senderDeviceID: UUID, messageID: UUID = UUID(), payload: Data) { self.kind = kind; self.senderDeviceID = senderDeviceID; self.messageID = messageID; self.payload = payload }
}

struct PhoneRootView: View {
    @EnvironmentObject private var match: PhoneMatchStore
    @Environment(\.refereeCopy) private var copy
    @AppStorage("referee.app.language") private var languageCode = AppLanguage.korean.rawValue
    @State private var showingCreate = false
    @State private var showingControl = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(copy.createMatch, systemImage: "plus.circle.fill") {
                        match.createMatch()
                        showingCreate = true
                    }
                    .accessibilityIdentifier("matches.create")
                }
                Section(copy.resumeMatch) {
                    if match.matches.isEmpty {
                        Text(copy.noSavedMatches).foregroundStyle(.secondary)
                    }
                    ForEach(match.matches, id: \.matchID) { fixture in
                        Button {
                            match.resumeMatch(fixture)
                            showingControl = true
                        } label: {
                            VStack(alignment: .leading) {
                                Text("\(fixture.homeTeamName) vs \(fixture.awayTeamName)").font(.headline)
                                Text("\(fixture.competition) · \(fixture.scheduledAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section(copy.settings) {
                    Menu {
                        Button(copy.korean) { select(.korean) }
                        Button(copy.english) { select(.english) }
                    } label: {
                        HStack {
                            Label(copy.languageLabel, systemImage: "globe")
                            Spacer()
                            Text(copy.selectedLanguageName).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("settings.language")
                }
            }
            .navigationTitle(copy.matches)
            .navigationDestination(isPresented: $showingCreate) { PhoneFixtureView() }
            .navigationDestination(isPresented: $showingControl) { PhoneMatchControlView() }
        }
    }

    private func select(_ language: AppLanguage) {
        match.updateAppLanguage(language)
        languageCode = language.rawValue
    }
}

private struct PhoneFixtureView: View {
    @EnvironmentObject private var match: PhoneMatchStore
    @Environment(\.refereeCopy) private var copy
    @State private var showingControl = false
    @State private var showingSetup = false

    var body: some View {
        Form {
            Section(copy.fixture) {
                TextField(copy.competition, text: $match.competition)
                    .accessibilityIdentifier("fixture.competition")
                DatePicker(copy.kickOff, selection: $match.scheduledAt)
                TextField(copy.venue, text: $match.venue)
                    .accessibilityIdentifier("fixture.venue")
                TextField(copy.homeTeam, text: $match.homeTeam)
                    .accessibilityIdentifier("fixture.homeTeam")
                TextField(copy.awayTeam, text: $match.awayTeam)
                    .accessibilityIdentifier("fixture.awayTeam")
            }
            Section {
                Text(copy.fixtureGuidance)
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section {
                Button(copy.createMatch) {
                    if match.participantSetupComplete {
                        if match.saveFixture() { showingControl = true }
                    } else if match.saveFixtureDraft() {
                        showingSetup = true
                    }
                }
                    .disabled(!match.fixtureDetailsValid)
                    .accessibilityIdentifier("fixture.save")
            }
        }
        .navigationTitle(copy.createMatch)
        .navigationDestination(isPresented: $showingSetup) { PhoneMatchSetupView() }
        .navigationDestination(isPresented: $showingControl) { PhoneMatchControlView() }
    }
}

private struct PhoneMatchSetupView: View {
    @EnvironmentObject private var match: PhoneMatchStore
    @Environment(\.refereeCopy) private var copy
    @State private var showingControl = false

    var body: some View {
        List {
            Section(copy.preparation) {
                NavigationLink { PhoneSetupDetailsView() } label: {
                    setupRow(copy.crewAndTeams, complete: match.participantSetupComplete,
                             detail: match.participantSetupComplete ? copy.ready : copy.needsDetails)
                }
                NavigationLink { PhoneSetupDetailsView(startAtChecklist: true) } label: {
                    setupRow(copy.preMatchChecklist, complete: match.checklist.isComplete,
                             detail: copy.checkedCount(match.checklist.completedCount))
                }
                setupRow(copy.venueAndPitch, complete: match.pitchSetupValid,
                         detail: "\(match.pitchLengthMetres.formatted()) × \(match.pitchWidthMetres.formatted()) m")
                setupRow(copy.competitionRules, complete: true,
                         detail: match.extraTimeEnabled ? copy.extraTimeEnabled : copy.standardPeriods)
            }
            Section {
                if let readiness = match.fieldReadiness {
                    if !readiness.blocking.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(copy.completeBeforeStarting)
                                .font(.headline).foregroundStyle(.red)
                                .accessibilityIdentifier("setup.readiness.blocking")
                            ForEach(readiness.blocking) { issue in
                                Text("• \(copy.readinessIssueTitle(id: issue.id, fallback: issue.title))").font(.caption).foregroundStyle(.red)
                            }
                        }
                    }
                    if !readiness.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(copy.recommendedBeforeKickOff)
                                .font(.headline).foregroundStyle(.orange)
                                .accessibilityIdentifier("setup.readiness.warning")
                            ForEach(readiness.warnings) { issue in
                                Text("• \(copy.readinessIssueTitle(id: issue.id, fallback: issue.title))").font(.caption).foregroundStyle(.orange)
                            }
                        }
                    }
                }
                Text(copy.readinessGuidance)
                    .font(.callout).foregroundStyle(.secondary)
                Button(copy.savePreparation) { _ = match.saveFixtureDraft() }
                    .accessibilityIdentifier("setup.save")
                Button(copy.openMatchControl) {
                    if match.saveFixtureDraft() { showingControl = true }
                }
                .buttonStyle(.borderedProminent)
                .disabled(match.fieldReadiness?.canStartMatch == false)
                .accessibilityIdentifier("setup.openControl")
            }
            if let message = match.saveMessage { Text(copy.statusMessage(message)).font(.footnote).foregroundStyle(.secondary) }
        }
        .navigationTitle(copy.matchSetup)
        .navigationDestination(isPresented: $showingControl) { PhoneMatchControlView() }
    }

    private func setupRow(_ title: String, complete: Bool, detail: String) -> some View {
        HStack {
            Image(systemName: complete ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(complete ? Color.green : Color.orange)
            VStack(alignment: .leading) { Text(title); Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct PhoneSetupDetailsView: View {
    @EnvironmentObject private var match: PhoneMatchStore
    @Environment(\.refereeCopy) private var copy
    let startAtChecklist: Bool

    init(startAtChecklist: Bool = false) { self.startAtChecklist = startAtChecklist }

    var body: some View {
        Form {
            if !startAtChecklist {
                Section(copy.rules) { Toggle(copy.extraTime, isOn: $match.extraTimeEnabled) }
                Section(copy.teamKitColors) {
                    Picker(copy.homeKit, selection: $match.homeTeamColor) {
                        ForEach(TeamKitPalette.all) { option in
                            Label(copy.kitColorName(option.id), systemImage: "circle.fill").foregroundStyle(option.color).tag(option.id)
                        }
                    }
                    ColorPicker(copy.homeCustomColor, selection: customColorBinding(for: $match.homeTeamColor), supportsOpacity: false)
                    Picker(copy.awayKit, selection: $match.awayTeamColor) {
                        ForEach(TeamKitPalette.all) { option in
                            Label(copy.kitColorName(option.id), systemImage: "circle.fill").foregroundStyle(option.color).tag(option.id)
                        }
                    }
                    ColorPicker(copy.awayCustomColor, selection: customColorBinding(for: $match.awayTeamColor), supportsOpacity: false)
                }
                Section(copy.pitchDimensions) {
                    HStack {
                        TextField(copy.length, value: $match.pitchLengthMetres, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                        Text("m ×").foregroundStyle(.secondary)
                        TextField(copy.width, value: $match.pitchWidthMetres, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                        Text("m").foregroundStyle(.secondary)
                    }
                }
                Section(copy.accountableReferee) {
                    TextField(copy.fullName, text: $match.accountableReferee)
                        .accessibilityIdentifier("fixture.referee")
                }
                rosterSection(side: "home", title: match.homeTeam)
                rosterSection(side: "away", title: match.awayTeam)
            }
            Section(copy.preMatchChecklist) {
                Toggle(copy.pitchAndMarkings, isOn: $match.pitchChecked)
                Toggle(copy.matchBallsAndEquipment, isOn: $match.equipmentChecked)
                Toggle(copy.refereeCrewBriefing, isOn: $match.crewChecked)
                Toggle(copy.teamSheetsAndLineups, isOn: $match.lineupChecked)
                TextField(copy.operationalNotes, text: $match.checklistNotes, axis: .vertical)
                    .lineLimit(2...5)
            }
            Section {
                Button(copy.savePreparation) { _ = match.saveFixtureDraft() }
                    .disabled(!match.pitchSetupValid)
                    .accessibilityIdentifier("setup.details.save")
            }
        }
        .navigationTitle(startAtChecklist ? copy.checklist : copy.setupDetails)
    }

    @ViewBuilder
    private func rosterSection(side: String, title: String) -> some View {
        Section(copy.rosterTitle(side: side, team: title)) {
            let players = side == "home" ? $match.homePlayers : $match.awayPlayers
            ForEach(players) { $player in
                HStack {
                    TextField(copy.playerName, text: $player.name)
                        .accessibilityIdentifier("fixture.\(side)Player.\(player.id.uuidString)")
                    TextField(copy.shirtNumber, value: $player.shirtNumber, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 52)
                }
            }
            .onDelete { match.removePlayers(at: $0, from: side) }
            Button(copy.addPlayer(side: side), systemImage: "person.badge.plus") { match.addPlayer(to: side) }
        }
    }

    private func customColorBinding(for value: Binding<String>) -> Binding<Color> {
        Binding(get: { Color(hex: value.wrappedValue) }, set: { value.wrappedValue = $0.hexString })
    }
}

struct PhoneMatchControlView: View {
    @EnvironmentObject private var match: PhoneMatchStore
    @Environment(\.refereeCopy) private var copy
    @State private var showingMoreActions = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = match.elapsed(at: context.date)
            ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Label(copy.periodLabel(match.periodLabel), systemImage: match.activePeriodID == nil ? "pause.circle" : "record.circle")
                    Spacer()
                    Text(copy.localSave).font(.caption2.weight(.bold)).foregroundStyle(.green)
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: match.syncFailure != nil ? "exclamationmark.icloud" :
                            (match.pendingSyncCount == 0 ? "checkmark.icloud" : "arrow.triangle.2.circlepath.icloud"))
                        .foregroundStyle(match.syncFailure != nil ? Color.red : (match.pendingSyncCount == 0 ? Color.green : Color.orange))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(copy.syncStatus(peer: "Watch", reachable: match.isWatchReachable,
                                             pending: match.pendingSyncCount, failed: match.syncFailure != nil))
                            .font(.footnote.weight(.semibold))
                        if let failure = match.syncFailure {
                            Text(copy.statusMessage(failure)).font(.caption).foregroundStyle(.secondary)
                        } else if let synced = match.lastPeerSyncAt {
                            Text(copy.lastWatchContact(synced.formatted(date: .omitted, time: .shortened)))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if match.pendingSyncCount > 0 || match.syncFailure != nil {
                        Button(copy.retry) { match.retrySynchronization() }.font(.caption.weight(.semibold))
                    }
                }
                .padding(10).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text(clock(elapsed)).font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                HStack {
                    score(team: match.homeTeam, score: match.homeScore, color: Color(hex: match.homeTeamColor))
                    Text("–").font(.title)
                    score(team: match.awayTeam, score: match.awayScore, color: Color(hex: match.awayTeamColor))
                }
                .padding(14).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                if match.activePeriodID == nil {
                    Label(match.periodLabel == "FULL TIME" ? copy.matchComplete : copy.holdToStart(copy.periodLabel(match.periodLabel)), systemImage: "play.fill")
                        .font(.headline).padding().frame(maxWidth: .infinity)
                        .background(.tint, in: RoundedRectangle(cornerRadius: 18, style: .continuous)).foregroundStyle(.white)
                        .onLongPressGesture(minimumDuration: 1) { match.startNextPeriod() }
                        .disabled(match.periodLabel == "FULL TIME")
                        .accessibilityIdentifier("match.period.start")
                } else {
                    Text(copy.activeMatchGuidance)
                        .font(.caption).foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    quickAction(title: copy.goal, subtitle: match.homeTeam, icon: "soccerball", tint: .green) { match.recordGoal(for: "home", matchClockMs: elapsed) }
                    quickAction(title: copy.goal, subtitle: match.awayTeam, icon: "soccerball", tint: .green) { match.recordGoal(for: "away", matchClockMs: elapsed) }
                }
                .disabled(match.activePeriodID == nil)
                HStack(spacing: 12) {
                    quickAction(title: copy.foul, subtitle: match.homeTeam, icon: "figure.soccer", tint: .orange) { match.recordFoul(for: "home", matchClockMs: elapsed) }
                    quickAction(title: copy.foul, subtitle: match.awayTeam, icon: "figure.soccer", tint: .orange) { match.recordFoul(for: "away", matchClockMs: elapsed) }
                }
                .disabled(match.activePeriodID == nil)
                HStack(spacing: 12) {
                    Button { match.recordCard(for: "home", colour: "yellow", matchClockMs: elapsed) } label: { Label("\(copy.yellow) · \(match.homeTeam)", systemImage: "rectangle.fill").frame(maxWidth: .infinity) }
                    Button { match.recordCard(for: "away", colour: "yellow", matchClockMs: elapsed) } label: { Label("\(copy.yellow) · \(match.awayTeam)", systemImage: "rectangle.fill").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.bordered).tint(.yellow).disabled(match.activePeriodID == nil)
                Button { showingMoreActions = true } label: { Label(copy.moreMatchActions, systemImage: "ellipsis.circle").frame(maxWidth: .infinity) }
                    .buttonStyle(.bordered).disabled(match.activePeriodID == nil)
                NavigationLink {
                    PhoneTimelineView()
                } label: {
                    Label(copy.eventTimeline, systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("match.timeline")
                NavigationLink {
                    PhoneMatchSetupView()
                } label: {
                    Label(copy.matchSetup, systemImage: match.participantSetupComplete ? "checkmark.circle" : "exclamationmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("match.setup")
                NavigationLink {
                    PhonePostMatchReviewView()
                } label: {
                    Label(match.periodLabel == "FULL TIME" ? copy.reviewAndSignReports : copy.reportReadiness,
                          systemImage: "checkmark.seal")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("match.review")
                if match.activePeriodID != nil {
                    Label(copy.holdToEndPeriod, systemImage: "stop.fill")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                        .padding(.vertical, 10).frame(maxWidth: .infinity)
                        .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .onLongPressGesture(minimumDuration: 1) { match.endCurrentPeriod(at: context.date) }
                        .accessibilityIdentifier("match.period.end")
                }
                if let saveMessage = match.saveMessage {
                    Label(copy.statusMessage(saveMessage), systemImage: "checkmark.icloud")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .padding()
            }
            .navigationTitle(match.competition)
            .sheet(isPresented: $showingMoreActions) {
                MorePhoneActionsView(elapsed: elapsed).environmentObject(match)
                    .presentationDetents([.medium])
            }
        }
    }

    private func score(team: String, score: Int, color: Color) -> some View {
        VStack { Text(team).lineLimit(1).foregroundStyle(color); Text("\(score)").font(.system(size: 48, weight: .bold, design: .rounded)).foregroundStyle(color) }
            .frame(maxWidth: .infinity)
    }

    private func quickAction(title: String, subtitle: String, icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon).font(.title2.weight(.bold))
                Text(title).font(.caption.weight(.heavy))
                Text(subtitle).font(.headline).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading).padding(14)
            .foregroundStyle(.white).background(tint.gradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(subtitle)")
    }

    private func clock(_ milliseconds: Int64) -> String {
        return String(format: "%02lld:%02lld", milliseconds / 60_000, (milliseconds / 1_000) % 60)
    }
}

private extension ReportKind {
    var displayName: String {
        switch self {
        case .match: return "Match report"
        case .referee: return "Referee report"
        case .incident: return "Incident report"
        }
    }
}

private struct PhonePostMatchReviewView: View {
    @EnvironmentObject private var match: PhoneMatchStore
    @Environment(\.refereeCopy) private var copy
    @State private var reportKind: ReportKind = .match
    @State private var scoreConfirmed = false
    @State private var declarationAccepted = false
    @State private var showingSignConfirmation = false
    @State private var selectedDocumentID: UUID?
    @State private var summary = ""
    @State private var narrativeDescription = ""
    @State private var actionTaken = ""
    @State private var additionalNotes = ""
    @State private var showingFileImporter = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var attachmentIsRequired = false

    private var declaration: String { copy.declaration }

    private var confirmedScore: ConfirmedScore? {
        scoreConfirmed ? ConfirmedScore(home: match.homeScore, away: match.awayScore) : nil
    }

    private var validation: PostMatchValidationResult? { match.postMatchValidation }
    private var blockingIssues: [ReportValidationIssue] { validation?.blockingIssues ?? [] }
    private var warnings: [ReportValidationIssue] {
        validation?.issues.filter { $0.severity == .warning } ?? []
    }
    private var documents: [ReportDocument] { match.reportDocuments.filter { $0.kind == reportKind } }
    private var selectedDocument: ReportDocument? {
        documents.first { $0.id == selectedDocumentID } ?? documents.first
    }
    private var versions: [SignedReportVersion] {
        (match.signedReportHistory[reportKind] ?? []).filter { $0.documentID == selectedDocument?.id }
    }
    private var canSign: Bool {
        scoreConfirmed && declarationAccepted && validation?.canSign == true &&
        selectedDocument.map { match.attachments(documentID: $0.id).allSatisfy { !$0.isRequired || $0.isReadable } } == true
    }

    var body: some View {
        List {
            Section(copy.report) {
                Picker(copy.report, selection: $reportKind) {
                    ForEach(ReportKind.allCases, id: \.self) { kind in
                        Text(copy.reportKindName(kind.rawValue)).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                if reportKind == .incident {
                    if documents.isEmpty {
                        Text(copy.noQualifyingIncidents).foregroundStyle(.secondary)
                    } else {
                        Picker(copy.incident, selection: $selectedDocumentID) {
                            ForEach(documents) { document in
                                Text(copy.incidentReference(document.primaryEventID.map { String($0.uuidString.prefix(8)) } ?? copy.unknown))
                                    .tag(Optional(document.id))
                            }
                        }
                    }
                }
            }

            if let document = selectedDocument {
                Section {
                    TextField(copy.shortSummary, text: $summary)
                    TextField(reportKind == .incident ? copy.whatHappened : copy.description, text: $narrativeDescription, axis: .vertical)
                        .lineLimit(3...8)
                    TextField(copy.actionTaken, text: $actionTaken, axis: .vertical)
                        .lineLimit(2...6)
                    TextField(copy.additionalNotes, text: $additionalNotes, axis: .vertical)
                        .lineLimit(2...6)
                    Button(copy.saveNewContentVersion, systemImage: "square.and.arrow.down") {
                        let content = StructuredReportContent(summary: summary,
                                                              description: narrativeDescription,
                                                              actionTaken: actionTaken,
                                                              additionalNotes: additionalNotes)
                        _ = match.saveReportContent(documentID: document.id, content: content,
                                                    confirmedScore: confirmedScore)
                    }
                    Text(copy.currentContentVersion(document.contentVersion))
                        .font(.caption).foregroundStyle(.secondary)
                    if versions.contains(where: { $0.status == .superseded }) {
                        Label(copy.supersededContentGuidance,
                              systemImage: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if reportKind == .incident {
                        Text(copy.linkedSeriousEvents(document.linkedEventIDs.map { String($0.uuidString.prefix(8)) }.joined(separator: ", ")))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } header: { Text(copy.structuredNarrative) }

                Section {
                    Toggle(copy.requiredForSignOff, isOn: $attachmentIsRequired)
                    HStack {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(copy.addPhoto, systemImage: "photo.badge.plus")
                        }
                        Spacer()
                        Button { showingFileImporter = true } label: {
                            Label(copy.addFile, systemImage: "doc.badge.plus")
                        }
                    }
                    let attachments = match.attachments(documentID: document.id)
                    if attachments.isEmpty {
                        Text(copy.noAttachments).foregroundStyle(.secondary)
                    } else {
                        let transfers = match.attachmentTransfers(documentID: document.id)
                        ForEach(attachments) { attachment in
                            HStack(alignment: .top) {
                                Image(systemName: attachment.isReadable ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                                    .foregroundStyle(attachment.isReadable ? Color.green : .red)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(attachment.originalFilename).lineLimit(1)
                                    Text(copy.attachmentSummary(bytes: attachment.byteCount,
                                                                checksum: String(attachment.checksum.prefix(12)),
                                                                required: attachment.isRequired))
                                        .font(.caption).foregroundStyle(.secondary)
                                    ForEach(transfers.filter { $0.attachmentID == attachment.id }) { transfer in
                                        Text(transferLabel(transfer))
                                            .font(.caption2)
                                            .foregroundStyle(transfer.state == .failed ? Color.red : .secondary)
                                    }
                                }
                            }
                        }
                    }
                } header: { Text(copy.privateAttachments) } footer: {
                    Text(copy.attachmentGuidance)
                }
            }

            Section(copy.finalScore) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(match.homeTeam).font(.subheadline).foregroundStyle(.secondary)
                        Text("\(match.homeScore)").font(.largeTitle.bold()).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Text("–").font(.title2).foregroundStyle(.secondary)
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(match.awayTeam).font(.subheadline).foregroundStyle(.secondary)
                        Text("\(match.awayScore)").font(.largeTitle.bold()).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Toggle(copy.confirmFinalScore, isOn: $scoreConfirmed)
                    .font(.headline)
                    .accessibilityIdentifier("report.score.confirm")
            }

            if !blockingIssues.isEmpty {
                Section {
                    ForEach(blockingIssues) { issue in issueRow(issue, colour: .red) }
                } header: {
                    Label(copy.blockingIssues, systemImage: "xmark.octagon.fill")
                } footer: {
                    Text(copy.resolveBlockingIssues)
                }
            } else if validation != nil {
                Section {
                    Label(copy.noBlockingIssues, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } header: { Text(copy.validation) }
            }

            if !warnings.isEmpty {
                Section {
                    ForEach(warnings) { issue in issueRow(issue, colour: .orange) }
                } header: {
                    Label(copy.warnings, systemImage: "exclamationmark.triangle.fill")
                } footer: {
                    Text(copy.warningsGuidance)
                }
            }

            Section(copy.refereeDeclaration) {
                Text(declaration).font(.subheadline).foregroundStyle(.secondary)
                Toggle(copy.agreeAndSign, isOn: $declarationAccepted)
                    .font(.headline)
                    .accessibilityIdentifier("report.declaration.accept")
            }

            Section {
                Button(copy.sign(copy.reportKindName(reportKind.rawValue)), systemImage: "signature") {
                    showingSignConfirmation = true
                }
                .disabled(!canSign || selectedDocument == nil)
                .accessibilityIdentifier("report.sign")
            } footer: {
                if !scoreConfirmed {
                    Text(copy.confirmProjectedScore)
                } else if !declarationAccepted {
                    Text(copy.acceptDeclaration)
                }
            }

            Section(copy.signedVersionHistory) {
                if versions.isEmpty {
                    Text(copy.noSignedVersions).foregroundStyle(.secondary)
                } else {
                    ForEach(versions) { version in
                        SignedReportVersionRow(
                            version: version,
                            exportedURL: match.lastExportedReportID == version.id ? match.lastExportedFile : nil,
                            exportedFormat: match.lastExportedReportID == version.id ? match.lastExportedFormat : nil,
                            export: { match.exportReport(version, format: $0) }
                        )
                    }
                }
            }

            if let saveMessage = match.saveMessage {
                Section {
                    Text(copy.statusMessage(saveMessage))
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("report.saveMessage")
                }
            }
        }
        .navigationTitle(copy.postMatchReview)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
        .onChange(of: scoreConfirmed) { _ in refresh() }
        .onChange(of: reportKind) { _ in selectedDocumentID = nil; refresh() }
        .onChange(of: selectedDocumentID) { _ in loadSelectedContent() }
        .refreshable { refresh() }
        .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.item]) { result in
            guard let document = selectedDocument, case .success(let url) = result else { return }
            _ = match.addAttachment(documentID: document.id, url: url, required: attachmentIsRequired)
        }
        .onChange(of: selectedPhoto) { item in
            guard let item, let document = selectedDocument else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    _ = match.addAttachment(documentID: document.id, data: data,
                                            mediaType: "image/jpeg",
                                            filename: "photo-\(UUID().uuidString.lowercased()).jpg",
                                            required: attachmentIsRequired)
                }
                selectedPhoto = nil
            }
        }
        .confirmationDialog(copy.signReportVersionPrompt, isPresented: $showingSignConfirmation,
                            titleVisibility: .visible) {
            Button(copy.sign(copy.reportKindName(reportKind.rawValue))) {
                guard let confirmedScore, let document = selectedDocument else { return }
                if match.signReport(kind: reportKind, documentID: document.id,
                                    confirmedScore: confirmedScore, declaration: declaration) {
                    declarationAccepted = false
                }
            }
            .accessibilityIdentifier("report.sign.confirm")
            Button(copy.cancel, role: .cancel) {}
        } message: {
            Text(copy.signingFreezeGuidance)
        }
    }

    private func transferLabel(_ transfer: AttachmentTransfer) -> String {
        let progress = transfer.byteCount > 0
            ? " · \(Int((Double(transfer.bytesConfirmed) / Double(transfer.byteCount)) * 100))%"
            : ""
        return copy.transferLabel(peer: transfer.peer, state: transfer.state.rawValue,
                                  progress: progress, error: transfer.error)
    }

    private func refresh() {
        match.refreshPostMatchReview(confirmedScore: confirmedScore)
        if selectedDocumentID == nil || !documents.contains(where: { $0.id == selectedDocumentID }) {
            selectedDocumentID = documents.first?.id
        }
        loadSelectedContent()
    }

    private func loadSelectedContent() {
        guard let content = selectedDocument?.content else {
            summary = ""; narrativeDescription = ""; actionTaken = ""; additionalNotes = ""; return
        }
        summary = content.summary; narrativeDescription = content.description
        actionTaken = content.actionTaken; additionalNotes = content.additionalNotes
    }

    private func issueRow(_ issue: ReportValidationIssue, colour: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: issue.severity == .blocking ? "xmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(colour)
            VStack(alignment: .leading, spacing: 3) {
                Text(copy.reportIssueTitle(code: issue.code, fallback: issueTitle(issue.code)))
                if let eventID = issue.eventID {
                    Text(copy.eventReference(String(eventID.uuidString.prefix(8))))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func issueTitle(_ code: String) -> String {
        switch code {
        case "fixture_missing": return "Fixture details are missing"
        case "period_still_active": return "A match period is still active"
        case "match_not_complete": return "The match has not reached full time"
        case "score_not_confirmed": return "Final score has not been confirmed"
        case "score_confirmation_mismatch": return "Confirmed score does not match the event timeline"
        case "accountable_referee_missing": return "Accountable referee is missing"
        case "timeline_integrity_invalid": return "Timeline integrity validation failed"
        case "event_payload_invalid": return "An event contains invalid data"
        case "goal_player_missing": return "Goalscorer is missing"
        case "card_player_missing": return "Card recipient is missing"
        case "card_reason_missing": return "Disciplinary reason is missing"
        case "direct_red_narrative_missing": return "Direct-red incident narrative is missing"
        case "required_location_missing": return "A required incident pitch location is missing"
        case "substitution_players_missing": return "A substitution needs both outgoing and incoming players"
        case "penalty_outcome_pending": return "A penalty outcome still needs confirmation"
        case "injury_player_missing": return "The injured player has not been identified"
        case "var_outcome_pending": return "The VAR review outcome has not been completed"
        case "required_attachment_unreadable": return "A required attachment is missing or failed its checksum"
        case "missing_revision_target": return "A correction or reversal target is missing"
        case "ambiguous_revision": return "An event has conflicting revisions"
        case "revision_cycle": return "A correction or reversal chain is cyclic"
        default: return code.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

private struct SignedReportVersionRow: View {
    @Environment(\.refereeCopy) private var copy
    let version: SignedReportVersion
    let exportedURL: URL?
    let exportedFormat: ReportExportFormat?
    let export: (ReportExportFormat) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(copy.version(version.version)).font(.headline)
                Spacer()
                Text(version.status == .current ? copy.current : copy.superseded)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(version.status == .current ? Color.green : .orange)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background((version.status == .current ? Color.green : .orange).opacity(0.12),
                                in: Capsule())
            }
            Text(copy.signedBy(version.signer.displayName,
                               at: version.signedAt.formatted(date: .abbreviated, time: .shortened)))
                .font(.subheadline).foregroundStyle(.secondary)
            Text(copy.reportVersionDetails(content: version.contentVersion,
                                           template: version.templateVersion,
                                           events: version.eventIDs.count))
                .font(.caption).foregroundStyle(.secondary)
            if version.status == .superseded {
                Text(copy.immutableHistoryGuidance)
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("PDF") { export(.pdf) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("report.export.pdf")
                Button("XLSX") { export(.xlsx) }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("report.export.xlsx")
                Spacer()
                if let exportedURL {
                    ShareLink(item: exportedURL) {
                        Label(copy.share(exportedFormat?.rawValue.uppercased() ?? copy.file), systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("report.export.share")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private enum TimelineRevisionMode: String { case correct, reverse }

private struct PhoneTimelineView: View {
    @EnvironmentObject private var match: PhoneMatchStore
    @Environment(\.refereeCopy) private var copy
    @State private var editor: TimelineEditor?
    @State private var detailEntry: MatchTimelineEntry?
    @State private var locationEntry: MatchTimelineEntry?

    private struct TimelineEditor: Identifiable {
        let entry: MatchTimelineEntry
        let mode: TimelineRevisionMode
        var id: String { "\(entry.eventID.uuidString)-\(mode.rawValue)" }
    }

    var body: some View {
        List {
            if match.timeline.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock").font(.largeTitle).foregroundStyle(.secondary)
                    Text(copy.noEventsYet).font(.headline)
                    Text(copy.timelineEmptyGuidance).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 36)
            }
            ForEach(match.timeline) { entry in
                timelineRow(entry)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if canLocate(entry) {
                            Button { locationEntry = entry } label: {
                                Label(copy.pitch, systemImage: "map")
                            }
                            .tint(.green)
                        }
                        if entry.canRevise {
                            Button(role: .destructive) { editor = TimelineEditor(entry: entry, mode: .reverse) } label: {
                                Label(copy.reverse, systemImage: "arrow.uturn.backward")
                            }
                            if canCorrect(entry) {
                                Button { editor = TimelineEditor(entry: entry, mode: .correct) } label: {
                                    Label(copy.correct, systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            if detailTypes.contains(entry.eventType) {
                                Button { detailEntry = entry } label: {
                                    Label(copy.details, systemImage: "person.text.rectangle")
                                }
                                .tint(.indigo)
                            }
                        }
                    }
            }
        }
        .navigationTitle(copy.eventTimeline)
        .sheet(item: $editor) { editor in
            RevisionEditorView(entry: editor.entry, mode: editor.mode)
                .environmentObject(match)
        }
        .sheet(item: $detailEntry) { entry in
            if entry.eventType == "goal_recorded" || entry.eventType == "card_recorded" {
                EventDetailsView(entry: entry).environmentObject(match)
            } else {
                ExtendedActionDetailsView(entry: entry).environmentObject(match)
            }
        }
        .sheet(item: $locationEntry) { entry in
            PitchLocationView(entry: entry).environmentObject(match)
        }
    }

    private func timelineRow(_ entry: MatchTimelineEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon(entry.eventType))
                .frame(width: 24).foregroundStyle(entry.isActive ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title(entry)).font(.headline)
                    if !entry.isActive { Text(copy.revised).font(.caption2.weight(.bold)).foregroundStyle(.secondary) }
                    if entry.hasRevisionIssue { Text(copy.issue).font(.caption2.weight(.bold)).foregroundStyle(.red) }
                }
                HStack(spacing: 8) {
                    if let clock = entry.matchClockMs { Text(formatClock(clock)) }
                    Text(entry.recordedAt.formatted(date: .omitted, time: .standard))
                }
                .font(.caption).foregroundStyle(.secondary)
                if let detail = detail(entry) { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            }
        }
        .opacity(entry.isActive ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture {
            if entry.isActive && detailTypes.contains(entry.eventType) {
                detailEntry = entry
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("timeline.\(entry.eventType).\(entry.eventID.uuidString)")
    }

    private func canCorrect(_ entry: MatchTimelineEntry) -> Bool {
        ["goal_recorded", "foul_recorded", "card_recorded"].contains(entry.eventType)
    }

    private var detailTypes: Set<String> {
        ["goal_recorded", "card_recorded", MatchActionType.substitution.rawValue,
         MatchActionType.penalty.rawValue, MatchActionType.injury.rawValue, MatchActionType.varReview.rawValue]
    }

    private func canLocate(_ entry: MatchTimelineEntry) -> Bool {
        guard entry.isActive else { return false }
        var type = entry.eventType
        var object = (try? JSONSerialization.jsonObject(with: Data(entry.payloadJSON.utf8))) as? [String: Any] ?? [:]
        if type == "event_corrected" {
            type = object["replacementEventType"] as? String ?? type
            object = object["replacementPayload"] as? [String: Any] ?? [:]
        }
        return type == "foul_recorded" || object["locationRequired"] as? Bool == true
    }

    private func title(_ entry: MatchTimelineEntry) -> String {
        let fallback: String
        switch entry.eventType {
        case "goal_recorded": fallback = "Goal"
        case "foul_recorded": fallback = "Foul"
        case "card_recorded": fallback = "Card"
        case "stoppage_time_recorded": fallback = "Added-time marker"
        case MatchActionType.substitution.rawValue: fallback = "Substitution"
        case MatchActionType.penalty.rawValue: fallback = "Penalty"
        case MatchActionType.injury.rawValue: fallback = "Injury"
        case MatchActionType.varReview.rawValue: fallback = "VAR review"
        case MatchActionType.suspension.rawValue: fallback = "Match suspension"
        case MatchActionType.restart.rawValue: fallback = "Restart"
        case "period_started": fallback = "Period started"
        case "period_ended": fallback = "Period ended"
        case "event_corrected": fallback = "Correction"
        case "event_reversed": fallback = "Reversal"
        case "location_added": fallback = "Pitch location"
        default: fallback = entry.eventType.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return copy.timelineEventTitle(entry.eventType, fallback: fallback)
    }

    private func icon(_ type: String) -> String {
        switch type {
        case "goal_recorded": return "soccerball"
        case "card_recorded": return "rectangle.fill"
        case "period_started": return "play.fill"
        case "period_ended": return "stop.fill"
        case "event_corrected": return "pencil"
        case "event_reversed": return "arrow.uturn.backward"
        case "location_added": return "map.fill"
        case MatchActionType.substitution.rawValue: return "arrow.left.arrow.right"
        case MatchActionType.penalty.rawValue: return "scope"
        case MatchActionType.injury.rawValue: return "cross.case.fill"
        case MatchActionType.varReview.rawValue: return "video.fill"
        case MatchActionType.suspension.rawValue: return "pause.fill"
        case MatchActionType.restart.rawValue: return "arrow.clockwise"
        default: return "circle.fill"
        }
    }

    private func detail(_ entry: MatchTimelineEntry) -> String? {
        guard var object = try? JSONSerialization.jsonObject(with: Data(entry.payloadJSON.utf8)) as? [String: Any] else { return nil }
        if let replacement = object["replacementPayload"] as? [String: Any] { object = replacement }
        if let reason = object["reason"] as? String { return reason }
        var parts: [String] = []
        if let side = object["teamSide"] as? String { parts.append(side == "home" ? match.homeTeam : match.awayTeam) }
        if let colour = object["colour"] as? String { parts.append(copy.enumValue(colour)) }
        if let player = object["participantDisplayName"] as? String { parts.append(player) }
        if let discipline = object["disciplinaryReason"] as? String { parts.append(discipline) }
        if let cause = object["cause"] as? String { parts.append(cause.replacingOccurrences(of: "_", with: " ").capitalized) }
        if let player = object["playerOutDisplayName"] as? String { parts.append("\(copy.detailPrefix("Out")): \(player)") }
        if let player = object["playerInDisplayName"] as? String { parts.append("\(copy.detailPrefix("In")): \(player)") }
        if let outcome = object["outcome"] as? String { parts.append(copy.enumValue(outcome)) }
        if let review = object["reviewType"] as? String { parts.append(copy.enumValue(review)) }
        if let state = object["state"] as? String { parts.append(copy.enumValue(state)) }
        if let restart = object["restartType"] as? String { parts.append(copy.enumValue(restart)) }
        if let kind = object["periodKind"] as? String { parts.append(copy.enumValue(kind)) }
        if let regions = object["regions"] as? [String] {
            parts.append(regions.map { $0.replacingOccurrences(of: "_", with: " ").capitalized }.joined(separator: ", "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formatClock(_ milliseconds: Int64) -> String {
        String(format: "%02lld:%02lld", milliseconds / 60_000, (milliseconds / 1_000) % 60)
    }
}

private struct ExtendedActionDetailsView: View {
    @EnvironmentObject private var match: PhoneMatchStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.refereeCopy) private var copy
    let entry: MatchTimelineEntry
    @State private var primary: UUID?
    @State private var secondary: UUID?
    @State private var penaltyOutcome = PenaltyOutcome.pending
    @State private var varOutcome = VAROutcome.pending

    private var payload: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(entry.payloadJSON.utf8))) as? [String: Any] ?? [:]
    }
    private var side: String? { payload["teamSide"] as? String }
    private var players: [MatchParticipantSnapshot] {
        guard let side else { return match.roster(for: "home") + match.roster(for: "away") }
        return match.roster(for: side)
    }

    var body: some View {
        NavigationStack {
            Form {
                if entry.eventType == MatchActionType.substitution.rawValue {
                    participantPicker(copy.playerOutTitle, selection: $primary)
                    participantPicker(copy.playerInTitle, selection: $secondary)
                } else if entry.eventType == MatchActionType.penalty.rawValue {
                    participantPicker(copy.penaltyTaker, selection: $primary)
                    Picker(copy.outcome, selection: $penaltyOutcome) {
                        ForEach(PenaltyOutcome.allCases, id: \.rawValue) { Text(copy.enumValue($0.rawValue)).tag($0) }
                    }
                } else if entry.eventType == MatchActionType.injury.rawValue {
                    participantPicker(copy.injuredPlayer, selection: $primary)
                } else if entry.eventType == MatchActionType.varReview.rawValue {
                    Picker(copy.outcome, selection: $varOutcome) {
                        ForEach(VAROutcome.allCases, id: \.rawValue) {
                            Text(copy.enumValue($0.rawValue)).tag($0)
                        }
                    }
                }
                Section {
                    Button(copy.appendCompletedDetails) {
                        match.completeMatchAction(entry, primary: primary, secondary: secondary,
                                                  outcome: completionOutcome)
                        dismiss()
                    }.disabled(!isValid)
                }
            }
            .navigationTitle(copy.completeAction)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(copy.cancel) { dismiss() } } }
        }
    }

    @ViewBuilder private func participantPicker(_ title: String, selection: Binding<UUID?>) -> some View {
        Picker(title, selection: selection) {
            Text(copy.select).tag(UUID?.none)
            ForEach(players) { player in
                Text("\(player.shirtNumber.map(String.init) ?? "–") · \(player.displayName)").tag(Optional(player.id))
            }
        }
    }

    private var completionOutcome: String? {
        if entry.eventType == MatchActionType.penalty.rawValue { return penaltyOutcome.rawValue }
        if entry.eventType == MatchActionType.varReview.rawValue { return varOutcome.rawValue }
        return nil
    }
    private var isValid: Bool {
        switch entry.eventType {
        case MatchActionType.substitution.rawValue: return primary != nil && secondary != nil && primary != secondary
        case MatchActionType.penalty.rawValue: return penaltyOutcome != .pending
        case MatchActionType.injury.rawValue: return primary != nil
        case MatchActionType.varReview.rawValue: return varOutcome != .pending
        default: return false
        }
    }
}

private struct EventDetailsView: View {
    @EnvironmentObject private var match: PhoneMatchStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.refereeCopy) private var copy
    let entry: MatchTimelineEntry
    @State private var playerID: UUID?
    @State private var disciplinaryReason = ""
    @State private var incidentNarrative = ""
    @State private var locationRequired = false

    private var payload: [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(entry.payloadJSON.utf8))) as? [String: Any] ?? [:]
    }
    private var side: String { payload["teamSide"] as? String ?? "home" }
    private var players: [MatchParticipantSnapshot] { match.roster(for: side) }
    private var isCard: Bool { entry.eventType == "card_recorded" }
    private var isDirectRed: Bool { payload["isDirectRed"] as? Bool == true }

    var body: some View {
        NavigationStack {
            Form {
                Section(entry.eventType == "goal_recorded" ? copy.goalscorer : copy.cardRecipient) {
                    Picker(copy.player, selection: $playerID) {
                        Text(copy.selectPlayer).tag(UUID?.none)
                        ForEach(players) { player in
                            Text("\(player.shirtNumber.map(String.init) ?? "–") · \(player.displayName)").tag(Optional(player.id))
                        }
                    }
                    .accessibilityIdentifier("event.details.player")
                }
                if isCard {
                    Section(copy.disciplinaryReason) {
                        TextField(copy.requiredReason, text: $disciplinaryReason, axis: .vertical).lineLimit(2...4)
                    }
                }
                if isDirectRed {
                    Section(copy.requiredIncidentNarrative) {
                        TextField(copy.describeIncident, text: $incidentNarrative, axis: .vertical)
                            .lineLimit(5...10)
                        Text(copy.directRedNarrativeGuidance)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section(copy.incidentLocation) {
                        Toggle(copy.exactLocationRequired, isOn: $locationRequired)
                        Text(copy.incidentLocationGuidance)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button(copy.appendCompletedDetails) {
                        guard let playerID else { return }
                        match.completeDetails(for: entry, playerID: playerID,
                                              disciplinaryReason: isCard ? disciplinaryReason : nil,
                                              incidentNarrative: isDirectRed ? incidentNarrative : nil,
                                              locationRequired: isDirectRed && locationRequired)
                        dismiss()
                    }
                    .disabled(!isValid)
                    .accessibilityIdentifier("event.details.save")
                }
            }
            .navigationTitle(copy.completeEvent)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(copy.cancel) { dismiss() } } }
        }
    }

    private var isValid: Bool {
        playerID != nil && (!isCard || !disciplinaryReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) &&
        (!isDirectRed || !incidentNarrative.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

private struct PitchLocationView: View {
    @EnvironmentObject private var match: PhoneMatchStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.refereeCopy) private var copy
    let entry: MatchTimelineEntry
    @State private var point = CGPoint(x: 50, y: 50)
    @State private var accuracy: LocationAccuracy = .refereeConfirmed

    var body: some View {
        NavigationStack {
            Form {
                Section(copy.tapIncidentLocation) {
                    GeometryReader { proxy in
                        ZStack {
                            RoundedRectangle(cornerRadius: 8).fill(Color.green.opacity(0.72))
                            pitchLines(in: proxy.size).stroke(.white.opacity(0.9), lineWidth: 2)
                            Circle().fill(.red).overlay(Circle().stroke(.white, lineWidth: 2))
                                .frame(width: 18, height: 18)
                                .position(x: proxy.size.width * point.x / 100,
                                          y: proxy.size.height * point.y / 100)
                        }
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                            point = CGPoint(x: min(100, max(0, value.location.x / proxy.size.width * 100)),
                                            y: min(100, max(0, value.location.y / proxy.size.height * 100)))
                        })
                    }
                    .aspectRatio(match.pitchLengthMetres / match.pitchWidthMetres, contentMode: .fit)
                    Text(String(format: "%.1f, %.1f m · %.1f, %.1f / 100",
                                point.x * match.pitchLengthMetres / 100,
                                point.y * match.pitchWidthMetres / 100, point.x, point.y))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Section(copy.accuracy) {
                    Picker(copy.status, selection: $accuracy) {
                        Text(copy.refereeConfirmed).tag(LocationAccuracy.refereeConfirmed)
                        Text(copy.estimated).tag(LocationAccuracy.estimated)
                        Text(copy.unconfirmed).tag(LocationAccuracy.unconfirmed)
                    }
                }
                Section {
                    Button(copy.appendPitchLocation) {
                        if match.addLocation(to: entry, normalizedX: point.x, normalizedY: point.y,
                                             accuracy: accuracy) { dismiss() }
                    }
                }
            }
            .navigationTitle(copy.pitchLocation)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(copy.cancel) { dismiss() } } }
        }
    }

    private func pitchLines(in size: CGSize) -> Path {
        Path { path in
            let inset: CGFloat = 8
            let rect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
            path.addRect(rect)
            path.move(to: CGPoint(x: size.width / 2, y: inset)); path.addLine(to: CGPoint(x: size.width / 2, y: size.height - inset))
            path.addEllipse(in: CGRect(x: size.width / 2 - 28, y: size.height / 2 - 28, width: 56, height: 56))
            let boxWidth = rect.width * 16.5 / max(match.pitchLengthMetres, 1)
            let boxHeight = rect.height * min(1, 40.32 / max(match.pitchWidthMetres, 1))
            path.addRect(CGRect(x: inset, y: size.height / 2 - boxHeight / 2, width: boxWidth, height: boxHeight))
            path.addRect(CGRect(x: size.width - inset - boxWidth, y: size.height / 2 - boxHeight / 2, width: boxWidth, height: boxHeight))
        }
    }
}

private struct RevisionEditorView: View {
    @EnvironmentObject private var match: PhoneMatchStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.refereeCopy) private var copy
    let entry: MatchTimelineEntry
    let mode: TimelineRevisionMode
    @State private var reason = ""
    @State private var teamSide: String
    @State private var colour: String

    init(entry: MatchTimelineEntry, mode: TimelineRevisionMode) {
        self.entry = entry; self.mode = mode
        let object = (try? JSONSerialization.jsonObject(with: Data(entry.payloadJSON.utf8))) as? [String: Any]
        _teamSide = State(initialValue: object?["teamSide"] as? String ?? "home")
        _colour = State(initialValue: object?["colour"] as? String ?? "yellow")
    }

    var body: some View {
        NavigationStack {
            Form {
                if mode == .correct {
                    Section(copy.correctedEvent) {
                        Picker(copy.team, selection: $teamSide) {
                            Text(match.homeTeam).tag("home")
                            Text(match.awayTeam).tag("away")
                        }
                        if entry.eventType == "card_recorded" {
                            Picker(copy.cardLabel, selection: $colour) {
                                Text(copy.yellow).tag("yellow")
                                Text(copy.red).tag("red")
                            }
                        }
                    }
                }
                Section(copy.requiredReason) {
                    TextField(mode == .correct ? copy.whatWasCorrected : copy.whyReverseEvent, text: $reason, axis: .vertical)
                        .lineLimit(3...6)
                }
                Section {
                    Button(mode == .correct ? copy.appendCorrection : copy.appendReversal, role: mode == .reverse ? .destructive : nil) {
                        if mode == .correct {
                            match.correct(entry, teamSide: teamSide, colour: entry.eventType == "card_recorded" ? colour : nil, reason: reason)
                        } else {
                            match.reverse(entry, reason: reason)
                        }
                        dismiss()
                    }
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(mode == .correct ? copy.correctEvent : copy.reverseEvent)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(copy.cancel) { dismiss() } } }
        }
    }
}

private struct MorePhoneActionsView: View {
    @EnvironmentObject private var match: PhoneMatchStore
    @Environment(\.refereeCopy) private var copy
    let elapsed: Int64
    @Environment(\.dismiss) private var dismiss
    @State private var substitutionSide = "home"
    @State private var playerOut: UUID?
    @State private var playerIn: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section(copy.substitution) {
                    Picker(copy.team, selection: $substitutionSide) {
                        Text(match.homeTeam).tag("home"); Text(match.awayTeam).tag("away")
                    }
                    Picker(copy.playerOut, selection: $playerOut) {
                        Text(copy.select).tag(UUID?.none)
                        ForEach(match.roster(for: substitutionSide)) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    Picker(copy.playerIn, selection: $playerIn) {
                        Text(copy.select).tag(UUID?.none)
                        ForEach(match.roster(for: substitutionSide)) { Text($0.displayName).tag(Optional($0.id)) }
                    }
                    Button(copy.saveSubstitution) {
                        guard let playerOut, let playerIn else { return }
                        match.recordSubstitution(for: substitutionSide, playerOut: playerOut,
                                                 playerIn: playerIn, matchClockMs: elapsed); dismiss()
                    }.disabled(playerOut == nil || playerIn == nil || playerOut == playerIn)
                }
                Section(copy.penalty) {
                    Button(copy.penaltyAction(side: "home", scored: true)) { penalty("home", .scored) }
                    Button(copy.penaltyAction(side: "home", scored: false)) { penalty("home", .missed) }
                    Button(copy.penaltyAction(side: "away", scored: true)) { penalty("away", .scored) }
                    Button(copy.penaltyAction(side: "away", scored: false)) { penalty("away", .missed) }
                }
                Section(copy.injuryAndVAR) {
                    Button(copy.injuryAction(side: "home")) { injury("home") }
                    Button(copy.injuryAction(side: "away")) { injury("away") }
                    Button(copy.injuryAction(side: nil)) { injury(nil) }
                    Button(copy.startVARReview) { match.recordVAR(type: .other, matchClockMs: elapsed); dismiss() }
                }
                Section(copy.suspensionAndRestart) {
                    Button(copy.suspendWeather) { suspend(.started, "weather") }
                    Button(copy.suspendCrowd) { suspend(.started, "crowd_control") }
                    Button(copy.resumeMatchAction) { suspend(.resumed, "match_interruption") }
                    Button(copy.droppedBallRestart) { restart(.droppedBall) }
                    Button(copy.freeKickRestart) { restart(.freeKick) }
                }
                Section(copy.addedTimeSection) {
                    Button(copy.injuryMarker) { save("injury") }
                    Button(copy.varMarker) { save("var") }
                    Button(copy.delayedRestartMarker) { save("delayed_restart") }
                }
                Section(copy.directRedHoldToConfirm) {
                    Text(copy.homeTeam).foregroundStyle(.red).onLongPressGesture(minimumDuration: 1) { match.recordCard(for: "home", colour: "red", matchClockMs: elapsed); dismiss() }
                    Text(copy.awayTeam).foregroundStyle(.red).onLongPressGesture(minimumDuration: 1) { match.recordCard(for: "away", colour: "red", matchClockMs: elapsed); dismiss() }
                }
            }
            .navigationTitle(copy.matchActions)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(copy.done) { dismiss() } } }
        }
    }
    private func save(_ cause: String) { match.recordStoppage(cause: cause, matchClockMs: elapsed); dismiss() }
    private func penalty(_ side: String, _ outcome: PenaltyOutcome) {
        match.recordPenalty(for: side, outcome: outcome, matchClockMs: elapsed); dismiss()
    }
    private func injury(_ side: String?) { match.recordInjury(for: side, matchClockMs: elapsed); dismiss() }
    private func suspend(_ state: SuspensionState, _ reason: String) {
        match.recordSuspension(state: state, reason: reason, matchClockMs: elapsed); dismiss()
    }
    private func restart(_ type: RestartType) { match.recordRestart(type: type, matchClockMs: elapsed); dismiss() }
}
