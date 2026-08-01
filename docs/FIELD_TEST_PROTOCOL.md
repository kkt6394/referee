# 11인제 현장 필드 테스트 프로토콜

이 문서는 개발자가 아닌 실제 심판이 iPhone과 Apple Watch로 한 경기를 운영하며 MVP를 검증하는 절차다. 테스트 시작 시 앱 커밋 SHA, iPhone/Watch 모델과 OS, 테스트 날짜, 관찰자 이름을 기록한다. 각 단계가 실패하면 다음 단계로 진행하지 않고 관찰 내용과 result bundle 또는 화면 기록을 보존한다.

## 2026-08-01 릴리스 게이트 기준

- 현장 검증 대상 구현 커밋은 `e416e7a7f9c311caa63dfd80e405a26843875811`이며, 기능 범위는 `d222a02684f3c6525df069ca532f09b81b8353e1..e416e7a7f9c311caa63dfd80e405a26843875811`이다.
- 자동화 결과는 `swift test` 61/61 통과, Watch UI 3/3 통과, iPhone UI 7/8 통과다. iPhone 전체 UI suite는 기존 sign/export 경로가 timeline goal row를 탭한 뒤 event detail을 열지 못해 1개 test case가 실패했으므로 완전 통과로 표시하지 않는다.
- clean DerivedData에서 iPhone과 Watch simulator build, install, launch를 확인했다. iPhone 1206×2622 screenshot에서 앱이 letterbox 없이 전체 화면을 사용했다.
- clean install의 iPhone 첫 화면에서 한국어 기본값을 확인했고, 앱의 언어 선택 UI로 English를 선택한 뒤 영어 화면과 선택값 유지를 확인했다. Watch 한국어 화면도 확인했다.
- 이 자동화 게이트는 paired hardware 현장 통과를 의미하지 않는다. 아래 표의 실제 경기 운영, 2초 측정, haptic 체감, 연결 해제/복구는 심판과 관찰자가 물리 기기에서 수행해야 한다.

## 사전 조건

- iPhone과 Apple Watch가 페어링되어 있고 두 기기의 잠금이 해제되어 있다.
- 동일한 개발 빌드 커밋을 iPhone과 Watch에 설치한다.
- clean install 직후 iPhone의 기본 언어가 한국어인지 확인하고, English 전환 후 iPhone과 Watch에 의도한 언어가 표시되는지 확인한다.
- 테스트 경기: 11인제, 홈 Seoul, 원정 Busan, 경기장 Main pitch, 전후반 각 45분.
- 최소 홈 선수 1명, 원정 선수 1명, 책임 심판 1명을 입력한다.
- 아래 표의 `Observed`와 `Evidence`는 실행 중 실제 값만 기록한다.

## 절차

| Step | Expected | Observed | Pass | Evidence | Notes |
| --- | --- | --- | --- | --- | --- |
| 한국어 기본값 | clean install 직후 iPhone에 `경기`, `경기 생성`, `언어`, `한국어`가 표시된다. |  |  |  |  |
| 영어 전환 | iPhone 언어 설정에서 English를 선택하면 `Matches`, `Create match`, `Language`, `English`가 표시되고 재실행 후에도 유지된다. |  |  |  |  |
| Watch 언어 | Watch가 선택한 언어의 period와 sync 상태를 표시하며 점수와 팀명은 잘리지 않는다. |  |  |  |  |
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
- 자동화 test나 simulator screenshot만으로 위 표를 Pass 처리하지 않는다. 물리 기기에서 관찰한 값과 evidence를 각 행에 기록해야 한다.
- haptic은 XCTest 결과가 아니라 관찰자가 직접 느낀 결과만 인정한다.
- 연결 지연, 중복 이벤트, 점수 불일치, 서명 전 blocking 누락은 실패다.
- 테스트가 중단되면 `docs/DEVICE_ACCEPTANCE_EVIDENCE.md`에 실패 원인과 재현 조건을 추가하고, 수정 전까지 통과로 표시하지 않는다.

## 실행 명령

```sh
swift test
xcodebuild -project Referee.xcodeproj -scheme RefereePhone \
  -destination 'platform=iOS Simulator,id=<Referee-iPhone-id>' test
xcodebuild -project Referee.xcodeproj -scheme RefereeWatch \
  -destination 'platform=watchOS Simulator,id=<Series-11-id>' test
xcodebuild -project Referee.xcodeproj -scheme RefereePhone \
  -destination 'platform=iOS,name=<paired iPhone name>' build
xcodebuild -project Referee.xcodeproj -scheme RefereeWatch \
  -destination 'platform=watchOS,name=<paired Watch name>' build
```
