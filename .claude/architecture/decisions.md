# Architecture Decisions

> 이 문서는 ADR(Architecture Decision Record) 의 가벼운 버전이다.
> 각 결정은 *언제 / 왜 / 무엇을 / 기존 결정과의 차이* 를 적는다.
>
> **중요**: 아래 결정 중 일부는 `project-spec.md` 의 기존 항목을 **뒤집는다** (특히 §10 비목표의 "마이크로서비스 분리" 항목). 충돌 시 이 문서가 최신이다.

---

## 2026-04-29 — 대규모 방향 전환

대화 흐름에서 다섯 가지 결정이 한꺼번에 내려졌다. M1 시작 전에 잡고 가는 큰 그림이다.

### 배경

`project-spec.md` 는 원래 "단일 바이너리 → 점진 확장" 가정이었다. 하지만 사용자의 진짜 학습 목표가 "**MSA · 서버 아키텍처 · 메시지 브로커**" 라는 게 명확해지면서, 처음부터 분산 구조로 가기로 결정했다.

> "공부 목적이라 처음부터 MSA 로 갈 거임. NATS 도 경험해보고 싶음."
>
> — 사용자, 2026-04-29

이건 "실용적으로는 오버엔지니어링" 이지만, "학습 목적으로는 정답" 이다. 분산 시스템 이슈를 직접 부딪혀봐야 배우는 영역이기 때문.

---

### Decision 1 — 처음부터 MSA, gateway / game 별도 프로세스

**무엇**

- `gateway-service` 와 `game-service` 를 **별도 binary, 별도 프로세스** 로 운영한다.
- 클라이언트는 오직 gateway 와만 통신 (WS / HTTP).
- gateway ↔ game 은 NATS 로 통신.

**Why**

- MSA / 서버 아키텍처 학습 자체가 목적.
- 단일 바이너리로 시작하면 "왜 분리하는가" 의 고민을 회피하게 됨.
- gateway 의 connection 부하와 game 의 비즈니스 로직 부하가 명확히 다른 축이라 분리 학습 가치가 큼.

**기존 spec 과 차이**

- `project-spec.md` §10 비목표의 **"마이크로서비스 분리"** 항목 → **무효화**.
- §5.1 단일 바이너리 그림 → 이 문서의 `system.md` 그림으로 대체.

**유보**

- `room-service` 분리는 아직 안 함. 룰렛/사다리는 결국 "방 단위" 라 트랜잭션 경계가 game 과 거의 일치하기 때문. M3~M4 에서 도메인 독립성이 확실해지면 그때 분리.
- `auth-service` 도 아직 안 함. 닉네임 기반 게스트 입장이라 인증 로직이 거의 없음.

---

### Decision 2 — NATS, 단계적 도입 (core → JetStream)

**무엇**

- 메시지 브로커는 **NATS**.
- M1~M2 는 **core NATS pub/sub** 만 사용.
- "메시지 유실되면 안 되는 시점" 이 생기는 단계 (예: 게임 결과 영속화 직전) 에 **JetStream** 도입.

**Why**

- 사용자가 "메시지 브로커를 경험해보고 싶다" 고 명시.
- core → JetStream 전환을 **한번에 안 하고 단계 분리** 하면, "왜 persistent 가 필요한가" 를 직접 느끼게 된다.

**유보**

- request-reply 패턴을 어느 시점에 도입할지는 미정. 일단 모든 통신은 fire-and-forget pub/sub 으로 시작.

---

### Decision 3 — 메시지 포맷은 Protobuf (학습 후 도입)

**무엇**

- gateway ↔ game 사이 메시지 페이로드는 **Protobuf**.
- `.proto` 파일이 두 서비스 사이의 **계약서** 가 된다.
- 단, 도입은 **사용자가 Protobuf 개념을 학습한 뒤**. 그 전까지는 임시로 JSON 사용 가능.

**Why**

- service contract 개념을 직접 익히는 게 MSA 학습의 핵심.
- 한쪽이 필드 이름 바꿔도 컴파일 에러 안 나는 JSON 의 함정을 몸으로 느껴봐야 함.

**클라이언트 ↔ gateway 사이는 별개**

- WS 메시지는 브라우저 친화적인 **JSON** 유지 (project-spec.md §8 그대로).
- Protobuf 는 *서버 간 통신* 에만 적용.

---

### Decision 4 — Monorepo + go work

**무엇**

- 한 레포 (`github.com/JongDeug/coffee-bet`) 안에 여러 Go module 을 둔다.
- `go.work` 로 묶어서 같이 빌드.

**Why**

- 혼자 개발이라 polyrepo 의 장점 (팀별 권한 분리, 독립 배포 사이클) 이 의미 없음.
- proto 스키마 변경이 여러 서비스에 동시에 영향 → 한 PR 로 묶이는 게 명확.

**예상 디렉토리 구조 (초안)**

```
coffee-bet/
├── go.work
├── proto/           ← .proto 파일 + 생성된 Go 코드
├── gateway/
│   ├── go.mod
│   └── cmd/main.go
├── game/
│   ├── go.mod
│   └── cmd/main.go
└── shared/          ← 공통 유틸 (logger, config 등)
    └── go.mod
```

**기존 spec 과 차이**

- `project-spec.md` §7 의 단일 module 폴더 구조 → 위 구조로 대체.

---

### Decision 5 — Connection Hub 는 channel + goroutine ownership

**무엇**

- gateway 의 WS connection hub 는 **단일 owner goroutine + channel** 로 구성.
- `sync.Mutex` 로 map 보호하는 방식은 채택 안 함.

**Why**

- 사용자가 "Go 공부 목적이 큼" 이라고 명시.
- mutex 는 다른 언어에도 다 있어 Go 학습 가치가 낮음.
- channel / select / goroutine ownership / channel close 같은 Go 고유 패턴을 직접 만나야 학습 가치가 높음.

**참고**

- gorilla/websocket 공식 chat 예제 (`project-spec.md` §12 참고) 가 정확히 이 패턴.
