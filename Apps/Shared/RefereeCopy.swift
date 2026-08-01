import SwiftUI
import RefereeLedger

struct RefereeCopy: Sendable {
    private let usesKorean: Bool

    init(language: AppLanguage) {
        usesKorean = language == .korean
    }

    // Navigation and settings
    var matches: String { text("경기", "Matches") }
    var createMatch: String { text("경기 생성", "Create match") }
    var resumeMatch: String { text("경기 재개", "Resume match") }
    var noSavedMatches: String { text("저장된 경기가 없습니다", "No saved matches yet") }
    var settings: String { text("설정", "Settings") }
    var languageLabel: String { text("언어", "Language") }
    var korean: String { "한국어" }
    var english: String { "English" }
    var selectedLanguageName: String { usesKorean ? korean : english }

    // Fixture and setup
    var fixture: String { text("경기 정보", "Fixture") }
    var competition: String { text("대회", "Competition") }
    var kickOff: String { text("경기 시작", "Kick-off") }
    var venue: String { text("경기장", "Venue") }
    var homeTeam: String { text("홈팀", "Home team") }
    var awayTeam: String { text("원정팀", "Away team") }
    var fixtureGuidance: String {
        text("먼저 경기를 생성하세요. 심판진, 명단, 규칙, 구장 정보와 준비 확인은 다음 단계에서 완료할 수 있습니다.",
             "Create the match now. Crew, rosters, rules, pitch details, and readiness checks can be completed next or later.")
    }
    var preparation: String { text("경기 준비", "Preparation") }
    var crewAndTeams: String { text("심판진과 팀", "Crew and teams") }
    var ready: String { text("준비 완료", "Ready") }
    var needsDetails: String { text("추가 정보 필요", "Needs details") }
    var preMatchChecklist: String { text("경기 전 체크리스트", "Pre-match checklist") }
    func checkedCount(_ count: Int) -> String { text("4개 중 \(count)개 확인", "\(count) of 4 checked") }
    var venueAndPitch: String { text("경기장과 구장", "Venue and pitch") }
    var competitionRules: String { text("대회 규칙", "Competition rules") }
    var extraTimeEnabled: String { text("연장전 사용", "Extra time enabled") }
    var standardPeriods: String { text("표준 경기 시간", "Standard periods") }
    var completeBeforeStarting: String { text("시작 전 필수 사항", "Complete before starting") }
    var readinessUnavailable: String { text("준비 상태 확인 불가", "Readiness unavailable") }
    var recommendedBeforeKickOff: String { text("경기 전 권장 사항", "Recommended before kick-off") }
    var readinessGuidance: String {
        text("필수 준비가 완료되어야 경기 제어를 시작할 수 있습니다. 권장 사항은 나중에 완료해도 되지만, 보고서 서명 전에 필수 정보를 다시 확인합니다.",
             "Required preparation blocks live control; warnings can be completed later, but report sign-off still validates mandatory details.")
    }
    var savePreparation: String { text("준비 저장", "Save preparation") }
    var openMatchControl: String { text("경기 제어 열기", "Open match control") }
    var matchSetup: String { text("경기 설정", "Match setup") }
    var setupDetails: String { text("상세 설정", "Setup details") }
    var checklist: String { text("체크리스트", "Checklist") }
    var rules: String { text("규칙", "Rules") }
    var extraTime: String { text("연장전", "Extra time") }
    var teamKitColors: String { text("팀 유니폼 색상", "Team kit colors") }
    var homeKit: String { text("홈 유니폼", "Home kit") }
    var awayKit: String { text("원정 유니폼", "Away kit") }
    var homeCustomColor: String { text("홈 사용자 색상", "Home custom color") }
    var awayCustomColor: String { text("원정 사용자 색상", "Away custom color") }
    var pitchDimensions: String { text("구장 크기", "Pitch dimensions") }
    var length: String { text("길이", "Length") }
    var width: String { text("너비", "Width") }
    var accountableReferee: String { text("책임 심판", "Accountable referee") }
    var fullName: String { text("성명", "Full name") }
    var pitchAndMarkings: String { text("구장과 라인 확인", "Pitch and field markings") }
    var matchBallsAndEquipment: String { text("경기구와 장비 확인", "Match balls and equipment") }
    var refereeCrewBriefing: String { text("심판진 브리핑", "Referee crew briefing") }
    var teamSheetsAndLineups: String { text("출전 명단과 라인업", "Team sheets and lineups") }
    var operationalNotes: String { text("운영 메모", "Operational notes") }
    var playerName: String { text("선수 이름", "Player name") }
    var shirtNumber: String { text("번호", "No.") }
    func rosterTitle(side: String, team: String) -> String {
        if !team.isEmpty { return text("\(team) 명단", "\(team) roster") }
        return side == "home" ? text("홈팀 명단", "Home roster") : text("원정팀 명단", "Away roster")
    }
    func addPlayer(side: String) -> String {
        side == "home" ? text("홈팀 선수 추가", "Add home player") : text("원정팀 선수 추가", "Add away player")
    }
    func kitColorName(_ id: String) -> String {
        let koreanNames = ["#D32F2F": "빨강", "#F57C00": "주황", "#FBC02D": "노랑", "#388E3C": "녹색",
                           "#00838F": "청록", "#1565C0": "파랑", "#283593": "남색", "#7B1FA2": "보라",
                           "#C2185B": "분홍", "#212121": "검정"]
        let englishNames = ["#D32F2F": "Red", "#F57C00": "Orange", "#FBC02D": "Yellow", "#388E3C": "Green",
                            "#00838F": "Teal", "#1565C0": "Blue", "#283593": "Navy", "#7B1FA2": "Purple",
                            "#C2185B": "Pink", "#212121": "Black"]
        return (usesKorean ? koreanNames : englishNames)[id] ?? id
    }

