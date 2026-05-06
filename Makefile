# ── 변수 ───────────────────────────────────────────
NATS_URL        ?= nats://localhost:4222
HTTP_ADDR       ?= :8080
BIN_DIR         := bin
NATS_CONTAINER  := coffee-bet-nats
GATEWAY_PORT    := 8080

# ── PHONY ──────────────────────────────────────────
.PHONY: help \
        run-nats run-nats-bg stop-nats \
        run-gateway stop-gateway \
        run-game stop-game \
        stop-all \
        tidy build clean

help:
	@echo "사용 가능한 타겟:"
	@echo ""
	@echo "  ▸ 실행 (foreground — Ctrl+C 로 종료)"
	@echo "    make run-nats         NATS 컨테이너 띄우기 (4222, 8222)"
	@echo "    make run-gateway      gateway-service 실행"
	@echo "    make run-game         game-service 실행"
	@echo ""
	@echo "  ▸ 실행 (background)"
	@echo "    make run-nats-bg      NATS 백그라운드 기동"
	@echo ""
	@echo "  ▸ 종료 (잃어버린 프로세스 청소용)"
	@echo "    make stop-nats        NATS 컨테이너 정지"
	@echo "    make stop-gateway     gateway 종료 (port $(GATEWAY_PORT) 점유 프로세스)"
	@echo "    make stop-game        game 종료 (pkill)"
	@echo "    make stop-all         위 셋 다"
	@echo ""
	@echo "  ▸ 모듈 / 빌드"
	@echo "    make tidy             모든 모듈 go mod tidy + go work sync"
	@echo "    make build            두 서비스 빌드 → $(BIN_DIR)/"
	@echo "    make clean            $(BIN_DIR)/ 정리"

# ── 인프라 ─────────────────────────────────────────
run-nats:
	docker run --rm --name $(NATS_CONTAINER) -p 4222:4222 -p 8222:8222 nats:alpine

run-nats-bg:
	docker run -d --rm --name $(NATS_CONTAINER) -p 4222:4222 -p 8222:8222 nats:alpine
	@echo "✓ NATS 백그라운드 기동 ($(NATS_CONTAINER)). 종료: make stop-nats"

stop-nats:
	@docker stop $(NATS_CONTAINER) >/dev/null 2>&1 && echo "✓ $(NATS_CONTAINER) 정지" || echo "(정지할 NATS 컨테이너 없음)"

# ── 서비스 실행 ────────────────────────────────────
run-gateway:
	NATS_URL=$(NATS_URL) HTTP_ADDR=$(HTTP_ADDR) go run ./gateway/cmd/...

stop-gateway:
	@PIDS=$$(lsof -ti:$(GATEWAY_PORT) 2>/dev/null); \
	if [ -n "$$PIDS" ]; then kill $$PIDS && echo "✓ gateway 종료 (PID: $$PIDS)"; \
	else echo "(gateway 안 떠 있음)"; fi

run-game:
	NATS_URL=$(NATS_URL) go run ./game/cmd/...

stop-game:
	@pkill -f "coffee-bet/game/cmd" >/dev/null 2>&1 && echo "✓ game 종료" || echo "(game 안 떠 있음)"

stop-all: stop-gateway stop-game stop-nats

# ── 모듈 / 워크스페이스 ────────────────────────────
tidy:
	cd gateway && go mod tidy
	cd game    && go mod tidy
	cd shared  && go mod tidy
	cd proto   && go mod tidy
	go work sync

# ── 빌드 ───────────────────────────────────────────
build:
	@mkdir -p $(BIN_DIR)
	go build -o $(BIN_DIR)/gateway ./gateway/cmd/...
	go build -o $(BIN_DIR)/game    ./game/cmd/...
	@echo "✓ 빌드 완료 → $(BIN_DIR)/"

clean:
	rm -rf $(BIN_DIR)
	@echo "✓ $(BIN_DIR)/ 제거"
