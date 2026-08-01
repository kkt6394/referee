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