    func readinessIssueTitle(id: String, fallback: String) -> String {
        guard usesKorean else { return fallback }
        return [
            "fixture.competition": "대회 정보가 없습니다", "fixture.venue": "경기장 정보가 없습니다",
            "fixture.distinctTeams": "팀 정보가 완전하지 않습니다", "roster.home": "홈팀 명단이 없습니다",
            "roster.away": "원정팀 명단이 없습니다", "referee.accountable": "책임 심판이 없습니다",
            "checklist.pitch": "구장 확인이 완료되지 않았습니다", "checklist.equipment": "장비 확인이 완료되지 않았습니다",
            "checklist.crew": "심판진 확인이 완료되지 않았습니다", "checklist.lineup": "라인업 확인이 완료되지 않았습니다",
            "pitch.dimensions": "구장 크기 정보가 없습니다"
        ][id] ?? fallback
    }

    // Live match actions and status
    var localSave: String { text("로컬 저장", "LOCAL SAVE") }
    var goal: String { text("득점", "GOAL") }
    var foul: String { text("파울", "FOUL") }
    var card: String { text("카드", "CARD") }
    var more: String { text("더보기", "MORE") }
    var yellow: String { text("경고", "Yellow") }
    var moreMatchActions: String { text("더 많은 경기 기록", "More match actions") }
    var eventTimeline: String { text("경기 기록", "Event timeline") }
    var reportReadiness: String { text("보고서 준비", "Report readiness") }
    var reviewAndSignReports: String { text("보고서 검토 및 서명", "Review and sign reports") }
    var primaryAction: String { text("주요 작업", "Primary action") }
    var secondaryAction: String { text("보조 작업", "Secondary action") }
    var matchComplete: String { text("경기 종료", "Match complete") }
    var holdToStart: String { text("길게 눌러 시작", "Hold to start") }
    func holdToStart(_ period: String) -> String { text("길게 눌러 \(period) 시작", "Hold to start \(period.lowercased())") }
    var activeMatchGuidance: String { text("팀 액션을 스와이프해 저장·경기 제어를 길게 눌러 종료", "Swipe a team action to save · hold the period control to end") }
    var holdToEndPeriod: String { text("길게 눌러 피리어드 종료", "Hold to end period") }
    var retry: String { text("다시 시도", "Retry") }
    func lastWatchContact(_ date: String) -> String { text("마지막 Watch 연결 \(date)", "Last Watch contact \(date)") }
    func syncStatus(peer: String, reachable: Bool, pending: Int, failed: Bool) -> String {
        let localizedPeer = peer == "Watch" ? "Watch" : text("iPhone", "iPhone")
        if failed { return text("동기화 확인 필요 · 로컬에 저장됨", "Sync needs attention · events remain local") }
        if reachable {
            return pending == 0 ? text("\(localizedPeer) 연결됨", "\(localizedPeer) connected")
                                : text("\(pending)건 동기화 중", "Syncing \(pending)")
        }
        return pending == 0 ? text("로컬 저장 · \(localizedPeer) 오프라인", "Saved locally · \(localizedPeer) offline")
                            : text("\(pending)건 안전하게 대기 중", "\(pending) queued safely")
    }
    func queueStatus(_ count: Int) -> String { text("대기 \(count)", "Queue \(count)") }
    func savedLocally(queue count: Int) -> String { text("로컬 저장 · 대기 \(count)", "Saved locally · Queue \(count)") }
    var retryPhoneSync: String { text("iPhone 동기화 다시 시도", "Retry iPhone sync") }

