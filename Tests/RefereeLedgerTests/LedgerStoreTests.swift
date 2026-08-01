import Foundation
import Testing
@testable import RefereeLedger

struct LedgerStoreTests {
    private let matchID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let deviceID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    @Test func elevenAsideDraftCannotStartUntilMinimumFieldDataExists() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        try store.saveFixture(MatchFixture(matchID: matchID, competition: "KFA League", scheduledAt: .now,
                                           venueName: "Main pitch", homeTeamName: "Seoul", awayTeamName: "Busan"))

        let readiness = try store.fieldReadiness(matchID: matchID)

        #expect(!readiness.canStartMatch)
        #expect(readiness.blocking.map(\.id) == ["roster.home", "roster.away", "referee.accountable"])
    }

    @Test func completeElevenAsidePreparationIsStartable() throws {
        let store = try preparedElevenAsideStore(matchID: matchID, deviceID: deviceID)

        let readiness = try store.fieldReadiness(matchID: matchID)

        #expect(readiness.blocking.isEmpty)
        #expect(readiness.warnings.isEmpty)
        #expect(readiness.canStartMatch)
    }

    @Test func creationAtomicallyAllocatesSequenceAndOutbox() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let first = try store.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"home"}"#), peers: ["watch", "watch"])
        let second = try store.create(EventDraft(matchID: matchID, eventType: "foul_recorded", payloadJSON: #"{"teamSide":"away"}"#), peers: ["watch"])
        #expect(first.originSequence == 1); #expect(second.originSequence == 2)
        #expect(try store.eventCount() == 2); #expect(try store.outboxCount() == 2)
        try store.acknowledge(eventID: first.draft.eventID, integrityHash: first.integrityHash, peer: "watch")
        #expect(try store.pendingOutboxCount() == 1)
    }

    @Test func fixtureSnapshotPersistsWithItsMatchID() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let scheduled = Date(timeIntervalSince1970: 1_700_000_000)
        let fixture = MatchFixture(matchID: matchID, competition: "KFA Youth", scheduledAt: scheduled,
                                   venueName: "Main pitch", homeTeamName: "Seoul", awayTeamName: "Busan")
        try store.saveFixture(fixture)
        #expect(try store.fixture(matchID: matchID) == fixture)
    }

    @Test func teamKitColorsPersistAndTravelInWatchPackage() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let fixture = MatchFixture(matchID: matchID, competition: "KFA League", scheduledAt: Date(timeIntervalSince1970: 1_700_000_000),
                                   venueName: "Main pitch", homeTeamName: "Seoul", awayTeamName: "Busan",
                                   homeTeamColor: "#E53935", awayTeamColor: "#1565C0")
        try store.saveFixture(fixture)

        #expect(try store.fixture(matchID: matchID) == fixture)
        #expect(try store.matchPackage(matchID: matchID)?.fixture == fixture)
    }

    @Test func incompletePreparationAndChecklistPersistAcrossRestart() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("referee-setup-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        let player = MatchParticipantSnapshot(id: UUID(), teamSide: "home", role: "player",
                                              displayName: "Home 7", shirtNumber: 7)
        let checklist = PreMatchChecklist(pitchChecked: true, equipmentChecked: true,
                                          crewChecked: false, lineupChecked: false,
                                          notes: "Away team sheet pending")
        do {
            let store = try LedgerStore(path: path, originDeviceID: deviceID)
            try store.saveParticipantDrafts([player], matchID: matchID)
            try store.savePreMatchChecklist(checklist, matchID: matchID)
        }
        let restarted = try LedgerStore(path: path, originDeviceID: deviceID)
        #expect(try restarted.participants(matchID: matchID) == [player])
        #expect(try restarted.preMatchChecklist(matchID: matchID) == checklist)
        #expect(try restarted.preMatchChecklist(matchID: matchID).completedCount == 2)
        #expect(!checklist.isComplete)
    }

    @Test func committedWatchActionSurvivesStoreRestartWithSequenceAndOutbox() throws {
        let path = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("referee-ledger-\(UUID().uuidString).sqlite").path
        defer { try? FileManager.default.removeItem(atPath: path) }
        do {
            let watchStore = try LedgerStore(path: path, originDeviceID: deviceID)
            let saved = try watchStore.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"home"}"#), peers: ["iphone"])
            #expect(saved.originSequence == 1)
        }
        let restartedStore = try LedgerStore(path: path, originDeviceID: deviceID)
        let next = try restartedStore.create(EventDraft(matchID: matchID, eventType: "foul_recorded", payloadJSON: #"{"teamSide":"away"}"#), peers: [])
        #expect(next.originSequence == 2)
        #expect(try restartedStore.eventCount() == 2)
        #expect(try restartedStore.outboxCount() == 1)
    }

    @Test func equivalentPayloadFormattingHasSameCanonicalHash() throws {
        let recorded = Date(timeIntervalSince1970: 1_700_000_000.123)
        let draft = EventDraft(eventID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!, matchID: matchID, eventType: "goal_recorded", recordedAt: recorded, payloadJSON: #"{ "b": 1, "teamSide": "home", "a": true }"#)
        let store = try LedgerStore(originDeviceID: deviceID)
        let saved = try store.create(draft, peers: [])
        #expect(saved.canonicalPayload == #"{"a":true,"b":1,"teamSide":"home"}"#)
        #expect(saved.integrityHash == "a1f95cd79ec29497c6026e2bd128b96811c1e4b92e5ace58005e8d1e8947dc9d")
    }

    @Test func projectionRebuildsScoreFromLedger() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        _ = try store.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        _ = try store.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"away"}"#), peers: [])
        _ = try store.create(EventDraft(matchID: matchID, eventType: "foul_recorded", payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        #expect(try store.projectionIsDirty(matchID: matchID))
        #expect(try store.rebuildProjection(matchID: matchID) == MatchProjection(homeScore: 1, awayScore: 1))
        #expect(try !store.projectionIsDirty(matchID: matchID))
    }

    @Test func identicalIncomingEventIsIdempotent() throws {
        let sender = try LedgerStore(originDeviceID: deviceID)
        let saved = try sender.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        let receiver = try LedgerStore(originDeviceID: UUID())
        let delivery = ReplicatedEvent(event: saved)
        let messageID = UUID(), peer = UUID()
        try receiver.receive(delivery, messageID: messageID, from: peer)
        try receiver.receive(delivery, messageID: messageID, from: peer)
        #expect(try receiver.eventCount() == 1)
        #expect(try receiver.quarantineCount() == 0)
    }

    @Test func receiveAdvancesCursorOnlyAfterMissingSequenceArrives() throws {
        let sender = try LedgerStore(originDeviceID: deviceID)
        let first = try sender.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        let second = try sender.create(EventDraft(matchID: matchID, eventType: "foul_recorded", payloadJSON: #"{"teamSide":"away"}"#), peers: [])
        let receiver = try LedgerStore(originDeviceID: UUID())
        let peer = UUID()
        try receiver.receive(ReplicatedEvent(event: second), messageID: UUID(), from: peer)
        #expect(try receiver.syncCursor(matchID: matchID, peerDeviceID: peer, originDeviceID: deviceID) == 0)
        try receiver.receive(ReplicatedEvent(event: first), messageID: UUID(), from: peer)
        #expect(try receiver.syncCursor(matchID: matchID, peerDeviceID: peer, originDeviceID: deviceID) == 2)
    }

    @Test func watermarksDriveMissingEventDeliveryAndAcknowledgement() throws {
        let phoneID = UUID(), watchID = UUID()
        let phone = try LedgerStore(originDeviceID: phoneID)
        let watch = try LedgerStore(originDeviceID: watchID)
        let fixture = MatchFixture(matchID: matchID, competition: "KFA Youth", scheduledAt: Date(timeIntervalSince1970: 1_700_000_000),
                                   venueName: "Main", homeTeamName: "Seoul", awayTeamName: "Busan")
        try phone.saveFixture(fixture)
        let goal = try phone.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"home"}"#), peers: ["watch"])
        let package = try #require(try phone.matchPackage(matchID: matchID))
        #expect(package.fixture == fixture)
        #expect(package.originWatermarks[phoneID.uuidString.lowercased()] == 1)
        let missing = try phone.eventsMissing(from: try watch.originWatermarks(matchID: matchID), matchID: matchID)
        #expect(missing.count == 1)
        #expect(try watch.receive(missing[0], messageID: UUID(), from: phoneID) == .committed)
        try phone.acknowledge(eventID: goal.draft.eventID, integrityHash: goal.integrityHash, peer: "watch")
        #expect(try phone.pendingOutboxCount() == 0)
        #expect(try watch.rebuildProjection(matchID: matchID).homeScore == 1)
    }

    @Test func pairedStoresKeepDisconnectedActionsDurableAndQueued() throws {
        let phone = try LedgerStore(originDeviceID: UUID())
        let watch = try LedgerStore(originDeviceID: UUID())
        _ = try phone.create(EventDraft(matchID: matchID, eventType: "goal_recorded",
                                        payloadJSON: #"{"teamSide":"home"}"#), peers: ["watch"])
        _ = try watch.create(EventDraft(matchID: matchID, eventType: "foul_recorded",
                                        payloadJSON: #"{"teamSide":"away"}"#), peers: ["iphone"])

        #expect(try phone.pendingOutboxCount(matchID: matchID, peer: "watch") == 1)
        #expect(try watch.pendingOutboxCount(matchID: matchID, peer: "iphone") == 1)
        #expect(try phone.rebuildProjection(matchID: matchID).homeScore == 1)
        #expect(try watch.rebuildProjection(matchID: matchID).homeScore == 0)
    }

    @Test func pairedStoresRestartWithQueuesAndThenConverge() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("referee-paired-restart-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let phonePath = root.appendingPathComponent("phone.sqlite").path
        let watchPath = root.appendingPathComponent("watch.sqlite").path
        let phoneID = UUID(), watchID = UUID()
        do {
            let phone = try LedgerStore(path: phonePath, originDeviceID: phoneID)
            let watch = try LedgerStore(path: watchPath, originDeviceID: watchID)
            _ = try phone.create(EventDraft(matchID: matchID, eventType: "goal_recorded",
                                            payloadJSON: #"{"teamSide":"home"}"#), peers: ["watch"])
            _ = try watch.create(EventDraft(matchID: matchID, eventType: "card_recorded",
                                            payloadJSON: #"{"colour":"yellow","isDirectRed":false,"teamSide":"away"}"#), peers: ["iphone"])
        }

        let phone = try LedgerStore(path: phonePath, originDeviceID: phoneID)
        let watch = try LedgerStore(path: watchPath, originDeviceID: watchID)
        #expect(try phone.pendingOutboxCount(matchID: matchID, peer: "watch") == 1)
        #expect(try watch.pendingOutboxCount(matchID: matchID, peer: "iphone") == 1)
        try deliverPending(from: phone, to: watch, outboxPeer: "watch", senderID: phoneID)
        try deliverPending(from: watch, to: phone, outboxPeer: "iphone", senderID: watchID)
        try expectConvergence(phone, watch)
    }

    @Test func pairedStoresAcceptOutOfOrderDeliveryAndCloseTheCursorGap() throws {
        let phoneID = UUID()
        let phone = try LedgerStore(originDeviceID: phoneID)
        let watch = try LedgerStore(originDeviceID: UUID())
        _ = try phone.create(EventDraft(matchID: matchID, eventType: "goal_recorded",
                                        payloadJSON: #"{"teamSide":"home"}"#), peers: ["watch"])
        _ = try phone.create(EventDraft(matchID: matchID, eventType: "foul_recorded",
                                        payloadJSON: #"{"teamSide":"away"}"#), peers: ["watch"])
        let pending = try phone.pendingOutboxEvents(matchID: matchID, peer: "watch")

        #expect(try watch.receive(pending[1], messageID: UUID(), from: phoneID) == .committed)
        #expect(try watch.syncCursor(matchID: matchID, peerDeviceID: phoneID, originDeviceID: phoneID) == 0)
        #expect(try watch.receive(pending[0], messageID: UUID(), from: phoneID) == .committed)
        #expect(try watch.syncCursor(matchID: matchID, peerDeviceID: phoneID, originDeviceID: phoneID) == 2)
        for delivery in pending {
            try phone.acknowledge(eventID: delivery.event.draft.eventID,
                                  integrityHash: delivery.event.integrityHash, peer: "watch")
        }
        try expectConvergence(phone, watch)
    }

    @Test func pairedStoresTreatDuplicateReconnectDeliveryAsSuccess() throws {
        let phoneID = UUID()
        let phone = try LedgerStore(originDeviceID: phoneID)
        let watch = try LedgerStore(originDeviceID: UUID())
        let saved = try phone.create(EventDraft(matchID: matchID, eventType: "goal_recorded",
                                                payloadJSON: #"{"teamSide":"away"}"#), peers: ["watch"])
        let delivery = ReplicatedEvent(event: saved)
        let messageID = UUID()

        #expect(try watch.receive(delivery, messageID: messageID, from: phoneID) == .committed)
        #expect(try watch.receive(delivery, messageID: messageID, from: phoneID) == .alreadyCommitted)
        try phone.acknowledge(eventID: saved.draft.eventID, integrityHash: saved.integrityHash, peer: "watch")
        #expect(try watch.quarantineCount() == 0)
        try expectConvergence(phone, watch)
    }

    @Test func pairedStoresReconnectBidirectionallyToTheSameDigest() throws {
        let phoneID = UUID(), watchID = UUID()
        let phone = try LedgerStore(originDeviceID: phoneID)
        let watch = try LedgerStore(originDeviceID: watchID)
        _ = try phone.create(EventDraft(matchID: matchID, eventType: "goal_recorded",
                                        payloadJSON: #"{"teamSide":"home"}"#), peers: ["watch"])
        _ = try watch.create(EventDraft(matchID: matchID, eventType: "goal_recorded",
                                        payloadJSON: #"{"teamSide":"away"}"#), peers: ["iphone"])
        _ = try watch.create(EventDraft(matchID: matchID, eventType: "foul_recorded",
                                        payloadJSON: #"{"teamSide":"home"}"#), peers: ["iphone"])

        try deliverPending(from: watch, to: phone, outboxPeer: "iphone", senderID: watchID, duplicate: true)
        try deliverPending(from: phone, to: watch, outboxPeer: "watch", senderID: phoneID, duplicate: true)
        try expectConvergence(phone, watch)
        #expect(try phone.rebuildProjection(matchID: matchID) == MatchProjection(homeScore: 1, awayScore: 1))
        #expect(try watch.rebuildProjection(matchID: matchID) == MatchProjection(homeScore: 1, awayScore: 1))
    }

    @Test func fieldMvpReadinessAndOfflineWatchEventReachSignedMatchReport() throws {
        let phoneID = UUID(), watchID = UUID()
        let phone = try preparedElevenAsideStore(matchID: matchID, deviceID: phoneID)
        let watch = try LedgerStore(originDeviceID: watchID)
        #expect(try phone.fieldReadiness(matchID: matchID).canStartMatch)
        try watch.installMatchPackage(try #require(try phone.matchPackage(matchID: matchID)), from: phoneID)

        _ = try watch.create(EventDraft(matchID: matchID, eventType: "foul_recorded", matchClockMs: 600_000,
                                        payloadJSON: #"{"teamSide":"away"}"#), peers: ["iphone"])
        try deliverPending(from: watch, to: phone, outboxPeer: "iphone", senderID: watchID)
        #expect(try phone.timeline(matchID: matchID).contains { $0.eventType == "foul_recorded" })

        for definition in [MatchPeriodDefinition(kind: "first_half", ordinal: 1),
                           MatchPeriodDefinition(kind: "second_half", ordinal: 2)] {
            let periodID = UUID()
            _ = try phone.create(EventDraft(matchID: matchID, eventType: "period_started", matchPeriodID: periodID,
                                            matchClockMs: 0,
                                            payloadJSON: "{\"ordinal\":\(definition.ordinal),\"periodKind\":\"\(definition.kind)\"}"), peers: [])
            _ = try phone.create(EventDraft(matchID: matchID, eventType: "period_ended", matchPeriodID: periodID,
                                            matchClockMs: 2_700_000,
                                            payloadJSON: "{\"finalClockMs\":2700000,\"ordinal\":\(definition.ordinal),\"periodKind\":\"\(definition.kind)\"}"), peers: [])
        }
        let validation = try phone.validatePostMatch(matchID: matchID, confirmedScore: ConfirmedScore(home: 0, away: 0))
        #expect(validation.canSign)
        let report = try #require(try phone.reportDocuments(matchID: matchID).first { $0.kind == .match })
        let signed = try phone.signReport(matchID: matchID, kind: .match, documentID: report.id,
                                          confirmedScore: ConfirmedScore(home: 0, away: 0), declaration: "Reviewed")
        #expect(signed.status == .current)
    }

    @Test func fullAcceptancePathFromOfflineWatchToSignedExports() throws {
        let phoneID = UUID(), watchID = UUID()
        let phone = try LedgerStore(originDeviceID: phoneID)
        let watch = try LedgerStore(originDeviceID: watchID)
        let scorer = MatchParticipantSnapshot(id: UUID(), teamSide: "home", role: "player",
                                              displayName: "Home 9", shirtNumber: 9)
        let opponent = MatchParticipantSnapshot(id: UUID(), teamSide: "away", role: "player",
                                                displayName: "Away 10", shirtNumber: 10)
        let referee = MatchParticipantSnapshot(id: UUID(), role: "accountable_referee",
                                               displayName: "Referee Kim")
        try phone.saveFixture(MatchFixture(matchID: matchID, competition: "KFA League", scheduledAt: Date(),
                                           venueName: "Acceptance Ground", homeTeamName: "Seoul", awayTeamName: "Busan"))
        try phone.saveParticipants([scorer, opponent, referee], matchID: matchID)
        try phone.saveRules(MatchRuleSnapshot(), matchID: matchID)
        try phone.savePitchDimensions(PitchDimensions(lengthMetres: 105, widthMetres: 68), matchID: matchID)
        try watch.installMatchPackage(try #require(try phone.matchPackage(matchID: matchID)), from: phoneID)

        let firstPeriod = UUID()
        _ = try watch.create(EventDraft(matchID: matchID, eventType: "period_started", matchPeriodID: firstPeriod,
                                        matchClockMs: 0,
                                        payloadJSON: #"{"ordinal":1,"periodKind":"first_half"}"#), peers: ["iphone"])
        let goal = try watch.create(EventDraft(matchID: matchID, eventType: "goal_recorded", matchPeriodID: firstPeriod,
                                               matchClockMs: 612_000, payloadJSON: #"{"teamSide":"home"}"#), peers: ["iphone"])
        let foul = try watch.create(EventDraft(matchID: matchID, eventType: "foul_recorded", matchPeriodID: firstPeriod,
                                               matchClockMs: 725_000, payloadJSON: #"{"teamSide":"away"}"#), peers: ["iphone"])
        _ = try watch.create(EventDraft(matchID: matchID, eventType: "period_ended", matchPeriodID: firstPeriod,
                                        matchClockMs: 2_700_000,
                                        payloadJSON: #"{"finalClockMs":2700000,"ordinal":1,"periodKind":"first_half"}"#), peers: ["iphone"])
        #expect(try phone.eventCount() == 0)
        #expect(try watch.pendingOutboxCount(matchID: matchID, peer: "iphone") == 4)

        try deliverPending(from: watch, to: phone, outboxPeer: "iphone", senderID: watchID)
        #expect(try phone.rebuildProjection(matchID: matchID).homeScore == 1)
        _ = try phone.completeEventDetails(eventID: goal.draft.eventID,
                                           completion: EventDetailCompletion(participantID: scorer.id), peers: ["watch"])
        _ = try phone.addLocation(to: foul.draft.eventID, normalizedX: 64, normalizedY: 42,
                                  accuracy: .refereeConfirmed, peers: ["watch"])

        let secondPeriod = UUID()
        _ = try phone.create(EventDraft(matchID: matchID, eventType: "period_started", matchPeriodID: secondPeriod,
                                        matchClockMs: 0,
                                        payloadJSON: #"{"ordinal":2,"periodKind":"second_half"}"#), peers: ["watch"])
        _ = try phone.create(EventDraft(matchID: matchID, eventType: "period_ended", matchPeriodID: secondPeriod,
                                        matchClockMs: 2_700_000,
                                        payloadJSON: #"{"finalClockMs":2700000,"ordinal":2,"periodKind":"second_half"}"#), peers: ["watch"])
        try deliverPending(from: phone, to: watch, outboxPeer: "watch", senderID: phoneID)
        try expectConvergence(phone, watch)

        let score = ConfirmedScore(home: 1, away: 0)
        let validation = try phone.validatePostMatch(matchID: matchID, confirmedScore: score)
        #expect(validation.canSign)
        let report = try #require(try phone.reportDocuments(matchID: matchID).first { $0.kind == .match })
        let signed = try phone.signReport(matchID: matchID, kind: .match, documentID: report.id,
                                          confirmedScore: score, declaration: "Reviewed and confirmed")
        let snapshot = try phone.exportSnapshot(reportID: signed.id)
        #expect(snapshot.events.contains { $0.effectiveEventType == "goal_recorded" })
        #expect(snapshot.events.contains { $0.effectiveEventType == "location_added" })
        _ = try phone.recordExport(reportID: signed.id, format: .pdf, filePath: "/exports/acceptance.pdf",
                                   checksum: String(repeating: "a", count: 64))
        _ = try phone.recordExport(reportID: signed.id, format: .xlsx, filePath: "/exports/acceptance.xlsx",
                                   checksum: String(repeating: "b", count: 64))
        #expect(try phone.exportAudits(reportID: signed.id).count == 2)
    }

    private func deliverPending(from sender: LedgerStore, to receiver: LedgerStore,
                                outboxPeer: String, senderID: UUID, duplicate: Bool = false) throws {
        for delivery in try sender.pendingOutboxEvents(matchID: matchID, peer: outboxPeer) {
            let messageID = UUID()
            _ = try receiver.receive(delivery, messageID: messageID, from: senderID)
            if duplicate { #expect(try receiver.receive(delivery, messageID: messageID, from: senderID) == .alreadyCommitted) }
            try sender.acknowledge(eventID: delivery.event.draft.eventID,
                                   integrityHash: delivery.event.integrityHash, peer: outboxPeer)
        }
    }

    private func expectConvergence(_ first: LedgerStore, _ second: LedgerStore) throws {
        let firstWatermark = try first.syncWatermark(matchID: matchID)
        let secondWatermark = try second.syncWatermark(matchID: matchID)
        #expect(firstWatermark.originWatermarks == secondWatermark.originWatermarks)
        #expect(firstWatermark.eventDigest == secondWatermark.eventDigest)
        #expect(try first.pendingOutboxCount() == 0)
        #expect(try second.pendingOutboxCount() == 0)
    }

    @Test func matchPackagePersistsActiveContextForWatchRecovery() throws {
        let phoneID = UUID(), watchID = UUID()
        let phone = try LedgerStore(originDeviceID: phoneID)
        let watch = try LedgerStore(originDeviceID: watchID)
        let fixture = MatchFixture(matchID: matchID, competition: "KFA Youth", scheduledAt: Date(timeIntervalSince1970: 1_700_000_000),
                                   venueName: "Main", homeTeamName: "Seoul", awayTeamName: "Busan")
        try phone.saveFixture(fixture)
        let periodID = UUID()
        let package = try #require(try phone.matchPackage(matchID: matchID, periodID: periodID, periodLabel: "FIRST HALF", clockAnchorMs: 12_000))
        try watch.installMatchPackage(package, from: phoneID)
        let recovered = try #require(try watch.installedMatchPackage(matchID: matchID, from: phoneID))
        #expect(recovered.activeMatchID == matchID)
        #expect(recovered.projection.periodID == periodID)
        #expect(recovered.projection.periodLabel == "FIRST HALF")
        #expect(try watch.fixture(matchID: matchID) == fixture)
    }

    @Test func matchOwnedRosterPersistsAndTravelsInWatchPackage() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let fixture = MatchFixture(matchID: matchID, competition: "League", scheduledAt: Date(), venueName: "Ground",
                                   homeTeamName: "Home", awayTeamName: "Away")
        try store.saveFixture(fixture)
        let home = MatchParticipantSnapshot(id: UUID(), teamSide: "home", role: "player", displayName: "Home 9", shirtNumber: 9)
        let away = MatchParticipantSnapshot(id: UUID(), teamSide: "away", role: "player", displayName: "Away 10", shirtNumber: 10)
        let referee = MatchParticipantSnapshot(id: UUID(), role: "accountable_referee", displayName: "Referee Kim")
        try store.saveParticipants([home, away, referee], matchID: matchID)
        #expect(try store.participants(matchID: matchID) == [home, away, referee])
        #expect(try #require(try store.matchPackage(matchID: matchID)).roster == [home, away, referee])
    }

    @Test func rosterRequiresBothTeamsAndOneAccountableReferee() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let home = MatchParticipantSnapshot(id: UUID(), teamSide: "home", role: "player", displayName: "Home 9", shirtNumber: 9)
        let referee = MatchParticipantSnapshot(id: UUID(), role: "accountable_referee", displayName: "Referee")
        #expect(throws: LedgerError.invalidDraft("roster requires valid players and exactly one accountable referee")) {
            try store.saveParticipants([home, referee], matchID: matchID)
        }
    }

    @Test func goalDetailsAppendCorrectionWithoutMutatingOriginal() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let player = MatchParticipantSnapshot(id: UUID(), teamSide: "home", role: "player", displayName: "Striker", shirtNumber: 9)
        let opponent = MatchParticipantSnapshot(id: UUID(), teamSide: "away", role: "player", displayName: "Opponent", shirtNumber: 1)
        let referee = MatchParticipantSnapshot(id: UUID(), role: "accountable_referee", displayName: "Referee")
        try store.saveParticipants([player, opponent, referee], matchID: matchID)
        let goal = try store.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        _ = try store.completeEventDetails(eventID: goal.draft.eventID,
                                           completion: EventDetailCompletion(participantID: player.id), peers: [])
        let timeline = try store.timeline(matchID: matchID)
        #expect(try store.eventCount() == 2)
        #expect(timeline[1].payloadJSON == #"{"teamSide":"home"}"#)
        #expect(!timeline[1].isActive)
        #expect(timeline[0].payloadJSON.contains("participantDisplayName"))
        #expect(try store.rebuildProjection(matchID: matchID).homeScore == 1)
    }

    @Test func directRedCompletionRequiresReasonAndIncidentNarrative() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let player = MatchParticipantSnapshot(id: UUID(), teamSide: "away", role: "player", displayName: "Away 4", shirtNumber: 4)
        let opponent = MatchParticipantSnapshot(id: UUID(), teamSide: "home", role: "player", displayName: "Home 1", shirtNumber: 1)
        let referee = MatchParticipantSnapshot(id: UUID(), role: "accountable_referee", displayName: "Referee")
        try store.saveParticipants([player, opponent, referee], matchID: matchID)
        let card = try store.create(EventDraft(matchID: matchID, eventType: "card_recorded",
                                                payloadJSON: #"{"colour":"red","isDirectRed":true,"teamSide":"away"}"#), peers: [])
        #expect(throws: LedgerError.invalidDraft("cards require a disciplinary reason")) {
            try store.completeEventDetails(eventID: card.draft.eventID,
                                           completion: EventDetailCompletion(participantID: player.id), peers: [])
        }
        #expect(throws: LedgerError.invalidDraft("direct red cards require an incident narrative")) {
            try store.completeEventDetails(eventID: card.draft.eventID,
                                           completion: EventDetailCompletion(participantID: player.id, disciplinaryReason: "Violent conduct"), peers: [])
        }
        let completed = try store.completeEventDetails(eventID: card.draft.eventID,
                                                       completion: EventDetailCompletion(participantID: player.id,
                                                                                         disciplinaryReason: "Violent conduct",
                                                                                         incidentNarrative: "Struck an opponent away from the ball."), peers: [])
        #expect(completed.canonicalPayload.contains("requiresIncidentReport"))
        #expect(completed.canonicalPayload.contains("incidentNarrative"))
    }

    @Test func pendingOutboxIsAvailableForRetryUntilAcknowledged() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let saved = try store.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"home"}"#), peers: ["watch"])
        #expect(try store.pendingOutboxEvents(matchID: matchID, peer: "watch").map(\.event.draft.eventID) == [saved.draft.eventID])
        #expect(try store.pendingOutboxCount(matchID: matchID, peer: "watch") == 1)
        try store.acknowledge(eventID: saved.draft.eventID, integrityHash: saved.integrityHash, peer: "watch")
        #expect(try store.pendingOutboxEvents(matchID: matchID, peer: "watch").isEmpty)
        #expect(try store.pendingOutboxCount(matchID: matchID, peer: "watch") == 0)
    }

    @Test func watchOperationalActionsRemainDurableAndDoNotChangeScore() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let periodID = UUID()
        _ = try store.create(EventDraft(matchID: matchID, eventType: "period_started", matchPeriodID: periodID,
                                        matchClockMs: 0, payloadJSON: #"{"ordinal":1,"periodKind":"first_half"}"#), peers: ["iphone"])
        _ = try store.create(EventDraft(matchID: matchID, eventType: "foul_recorded", matchPeriodID: periodID,
                                        matchClockMs: 24_000, payloadJSON: #"{"teamSide":"home"}"#), peers: ["iphone"])
        _ = try store.create(EventDraft(matchID: matchID, eventType: "card_recorded", matchPeriodID: periodID,
                                        matchClockMs: 25_000, payloadJSON: #"{"colour":"red","isDirectRed":true,"teamSide":"away"}"#), peers: ["iphone"])
        #expect(try store.eventCount() == 3)
        #expect(try store.pendingOutboxCount() == 3)
        #expect(try store.rebuildProjection(matchID: matchID) == MatchProjection(homeScore: 0, awayScore: 0))
    }

    @Test func activePeriodContextAndPackageAreDerivedFromBoundaryEvents() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let fixture = MatchFixture(matchID: matchID, competition: "KFA Youth", scheduledAt: Date(timeIntervalSince1970: 1_700_000_000),
                                   venueName: "Main", homeTeamName: "Seoul", awayTeamName: "Busan")
        try store.saveFixture(fixture)
        let periodID = UUID(), startedAt = Date(timeIntervalSince1970: 1_700_000_100)
        _ = try store.create(EventDraft(matchID: matchID, eventType: "period_started", recordedAt: startedAt,
                                        matchPeriodID: periodID, matchClockMs: 0,
                                        payloadJSON: #"{"ordinal":1,"periodKind":"first_half"}"#), peers: [])
        let context = try #require(try store.activePeriodContext(matchID: matchID))
        #expect(context.periodID == periodID)
        #expect(context.label == "FIRST HALF")
        #expect(context.startedAt == startedAt)
        let package = try #require(try store.matchPackage(matchID: matchID))
        #expect(package.projection.periodID == periodID)
        #expect(package.projection.periodLabel == "FIRST HALF")
        _ = try store.create(EventDraft(matchID: matchID, eventType: "period_ended", matchPeriodID: periodID,
                                        matchClockMs: 2_700_000,
                                        payloadJSON: #"{"finalClockMs":2700000,"ordinal":1,"periodKind":"first_half"}"#), peers: [])
        #expect(try store.activePeriodContext(matchID: matchID) == nil)
    }

    @Test func periodStateMachineRequiresOrderedBoundariesAndCompletesMatch() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let first = MatchPeriodDefinition(kind: "first_half", ordinal: 1)
        let second = MatchPeriodDefinition(kind: "second_half", ordinal: 2)
        #expect(try store.periodState(matchID: matchID).next == first)
        #expect(throws: LedgerError.invalidDraft("period start is not the next permitted transition")) {
            try store.create(EventDraft(matchID: matchID, eventType: "period_started", matchPeriodID: UUID(),
                                        payloadJSON: #"{"ordinal":2,"periodKind":"second_half"}"#), peers: [])
        }
        let firstID = UUID()
        _ = try store.create(EventDraft(matchID: matchID, eventType: "period_started", matchPeriodID: firstID,
                                        payloadJSON: #"{"ordinal":1,"periodKind":"first_half"}"#), peers: [])
        #expect(throws: LedgerError.invalidDraft("period start is not the next permitted transition")) {
            try store.create(EventDraft(matchID: matchID, eventType: "period_started", matchPeriodID: UUID(),
                                        payloadJSON: #"{"ordinal":2,"periodKind":"second_half"}"#), peers: [])
        }
        _ = try store.create(EventDraft(matchID: matchID, eventType: "period_ended", matchPeriodID: firstID,
                                        payloadJSON: #"{"finalClockMs":2700000,"ordinal":1,"periodKind":"first_half"}"#), peers: [])
        #expect(try store.periodState(matchID: matchID).next == second)
        let secondID = UUID()
        _ = try store.create(EventDraft(matchID: matchID, eventType: "period_started", matchPeriodID: secondID,
                                        payloadJSON: #"{"ordinal":2,"periodKind":"second_half"}"#), peers: [])
        _ = try store.create(EventDraft(matchID: matchID, eventType: "period_ended", matchPeriodID: secondID,
                                        payloadJSON: #"{"finalClockMs":2700000,"ordinal":2,"periodKind":"second_half"}"#), peers: [])
        let complete = try store.periodState(matchID: matchID)
        #expect(complete.isComplete); #expect(complete.displayLabel == "FULL TIME")
    }

    @Test func extraTimeRulesExtendThePermittedPeriodSequence() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        try store.saveRules(MatchRuleSnapshot(extraTimeEnabled: true), matchID: matchID)
        for definition in [MatchPeriodDefinition(kind: "first_half", ordinal: 1), MatchPeriodDefinition(kind: "second_half", ordinal: 2)] {
            let id = UUID()
            _ = try store.create(EventDraft(matchID: matchID, eventType: "period_started", matchPeriodID: id,
                                            payloadJSON: "{\"ordinal\":\(definition.ordinal),\"periodKind\":\"\(definition.kind)\"}"), peers: [])
            _ = try store.create(EventDraft(matchID: matchID, eventType: "period_ended", matchPeriodID: id,
                                            payloadJSON: "{\"finalClockMs\":1,\"ordinal\":\(definition.ordinal),\"periodKind\":\"\(definition.kind)\"}"), peers: [])
        }
        #expect(try store.periodState(matchID: matchID).next == MatchPeriodDefinition(kind: "extra_time_first_half", ordinal: 3))
    }

    @Test func operationalPayloadValidationRejectsInvalidCaptureData() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        #expect(throws: LedgerError.invalidDraft("goals and fouls require a home or away team")) {
            try store.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"neutral"}"#), peers: [])
        }
        #expect(throws: LedgerError.invalidDraft("cards require team, yellow or red colour, and direct-red state")) {
            try store.create(EventDraft(matchID: matchID, eventType: "card_recorded", payloadJSON: #"{"colour":"blue","teamSide":"home"}"#), peers: [])
        }
        #expect(throws: LedgerError.invalidDraft("period start requires period ID, kind, and ordinal")) {
            try store.create(EventDraft(matchID: matchID, eventType: "period_started", payloadJSON: #"{"ordinal":1,"periodKind":"first_half"}"#), peers: [])
        }
        #expect(throws: LedgerError.invalidDraft("match clock cannot be negative")) {
            try store.create(EventDraft(matchID: matchID, eventType: "foul_recorded", matchClockMs: -1,
                                        payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        }
    }

    @Test func conflictingIncomingEventIsQuarantinedWithoutOverwrite() throws {
        let sender = try LedgerStore(originDeviceID: deviceID)
        let saved = try sender.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        let receiver = try LedgerStore(originDeviceID: UUID())
        try receiver.receive(ReplicatedEvent(event: saved), messageID: UUID(), from: UUID())
        let altered = LedgerEvent(draft: saved.draft, originDeviceID: saved.originDeviceID, originSequence: saved.originSequence, canonicalPayload: #"{"teamSide":"away"}"#, integrityHash: saved.integrityHash)
        try receiver.receive(ReplicatedEvent(event: altered), messageID: UUID(), from: UUID())
        #expect(try receiver.eventCount() == 1)
        #expect(try receiver.quarantineCount() == 1)
    }

    @Test func reusedMessageIDCannotCommitAnotherEvent() throws {
        let sender = try LedgerStore(originDeviceID: deviceID)
        let first = try sender.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        let second = try sender.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"away"}"#), peers: [])
        let receiver = try LedgerStore(originDeviceID: UUID())
        let messageID = UUID(), peer = UUID()
        try receiver.receive(ReplicatedEvent(event: first), messageID: messageID, from: peer)
        try receiver.receive(ReplicatedEvent(event: second), messageID: messageID, from: peer)
        #expect(try receiver.eventCount() == 1)
        #expect(try receiver.quarantineCount() == 1)
    }

    @Test func conflictingOriginSequenceIsQuarantined() throws {
        let sender = try LedgerStore(originDeviceID: deviceID)
        let saved = try sender.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        let receiver = try LedgerStore(originDeviceID: UUID())
        try receiver.receive(ReplicatedEvent(event: saved), messageID: UUID(), from: UUID())
        let anotherDraft = EventDraft(matchID: matchID, eventType: "goal_recorded", recordedAt: saved.draft.recordedAt, payloadJSON: #"{"teamSide":"away"}"#)
        let payload = try CanonicalJSON.canonicalize(anotherDraft.payloadJSON)
        let collision = LedgerEvent(draft: anotherDraft, originDeviceID: saved.originDeviceID, originSequence: saved.originSequence, canonicalPayload: payload, integrityHash: EventIntegrity.hash(draft: anotherDraft, deviceID: saved.originDeviceID, sequence: saved.originSequence, payload: payload))
        try receiver.receive(ReplicatedEvent(event: collision), messageID: UUID(), from: UUID())
        #expect(try receiver.eventCount() == 1)
        #expect(try receiver.quarantineCount() == 1)
    }

    @Test func reversalPreservesLedgerButExcludesGoalFromProjection() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let goal = try store.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        _ = try store.create(EventDraft(matchID: matchID, eventType: "event_reversed", supersedesEventID: goal.draft.eventID, payloadJSON: #"{"reason":"duplicate entry"}"#), peers: [])
        #expect(try store.eventCount() == 2)
        #expect(try store.rebuildProjection(matchID: matchID) == MatchProjection(homeScore: 0, awayScore: 0))
    }

    @Test func reversalWithoutReasonIsRejected() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        #expect(throws: LedgerError.invalidDraft("corrections and reversals require a target and reason")) {
            try store.create(EventDraft(matchID: matchID, eventType: "event_reversed", supersedesEventID: UUID(), payloadJSON: #"{}"#), peers: [])
        }
    }

    @Test func correctionReplacesOriginalInterpretationInProjection() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let goal = try store.create(EventDraft(matchID: matchID, eventType: "goal_recorded", payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        _ = try store.create(EventDraft(matchID: matchID, eventType: "event_corrected", supersedesEventID: goal.draft.eventID, payloadJSON: #"{"reason":"own goal correction","replacementEventType":"goal_recorded","replacementPayload":{"teamSide":"away"}}"#), peers: [])
        #expect(try store.eventCount() == 2)
        #expect(try store.rebuildProjection(matchID: matchID) == MatchProjection(homeScore: 0, awayScore: 1))
    }

    @Test func timelineRetainsOriginalAndMarksItInactiveAfterRevision() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let periodID = UUID()
        let goal = try store.create(EventDraft(matchID: matchID, eventType: "goal_recorded",
                                                matchPeriodID: periodID, matchClockMs: 123_000,
                                                payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        let correction = try store.create(EventDraft(matchID: matchID, eventType: "event_corrected",
                                                      matchPeriodID: periodID, matchClockMs: 123_000,
                                                      supersedesEventID: goal.draft.eventID,
                                                      payloadJSON: #"{"reason":"wrong team","replacementEventType":"goal_recorded","replacementPayload":{"teamSide":"away"}}"#), peers: [])
        let timeline = try store.timeline(matchID: matchID)
        #expect(timeline.map(\.eventID) == [correction.draft.eventID, goal.draft.eventID])
        #expect(timeline[0].isActive && timeline[0].isRevision)
        #expect(!timeline[1].isActive && timeline[1].canRevise == false)
        #expect(timeline[0].matchPeriodID == periodID)
        #expect(timeline[0].matchClockMs == 123_000)
    }

    @Test func missingRevisionTargetCreatesBlockingIssueAndDoesNotProjectCorrection() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        _ = try store.create(EventDraft(matchID: matchID, eventType: "event_corrected", supersedesEventID: UUID(), payloadJSON: #"{"reason":"late import","replacementEventType":"goal_recorded","replacementPayload":{"teamSide":"home"}}"#), peers: [])
        let projection = try store.rebuildProjection(matchID: matchID)
        #expect(projection == MatchProjection(homeScore: 0, awayScore: 0, issues: [ProjectionIssue(code: "missing_revision_target", eventID: projection.issues[0].eventID)]))
    }

    @Test func postMatchValidationDerivesBlockingReviewItems() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let result = try store.validatePostMatch(matchID: matchID, confirmedScore: nil)
        #expect(!result.canSign)
        #expect(Set(result.blockingIssues.map(\.code)).isSuperset(of: [
            "fixture_missing", "match_not_complete", "score_not_confirmed", "accountable_referee_missing"
        ]))
    }

    @Test func completedMatchCanBeSignedAndLaterEventSupersedesFrozenVersion() throws {
        let store = try completedMatchStore()
        let signed = try store.signReport(matchID: matchID, kind: .match,
                                          confirmedScore: ConfirmedScore(home: 0, away: 0),
                                          declaration: "I confirm this report is accurate.")
        #expect(signed.version == 1)
        #expect(signed.status == .current)
        #expect(try store.signedReports(matchID: matchID, kind: .match).first?.status == .current)

        _ = try store.create(EventDraft(matchID: matchID, eventType: "foul_recorded",
                                        payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        let historical = try #require(try store.signedReports(matchID: matchID, kind: .match).first)
        #expect(historical.status == .superseded)
        #expect(historical.eventIDs == signed.eventIDs)
    }

    @Test func reportProseCreatesIndependentContentVersionsAndSupersedesSignature() throws {
        let store = try completedMatchStore()
        #expect(try store.saveReportContent(matchID: matchID, kind: .referee,
                                            proseJSON: #"{"operationalNotes":"None"}"#) == 1)
        _ = try store.signReport(matchID: matchID, kind: .referee,
                                 confirmedScore: ConfirmedScore(home: 0, away: 0),
                                 declaration: "Reviewed and confirmed.")
        #expect(try store.signedReports(matchID: matchID, kind: .referee).first?.status == .current)
        #expect(try store.saveReportContent(matchID: matchID, kind: .referee,
                                            proseJSON: #"{"operationalNotes":"Pitch inspection completed"}"#) == 2)
        #expect(try store.signedReports(matchID: matchID, kind: .referee).first?.status == .superseded)
    }

    @Test func exportSnapshotUsesFrozenSigningInputsAndEffectiveEventRows() throws {
        let store = try completedMatchStore()
        let goal = try store.create(EventDraft(matchID: matchID, eventType: "goal_recorded",
                                                matchClockMs: 12_000,
                                                payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        _ = try store.create(EventDraft(matchID: matchID, eventType: "event_corrected",
                                        matchClockMs: 12_000, supersedesEventID: goal.draft.eventID,
                                        payloadJSON: #"{"reason":"wrong team","replacementEventType":"goal_recorded","replacementPayload":{"teamSide":"away"}}"#), peers: [])
        let signed = try store.signReport(matchID: matchID, kind: .match,
                                          confirmedScore: ConfirmedScore(home: 0, away: 1),
                                          declaration: "Confirmed")
        try store.saveFixture(MatchFixture(matchID: matchID, competition: "Changed", scheduledAt: Date(),
                                           venueName: "Another ground", homeTeamName: "New Home", awayTeamName: "New Away"))
        _ = try store.create(EventDraft(matchID: matchID, eventType: "foul_recorded",
                                        payloadJSON: #"{"teamSide":"home"}"#), peers: [])

        let snapshot = try store.exportSnapshot(reportID: signed.id)
        #expect(snapshot.fixture.competition == "League")
        #expect(snapshot.report.status == .superseded)
        #expect(!snapshot.events.contains { $0.effectiveEventType == "foul_recorded" })
        let exportedGoal = try #require(snapshot.events.first { $0.effectiveEventType == "goal_recorded" })
        #expect(exportedGoal.sourceEventType == "event_corrected")
        #expect(exportedGoal.revisionOfEventID == goal.draft.eventID)
        #expect(exportedGoal.payloadJSON == #"{"teamSide":"away"}"#)
    }

    @Test func successfulExportsAppendImmutableAuditRows() throws {
        let store = try completedMatchStore()
        let signed = try store.signReport(matchID: matchID, kind: .match,
                                          confirmedScore: ConfirmedScore(home: 0, away: 0),
                                          declaration: "Confirmed")
        let checksum = String(repeating: "a", count: 64)
        let first = try store.recordExport(reportID: signed.id, format: .pdf,
                                           filePath: "/exports/report.pdf", checksum: checksum)
        let second = try store.recordExport(reportID: signed.id, format: .xlsx,
                                            filePath: "/exports/report.xlsx", checksum: String(repeating: "b", count: 64))
        let audits = try store.exportAudits(reportID: signed.id)
        #expect(audits.count == 2)
        #expect(Set(audits.map(\.id)) == [first.id, second.id])
        #expect(audits.allSatisfy { $0.statusLabel == "SIGNED — CURRENT" })
        #expect(throws: LedgerError.invalidDraft("export requires a file path and SHA-256 checksum")) {
            try store.recordExport(reportID: signed.id, format: .pdf, filePath: "", checksum: "bad")
        }
    }

    @Test func qualifyingEventsCreateStableIndependentIncidentReports() throws {
        let store = try completedMatchStore()
        let first = try store.create(EventDraft(matchID: matchID, eventType: "card_recorded",
                                                payloadJSON: #"{"colour":"red","disciplinaryReason":"Violent conduct","incidentNarrative":"Struck an opponent.","isDirectRed":true,"participantId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","requiresIncidentReport":true,"teamSide":"away"}"#), peers: [])
        let second = try store.create(EventDraft(matchID: matchID, eventType: "card_recorded",
                                                 payloadJSON: #"{"colour":"red","disciplinaryReason":"Serious foul play","incidentNarrative":"Used excessive force.","isDirectRed":true,"participantId":"bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb","requiresIncidentReport":true,"teamSide":"home"}"#), peers: [])
        let incidents = try store.reportDocuments(matchID: matchID).filter { $0.kind == .incident }
        #expect(incidents.count == 2)
        #expect(Set(incidents.compactMap(\.primaryEventID)) == [first.draft.eventID, second.draft.eventID])
        #expect(Set(try store.reportDocuments(matchID: matchID).filter { $0.kind == .incident }.map(\.id)) == Set(incidents.map(\.id)))
        #expect(incidents.allSatisfy { $0.contentVersion == 1 && !$0.content.description.isEmpty })
    }

    @Test func editingOneIncidentSupersedesOnlyItsSignedDocument() throws {
        let store = try completedMatchStore()
        _ = try store.create(EventDraft(matchID: matchID, eventType: "card_recorded",
                                        payloadJSON: #"{"colour":"red","disciplinaryReason":"Violent conduct","incidentNarrative":"Initial account.","isDirectRed":true,"participantId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","requiresIncidentReport":true,"teamSide":"away"}"#), peers: [])
        let incident = try #require(try store.reportDocuments(matchID: matchID).first { $0.kind == .incident })
        let signed = try store.signReport(matchID: matchID, kind: .incident, documentID: incident.id,
                                          confirmedScore: ConfirmedScore(home: 0, away: 0), declaration: "Confirmed")
        #expect(signed.documentID == incident.id)
        #expect(signed.eventIDs == incident.linkedEventIDs)
        _ = try store.create(EventDraft(matchID: matchID, eventType: "foul_recorded",
                                        payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        #expect(try store.signedReports(matchID: matchID, kind: .incident).first?.status == .current)
        _ = try store.saveReportContent(documentID: incident.id,
                                        content: StructuredReportContent(summary: "Updated", description: "Expanded account.",
                                                                         actionTaken: "Sent off", additionalNotes: ""))
        #expect(try store.signedReports(matchID: matchID, kind: .incident).first?.status == .superseded)
    }

    @Test func incompleteDirectRedBlocksSignOffWithDetailSpecificIssues() throws {
        let store = try completedMatchStore()
        let card = try store.create(EventDraft(matchID: matchID, eventType: "card_recorded",
                                                payloadJSON: #"{"colour":"red","isDirectRed":true,"teamSide":"away"}"#), peers: [])
        let result = try store.validatePostMatch(matchID: matchID, confirmedScore: ConfirmedScore(home: 0, away: 0))
        let eventIssues = result.blockingIssues.filter { $0.eventID == card.draft.eventID }.map(\.code)
        #expect(Set(eventIssues) == ["card_player_missing", "card_reason_missing", "direct_red_narrative_missing"])
    }

    @Test func attachmentBytesAreHashedFrozenAndSupersedeSignedDocument() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try completedMatchStore(attachmentRoot: root)
        let document = try #require(try store.reportDocuments(matchID: matchID).first { $0.kind == .match })
        let bytes = Data("immutable evidence".utf8)
        let attachment = try store.addAttachment(documentID: document.id, data: bytes,
                                                 mediaType: "text/plain", originalFilename: "evidence.txt",
                                                 isRequired: true)
        #expect(attachment.byteCount == bytes.count)
        #expect(attachment.checksum.count == 64)
        #expect(try store.attachments(documentID: document.id).first?.isReadable == true)

        let signed = try store.signReport(matchID: matchID, kind: .match, documentID: document.id,
                                          confirmedScore: ConfirmedScore(home: 0, away: 0), declaration: "Confirmed")
        let snapshot = try store.exportSnapshot(reportID: signed.id)
        #expect(snapshot.attachments == [attachment])

        _ = try store.addAttachment(documentID: document.id, data: Data("later".utf8),
                                    mediaType: "text/plain", originalFilename: "later.txt")
        #expect(try store.signedReports(matchID: matchID, kind: .match).first?.status == .superseded)
        #expect(try store.exportSnapshot(reportID: signed.id).attachments == [attachment])
    }

    @Test func unreadableRequiredAttachmentBlocksSignOff() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try completedMatchStore(attachmentRoot: root)
        let document = try #require(try store.reportDocuments(matchID: matchID).first { $0.kind == .match })
        let attachment = try store.addAttachment(documentID: document.id, data: Data("required".utf8),
                                                 mediaType: "text/plain", originalFilename: "required.txt",
                                                 isRequired: true)
        try FileManager.default.removeItem(at: root.appendingPathComponent(attachment.relativePath))
        #expect(try store.attachments(documentID: document.id).first?.isReadable == false)
        #expect(throws: LedgerError.invalidDraft("report has blocking validation issues")) {
            try store.signReport(matchID: matchID, kind: .match, documentID: document.id,
                                 confirmedScore: ConfirmedScore(home: 0, away: 0), declaration: "Confirmed")
        }
    }

    @Test func attachmentTransferIsResumableAndAcknowledgedIndependentlyFromEvents() throws {
        let senderRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let receiverRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let receiverDatabase = receiverRoot.appendingPathComponent("receiver.sqlite")
        try FileManager.default.createDirectory(at: receiverRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: senderRoot)
            try? FileManager.default.removeItem(at: receiverRoot)
        }
        let sender = try completedMatchStore(attachmentRoot: senderRoot)
        let document = try #require(try sender.reportDocuments(matchID: matchID).first { $0.kind == .match })
        let event = try sender.create(EventDraft(matchID: matchID, eventType: "foul_recorded",
                                                 payloadJSON: #"{"teamSide":"home"}"#), peers: ["backup"])
        let bytes = Data("a resumable attachment payload".utf8)
        let attachment = try sender.addAttachment(documentID: document.id, data: bytes,
                                                  mediaType: "text/plain", originalFilename: "evidence.txt",
                                                  peers: ["backup"])
        #expect(try sender.pendingAttachmentManifests(matchID: matchID, peer: "backup").count == 1)

        let firstChunk = try #require(try sender.nextAttachmentChunk(attachmentID: attachment.id, peer: "backup", maximumBytes: 7))
        let firstAcknowledgement: AttachmentTransferAcknowledgement
        do {
            let receiver = try LedgerStore(path: receiverDatabase.path, originDeviceID: UUID(), attachmentRoot: receiverRoot)
            firstAcknowledgement = try receiver.receiveAttachmentChunk(firstChunk, from: "phone")
            #expect(firstAcknowledgement.nextOffset == 7)
            #expect(!firstAcknowledgement.isComplete)
        }
        try sender.acknowledgeAttachment(firstAcknowledgement, peer: "backup")

        let restartedReceiver = try LedgerStore(path: receiverDatabase.path, originDeviceID: UUID(), attachmentRoot: receiverRoot)
        #expect(try restartedReceiver.attachmentTransfer(attachmentID: attachment.id, peer: "phone", direction: .incoming)?.bytesConfirmed == 7)
        while let chunk = try sender.nextAttachmentChunk(attachmentID: attachment.id, peer: "backup", maximumBytes: 6) {
            let acknowledgement = try restartedReceiver.receiveAttachmentChunk(chunk, from: "phone")
            try sender.acknowledgeAttachment(acknowledgement, peer: "backup")
        }
        #expect(try restartedReceiver.attachments(documentID: document.id).first?.isReadable == true)
        #expect(try restartedReceiver.attachments(documentID: document.id).first?.checksum == attachment.checksum)
        #expect(try sender.attachmentTransfer(attachmentID: attachment.id, peer: "backup", direction: .outgoing)?.state == .completed)
        #expect(try sender.pendingAttachmentManifests(matchID: matchID, peer: "backup").isEmpty)

        // Event acknowledgement changes only the event row. Attachment delivery
        // has already followed its own checksum acknowledgement path.
        try sender.acknowledge(eventID: event.draft.eventID, integrityHash: event.integrityHash, peer: "backup")
        #expect(try sender.pendingOutboxCount(matchID: matchID, peer: "backup") == 0)
    }

    @Test func corruptReceivedAttachmentIsRejectedAndSurfacedAsFailed() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let receiver = try LedgerStore(originDeviceID: UUID(), attachmentRoot: root)
        let manifest = AttachmentManifest(attachmentID: UUID(), matchID: matchID, documentID: UUID(),
                                          mediaType: "text/plain", originalFilename: "proof.txt",
                                          byteCount: 7, checksum: String(repeating: "0", count: 64),
                                          createdAt: Date(), isRequired: false)
        #expect(throws: LedgerError.integrityConflict(manifest.attachmentID)) {
            try receiver.receiveAttachmentChunk(AttachmentChunk(manifest: manifest, offset: 0,
                                                                 bytes: Data("corrupt".utf8)), from: "peer")
        }
        let transfer = try #require(try receiver.attachmentTransfer(attachmentID: manifest.attachmentID,
                                                                   peer: "peer", direction: .incoming))
        #expect(transfer.state == .failed)
        #expect(transfer.bytesConfirmed == 0)
        #expect(transfer.error != nil)
    }

    @Test func startupRemovesOnlyUnreferencedAttachmentStagingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let staging = root.appendingPathComponent("Staging", isDirectory: true)
        let orphan = staging.appendingPathComponent("orphan.part")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        try Data("uncommitted".utf8).write(to: orphan)
        #expect(FileManager.default.fileExists(atPath: orphan.path))
        _ = try LedgerStore(originDeviceID: UUID(), attachmentRoot: root)
        #expect(!FileManager.default.fileExists(atPath: orphan.path))
    }

    @Test func pitchTapFreezesNormalizedMetreAndRegionDataInAppendOnlyEvent() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        try store.savePitchDimensions(PitchDimensions(lengthMetres: 105, widthMetres: 68), matchID: matchID)
        let foul = try store.create(EventDraft(matchID: matchID, eventType: "foul_recorded",
                                                payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        let added = try store.addLocation(to: foul.draft.eventID, normalizedX: 10, normalizedY: 50,
                                          accuracy: .refereeConfirmed, peers: ["watch"])
        let location = try #require(try store.location(for: foul.draft.eventID))
        #expect(added.draft.eventType == "location_added")
        #expect(location.metresX == 10.5); #expect(location.metresY == 34)
        #expect(location.pitchLengthMetres == 105); #expect(location.pitchWidthMetres == 68)
        #expect(location.regions.contains("defending_third")); #expect(location.regions.contains("penalty_area"))
        #expect(try store.eventCount() == 2); #expect(try store.pendingOutboxCount() == 1)
    }

    @Test func requiredIncidentLocationBlocksReviewUntilLocationEventIsAdded() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        try store.savePitchDimensions(PitchDimensions(lengthMetres: 105, widthMetres: 68), matchID: matchID)
        let card = try store.create(EventDraft(matchID: matchID, eventType: "card_recorded",
                                                payloadJSON: #"{"colour":"red","disciplinaryReason":"Violent conduct","incidentNarrative":"Struck opponent.","isDirectRed":true,"locationRequired":true,"participantId":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","requiresIncidentReport":true,"teamSide":"away"}"#), peers: [])
        var review = try store.validatePostMatch(matchID: matchID, confirmedScore: nil)
        #expect(review.issues.contains { $0.code == "required_location_missing" && $0.eventID == card.draft.eventID })
        _ = try store.addLocation(to: card.draft.eventID, normalizedX: 72, normalizedY: 30,
                                  accuracy: .estimated, peers: [])
        review = try store.validatePostMatch(matchID: matchID, confirmedScore: nil)
        #expect(!review.issues.contains { $0.code == "required_location_missing" })
        let incident = try #require(try store.reportDocuments(matchID: matchID).first { $0.kind == .incident })
        #expect(incident.linkedEventIDs.count == 2)
    }

    @Test func locationRejectsMissingDimensionsAndUnrelatedEvents() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let foul = try store.create(EventDraft(matchID: matchID, eventType: "foul_recorded",
                                                payloadJSON: #"{"teamSide":"away"}"#), peers: [])
        #expect(throws: LedgerError.invalidDraft("pitch dimensions are required before adding a location")) {
            try store.addLocation(to: foul.draft.eventID, normalizedX: 50, normalizedY: 50, peers: [])
        }
        try store.savePitchDimensions(PitchDimensions(lengthMetres: 100, widthMetres: 64), matchID: matchID)
        let goal = try store.create(EventDraft(matchID: matchID, eventType: "goal_recorded",
                                                payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        #expect(throws: LedgerError.invalidDraft("locations may be added only to fouls or location-required incidents")) {
            try store.addLocation(to: goal.draft.eventID, normalizedX: 50, normalizedY: 50, peers: [])
        }
    }

    @Test func replicatedLocationMayArriveBeforeItsTargetAndConverges() throws {
        let sender = try LedgerStore(originDeviceID: deviceID)
        try sender.savePitchDimensions(PitchDimensions(lengthMetres: 105, widthMetres: 68), matchID: matchID)
        let foul = try sender.create(EventDraft(matchID: matchID, eventType: "foul_recorded",
                                                payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        let location = try sender.addLocation(to: foul.draft.eventID, normalizedX: 40, normalizedY: 60, peers: [])
        let receiver = try LedgerStore(originDeviceID: UUID())
        let peer = UUID()
        #expect(try receiver.receive(ReplicatedEvent(event: location), messageID: UUID(), from: peer) == .committed)
        #expect(try receiver.syncCursor(matchID: matchID, peerDeviceID: peer, originDeviceID: deviceID) == 0)
        #expect(try receiver.receive(ReplicatedEvent(event: foul), messageID: UUID(), from: peer) == .committed)
        #expect(try receiver.syncCursor(matchID: matchID, peerDeviceID: peer, originDeviceID: deviceID) == 2)
        #expect(try receiver.location(for: foul.draft.eventID)?.normalizedX == 40)
    }

    @Test func extendedMatchActionsEnforceCaptureTimeVocabulary() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        _ = try store.create(EventDraft(matchID: matchID, eventType: MatchActionType.substitution.rawValue,
                                        payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        _ = try store.create(EventDraft(matchID: matchID, eventType: MatchActionType.penalty.rawValue,
                                        payloadJSON: #"{"outcome":"pending","phase":"match","teamSide":"away"}"#), peers: [])
        _ = try store.create(EventDraft(matchID: matchID, eventType: MatchActionType.injury.rawValue,
                                        payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        _ = try store.create(EventDraft(matchID: matchID, eventType: MatchActionType.varReview.rawValue,
                                        payloadJSON: #"{"outcome":"pending","reviewType":"goal"}"#), peers: [])
        _ = try store.create(EventDraft(matchID: matchID, eventType: MatchActionType.suspension.rawValue,
                                        payloadJSON: #"{"reason":"weather","state":"started"}"#), peers: [])
        _ = try store.create(EventDraft(matchID: matchID, eventType: MatchActionType.restart.rawValue,
                                        payloadJSON: #"{"restartType":"dropped_ball"}"#), peers: [])
        #expect(try store.eventCount() == 6)
        #expect(throws: LedgerError.invalidDraft("penalties require team, phase, and outcome")) {
            try store.create(EventDraft(matchID: matchID, eventType: MatchActionType.penalty.rawValue,
                                        payloadJSON: #"{"outcome":"unknown","phase":"match","teamSide":"home"}"#), peers: [])
        }
        #expect(throws: LedgerError.invalidDraft("suspensions require state and reason")) {
            try store.create(EventDraft(matchID: matchID, eventType: MatchActionType.suspension.rawValue,
                                        payloadJSON: #"{"reason":"","state":"started"}"#), peers: [])
        }
    }

    @Test func deferredSubstitutionDetailsAppendCorrectionAndEnterReportProjection() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let outgoing = MatchParticipantSnapshot(id: UUID(), teamSide: "home", role: "player", displayName: "Out", shirtNumber: 9)
        let incoming = MatchParticipantSnapshot(id: UUID(), teamSide: "home", role: "player", displayName: "In", shirtNumber: 18)
        let opponent = MatchParticipantSnapshot(id: UUID(), teamSide: "away", role: "player", displayName: "Away", shirtNumber: 1)
        let referee = MatchParticipantSnapshot(id: UUID(), role: "accountable_referee", displayName: "Referee")
        try store.saveParticipants([outgoing, incoming, opponent, referee], matchID: matchID)
        let substitution = try store.create(EventDraft(matchID: matchID, eventType: MatchActionType.substitution.rawValue,
                                                        payloadJSON: #"{"teamSide":"home"}"#), peers: [])
        var review = try store.validatePostMatch(matchID: matchID, confirmedScore: nil)
        #expect(review.issues.contains { $0.code == "substitution_players_missing" })
        let completed = try store.completeMatchAction(eventID: substitution.draft.eventID,
                                                       primaryParticipantID: outgoing.id,
                                                       secondaryParticipantID: incoming.id, peers: [])
        #expect(completed.draft.eventType == "event_corrected")
        #expect(completed.canonicalPayload.contains("playerOutDisplayName"))
        review = try store.validatePostMatch(matchID: matchID, confirmedScore: nil)
        #expect(!review.issues.contains { $0.code == "substitution_players_missing" })
        #expect(try store.timeline(matchID: matchID).filter(\.isActive).first?.eventID == completed.draft.eventID)
    }

    @Test func pendingPenaltyAndVARProduceReviewIssuesWithCorrectSeverity() throws {
        let store = try LedgerStore(originDeviceID: deviceID)
        let penalty = try store.create(EventDraft(matchID: matchID, eventType: MatchActionType.penalty.rawValue,
                                                   payloadJSON: #"{"outcome":"pending","phase":"shootout","teamSide":"home"}"#), peers: [])
        let review = try store.create(EventDraft(matchID: matchID, eventType: MatchActionType.varReview.rawValue,
                                                  payloadJSON: #"{"outcome":"pending","reviewType":"penalty"}"#), peers: [])
        let validation = try store.validatePostMatch(matchID: matchID, confirmedScore: nil)
        #expect(validation.issues.contains { $0.code == "penalty_outcome_pending" && $0.eventID == penalty.draft.eventID && $0.severity == .blocking })
        #expect(validation.issues.contains { $0.code == "var_outcome_pending" && $0.eventID == review.draft.eventID && $0.severity == .warning })
    }

    private func preparedElevenAsideStore(matchID: UUID, deviceID: UUID) throws -> LedgerStore {
        let store = try LedgerStore(originDeviceID: deviceID)
        try store.saveFixture(MatchFixture(matchID: matchID, competition: "KFA League", scheduledAt: Date(),
                                           venueName: "Main pitch", homeTeamName: "Seoul", awayTeamName: "Busan"))
        try store.saveRules(MatchRuleSnapshot(), matchID: matchID)
        try store.savePitchDimensions(PitchDimensions(lengthMetres: 105, widthMetres: 68), matchID: matchID)
        try store.saveParticipants([
            MatchParticipantSnapshot(id: UUID(), teamSide: "home", role: "player", displayName: "Seoul 9", shirtNumber: 9),
            MatchParticipantSnapshot(id: UUID(), teamSide: "away", role: "player", displayName: "Busan 10", shirtNumber: 10),
            MatchParticipantSnapshot(id: UUID(), role: "accountable_referee", displayName: "Referee Kim")
        ], matchID: matchID)
        try store.savePreMatchChecklist(PreMatchChecklist(pitchChecked: true, equipmentChecked: true,
                                                         crewChecked: true, lineupChecked: true), matchID: matchID)
        return store
    }

    private func completedMatchStore(attachmentRoot: URL? = nil) throws -> LedgerStore {
        let store = try LedgerStore(originDeviceID: deviceID, attachmentRoot: attachmentRoot)
        try store.saveFixture(MatchFixture(matchID: matchID, competition: "League", scheduledAt: Date(),
                                           venueName: "Ground", homeTeamName: "Home", awayTeamName: "Away"))
        try store.saveParticipants([
            MatchParticipantSnapshot(id: UUID(), teamSide: "home", role: "player", displayName: "Home 9", shirtNumber: 9),
            MatchParticipantSnapshot(id: UUID(), teamSide: "away", role: "player", displayName: "Away 10", shirtNumber: 10),
            MatchParticipantSnapshot(id: UUID(), role: "accountable_referee", displayName: "Referee Kim")
        ], matchID: matchID)
        for definition in [MatchPeriodDefinition(kind: "first_half", ordinal: 1),
                           MatchPeriodDefinition(kind: "second_half", ordinal: 2)] {
            let periodID = UUID()
            _ = try store.create(EventDraft(matchID: matchID, eventType: "period_started", matchPeriodID: periodID,
                                            payloadJSON: "{\"ordinal\":\(definition.ordinal),\"periodKind\":\"\(definition.kind)\"}"), peers: [])
            _ = try store.create(EventDraft(matchID: matchID, eventType: "period_ended", matchPeriodID: periodID,
                                            payloadJSON: "{\"finalClockMs\":2700000,\"ordinal\":\(definition.ordinal),\"periodKind\":\"\(definition.kind)\"}"), peers: [])
        }
        return store
    }
}
