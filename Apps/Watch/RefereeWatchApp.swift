import SwiftUI
import WatchKit
import WatchConnectivity
import RefereeLedger

private extension Color {
    init(hex: String?) {
        let raw = hex ?? "#1565C0"
        let value = UInt64(raw.dropFirst(raw.hasPrefix("#") ? 1 : 0), radix: 16) ?? 0x1565C0
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}

@main
struct RefereeWatchApp: App {
    @StateObject private var match = WatchMatchStore()
    @AppStorage("referee.app.language") private var languageCode = AppLanguage.korean.rawValue

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                WatchMatchHomeView()
            }
            .environmentObject(match)
            .environment(\.locale, Locale(identifier: AppLanguage(rawValue: languageCode)?.rawValue ?? AppLanguage.korean.rawValue))
        }
    }
}

@MainActor
final class WatchMatchStore: NSObject, ObservableObject, WCSessionDelegate {
    private static let applicationContextPeerID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    @Published private(set) var homeScore = 0
    @Published private(set) var awayScore = 0
    @Published private(set) var homeTeamName = "HOME"
    @Published private(set) var awayTeamName = "AWAY"
    @Published private(set) var homeTeamColor: String?
    @Published private(set) var awayTeamColor: String?
    @Published private(set) var status = "Saving locally"
    @Published private(set) var saveConfirmation: String?

    @Published private(set) var matchID = UUID()
    @Published private(set) var periodLabel = "WAITING FOR IPHONE"
    @Published private(set) var hasMatchPackage = false
    @Published private(set) var activePeriodID: UUID?
    @Published private(set) var clockAnchor: Date?
    @Published private(set) var clockAnchorMs: Int64 = 0
    @Published private(set) var pendingSyncCount = 0
    @Published private(set) var isPhoneReachable = false
    @Published private(set) var syncFailure: String?
    @Published private(set) var lastPeerSyncAt: Date?
    @Published private(set) var regulationDurationMs: Int64 = 45 * 60 * 1_000
    private var extraTimeDurationMs: Int64 = 15 * 60 * 1_000
    private var ledger: LedgerStore?
    private let session: WCSession? = WCSession.isSupported() ? .default : nil