    // Timeline and follow-up editors
    var noEventsYet: String { text("아직 경기 기록이 없습니다", "No events yet") }
    var timelineEmptyGuidance: String { text("경기 액션이 여기에 표시됩니다.", "Match actions will appear here.") }
    var pitch: String { text("구장", "Pitch") }
    var reverse: String { text("되돌리기", "Reverse") }
    var correct: String { text("수정", "Correct") }
    var details: String { text("상세 정보", "Details") }
    var revised: String { text("수정됨", "REVISED") }
    var issue: String { text("문제", "ISSUE") }
    var completeAction: String { text("액션 완료", "Complete action") }
    var completeEvent: String { text("이벤트 완료", "Complete event") }
    var appendCompletedDetails: String { text("완료 정보 추가", "Append completed details") }
    var cancel: String { text("취소", "Cancel") }
    var playerOutTitle: String { text("교체 아웃 선수", "Player out") }
    var playerInTitle: String { text("교체 인 선수", "Player in") }
    var penaltyTaker: String { text("페널티 키커", "Penalty taker") }
    var outcome: String { text("결과", "Outcome") }
    var injuredPlayer: String { text("부상 선수", "Injured player") }
    var goalscorer: String { text("득점 선수", "Goalscorer") }
    var cardRecipient: String { text("카드 대상 선수", "Card recipient") }
    var player: String { text("선수", "Player") }
    var selectPlayer: String { text("선수 선택", "Select player") }
    var disciplinaryReason: String { text("징계 사유", "Disciplinary reason") }
    var requiredReason: String { text("필수 사유", "Required reason") }
    var requiredIncidentNarrative: String { text("필수 사건 설명", "Required incident narrative") }
    var describeIncident: String { text("목격 내용과 조치를 설명하세요", "Describe what you saw and the action taken") }
    var directRedNarrativeGuidance: String {
        text("이 설명은 퇴장 사건 보고서의 기초가 됩니다.",
             "This narrative becomes the foundation of the direct-red incident report.")
    }
    var incidentLocation: String { text("사건 위치", "Incident location") }
    var exactLocationRequired: String { text("보고서에 정확한 위치 필요", "Exact location required for report") }
    var incidentLocationGuidance: String {
        text("활성화하면 경기 기록에서 구장 위치를 추가할 때까지 서명할 수 없습니다.",
             "If enabled, sign-off is blocked until a pitch location is added from the timeline.")
    }
    var tapIncidentLocation: String { text("사건 위치를 탭하세요", "Tap the incident location") }
    var accuracy: String { text("정확도", "Accuracy") }
    var status: String { text("상태", "Status") }
    var refereeConfirmed: String { text("심판 확인", "Referee confirmed") }
    var estimated: String { text("추정", "Estimated") }
    var unconfirmed: String { text("미확인", "Unconfirmed") }
    var appendPitchLocation: String { text("구장 위치 추가", "Append pitch location") }
    var pitchLocation: String { text("구장 위치", "Pitch location") }
    var correctedEvent: String { text("수정된 이벤트", "Corrected event") }
    var cardLabel: String { text("카드", "Card") }
    var red: String { text("퇴장", "Red") }
    var whatWasCorrected: String { text("무엇을 수정했나요?", "What was corrected?") }
    var whyReverseEvent: String { text("이 이벤트를 되돌리는 이유는 무엇인가요?", "Why should this event be reversed?") }
    var appendCorrection: String { text("수정 사항 추가", "Append correction") }
    var appendReversal: String { text("되돌리기 추가", "Append reversal") }
    var correctEvent: String { text("이벤트 수정", "Correct event") }
    var reverseEvent: String { text("이벤트 되돌리기", "Reverse event") }

