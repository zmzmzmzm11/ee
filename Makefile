# EveBox Makefile
#
# Requirements:
#    - GNU Make

# Version info.
CARGO_VERSION	:=	$(shell cat Cargo.toml | \
			    awk '/^version/ { gsub(/"/, "", $$3); print $$3 }')
VERSION	:=		$(shell echo $(CARGO_VERSION) | \
				sed 's/\(.*\)\-.*/\1/')
VERSION_SUFFIX	:=	$(shell echo $(CARGO_VERSION) | \
				sed -n 's/.*-\(.*\)/\1/p')

BUILD_REV	?=	$(shell git rev-parse --short HEAD)
BUILD_DATE	?=	$(shell date +%s)
export BUILD_DATE

CARGO ?=	cargo

APP :=		evebox

WEBAPP_SRCS :=	$(shell find webapp -type f | grep -v node_modules)

HOST_TARGET := $(shell rustc -Vv| awk '/^host/ { print $$2 }')
TARGET ?= $(HOST_TARGET)
OS := $(shell rustc --target $(TARGET) --print cfg | awk -F'"' '/target_os/ { print $$2 }')
ifeq ($(OS),windows)
APP_EXT := .exe
endif

CARGO_BUILD_ARGS :=
ifdef TARGET
CARGO_BUILD_ARGS += --target $(TARGET)
endif

ifneq ($(VERSION_SUFFIX),)
DIST_VERSION := devel
else
DIST_VERSION :=	$(VERSION)
endif
DIST_ARCH :=	$(shell rustc --target $(TARGET) --print cfg | \
			awk -F'"' '/target_arch/ { print $$2 }' | \
			sed -e 's/x86_64/x64/' | sed -e 's/aarch64/arm64/')
EVEBOX_BIN :=	target/$(TARGET)/release/$(APP)$(APP_EXT)

all: evebox

clean:
	rm -rf dist target resources/public resources/webapp
	find . -name \*~ -exec rm -f {} \;
	$(MAKE) -C webapp clean

.PHONY: dist rpm deb

resources/webapp/index.html: $(WEBAPP_SRCS)
	cd webapp && $(MAKE)
webapp: resources/webapp/index.html

# Build's EveBox for the host platform.
evebox: webapp
	$(CARGO) build

dist: DIST_NAME ?= $(APP)-$(DIST_VERSION)-$(OS)-$(DIST_ARCH)
dist: DIST_DIR ?= dist/$(DIST_NAME)
dist:
	echo "Building $(DIST_NAME)..."
	$(MAKE) -C webapp
	$(CARGO) build --release $(CARGO_BUILD_ARGS)
	mkdir -p $(DIST_DIR)
	cp $(EVEBOX_BIN) $(DIST_DIR)/
	mkdir -p $(DIST_DIR)/examples
	cp examples/agent.yaml $(DIST_DIR)/examples/
	cp examples/evebox.yaml $(DIST_DIR)/examples/
	cd dist && zip -r $(DIST_NAME).zip $(DIST_NAME)

fmt:
	cargo fmt
	cd webapp && npm run fmt

fixup:
	$(MAKE) fmt
	cargo clippy --fix --allow-dirty

# ===== Docker Targets =====

DOCKER_IMAGE ?= evebox
DOCKER_TAG   ?= latest

# Build Docker image only (no compose)
docker:
	docker build \
		--build-arg GIT_REV=$(BUILD_REV) \
		--build-arg BUILD_REV=$(BUILD_REV) \
		-t $(DOCKER_IMAGE):$(DOCKER_TAG) \
		.

# Build and start with docker-compose (production: EveBox + ES)
docker-up:
	GIT_REV=$(BUILD_REV) BUILD_REV=$(BUILD_REV) \
		docker compose up -d --build

# Start with docker-compose (development: + simulator, auth disabled)
docker-dev:
	GIT_REV=$(BUILD_REV) BUILD_REV=$(BUILD_REV) \
		docker compose -f docker-compose.dev.yml up -d --build

# Start with SQLite standalone (no ES required)
docker-sqlite:
	GIT_REV=$(BUILD_REV) BUILD_REV=$(BUILD_REV) \
		docker compose -f docker-compose.sqlite.yml up -d --build

# Stop docker-compose (all variants)
docker-down:
	docker compose down 2>/dev/null || true
	docker compose -f docker-compose.dev.yml down 2>/dev/null || true
	docker compose -f docker-compose.sqlite.yml down 2>/dev/null || true

# View logs (follow mode)
docker-logs:
	docker compose logs -f

# View all container status
docker-ps:
	docker compose ps
	docker compose -f docker-compose.dev.yml ps 2>/dev/null || true
	docker compose -f docker-compose.sqlite.yml ps 2>/dev/null || true

# Push Docker image to registry
docker-push:
	docker push $(DOCKER_IMAGE):$(DOCKER_TAG)

# Full release: binary + docker image
docker-release: dist docker
	@echo "Release $(DIST_VERSION) built"
	@echo "  Binary: $(EVEBOX_BIN)"
	@echo "  Docker: $(DOCKER_IMAGE):$(DOCKER_TAG)"

# Clean Docker artifacts (images, containers, volumes)
docker-clean:
	docker compose down -v 2>/dev/null || true
	docker compose -f docker-compose.dev.yml down -v 2>/dev/null || true
	docker compose -f docker-compose.sqlite.yml down -v 2>/dev/null || true
	docker rmi $(DOCKER_IMAGE):$(DOCKER_TAG) 2>/dev/null || true