    override init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Referee", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        do {
            let deviceKey = "referee.watch.originDeviceID"
            let deviceID = UserDefaults.standard.string(forKey: deviceKey).flatMap(UUID.init(uuidString:)) ?? UUID()
            UserDefaults.standard.set(deviceID.uuidString, forKey: deviceKey)
            let databaseName = ProcessInfo.processInfo.environment["REFEREE_WATCH_UI_TEST_DATABASE"]
                .map { "watch-ledger-\($0).sqlite" } ?? "watch-ledger.sqlite"
            let store = try LedgerStore(path: directory.appendingPathComponent(databaseName).path, originDeviceID: deviceID)
            ledger = store
            if ProcessInfo.processInfo.environment["REFEREE_WATCH_UI_TEST_SEED"] == "fixture" {
                try Self.seedUITestFixtureIfNeeded(in: store)
            }
            if let active = UserDefaults.standard.string(forKey: "referee.watch.activeMatchID").flatMap(UUID.init(uuidString:)),
               let peer = UserDefaults.standard.string(forKey: "referee.watch.packagePeerID").flatMap(UUID.init(uuidString:)),
               let package = try store.installedMatchPackage(matchID: active, from: peer) {
                matchID = active; hasMatchPackage = true; periodLabel = package.projection.periodLabel
                homeTeamName = package.fixture.homeTeamName
                awayTeamName = package.fixture.awayTeamName
                homeTeamColor = package.fixture.homeTeamColor
                awayTeamColor = package.fixture.awayTeamColor
                activePeriodID = package.projection.periodID
                clockAnchor = package.projection.clockAnchor
                clockAnchorMs = package.projection.clockAnchorMs
                regulationDurationMs = Int64(package.rules.halfDurationSeconds) * 1_000
                extraTimeDurationMs = Int64(package.rules.extraTimeHalfDurationSeconds) * 1_000
                pendingSyncCount = (try? store.pendingOutboxCount(matchID: active, peer: "iphone")) ?? 0
                let projection = try? store.rebuildProjection(matchID: active)
                homeScore = projection?.homeScore ?? package.projection.homeScore
                awayScore = projection?.awayScore ?? package.projection.awayScore
                status = "Saved match package"
            }
        } catch {
            ledger = nil
            status = "Storage unavailable"
        }
        super.init()
        restoreActivePeriodFromLedger()
        session?.delegate = self
        session?.activate()
        refreshSyncState()
    }

    private static func seedUITestFixtureIfNeeded(in store: LedgerStore) throws {
        let seededMatchID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!
        let seededPeerID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        guard try store.fixture(matchID: seededMatchID) == nil else { return }

        let periodID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!
        let fixture = MatchFixture(matchID: seededMatchID, competition: "Watch UI Acceptance",
                                   scheduledAt: Date(), venueName: "Offline Ground",
                                   homeTeamName: "Seoul", awayTeamName: "Busan")
        let package = MatchPackage(
            fixture: fixture,
            projection: CompactMatchProjection(homeScore: 0, awayScore: 0, periodID: periodID,
                                               periodLabel: "FIRST HALF", clockAnchor: Date()),
            originWatermarks: [:], eventDigest: ""
        )
        try store.installMatchPackage(package, from: seededPeerID)
        _ = try store.create(EventDraft(matchID: seededMatchID, eventType: "period_started",
                                        matchPeriodID: periodID, matchClockMs: 0,
                                        payloadJSON: #"{"ordinal":1,"periodKind":"first_half"}"#), peers: [])
        UserDefaults.standard.set(seededMatchID.uuidString, forKey: "referee.watch.activeMatchID")
        UserDefaults.standard.set(seededPeerID.uuidString, forKey: "referee.watch.packagePeerID")
    }

    func elapsed(at date: Date) -> Int64 {
        guard let clockAnchor else { return clockAnchorMs }
        return clockAnchorMs + max(0, Int64(date.timeIntervalSince(clockAnchor) * 1_000))
    }

    func startNextPeriod() {
        guard hasMatchPackage, activePeriodID == nil else { return }
        guard let ledger, let definition = try? ledger.periodState(matchID: matchID).next else { return }
        let periodID = UUID()
        guard save(type: "period_started", payloadJSON: "{\"ordinal\":\(definition.ordinal),\"periodKind\":\"\(definition.kind)\"}", periodID: periodID, matchClockMs: 0, haptic: .start) else { return }
        activePeriodID = periodID
        clockAnchor = Date()
        clockAnchorMs = 0
        periodLabel = definition.label
        if definition.kind.hasPrefix("extra_time") { regulationDurationMs = extraTimeDurationMs }
    }

    func endCurrentPeriod(at date: Date) {
        guard let periodID = activePeriodID else { return }
        guard let ledger, let active = try? ledger.periodState(matchID: matchID).active else { return }
        let elapsed = elapsed(at: date)
        guard save(type: "period_ended", payloadJSON: "{\"finalClockMs\":\(elapsed),\"ordinal\":\(active.definition.ordinal),\"periodKind\":\"\(active.definition.kind)\"}", periodID: periodID, matchClockMs: elapsed, haptic: .stop) else { return }
        activePeriodID = nil
        clockAnchor = nil
        clockAnchorMs = elapsed
        refreshProjection()
    }

    func saveGoal(side: String, matchClockMs: Int64) {
        save(type: "goal_recorded", payloadJSON: #"{"teamSide":"\#(side)"}"#, matchClockMs: matchClockMs, haptic: .success)
    }

    func saveFoul(side: String, matchClockMs: Int64) {
        save(type: "foul_recorded", payloadJSON: #"{"teamSide":"\#(side)"}"#, matchClockMs: matchClockMs, haptic: .click)
    }

    func saveCard(side: String, colour: String, matchClockMs: Int64) {
        let isDirectRed = colour == "red"
        save(type: "card_recorded", payloadJSON: "{\"colour\":\"\(colour)\",\"isDirectRed\":\(isDirectRed),\"teamSide\":\"\(side)\"}", matchClockMs: matchClockMs, haptic: .success)
    }

    func saveStoppage(cause: String, matchClockMs: Int64) {
        save(type: "stoppage_time_recorded", payloadJSON: #"{"cause":"\#(cause)"}"#, matchClockMs: matchClockMs, haptic: .click)
    }

    func saveSubstitution(side: String, matchClockMs: Int64) {
        save(type: MatchActionType.substitution.rawValue, payloadJSON: #"{"teamSide":"\#(side)"}"#,
             matchClockMs: matchClockMs, haptic: .click)
    }

    func savePenalty(side: String, outcome: PenaltyOutcome = .pending, matchClockMs: Int64) {
        save(type: MatchActionType.penalty.rawValue,
             payloadJSON: #"{"outcome":"\#(outcome.rawValue)","phase":"match","teamSide":"\#(side)"}"#,
             matchClockMs: matchClockMs, haptic: .success)
    }

    func saveInjury(side: String?, matchClockMs: Int64) {
        let payload = side.map { #"{"teamSide":"\#($0)"}"# } ?? "{}"
        save(type: MatchActionType.injury.rawValue, payloadJSON: payload, matchClockMs: matchClockMs, haptic: .click)
    }

    func saveVAR(matchClockMs: Int64) {
        save(type: MatchActionType.varReview.rawValue,
             payloadJSON: #"{"outcome":"pending","reviewType":"other"}"#,
             matchClockMs: matchClockMs, haptic: .click)
    }

    func saveSuspension(state: SuspensionState, reason: String, matchClockMs: Int64) {
        save(type: MatchActionType.suspension.rawValue,
             payloadJSON: #"{"reason":"\#(reason)","state":"\#(state.rawValue)"}"#,
             matchClockMs: matchClockMs, haptic: .click)
    }

    func saveRestart(type: RestartType, matchClockMs: Int64) {
        save(type: MatchActionType.restart.rawValue, payloadJSON: #"{"restartType":"\#(type.rawValue)"}"#,
             matchClockMs: matchClockMs, haptic: .click)
    }

    @discardableResult
    private func save(type: String, payloadJSON: String, periodID: UUID? = nil, matchClockMs: Int64, haptic: WKHapticType) -> Bool {
        do {
            guard hasMatchPackage else { throw LedgerError.invalidDraft("waiting for an iPhone match package") }
            guard let ledger else { throw LedgerError.sqlite("local database unavailable") }
            _ = try ledger.create(
                EventDraft(matchID: matchID, eventType: type, matchPeriodID: periodID ?? activePeriodID,
                           matchClockMs: matchClockMs, payloadJSON: payloadJSON),
                peers: ["iphone"]
            )
            let projection = try ledger.rebuildProjection(matchID: matchID)
            homeScore = projection.homeScore
            awayScore = projection.awayScore
            status = "Saved on Watch"
            pendingSyncCount = try ledger.pendingOutboxCount(matchID: matchID, peer: "iphone")
            saveConfirmation = "Saved locally · Queue \(pendingSyncCount)"
            synchronize()
            WKInterfaceDevice.current().play(haptic)
            if haptic == .success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    WKInterfaceDevice.current().play(.click)
                }
            }
            return true
        } catch {
            status = "Save failed — reconnect"
            WKInterfaceDevice.current().play(.failure)
            return false
        }
    }

    private func synchronize() {
        refreshSyncState()
        guard let ledger, let watermark = try? ledger.syncWatermark(matchID: matchID), let payload = try? JSONEncoder().encode(watermark) else {
            noteSyncFailure("Local sync queue unavailable")
            return
        }
        status = isPhoneReachable ? "Reconciling with iPhone" : queuedSyncStatus
        send(kind: "watermark", payload: payload)
        sendPendingEvents()
    }

    func retrySynchronization() {
        syncFailure = nil
        synchronize()
    }

    private func sendPendingEvents() {
        guard let ledger, let events = try? ledger.pendingOutboxEvents(matchID: matchID, peer: "iphone") else {
            noteSyncFailure("Pending events could not be read")
            return
        }
        for event in events {
            if let payload = try? JSONEncoder().encode(event) { send(kind: "event", payload: payload) }
        }
        refreshSyncState()
    }

    private func send(kind: String, payload: Data) {
        guard let session, let data = try? JSONEncoder().encode(WatchTransportMessage(kind: kind, senderDeviceID: ledger?.originDeviceID ?? UUID(), payload: payload)) else { return }
        session.transferUserInfo(["referee.sync": data])
        if session.isReachable {
            session.sendMessage(["referee.sync": data], replyHandler: nil) { [weak self] error in
                Task { @MainActor in
                    self?.noteSyncFailure("Immediate iPhone delivery failed: \(error.localizedDescription)")
                    WKInterfaceDevice.current().play(.failure)
                }
            }
        }
    }

    private func install(_ package: MatchPackage, from peerDeviceID: UUID) {
        guard let ledger else { return }
        do {
            try ledger.installMatchPackage(package, from: peerDeviceID)
            matchID = package.fixture.matchID
            UserDefaults.standard.set(package.fixture.matchID.uuidString, forKey: "referee.watch.activeMatchID")
            UserDefaults.standard.set(peerDeviceID.uuidString, forKey: "referee.watch.packagePeerID")
            hasMatchPackage = true
            homeScore = package.projection.homeScore; awayScore = package.projection.awayScore
            periodLabel = package.projection.periodLabel
            activePeriodID = package.projection.periodID
            clockAnchor = package.projection.clockAnchor
            clockAnchorMs = package.projection.clockAnchorMs
            regulationDurationMs = Int64(package.rules.halfDurationSeconds) * 1_000
            extraTimeDurationMs = Int64(package.rules.extraTimeHalfDurationSeconds) * 1_000
            restoreActivePeriodFromLedger()
            pendingSyncCount = try ledger.pendingOutboxCount(matchID: matchID, peer: "iphone")
            status = "Match package ready"
            synchronize()
        } catch { status = "Package could not be saved" }
    }

    private func receiveTransport(_ data: Data) {
        guard let message = try? JSONDecoder().decode(WatchTransportMessage.self, from: data), let ledger else { return }
        lastPeerSyncAt = Date()
        syncFailure = nil
        switch message.kind {
        case "package":
            if let package = try? JSONDecoder().decode(MatchPackage.self, from: message.payload) { install(package, from: message.senderDeviceID) }
        case "watermark":
            guard let watermark = try? JSONDecoder().decode(SyncWatermark.self, from: message.payload), watermark.matchID == matchID,
                  let missing = try? ledger.eventsMissing(from: watermark.originWatermarks, matchID: matchID) else { return }
            for event in missing { if let payload = try? JSONEncoder().encode(event) { send(kind: "event", payload: payload) } }
            sendPendingEvents()
            if missing.isEmpty, let local = try? ledger.syncWatermark(matchID: matchID), local.eventDigest == watermark.eventDigest {
                status = "iPhone is up to date"
            }
        case "event":
            guard let event = try? JSONDecoder().decode(ReplicatedEvent.self, from: message.payload) else { return }
            let result = try? ledger.receive(event, messageID: message.messageID, from: message.senderDeviceID)
            guard result == .committed || result == .alreadyCommitted else { return }
            let acknowledgement = EventAcknowledgement(matchID: event.event.draft.matchID, eventID: event.event.draft.eventID, integrityHash: event.event.integrityHash)
            if let payload = try? JSONEncoder().encode(acknowledgement) { send(kind: "ack", payload: payload) }
            refreshProjection()
            synchronize()
        case "ack":
            guard let acknowledgement = try? JSONDecoder().decode(EventAcknowledgement.self, from: message.payload) else { return }
            try? ledger.acknowledge(eventID: acknowledgement.eventID, integrityHash: acknowledgement.integrityHash, peer: "iphone")
            refreshSyncState()
            if pendingSyncCount == 0 { status = "iPhone is up to date" }
        default: break
        }
    }

    private var queuedSyncStatus: String {
        pendingSyncCount == 0 ? "Saved locally · iPhone offline" : "\(pendingSyncCount) queued safely"
    }

    private func refreshSyncState() {
        isPhoneReachable = session?.isReachable ?? false
        pendingSyncCount = (try? ledger?.pendingOutboxCount(matchID: matchID, peer: "iphone")) ?? 0
        guard syncFailure == nil else { status = "Sync issue · saved locally"; return }
        if isPhoneReachable {
            status = pendingSyncCount == 0 ? "iPhone connected" : "Syncing \(pendingSyncCount)"
        } else {
            status = queuedSyncStatus
        }
    }

    private func noteSyncFailure(_ message: String) {
        syncFailure = message
        refreshSyncState()
    }

    private func refreshProjection() {
        guard let ledger, let projection = try? ledger.rebuildProjection(matchID: matchID) else { return }
        homeScore = projection.homeScore; awayScore = projection.awayScore
        restoreActivePeriodFromLedger()
    }

    /// A Watch relaunch must restore its clock from immutable period boundaries,
    /// rather than relying on a runtime-only anchor from a previous process.
    private func restoreActivePeriodFromLedger() {
        guard let ledger, let state = try? ledger.periodState(matchID: matchID) else { return }
        guard let context = state.active else {
            activePeriodID = nil; clockAnchor = nil; clockAnchorMs = 0; periodLabel = state.displayLabel
            return
        }
        activePeriodID = context.periodID
        periodLabel = context.label
        if context.definition.kind.hasPrefix("extra_time") { regulationDurationMs = extraTimeDurationMs }
        clockAnchor = context.startedAt
        clockAnchorMs = context.startClockMs
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let error { self.noteSyncFailure("Session activation failed: \(error.localizedDescription)"); return }
            if activationState == .activated { self.synchronize() }
            else { self.noteSyncFailure("iPhone session is not active") }
        }
    }
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.syncFailure = nil
            self.refreshSyncState()
            if reachable { self.synchronize() }
        }
    }
    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String : Any]) { if let data = message["referee.sync"] as? Data { Task { @MainActor in self.receiveTransport(data) } } }
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) { if let data = userInfo["referee.sync"] as? Data { Task { @MainActor in self.receiveTransport(data) } } }
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) { if let data = applicationContext["referee.matchPackage"] as? Data { Task { @MainActor in if let package = try? JSONDecoder().decode(MatchPackage.self, from: data) { self.install(package, from: Self.applicationContextPeerID) } } } }
}