    func timelineEventTitle(_ eventType: String, fallback: String) -> String {
        guard usesKorean else { return fallback }
        return [
            "goal_recorded": "득점", "foul_recorded": "파울", "card_recorded": "카드",
            "stoppage_time_recorded": "추가 시간 표시", "substitution_recorded": "선수 교체",
            "penalty_recorded": "페널티", "injury_recorded": "부상", "var_recorded": "VAR 판독",
            "suspension_recorded": "경기 중단", "restart_recorded": "경기 재개",
            "period_started": "피리어드 시작", "period_ended": "피리어드 종료",
            "event_corrected": "수정", "event_reversed": "되돌리기", "location_added": "구장 위치"
        ][eventType] ?? fallback
    }

    func detailPrefix(_ key: String) -> String {
        guard usesKorean else { return key }
        return ["Out": "교체 아웃", "In": "교체 인"][key] ?? key
    }

    func enumValue(_ rawValue: String) -> String {
        let values: [String: (korean: String, english: String)] = [
            "pending": ("대기 중", "Pending"), "scored": ("득점", "Scored"),
            "missed": ("실패", "Missed"), "saved": ("선방", "Saved"),
            "post": ("골대", "Post"), "retake": ("재시도", "Retake"),
            "confirmed": ("확정", "Confirmed"), "overturned": ("번복", "Overturned"),
            "no_change": ("변경 없음", "No Change"), "cancelled": ("취소", "Cancelled"),
            "yellow": ("경고", "Yellow"), "red": ("퇴장", "Red"),
            "goal": ("득점", "Goal"), "penalty": ("페널티", "Penalty"),
            "direct_red": ("직접 퇴장", "Direct Red"),
            "mistaken_identity": ("대상 선수 착오", "Mistaken Identity"), "other": ("기타", "Other"),
            "started": ("시작", "Started"), "resumed": ("재개", "Resumed"),
            "kickoff": ("킥오프", "Kickoff"), "free_kick": ("프리킥", "Free Kick"),
            "penalty_kick": ("페널티킥", "Penalty Kick"), "throw_in": ("스로인", "Throw In"),
            "goal_kick": ("골킥", "Goal Kick"), "corner_kick": ("코너킥", "Corner Kick"),
            "dropped_ball": ("드롭볼", "Dropped Ball"), "match": ("경기", "Match"),
            "shootout": ("승부차기", "Shootout"),
            "first_half": ("전반", "First Half"), "second_half": ("후반", "Second Half"),
            "extra_time_first_half": ("연장 전반", "Extra Time First Half"),
            "extra_time_second_half": ("연장 후반", "Extra Time Second Half"),
            "injury": ("부상", "Injury"), "var": ("VAR", "VAR"),
            "delayed_restart": ("경기 재개 지연", "Delayed Restart"),
            "weather": ("기상", "Weather"), "crowd_control": ("관중 통제", "Crowd Control"),
            "match_interruption": ("경기 중단", "Match Interruption"),
            "defending_third": ("수비 진영", "Defending Third"),
            "middle_third": ("중원", "Middle Third"), "attacking_third": ("공격 진영", "Attacking Third"),
            "left_channel": ("왼쪽 채널", "Left Channel"),
            "centre_channel": ("중앙 채널", "Centre Channel"), "right_channel": ("오른쪽 채널", "Right Channel"),
            "penalty_area": ("페널티 에어리어", "Penalty Area"), "goal_area": ("골 에어리어", "Goal Area"),
            "pitch_tap": ("구장 탭", "Pitch Tap"), "gps_assisted": ("GPS 보조", "GPS-assisted"),
            "later_correction": ("추후 수정", "Later Correction"),
            "referee_confirmed": ("심판 확인", "Referee Confirmed"),
            "estimated": ("추정", "Estimated"), "unconfirmed": ("미확인", "Unconfirmed")
        ]
        guard let value = values[rawValue] else { return rawValue }
        return usesKorean ? value.korean : value.english
    }

