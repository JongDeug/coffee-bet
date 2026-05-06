# Todo — coffee-bet

> 끝낸 항목은 `[x]` 로. 막힌 지점은 `❓` 로 표시해두면 나중에 한꺼번에 AI 에 질문하기 좋다.
> 코드는 직접 작성. AI 한테는 *왜? / 트레이드오프 / 디버깅* 만 묻는다.

---

## 0. 시작 전 정리 (지금 이 단계)

> 폴더는 만들어졌는데 아직 단일 `go.mod` 만 있다. Decision 4 (Monorepo + go.work) 가 미반영.
> M1 코드를 짜기 전에 워크스페이스 골격부터 잡는 게 안전하다.

- [x] **결정**: monorepo 유지 (polyrepo 로 가지 않음, 2026-04-29). `decisions.md` Decision 4 그대로.
- [x] **결정**: 루트 단일 `go.mod` 는 지우고 각 서비스 폴더에서 새로 init (A 안).
- [x] `rm go.mod` (루트 모듈 제거)
- [x] `gateway/go.mod` init — `go mod init github.com/JongDeug/coffee-bet/gateway`
- [x] `game/go.mod` init — `go mod init github.com/JongDeug/coffee-bet/game`
- [x] `shared/go.mod` init — `go mod init github.com/JongDeug/coffee-bet/shared`
- [x] `proto/go.mod` init — `go mod init github.com/JongDeug/coffee-bet/proto`
- [x] `go work init ./gateway ./game ./shared ./proto`
- [x] 빈 main 두 개가 그대로 빌드되는지 `go build ./...` 확인 (루트에서)
- [x] `go env GOWORK` 가 `coffee-bet/go.work` 가리키는지 확인
- [ ] `.gitignore` 정리 (binary, `.env`, IDE 설정)
- [ ] `Makefile` 에 최소한 `run-gateway`, `run-game`, `run-nats`, `up` 타겟 채우기

> ❓ 학습 질문 후보:
> - 모노레포에서 `go.work` vs `replace` 디렉티브의 차이가 뭔가?
> - 같은 모노레포 안에서 `shared` 모듈을 import 하면 vendor / module cache 동작이 어떻게 되나?

---

## 1. 인프라 (NATS / docker-compose)

- [ ] `docker-compose.yml` 작성
  - [ ] `nats:alpine` 4222 포트 노출
  - [ ] `gateway` 서비스 (Go 빌드 → 8080 노출)
  - [ ] `game` 서비스 (Go 빌드)
  - [ ] depends_on 으로 nats → gateway, game 순서
- [ ] `gateway/Dockerfile`, `game/Dockerfile` (multi-stage 권장)
- [ ] 환경변수 규약 정하기 (`NATS_URL`, `HTTP_ADDR`)

> ❓ 질문 후보:
> - core NATS 만 쓰는데 docker 에서 monitoring 포트 (8222) 도 열어두면 좋은가?

---

## 2. M1 — gateway-service

> 자세한 수용 기준은 `requirements-m1.md` 의 §1, §3, §5.

### 2-1. HTTP

- [ ] Gin (또는 net/http) 로 `POST /rooms` 핸들러
- [ ] room_id 는 UUID v4
- [ ] 응답 `{ "room_id": "..." }`

### 2-2. WebSocket 진입점

- [ ] `WS /rooms/:room_id` 업그레이드 (gorilla/websocket)
- [ ] 쿼리스트링 `nickname` 파싱
- [ ] Client 구조체: `conn`, `nickname`, `room_id`, `send chan []byte`

### 2-3. Hub (단일 owner goroutine)

- [ ] Hub 구조체: `register/unregister/broadcast` 채널
- [ ] Hub.run() 의 `select` 로 모든 변경을 직렬화
- [ ] room_id 별 client 목록 관리 (map\[string\][]*Client 인데 *오직 hub goroutine 만 접근*)
- [ ] mutex 사용 금지 (코드 리뷰 셀프체크)

### 2-4. read/write pump

- [ ] readPump: WS → JSON 파싱 → Hub 의 inbound 채널로
- [ ] writePump: send 채널 → WS WriteMessage
- [ ] pong/ping 핸들러 (gorilla 공식 chat 예제 참고)
- [ ] read deadline / write deadline 설정