private struct WatchTransportMessage: Codable {
    let kind: String
    let senderDeviceID: UUID
    let messageID: UUID
    let payload: Data
    init(kind: String, senderDeviceID: UUID, messageID: UUID = UUID(), payload: Data) { self.kind = kind; self.senderDeviceID = senderDeviceID; self.messageID = messageID; self.payload = payload }
}

struct WatchMatchHomeView: View {
    @EnvironmentObject private var match: WatchMatchStore
    @State private var selectedAction: QuickAction?

    private enum QuickAction {
        case goal(Int64)
        case foul(Int64)
        case card(Int64)
        case more(Int64)
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = match.elapsed(at: context.date)
            ScrollView(.vertical) {
                VStack(spacing: 7) {
                HStack {
                    Text(match.periodLabel).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: match.syncFailure != nil ? "exclamationmark.icloud" :
                            (match.pendingSyncCount == 0 ? "checkmark.icloud" : "arrow.triangle.2.circlepath"))
                        .foregroundStyle(match.syncFailure != nil ? Color.red : (match.pendingSyncCount == 0 ? Color.green : Color.orange))
                }
                Text(clock(elapsed, regulationDurationMs: match.regulationDurationMs)).font(.system(size: 36, weight: .bold, design: .rounded)).monospacedDigit()
                HStack(spacing: 4) {
                    Text("\(match.homeScore)").foregroundStyle(Color(hex: match.homeTeamColor))
                    Text("–").foregroundStyle(.secondary)
                    Text("\(match.awayScore)").foregroundStyle(Color(hex: match.awayTeamColor))
                }.font(.title3.weight(.bold)).monospacedDigit()
                if match.activePeriodID == nil {
                    Label(match.periodLabel == "FULL TIME" ? "Match complete" : "Hold to start", systemImage: "play.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.green)
                        .padding(.vertical, 6).frame(maxWidth: .infinity)
                        .background(.green.opacity(0.15), in: Capsule())
                        .onLongPressGesture(minimumDuration: 1) { match.startNextPeriod() }
                        .disabled(match.periodLabel == "FULL TIME")
                }
                HStack(spacing: 6) {
                    Button { selectedAction = .goal(elapsed) } label: { actionLabel("GOAL", icon: "soccerball", tint: .green) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("watch.action.goal")
                    Button { selectedAction = .foul(elapsed) } label: { actionLabel("FOUL", icon: "figure.soccer", tint: .orange) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("watch.action.foul")
                }
                .disabled(match.activePeriodID == nil || !match.hasMatchPackage)
                HStack(spacing: 6) {
                    Button { selectedAction = .card(elapsed) } label: { actionLabel("CARD", icon: "rectangle.fill", tint: .yellow) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("watch.action.card")
                    Button { selectedAction = .more(elapsed) } label: { actionLabel("MORE", icon: "ellipsis", tint: .blue) }
                        .buttonStyle(.plain)
                }
                .disabled(match.activePeriodID == nil || !match.hasMatchPackage)
                if match.activePeriodID != nil {
                    Label("Hold to end period", systemImage: "stop.fill")
                        .font(.caption2.weight(.semibold)).foregroundStyle(.red)
                        .onLongPressGesture(minimumDuration: 1) { match.endCurrentPeriod(at: context.date) }
                }
                    HStack(spacing: 4) {
                        Text("\(match.status) · Queue \(match.pendingSyncCount)")
                            .font(.caption2).foregroundStyle(match.syncFailure == nil ? Color.secondary : Color.red).lineLimit(2)
                            .accessibilityIdentifier("watch.sync.status")
                        if match.pendingSyncCount > 0 || match.syncFailure != nil {
                            Button { match.retrySynchronization() } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(.plain).accessibilityLabel("Retry iPhone sync")
                        }
                    }
                    if let saveConfirmation = match.saveConfirmation {
                        Text(saveConfirmation)
                            .font(.caption2.weight(.semibold)).foregroundStyle(.green)
                            .accessibilityIdentifier("watch.save.confirmation")
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedAction != nil },
            set: { if !$0 { selectedAction = nil } }
        )) {
            if let selectedAction {
                switch selectedAction {
                case .goal(let matchClockMs): GoalActionView(matchClockMs: matchClockMs)
                case .foul(let matchClockMs): FoulActionView(matchClockMs: matchClockMs)
                case .card(let matchClockMs): CardActionView(matchClockMs: matchClockMs)
                case .more(let matchClockMs): MoreActionView(matchClockMs: matchClockMs)
                }
            }
        }
    }

    private func clock(_ milliseconds: Int64, regulationDurationMs: Int64) -> String {
        if milliseconds >= regulationDurationMs {
            let added = milliseconds - regulationDurationMs
            return "\(regulationDurationMs / 60_000)+\(String(format: "%02lld:%02lld", added / 60_000, (added / 1_000) % 60))"
        }
        return String(format: "%02lld:%02lld", milliseconds / 60_000, (milliseconds / 1_000) % 60)
    }

    private func actionLabel(_ title: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.headline.weight(.bold))
            Text(title).font(.caption2.weight(.bold))
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .foregroundStyle(.white)
        .background(tint.gradient, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

private struct GoalActionView: View {
    @EnvironmentObject private var match: WatchMatchStore
    @Environment(\.dismiss) private var dismiss
    let matchClockMs: Int64

    var body: some View {
        List {
            Section("Select scoring team") {
                Button("\(match.homeTeamName) GOAL") { match.saveGoal(side: "home", matchClockMs: matchClockMs); dismiss() }
                    .accessibilityIdentifier("watch.goal.home")
                    .tint(Color(hex: match.homeTeamColor))
                Button("\(match.awayTeamName) GOAL") { match.saveGoal(side: "away", matchClockMs: matchClockMs); dismiss() }
                    .accessibilityIdentifier("watch.goal.away")
                    .tint(Color(hex: match.awayTeamColor))
            }
        }
        .navigationTitle("Goal")
    }
}

private struct FoulActionView: View {
    @EnvironmentObject private var match: WatchMatchStore
    @Environment(\.dismiss) private var dismiss
    let matchClockMs: Int64

    var body: some View {
        List {
            Button("\(match.homeTeamName) FOUL") { match.saveFoul(side: "home", matchClockMs: matchClockMs); dismiss() }
                .accessibilityIdentifier("watch.foul.home")
            Button("\(match.awayTeamName) FOUL") { match.saveFoul(side: "away", matchClockMs: matchClockMs); dismiss() }
                .accessibilityIdentifier("watch.foul.away")
        }
        .navigationTitle("Foul")
    }
}

private struct CardActionView: View {
    @EnvironmentObject private var match: WatchMatchStore
    @Environment(\.dismiss) private var dismiss
    let matchClockMs: Int64

    var body: some View {
        List {
            Section("Yellow") {
                Button(match.homeTeamName) { match.saveCard(side: "home", colour: "yellow", matchClockMs: matchClockMs); dismiss() }
                Button(match.awayTeamName) { match.saveCard(side: "away", colour: "yellow", matchClockMs: matchClockMs); dismiss() }
            }
            Section("Direct red — hold") {
                Text(match.homeTeamName)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 1) { match.saveCard(side: "home", colour: "red", matchClockMs: matchClockMs); dismiss() }
                    .accessibilityIdentifier("watch.card.red.home")
                Text(match.awayTeamName)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 1) { match.saveCard(side: "away", colour: "red", matchClockMs: matchClockMs); dismiss() }
                    .accessibilityIdentifier("watch.card.red.away")
            }
        }
        .navigationTitle("Card")
    }
}

private struct MoreActionView: View {
    @EnvironmentObject private var match: WatchMatchStore
    let matchClockMs: Int64

    var body: some View {
        List {
            Section("Match events") {
                Button("HOME PENALTY") { match.savePenalty(side: "home", matchClockMs: matchClockMs) }
                Button("AWAY PENALTY") { match.savePenalty(side: "away", matchClockMs: matchClockMs) }
                Button("VAR REVIEW") { match.saveVAR(matchClockMs: matchClockMs) }
            }
            Section("Team action") {
                Button("HOME SUB") { match.saveSubstitution(side: "home", matchClockMs: matchClockMs) }
                Button("AWAY SUB") { match.saveSubstitution(side: "away", matchClockMs: matchClockMs) }
                Button("INJURY") { match.saveInjury(side: nil, matchClockMs: matchClockMs) }
            }
            Section("Interruption") {
                Button("SUSPEND") { match.saveSuspension(state: .started, reason: "match_interruption", matchClockMs: matchClockMs) }
                Button("RESUME") { match.saveSuspension(state: .resumed, reason: "match_interruption", matchClockMs: matchClockMs) }
                Button("DROPPED BALL") { match.saveRestart(type: .droppedBall, matchClockMs: matchClockMs) }
                Button("ADDED TIME") { match.saveStoppage(cause: "other", matchClockMs: matchClockMs) }
            }
        }
        .navigationTitle("More")
    }
}