    // Post-match reports
    var postMatchReview: String { text("경기 후 검토", "Post-match review") }
    var report: String { text("보고서", "Report") }
    func reportKindName(_ kind: String) -> String {
        switch kind {
        case "match": return text("경기 보고서", "Match report")
        case "referee": return text("심판 보고서", "Referee report")
        case "incident": return text("사건 보고서", "Incident report")
        default: return kind
        }
    }
    var noQualifyingIncidents: String { text("해당 사건이 없습니다", "No qualifying incidents") }
    var incident: String { text("사건", "Incident") }
    var unknown: String { text("알 수 없음", "Unknown") }
    var shortSummary: String { text("짧은 요약", "Short summary") }
    var whatHappened: String { text("발생 내용", "What happened") }
    var description: String { text("설명", "Description") }
    var actionTaken: String { text("취한 조치", "Action taken") }
    var additionalNotes: String { text("추가 메모", "Additional notes") }
    var saveNewContentVersion: String { text("새 내용 버전 저장", "Save new content version") }
    func currentContentVersion(_ version: Int) -> String { text("현재 내용 버전: \(version)", "Current content version: \(version)") }
    var supersededContentGuidance: String {
        text("저장된 내용이 변경되어 이전 서명은 대체되었습니다.",
             "Saved content changed this report; earlier signatures are superseded.")
    }
    func linkedSeriousEvents(_ ids: String) -> String { text("연결된 중요 이벤트: \(ids)", "Linked serious events: \(ids)") }
    var structuredNarrative: String { text("구조화된 설명", "Structured narrative") }
    var requiredForSignOff: String { text("서명에 필수", "Required for sign-off") }
    var addPhoto: String { text("사진 추가", "Add photo") }
    var addFile: String { text("파일 추가", "Add file") }
    var noAttachments: String { text("첨부 파일 없음", "No attachments") }
    var required: String { text("필수", "Required") }
    func attachmentSummary(bytes: Int64, checksum: String, required: Bool) -> String {
        text("\(bytes)바이트 · SHA-256 \(checksum)…" + (required ? " · 필수" : ""),
             "\(bytes) bytes · SHA-256 \(checksum)…" + (required ? " · Required" : ""))
    }
    var privateAttachments: String { text("비공개 첨부 파일", "Private attachments") }
    var attachmentGuidance: String {
        text("파일은 비공개 앱 저장소에 복사됩니다. 보고서 서명 시 정확한 바이트와 체크섬이 고정됩니다.",
             "Files are copied into private app storage. Their exact bytes and checksum are frozen when this report is signed.")
    }
    var finalScore: String { text("최종 점수", "Final score") }
    var confirmFinalScore: String { text("이 최종 점수를 확인합니다", "I confirm this final score") }
    var blockingIssues: String { text("차단 문제", "Blocking issues") }
    var resolveBlockingIssues: String { text("서명 전에 모든 차단 문제를 해결하세요.", "Resolve every blocking issue before signing.") }
    var noBlockingIssues: String { text("차단 문제 없음", "No blocking issues") }
    var validation: String { text("검증", "Validation") }
    var warnings: String { text("경고", "Warnings") }
    var warningsGuidance: String { text("경고는 서명을 막지 않지만 검토해야 합니다.", "Warnings do not prevent signing, but should be reviewed.") }
    var refereeDeclaration: String { text("심판 선언", "Referee declaration") }
    var declaration: String {
        text("이 보고서를 검토했으며 경기 기록을 정확하게 반영함을 확인합니다.",
             "I confirm that I have reviewed this report and that it accurately reflects the match record.")
    }
    var agreeAndSign: String { text("동의하고 서명하겠습니다", "I agree and intend to sign") }
    func sign(_ reportName: String) -> String { text("\(reportName) 서명", "Sign \(reportName)") }
    var confirmProjectedScore: String {
        text("서명 가능한 검증을 실행하려면 예상 최종 점수를 확인하세요.",
             "Confirm the projected final score to run the signable validation.")
    }
    var acceptDeclaration: String { text("서명을 활성화하려면 선언에 동의하세요.", "Accept the declaration to enable signing.") }
    var signedVersionHistory: String { text("서명 버전 기록", "Signed version history") }
    var noSignedVersions: String { text("서명된 버전 없음", "No signed versions") }
    var signReportVersionPrompt: String { text("이 보고서 버전에 서명할까요?", "Sign this report version?") }
    var signingFreezeGuidance: String {
        text("서명하면 현재 보고서 내용과 감사 데이터가 고정됩니다. 이후 변경 시 이 버전은 대체됩니다.",
             "Signing freezes the current report content and audit data. Later changes will supersede this version.")
    }
    func version(_ number: Int) -> String { text("버전 \(number)", "Version \(number)") }
    var current: String { text("현재", "CURRENT") }
    var superseded: String { text("대체됨", "SUPERSEDED") }
    func signedBy(_ name: String, at date: String) -> String { text("\(name) 서명 · \(date)", "Signed by \(name) · \(date)") }
    func reportVersionDetails(content: Int, template: String, events: Int) -> String {
        text("내용 v\(content) · 템플릿 \(template) · 원본 이벤트 \(events)개",
             "Content v\(content) · Template \(template) · \(events) source events")
    }
    var immutableHistoryGuidance: String {
        text("변경 불가능한 기록으로 보관됩니다. 최신 버전을 만들려면 현재 보고서에 다시 서명하세요.",
             "Kept as immutable history. Sign the current report again for a current version.")
    }
    func share(_ format: String) -> String { text("\(format) 공유", "Share \(format)") }
    var file: String { text("파일", "file") }
    func eventReference(_ id: String) -> String { text("이벤트 \(id)", "Event \(id)") }
    func incidentReference(_ id: String) -> String { text("사건 \(id)", "Incident \(id)") }

