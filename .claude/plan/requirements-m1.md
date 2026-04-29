# M1 요구사항 명세 — Echo + Room + Broadcast (MSA 버전)

> M1 의 진짜 목표는 "메시지 한 번 왕복" 이 아니라
> **"gateway ↔ NATS ↔ game 의 골격이 살아있는 상태에서 두 탭이 broadcast 를 주고받는다"** 이다.
> 단일 바이너리 echo 가 아니라 분산 echo 라는 점이 핵심.

---

## 1. M1 이 끝났다고 부를 수 있는 기준 (Definition of Done)

다음을 **모두** 만족해야 M1 종료.

- [ ] **DoD-1.** `docker compose up` (또는 동등한 수단) 으로 `nats`, `gateway`, `game` 세 프로세스가 동시에 뜬다.
- [ ] **DoD-2.** `POST /rooms` 호출 시 새 `room_id` 가 응답으로 돌아온다. (UUID 면 충분)
- [ ] **DoD-3.** `WS /rooms/:room_id?nickname=...` 로 두 탭이 같은 room 에 접속한다.
- [ ] **DoD-4.** 한 탭에서 메시지(`{"type":"echo","payload":{"text":"hi"}}`) 를 보내면, **gateway → NATS → game → NATS → gateway → 두 탭** 의 경로를 거쳐 양쪽에 도착한다. (**game 을 안 거치는 단축경로 금지**)
- [ ] **DoD-5.** 한 탭이 끊어지면 다른 탭에 `user_left` 이벤트가 broadcast 된다.
- [ ] **DoD-6.** gateway 의 hub 는 **mutex 로 map 보호하지 않는다** — 단일 owner goroutine + channel 패턴으로 구성.
- [ ] **DoD-7.** game 은 connection 의 존재를 모른다 — 입출력은 NATS subject 로만 한다. (검증: gateway 코드 import 없이 game 단독 빌드 가능)
- [ ] **DoD-8.** `go work` 로 `gateway/`, `game/`, `shared/`, `proto/` 가 묶여 있고, 각자 자기 `go.mod` 를 가진다.
- [ ] **DoD-9.** README 또는 `Makefile` 의 한 줄 명령어로 "두 탭 echo 시연" 이 재현된다.

---

## 2. 의도적으로 *안* 할 것 (M1 스코프 밖)

학습 욕심이 커지기 쉬운 구간이다. 이번 단계에선 **명확히 미룬다.**

- 룰렛/사다리/벌칙 결과 결정 로직 → M2~M3
- 재접속 시 상태 복원 → M4
- 호스트 권한 / 추방 → M4
- DB 영속화 → M5
- Redis pub/sub / 멀티 인스턴스 → M6
- Protobuf 메시지 도입 → 학습 단계 별도 (M1 동안은 JSON 사용 가능, `decisions.md` Decision 3 참고)
- JetStream → 메시지 유실이 문제되는 시점 (M5 부근) 에 도입
- 인증 / JWT — 닉네임만으로 충분
- graceful shutdown 의 *완벽한* 형태 — "Ctrl+C 시 NATS 연결 끊기" 정도면 OK
- 메트릭 / 트레이싱 — 로그만으로 진행

---

## 3. 컴포넌트별 책임 (M1 한정)

### gateway-service

**해야 함**
- HTTP `POST /rooms` 핸들러: room_id 발급 후 그대로 응답. (M1 에선 game 에 알리지 않아도 됨 — 첫 WS 접속 때 lazy 생성으로 시작)
- `WS /rooms/:room_id` 업그레이드.
- 각 연결마다 readPump / writePump goroutine.
- room hub: `room_id → []*Client` 매핑을 **단일 owner goroutine** 이 관리.
- 클라이언트 → 서버 메시지를 NATS subject `room.<room_id>.client` 로 publish.
- NATS subject `room.<room_id>.event` 를 subscribe → 해당 room 의 모든 conn 으로 broadcast.

**하면 안 됨**
- 게임 결과 결정 (없는 단계지만, M1 에 echo 라도 game 안 거치고 가는 단축경로 금지).
- mutex 로 hub map 보호 (channel 로 직렬화).

### game-service

**해야 함**
- NATS subject `room.*.client` 를 subscribe.
- M1 한정: 받은 메시지를 그대로 `room.<room_id>.event` 로 다시 publish (echo).
- room_id 는 subject 의 `*` 자리에서 파싱.

**하면 안 됨**
- WS / HTTP 직접 노출.
- gateway 코드 import.

### shared/

- 로거 thin wrapper, NATS 연결 헬퍼 정도. M1 에선 비워두고 코드 중복이 거슬릴 때 추출해도 됨.

### proto/

- M1 에선 비어 있어도 OK. JSON 으로 진행.
- `RouletteStartCmd` 등 .proto 파일 정의는 M2 진입 전에.

---

## 4. 메시지 형태 (M1 한정 JSON)

### 클라이언트 ↔ gateway (WebSocket)

```json
// Client → Server
{ "type": "echo", "payload": { "text": "hi" } }

// Server → Client
{ "type": "echo_result", "payload": { "from": "닉네임", "text": "hi" } }
{ "type": "user_joined", "payload": { "nickname": "..." } }
{ "type": "user_left",   "payload": { "nickname": "..." } }
```

### gateway ↔ game (NATS, JSON 페이로드)

| Subject | 방향 | 페이로드 |
|---|---|---|
| `room.<room_id>.client` | gateway → game | `{ room_id, nickname, raw_message }` |
| `room.<room_id>.event`  | game → gateway | `{ type: "echo_result", payload: {...} }` |

> 명시적으로 `room_id` 를 페이로드에도 한 번 더 넣어둔다 — subject 파싱 실패 시 fallback 가능하고, 디버깅도 쉽다.

---

## 5. 검증 방법

```bash
# 1) 띄우기
docker compose up -d

# 2) 방 생성
curl -X POST localhost:8080/rooms
# {"room_id":"abc-123"}

# 3) 두 탭 (websocat 두 개)
websocat 'ws://localhost:8080/rooms/abc-123?nickname=A'
websocat 'ws://localhost:8080/rooms/abc-123?nickname=B'

# 4) 한쪽에서:
{"type":"echo","payload":{"text":"hi"}}
# → 양쪽에 echo_result 가 도착하면 성공.

# 5) 한쪽 Ctrl+C
# → 다른쪽에 user_left 이벤트가 도착하면 성공.

# 6) 추가 검증 — game 만 죽이면 echo 가 멈춰야 한다.
docker compose stop game
# 메시지 보내도 echo_result 안 옴. (gateway 가 game 우회 못 한다는 증명)
```

---

## 6. 열린 질문 (직접 결정 / 필요시 AI 에 질문)

- [ ] room 생성 시점에 game 에 미리 알릴지, 아니면 첫 WS 접속 시 lazy 생성할지. (M1 권장: lazy)
- [ ] `room.*.client` 페이로드에 nickname 을 그대로 넣을지, gateway 가 발급한 conn_id 를 넣을지. (M2 의 "결과 권위" 와 연결됨)
- [ ] 같은 nickname 두 명이 같은 방에 들어왔을 때 정책. (M1 에선 그냥 둘 다 통과시켜도 됨)
- [ ] WS write 가 막힌 client 처리 — drop 인지, 큐 비우기인지. (gorilla 공식 chat 예제 패턴 참고)
