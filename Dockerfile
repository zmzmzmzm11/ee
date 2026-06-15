# EveBox Docker Image
# Multi-stage: frontend (node) → backend (rust) → runtime (alpine)
#
# Build:  docker build -t evebox:latest .
# Deploy: docker compose up -d
#
# Build args:
#   GIT_REV   - Git revision for version display (default: unknown)
#   BUILD_REV - Same as GIT_REV, for Rust build.rs

# ===== Stage 1: Frontend Build =====
FROM node:22-alpine AS frontend
WORKDIR /build/webapp

# Install dependencies (cached layer — only re-runs when package.json changes)
COPY webapp/package.json webapp/package-lock.json ./
RUN npm ci --prefer-offline

# Build frontend
COPY webapp/ ./
ARG GIT_REV=unknown
RUN echo "export const GIT_REV = \"${GIT_REV}\";" > src/gitrev.ts \
 && npm run build

# ===== Stage 2: Backend Build =====
FROM rust:1-alpine AS backend
RUN apk add --no-cache musl-dev sqlite-dev binutils
WORKDIR /build

# Prevent build.rs from trying to run git (no .git in Docker context)
ARG BUILD_REV=unknown
ENV BUILD_REV=${BUILD_REV}

# ---- Cache Rust dependency downloads ----
# This layer only re-runs when Cargo.toml or Cargo.lock change
COPY Cargo.toml Cargo.lock ./

# ---- Compile dependencies (dummy source trick) ----
# Create stub files that exercise key dependency types to compile them all.
# When src/ changes, this layer stays cached and only the binary recompiles.
RUN mkdir -p src/bin resources/configdb/migrations resources/sqlite/migrations resources/webapp
COPY <<'RUSTLIB' src/lib.rs
use std::net::SocketAddr;
use axum::{Router, routing::get};
use reqwest::Client;
use serde_json::json;
use clap::Command;

pub async fn dummy() -> SocketAddr {
    let _r: Router = Router::new().route("/", get(|| async {}));
    let _c: Client = Client::new();
    let _j = json!({"key": "value"});
    let _cmd: Command = Command::new("dummy");
    "0.0.0.0:0".parse().unwrap()
}
RUSTLIB
COPY <<'RUSTMAIN' src/bin/evebox.rs
#[tokio::main]
async fn main() {
    let _ = evebox::dummy().await;
    println!("evebox");
}
RUSTMAIN
RUN echo '<html></html>' > resources/webapp/index.html \
 && cargo build --release \
 && rm -rf src

# ---- Copy actual source ----
COPY src/ ./src/
COPY build.rs ./
COPY resources/ ./resources/

# Overlay compiled frontend from stage 1
COPY --from=frontend /build/webapp/dist ./resources/webapp/

# Build release binary (dependencies already compiled in previous layer)
RUN cargo build --release \
 && strip target/release/evebox \
 && cp target/release/evebox /evebox

# ===== Stage 3: Runtime =====
FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata sqlite-libs curl \
 && mkdir -p /var/lib/evebox

ENV EVEBOX_HTTP_HOST=0.0.0.0
ENV TZ=Asia/Shanghai
ENV EVEBOX_DATA_DIRECTORY=/var/lib/evebox

VOLUME ["/var/lib/evebox"]

COPY --from=backend /evebox /bin/evebox

EXPOSE 5636
ENTRYPOINT ["/bin/evebox", "server"]