    func transferLabel(peer: String, state: String, progress: String, error: String?) -> String {
        let fallbackError = error ?? text("재시도 필요", "retry required")
        switch state {
        case "pending": return text("\(peer) 전송: 대기 중\(progress)", "Transfer to \(peer): pending\(progress)")
        case "transferring": return text("\(peer) 전송: 진행 중\(progress)", "Transfer to \(peer): in progress\(progress)")
        case "completed": return text("\(peer) 전송: 완료", "Transfer to \(peer): complete")
        default: return text("\(peer) 전송: 실패 · \(fallbackError)", "Transfer to \(peer): failed · \(fallbackError)")
        }
    }

    func reportIssueTitle(code: String, fallback: String) -> String {
        guard usesKorean else { return fallback }
        return [
            "fixture_missing": "경기 정보가 없습니다", "period_still_active": "경기 피리어드가 아직 진행 중입니다",
            "match_not_complete": "경기가 종료되지 않았습니다", "score_not_confirmed": "최종 점수가 확인되지 않았습니다",
            "score_confirmation_mismatch": "확인한 점수가 경기 기록과 일치하지 않습니다",
            "accountable_referee_missing": "책임 심판이 없습니다", "timeline_integrity_invalid": "경기 기록 무결성 검증에 실패했습니다",
            "event_payload_invalid": "이벤트 데이터가 올바르지 않습니다", "goal_player_missing": "득점 선수가 없습니다",
            "card_player_missing": "카드 대상 선수가 없습니다", "card_reason_missing": "징계 사유가 없습니다",
            "direct_red_narrative_missing": "퇴장 사건 설명이 없습니다", "required_location_missing": "필수 사건 위치가 없습니다",
            "substitution_players_missing": "교체 아웃 및 인 선수가 모두 필요합니다", "penalty_outcome_pending": "페널티 결과 확인이 필요합니다",
            "injury_player_missing": "부상 선수가 확인되지 않았습니다", "var_outcome_pending": "VAR 판독 결과가 완료되지 않았습니다",
            "required_attachment_unreadable": "필수 첨부 파일이 없거나 체크섬 검증에 실패했습니다",
            "missing_revision_target": "수정 또는 되돌리기 대상이 없습니다", "ambiguous_revision": "이벤트 수정 사항이 충돌합니다",
            "revision_cycle": "수정 또는 되돌리기 연결이 순환합니다"
        ][code] ?? fallback
    }

