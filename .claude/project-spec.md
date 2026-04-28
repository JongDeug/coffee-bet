# coffee-bet — 프로젝트 명세

## 1. 개요

| 항목 | 내용 |
|---|---|
| 이름 | **coffee-bet** (커피빵 실시간) |
| 한 줄 요약 | 친구·동료끼리 커피/점심 등 작은 내기를 룰렛·사다리·랜덤벌칙으로 결정하는 실시간 웹 서비스 |
| 레포 | `github.com/JongDeug/coffee-bet` |
| 주 언어 | Go (백엔드), Next.js/React (프론트엔드, 별도) |
| 단계 | 초기 개발 (M1) |

---

## 2. 목적

### 제품 목적
- 회사·친구 모임·술자리에서 **누가 살지 / 누가 벌칙 받을지** 를 재미있게 정한다.
- 호스트가 방을 만들고 → 링크로 초대 → 참가자 모두 같은 화면에서 결과를 본다.
- "그냥 쓰고 싶어지는" 작은 도구가 1차 목표.

### 학습 목적 (이게 더 중요)
- Go 백엔드 실력 향상.
- 특히 **websocket / room 관리 / 실시간 상태 동기화** 패턴 체득.
- 코드는 직접 작성한다. AI 는 *질문 답변* 으로만 사용. 코드 받아쓰기 X.

---

## 3. 핵심 시나리오

```
호스트가 방 생성
        │
        ▼
  room_id 발급 (공유 가능한 링크)
        │
        ▼
참가자들이 링크 타고 입장 → 닉네임만 입력
        │
        ▼
호스트가 게임 선택 (룰렛 / 사다리 / 벌칙)
        │
        ▼
호스트가 시작 버튼 → 서버가 결과 결정
        │
        ▼
모든 클라이언트에 동시에 broadcast
        │
        ▼
애니메이션 동기화 → 결과 공개
        │
        ▼
다시 시작 / 방 닫기
```

---

## 4. 핵심 기능 (단계별)

### 게임
- **룰렛**: 항목 입력 → 회전 후 한 명/한 항목 선택
- **사다리**: 참가자 ↔ 결과 매핑을 사다리로 시각화
- **랜덤 벌칙**: 미리 정의된 벌칙 풀(아아 사기, 점심 사기 등) 에서 추첨

### 인터랙션
- 닉네임 기반 게스트 입장 (회원가입 없음)
- 실시간 참가자 목록 / 입장·퇴장 알림
- 이모지 reaction (😂 👏 💀)
- 호스트 권한 (시작/리셋/추방)

### 견고함 (M4 이후)
- 연결 끊김 → 재접속 시 현재 게임 상태 복원
- 호스트 이탈 → 다음 사람에게 호스트 위임

---

## 5. 시스템 아키텍처

### 5.1 전체 그림 (M1~M4)

```
┌───────────┐         WebSocket         ┌──────────────────┐
│ 브라우저  │ ◄──────────────────────► │     Go 서버      │
│ (Next.js) │                            │   (단일 바이너리) │
└───────────┘         REST (room 생성)  │                  │
                                        │  ┌────────────┐  │
                                        │  │   Hub Map   │  │
                                        │  │ room_id →   │  │
                                        │  │   *Room     │  │
                                        │  └────────────┘  │
                                        └──────────────────┘
```

### 5.2 Room Hub 패턴

각 Room 마다 goroutine 1개가 다음을 select 처리:

```
Room.run()
 ├─ register   chan *Client   → clients map 에 추가
 ├─ unregister chan *Client   → clients map 에서 제거
 ├─ broadcast  chan []byte    → 모든 client.send 로 전달
 └─ command    chan Command   → 게임 시작/리셋 등 호스트 액션
```

각 Client 마다 goroutine 2개:
- `readPump`: websocket 에서 메시지 읽어 Room 으로 전달
- `writePump`: send 채널에서 받아 websocket 으로 보냄

→ mutex 거의 안 쓰고 channel 로 직렬화. Go 다운 패턴.

### 5.3 게임 결과 권위
- **결과는 무조건 서버가 결정** 한다.
- 클라이언트의 회전 애니메이션은 **시각 효과일 뿐**.
- 클라이언트가 보낸 시드/결과는 신뢰하지 않는다.

---

## 6. 기술 스택

| 레이어 | 선택 | 비고 |
|---|---|---|
| 언어 | Go 1.26 | go.mod 기준 |
| HTTP 라우팅 | Gin | 가볍고 충분 |
| WebSocket | `github.com/gorilla/websocket` | 사실상 표준 |
| DB (M5+) | SQLite → Postgres | 시작은 메모리만 |
| 멀티노드 (M6+) | Redis pub/sub | 처음엔 단일 인스턴스 |
| 프론트 | Next.js + Tailwind | AI 도움 OK |
| 배포 | 단일 바이너리 → Docker | k8s 는 한참 뒤 |

---

## 7. 폴더 구조

```
coffee-bet/
├── go.mod
├── Makefile
├── cmd/
│   └── server/
│       └── main.go              # 엔트리. DI / 라우팅만
├── internal/
│   ├── room/                    # Room, Hub, Client (메모리)
│   ├── ws/                      # websocket upgrade, read/write pump
│   ├── game/                    # 룰렛 / 사다리 결과 생성
│   ├── http/                    # REST handler (room 생성 등)
│   └── config/                  # 설정 로딩
├── configs/
│   └── config.yaml
└── (M5+) migrations/
```

