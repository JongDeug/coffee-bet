# ── 변수 ───────────────────────────────────────────
NATS_URL    ?= nats://localhost:4222
HTTP_ADDR   ?= :8080
BIN_DIR     := bin

# ── PHONY ──────────────────────────────────────────
.PHONY: help run-nats run-gateway run-game tidy build clean

help:
	@echo "사용 가능한 타겟:"
	@echo "  make run-nats      NATS 컨테이너 띄우기 (4222, 8222)"
	@echo "  make run-gateway   gateway-service 실행"
	@echo "  make run-game      game-service 실행"
	@echo "  make tidy          모든 모듈 go mod tidy + go work sync"
	@echo "  make build         두 서비스 빌드 → $(BIN_DIR)/"
	@echo "  make clean         $(BIN_DIR)/ 정리"

# ── 인프라 ─────────────────────────────────────────
run-nats:
	docker run --rm -p 4222:4222 -p 8222:8222 nats:alpine

# ── 서비스 실행 ────────────────────────────────────
run-gateway:
	NATS_URL=$(NATS_URL) HTTP_ADDR=$(HTTP_ADDR) go run ./gateway/cmd/...

run-game:
	NATS_URL=$(NATS_URL) go run ./game/cmd/...

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