    func statusMessage(_ value: String) -> String {
        guard usesKorean else { return value }
        let exact = [
            "Local database is unavailable": "로컬 데이터베이스를 사용할 수 없습니다",
            "Fixture saved locally": "경기 정보가 로컬에 저장되었습니다",
            "Match draft saved locally": "경기 초안이 로컬에 저장되었습니다",
            "Event details completed": "이벤트 상세 정보가 완료되었습니다",
            "Pitch location appended": "구장 위치가 추가되었습니다",
            "Goal saved locally": "득점이 로컬에 저장되었습니다", "Foul saved locally": "파울이 로컬에 저장되었습니다",
            "Yellow card saved locally": "경고가 로컬에 저장되었습니다", "Red card saved locally": "퇴장이 로컬에 저장되었습니다",
            "Added-time marker saved": "추가 시간 표시가 저장되었습니다", "Choose two distinct roster players": "서로 다른 명단 선수 두 명을 선택하세요",
            "Substitution saved locally": "선수 교체가 로컬에 저장되었습니다", "Penalty saved locally": "페널티가 로컬에 저장되었습니다",
            "Injury saved locally": "부상이 로컬에 저장되었습니다", "VAR review saved locally": "VAR 판독이 로컬에 저장되었습니다",
            "Suspension state saved locally": "경기 중단 상태가 로컬에 저장되었습니다", "Restart saved locally": "경기 재개가 로컬에 저장되었습니다",
            "Match action details completed": "경기 액션 상세 정보가 완료되었습니다", "Event reversed": "이벤트를 되돌렸습니다",
            "Event corrected": "이벤트를 수정했습니다", "Could not read the original event": "원본 이벤트를 읽을 수 없습니다",
            "Could not encode match action": "경기 액션을 인코딩할 수 없습니다", "Match is already complete": "경기가 이미 종료되었습니다",
            "Attachment stored and checksum verified": "첨부 파일을 저장하고 체크섬을 확인했습니다",
            "Watch session is not active": "Watch 세션이 활성 상태가 아닙니다",
            "Could not read the local sync queue": "로컬 동기화 대기열을 읽을 수 없습니다",
            "Could not read pending Watch events": "대기 중인 Watch 이벤트를 읽을 수 없습니다"
        ]
        if let localized = exact[value] { return localized }
        let errorPrefixes = [
            "Could not save fixture: ": "경기 정보를 저장할 수 없습니다: ", "Could not save match draft: ": "경기 초안을 저장할 수 없습니다: ",
            "Could not complete details: ": "상세 정보를 완료할 수 없습니다: ", "Could not add location: ": "위치를 추가할 수 없습니다: ",
            "Could not complete action: ": "액션을 완료할 수 없습니다: ", "Could not revise event: ": "이벤트를 수정할 수 없습니다: ",
            "Could not save event: ": "이벤트를 저장할 수 없습니다: ", "Could not start first half: ": "전반을 시작할 수 없습니다: ",
            "Could not end period: ": "피리어드를 종료할 수 없습니다: ", "Could not review report: ": "보고서를 검토할 수 없습니다: ",
            "Could not save report content: ": "보고서 내용을 저장할 수 없습니다: ", "Could not sign report: ": "보고서에 서명할 수 없습니다: ",
            "Could not export report: ": "보고서를 내보낼 수 없습니다: ", "Could not store attachment: ": "첨부 파일을 저장할 수 없습니다: ",
            "Could not read attachment: ": "첨부 파일을 읽을 수 없습니다: ", "Immediate Watch delivery failed: ": "Watch 즉시 전송에 실패했습니다: ",
            "Watch session activation failed: ": "Watch 세션 활성화에 실패했습니다: "
        ]
        for (prefix, localized) in errorPrefixes where value.hasPrefix(prefix) {
            return localized + value.dropFirst(prefix.count)
        }
        if value.hasSuffix(" started") {
            let period = String(value.dropLast(" started".count)).uppercased()
            return "\(periodLabel(period)) 시작"
        }
        if value.hasSuffix(" ended") {
            let period = String(value.dropLast(" ended".count)).uppercased()
            return "\(periodLabel(period)) 종료"
        }
        if value.hasPrefix("Report content version "), value.hasSuffix(" saved") {
            let version = value.dropFirst("Report content version ".count).dropLast(" saved".count)
            return "보고서 내용 버전 \(version)이 저장되었습니다"
        }
        if value.hasSuffix(" export ready to share") {
            return "\(value.dropLast(" export ready to share".count)) 내보내기 파일을 공유할 수 있습니다"
        }
        for reportName in ["Match report", "Referee report", "Incident report"]
            where value.hasPrefix("\(reportName) version ") && value.hasSuffix(" signed") {
            let number = value.dropFirst("\(reportName) version ".count).dropLast(" signed".count)
            let rawKind = reportName == "Match report" ? "match" : (reportName == "Referee report" ? "referee" : "incident")
            return "\(reportKindName(rawKind)) 버전 \(number)에 서명했습니다"
        }
        return value
    }