**규칙**
- `cmd/server/main.go` 는 *조립* 만. 비즈니스 로직 X.
- `internal/` 은 외부에서 import 불가 — 내부 전용으로 설계.
- 패키지는 *기능* 단위로 작게. DDD 욕심 X.

---

## 8. 메시지 프로토콜 (초안)

WebSocket 메시지는 JSON, 상위 형식 통일.

```json
{ "type": "string", "payload": { ... } }
```

### Client → Server

| type | payload | 설명 |
|---|---|---|
| `join` | `{ nickname }` | 방 입장 |
| `start_roulette` | `{ items[] }` | 호스트가 룰렛 시작 |
| `start_ladder` | `{ players[], rewards[] }` | 호스트가 사다리 시작 |
| `react` | `{ emoji }` | 이모지 반응 |
| `ping` | `{}` | keepalive |

### Server → Client

| type | payload | 설명 |
|---|---|---|
| `room_state` | 전체 방 상태 | 입장/재접속 직후 1회 |
| `user_joined` / `user_left` | `{ nickname }` | 참가자 변동 |
| `roulette_result` | `{ winner, items, seed, started_at }` | 결과 + 애니메이션 동기화 정보 |
| `ladder_result` | `{ ladder, mappings, started_at }` | 사다리 + 결과 |
| `reaction` | `{ from, emoji }` | 이모지 broadcast |
| `error` | `{ code, message }` | 에러 |

---

## 9. 마일스톤 로드맵

각 단계마다 **돌아가는 결과물** 이 나온다.

### M1. Echo 서버 + 방 + broadcast
- `POST /rooms` → room_id 발급
- `WS /rooms/:id` → 입장한 클라이언트끼리 메시지 broadcast
- 인메모리 hub 만. DB / 인증 X. 닉네임만 받음
- **목표**: "두 탭 사이에서 메시지가 오간다"

### M2. 룰렛
- 호스트 입력 → 서버에서 결과 결정
- 5초 회전 동안 모두 동일 화면
- 단위 테스트: 결과 분포·결정성

### M3. 사다리
- 사다리 구조 + 매핑 서버 생성
- 모든 참가자에게 동일 사다리 전송

### M4. 견고함
- reconnect 시 현재 상태 복원
- host 권한 / 위임

### M5. 영속화
- SQLite 도입
- 방·결과 저장 + 히스토리 조회

### M6. 멀티 인스턴스 대비
- Redis pub/sub
- 여러 노드에서 broadcast 일관성

---

## 10. 비목표 (Non-goals) — *지금 단계에서 안 할 것*

| 안 함 | 이유 |
|---|---|
| 회원가입 / 로그인 | 닉네임만으로 충분 |
| 모바일 앱 | 웹으로 충분 |
| 클린 아키텍처 / DDD | 작은 코드에 오버헤드 |
| 마이크로서비스 분리 | 단일 바이너리로 시작 |
| k8s / 풀 CI-CD | M6 이후 |
| 화려한 UI | 백엔드 학습 우선 |
| 실시간 음성/영상 | 범위 밖 |

---

## 11. 학습 진행 가이드

### M1 시작 시 떠올릴 키워드
- Gin 라우터 / 미들웨어 기본
- gorilla/websocket Upgrader, ReadMessage / WriteMessage
- Hub & Client 패턴 (gorilla 공식 chat 예제 참고)
- goroutine + channel 로 broadcast 직렬화
- JSON 메시지 type 디스패치

### 막힐 때 AI 에 *물어보기 좋은 질문* 예시
- "Hub 의 broadcast 채널이 unbuffered 면 어떤 문제?"
- "websocket 연결마다 reader/writer goroutine 2개 쓰는 이유?"
- "여러 room 에 같은 사용자가 동시 접속 시 어떻게 관리?"
- "M1 단계에서 sync.Map vs map+mutex 어느 게 적절?"

### 피해야 할 함정
- 처음부터 인터페이스 추상화 욕심 X — 구체 타입 시작 → 필요해지면 추출
- 처음부터 100% 테스트 커버리지 X — 핵심 game 로직만 우선
- 처음부터 graceful shutdown / 풀 미들웨어 X

---

## 12. 참고 자료

- gorilla/websocket 공식 chat 예제 (Hub 패턴의 교과서):
  https://github.com/gorilla/websocket/tree/main/examples/chat
- Go 동시성 격언: *"Don't communicate by sharing memory; share memory by communicating."*

---

## 13. 검증 방법

### M1
```bash
go run ./cmd/server

# 다른 터미널
curl -X POST localhost:8080/rooms

# 또 다른 두 터미널
websocat ws://localhost:8080/rooms/<id>
# 한쪽에서 보낸 메시지가 다른 쪽에 보이면 OK
```

### M2~M3
- `internal/game/` 단위 테스트로 결과 분포·결정성 검증
- 두 클라이언트 동시 접속 → 결과 동일 확인

### M4
- 게임 진행 중 한 클라이언트 강제 종료 → 재접속 시 현재 상태 복원되는지

---

> **이 문서는 살아있는 명세서다.** 마일스톤이 끝날 때마다 갱신한다.
