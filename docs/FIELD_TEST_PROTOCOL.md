# 11인제 현장 필드 테스트 프로토콜

이 문서는 개발자가 아닌 실제 심판이 iPhone과 Apple Watch로 한 경기를 운영하며 MVP를 검증하는 절차다. 테스트 시작 시 앱 커밋 SHA, iPhone/Watch 모델과 OS, 테스트 날짜, 관찰자 이름을 기록한다. 각 단계가 실패하면 다음 단계로 진행하지 않고 관찰 내용과 result bundle 또는 화면 기록을 보존한다.

## 사전 조건

- iPhone과 Apple Watch가 페어링되어 있고 두 기기의 잠금이 해제되어 있다.
- 동일한 개발 빌드 커밋을 iPhone과 Watch에 설치한다.
- 테스트 경기: 11인제, 홈 Seoul, 원정 Busan, 경기장 Main pitch, 전후반 각 45분.
- 최소 홈 선수 1명, 원정 선수 1명, 책임 심판 1명을 입력한다.
- 아래 표의 `Observed`와 `Evidence`는 실행 중 실제 값만 기록한다.

## 절차

| Step | Expected | Observed | Pass | Evidence | Notes |
| --- | --- | --- | --- | --- | --- |
| 경기 생성 | iPhone이 fixture와 준비 상태를 저장한다. |  |  |  |  |
| 준비 게이트 | 양 팀 roster와 책임 심판 전에는 라이브 제어가 비활성화된다. |  |  |  |  |
| 패키지 전송 | Watch에 팀명, 점수 0–0, `WAITING` 또는 시작 전 period가 표시된다. |  |  |  |  |
| 전반 시작 | Watch에서 1초 hold 후 `FIRST HALF`, `00:00`이 표시된다. |  |  |  |  |
| 득점 기록 | 팀 선택 후 점수가 즉시 증가하고 저장 확인이 보인다. |  |  |  |  |
| 파울 기록 | 팀 선택 후 Watch 홈으로 돌아오며 tap-to-home이 2초 이내다. |  |  |  |  | 실제 측정값을 초 단위로 기록 |
| 경고 기록 | 노란 카드가 저장되고 카드 haptic을 관찰자가 확인한다. |  |  |  |  |  |
| 직접 퇴장 | 레드 카드는 1초 hold 없이는 저장되지 않고 hold 후 저장된다. |  |  |  |  |  |
| 오프라인 전환 | iPhone 연결을 끊어도 Watch가 `saved locally`와 Queue를 표시한다. |  |  |  |  |  |
| 오프라인 재실행 | Watch 앱을 종료·재실행해도 직전 Queue와 이벤트가 남는다. |  |  |  |  |  |
| 재연결 | 연결 복구 후 Queue가 0이 되고 iPhone timeline에 이벤트가 중복 없이 보인다. |  |  |  |  |  |
| 전반 종료 | Watch 또는 iPhone에서 1초 hold 후 `HALF TIME`이 된다. |  |  |  |  |  |
| 후반 운영 | `SECOND HALF`에서 시계와 점수가 이어진다. |  |  |  |  |  |
| 경기 종료 | 2회 종료 hold 후 `FULL TIME`이 되고 자동 서명이 되지 않는다. |  |  |  |  |  |
| 상세 보완 | iPhone에서 골 선수와 직접 퇴장 사유/incident narrative를 입력한다. |  |  |  |  |  |
| 서명 | blocking issue를 해결하고 책임 심판 선언 후 match report를 서명한다. |  |  |  |  |  |
| 내보내기 | 서명된 현재 버전의 PDF와 XLSX가 생성되고 두 파일이 열리는지 확인한다. |  |  |  |  |  |

## 판정 기준

- 모든 행이 Pass이고 파울 저장 시간이 2.0초 이하면 MVP 현장 통과다.
- haptic은 XCTest 결과가 아니라 관찰자가 직접 느낀 결과만 인정한다.
- 연결 지연, 중복 이벤트, 점수 불일치, 서명 전 blocking 누락은 실패다.
- 테스트가 중단되면 `docs/DEVICE_ACCEPTANCE_EVIDENCE.md`에 실패 원인과 재현 조건을 추가하고, 수정 전까지 통과로 표시하지 않는다.

## 실행 명령

```sh
xcodebuild -project Referee.xcodeproj -scheme RefereePhone -destination 'platform=iOS,name=<paired iPhone name>' build
xcodebuild -project Referee.xcodeproj -scheme RefereeWatch -destination 'platform=watchOS,name=<paired Watch name>' build
swift test
```
