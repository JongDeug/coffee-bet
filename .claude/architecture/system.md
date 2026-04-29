# System Architecture

> `decisions.md` 의 결정을 시각화한 문서. 결정 자체는 그쪽에 있고, 여기는 *그림과 흐름* 만 담는다.

---

## 1. 큰 그림

```
┌─────────────┐
│   브라우저   │
│  (Next.js)  │
└──────┬──────┘
       │ WebSocket / HTTP
       ▼
┌────────────────────┐
│  gateway-service   │   ← WS 진입점, connection hub, event routing
│   (Go binary)      │
└──────┬─────────────┘
       │ NATS (pub/sub, 추후 JetStream)
       ▼
┌────────────────────┐
│   game-service     │   ← 룰렛/사다리/벌칙 결과 결정, 도메인 로직
│   (Go binary)      │
└────────────────────┘
```

---

## 2. 서비스별 책임

### gateway-service

| 책임 | 비책임 |
|---|---|
| WS upgrade / connection 관리 | 게임 결과 결정 |
| connection hub (room → conns 매핑) | 비즈니스 로직 |
| broadcast (NATS 메시지 → WS 다중 송출) | 영속화 |
| HTTP API 의 일부 (방 생성 등) — 단순 위임 | 게임 도메인 처리 |

> **원칙**: gateway 는 "실시간 전달" 만. 비즈니스 로직 최소화. WS connection 수천 개 들어와도 무거운 일 안 시켜야 함.

### game-service

| 책임 | 비책임 |
|---|---|
| 룰렛 결과 결정 (서버 권위) | WS connection 관리 |
| 사다리 구조 + 매핑 생성 | 클라이언트 직접 통신 |
| 벌칙 추첨 | broadcast 송출 (gateway 가 함) |

> **원칙**: client 의 존재를 모르고 동작해야 함. NATS 메시지로만 입출력.

---

## 3. 데이터 흐름 — 룰렛 시작 예시

```
┌──────────┐
│ Client   │
└────┬─────┘
     │ WS: { "type": "start_roulette", "items": ["A","B","C"] }
     ▼
┌────────────────┐
│ gateway        │  conn → user_id, room_id 결합
└────┬───────────┘
     │ NATS publish
     │   subject: "game.roulette.start"
     │   payload: RouletteStartCmd{ room_id, requester_id, items }
     ▼
┌────────────────┐
│ game           │  결과 계산 (서버 권위)
└────┬───────────┘
     │ NATS publish
     │   subject: "room.<room_id>.event"
     │   payload: RouletteFinished{ winner, items, seed, started_at }
     ▼
┌────────────────┐
│ gateway        │  subject 의 room_id 추출 → hub 에서 그 room 의 conn 들 조회
└────┬───────────┘
     │ WS broadcast: { "type": "roulette_result", "payload": {...} }
     ▼
┌──────────┐
│ Clients  │  애니메이션 동기화 → 결과 공개
└──────────┘
```

**핵심 포인트**

- 결과 결정은 **무조건 game-service**. 클라이언트가 보낸 시드/결과는 신뢰 X.
- `started_at` 은 game 이 찍은 server time. 모든 클라가 이걸 기준으로 애니메이션 동기화.
- gateway 는 NATS subject 의 room_id 를 보고 *어느 conn 들에게 보낼지* 만 결정.

---

## 4. 단일 인스턴스 가정

- gateway / game 각각 **1개 프로세스만** 띄운다.
- hub map 은 단일 프로세스 메모리에만 존재.
- 같은 room 에 들어온 conn 들이 *같은 gateway 인스턴스* 에 붙어있음을 가정.

---

## 5. 배포 단위

```
gateway-service  →  하나의 Go binary  →  단독 Docker 이미지
game-service     →  하나의 Go binary  →  단독 Docker 이미지
NATS             →  공식 nats:alpine 이미지
```

docker-compose 로 한꺼번에 띄운다.