### 2-5. NATS bridge

- [ ] NATS connect (재시도 옵션 포함)
- [ ] inbound: `room.<room_id>.client` publish
- [ ] outbound: `room.*.event` subscribe → subject 에서 room_id 파싱 → 해당 hub 로 전달

> ❓ 질문 후보:
> - readPump 에서 받은 메시지를 NATS publish 하는 goroutine 을 *별도로* 띄울지, readPump 안에서 동기 publish 할지. backpressure 의미가 다름.
> - WS conn 의 write 가 느린 client 한 명 때문에 hub 전체가 막히지 않으려면? (drop policy)
> - hub 의 broadcast 채널을 unbuffered 로 두면 어떤 데드락이 가능한가?

---

## 3. M1 — game-service

- [ ] NATS connect
- [ ] `room.*.client` subscribe
- [ ] 받은 메시지의 type 확인 → `echo` 면 그대로 `room.<room_id>.event` 로 publish
- [ ] room_id 는 subject 의 `*` 위치에서 파싱
- [ ] gateway 코드 import 안 한다는 컴파일 검증

> ❓ 질문 후보:
> - subscribe queue group 을 지정해야 하는 시점은 언제인가? (M1 단일 인스턴스니까 일단 안 해도 됨)
> - subject naming 컨벤션 — `room.<id>.event` vs `events.room.<id>` 어느 게 NATS 컨벤션에 맞나?

---

## 4. M1 — shared/

- [ ] (필요해지면) 로거 thin wrapper
- [ ] (필요해지면) NATS connect 헬퍼
- [ ] 처음부터 만들지 말 것 — 두 서비스에서 진짜 중복이 보이면 그때 추출

---

## 5. M1 — 검증

- [ ] `requirements-m1.md` §5 의 시나리오 그대로 통과
- [ ] DoD 9 항목 전부 체크
- [ ] README 에 시연 방법 1 페이지 추가

---

## 6. M2 — 룰렛 (덩어리 단위, M1 끝나면 세분화)

- [ ] Protobuf 학습 + `proto/roulette.proto` 작성 → Go 코드 생성
- [ ] `RouletteStartCmd`, `RouletteFinished` 메시지 정의
- [ ] game-service 에 룰렛 결과 결정 로직 (서버 권위)
- [ ] gateway → NATS subject `game.roulette.start` publish
- [ ] `started_at` 으로 클라이언트 애니메이션 동기화
- [ ] 단위 테스트: 결과 분포 / 결정성

---

## 7. M3 — 사다리

- [ ] 사다리 자료구조 + 매핑 생성 알고리즘
- [ ] `LadderFinished` 메시지
- [ ] 두 클라이언트가 같은 사다리·매핑을 받는지 검증

---

## 8. M4 — reconnect / host

- [ ] 게임 진행 상태를 game-service 가 in-memory 로 들고 있음
- [ ] WS 재접속 시 `room_state` 단발성 전송 → 현재 상태 복원
- [ ] 호스트 이탈 → 다음 사람에게 위임 정책
- [ ] 호스트 권한 액션 (시작 / 리셋 / 추방)

---

## 9. M5 — 영속화

- [ ] SQLite 도입 (game-service 쪽)
- [ ] 결과 저장 / 히스토리 조회 API
- [ ] 이 시점부터 NATS 를 **JetStream** 으로 전환 (메시지 유실되면 안 되는 시점)

---

## 10. M6 — 멀티 인스턴스

- [ ] gateway 인스턴스 두 개 띄우기
- [ ] 같은 room 에 인스턴스가 다른 conn 들이 들어와도 broadcast 일관성
- [ ] Redis pub/sub 도입 결정 — 또는 NATS subject 만으로 충분한지 비교

---

## 미정 / 백로그

- [ ] 프론트엔드 (Next.js) 골격 — 백엔드 M2 끝났을 때 얹기
- [ ] CI (GitHub Actions, lint + test)
- [ ] graceful shutdown 의 "제대로 된" 형태 (NATS drain → WS close → HTTP shutdown)
- [ ] 부하 테스트 (k6 또는 vegeta) — M4 이후
- [ ] OpenTelemetry / 트레이싱 — M6 이후