    func periodLabel(_ value: String) -> String {
        guard usesKorean else { return value }
        return ["WAITING FOR IPHONE": "iPhone 대기 중", "NOT STARTED": "시작 전", "FIRST HALF": "전반",
                "HALF TIME": "하프타임", "SECOND HALF": "후반", "FULL TIME": "경기 종료",
                "EXTRA TIME FIRST HALF": "연장 전반", "EXTRA TIME HALF TIME": "연장 하프타임",
                "EXTRA TIME SECOND HALF": "연장 후반"][value] ?? value
    }

    // Watch action sheets
    var selectScoringTeam: String { text("득점 팀 선택", "Select scoring team") }
    func teamGoal(_ team: String) -> String { text("\(team) 득점", "\(team) GOAL") }
    func teamFoul(_ team: String) -> String { text("\(team) 파울", "\(team) FOUL") }
    var directRedHold: String { text("퇴장 — 길게 누르기", "Direct red — hold") }
    var matchEvents: String { text("경기 상황", "Match events") }
    var teamAction: String { text("팀 액션", "Team action") }
    var interruption: String { text("경기 중단", "Interruption") }
    var homePenalty: String { text("홈 페널티", "HOME PENALTY") }
    var awayPenalty: String { text("원정 페널티", "AWAY PENALTY") }
    var varReview: String { text("VAR 판독", "VAR REVIEW") }
    var homeSubstitution: String { text("홈 교체", "HOME SUB") }
    var awaySubstitution: String { text("원정 교체", "AWAY SUB") }
    var injury: String { text("부상", "INJURY") }
    var suspend: String { text("경기 중단", "SUSPEND") }
    var resume: String { text("경기 재개", "RESUME") }
    var droppedBall: String { text("드롭볼", "DROPPED BALL") }
    var addedTime: String { text("추가 시간", "ADDED TIME") }
    var substitution: String { text("선수 교체", "Substitution") }
    var team: String { text("팀", "Team") }
    var playerOut: String { text("교체 아웃", "Player out") }
    var playerIn: String { text("교체 인", "Player in") }
    var select: String { text("선택", "Select") }
    var saveSubstitution: String { text("교체 저장", "Save substitution") }
    var penalty: String { text("페널티", "Penalty") }
    func penaltyAction(side: String, scored: Bool) -> String {
        let localizedSide = side == "home" ? text("홈", "Home") : text("원정", "Away")
        return "\(localizedSide) · \(scored ? text("득점", "scored") : text("실패", "not scored"))"
    }
    var injuryAndVAR: String { text("부상과 VAR", "Injury and VAR") }
    func injuryAction(side: String?) -> String {
        guard let side else { return text("팀 미지정 부상", "Unassigned injury") }
        return side == "home" ? text("홈팀 부상", "Home injury") : text("원정팀 부상", "Away injury")
    }
    var startVARReview: String { text("VAR 판독 시작", "Start VAR review") }
    var suspensionAndRestart: String { text("경기 중단과 재개", "Suspension and restart") }
    var suspendWeather: String { text("중단 · 날씨", "Suspend · weather") }
    var suspendCrowd: String { text("중단 · 관중 통제", "Suspend · crowd control") }
    var resumeMatchAction: String { text("경기 재개", "Resume match") }
    var droppedBallRestart: String { text("드롭볼 재개", "Dropped ball restart") }
    var freeKickRestart: String { text("프리킥 재개", "Free-kick restart") }
    var addedTimeSection: String { text("추가 시간", "Added time") }
    var injuryMarker: String { text("부상 표시", "Injury marker") }
    var varMarker: String { text("VAR 표시", "VAR marker") }
    var delayedRestartMarker: String { text("재개 지연 표시", "Delayed restart marker") }
    var directRedHoldToConfirm: String { text("퇴장 — 길게 눌러 확인", "Direct red — hold to confirm") }
    var matchActions: String { text("경기 액션", "Match actions") }
    var done: String { text("완료", "Done") }

    private func text(_ korean: String, _ english: String) -> String {
        usesKorean ? korean : english
    }
}

private struct RefereeCopyEnvironmentKey: EnvironmentKey {
    static let defaultValue = RefereeCopy(language: .korean)
}

extension EnvironmentValues {
    var refereeCopy: RefereeCopy {
        get { self[RefereeCopyEnvironmentKey.self] }
        set { self[RefereeCopyEnvironmentKey.self] = newValue }
    }
}
