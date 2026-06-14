# EveBox Docker Image
# Build: docker build -t evebox:latest .
# Multi-stage: frontend (node) → backend (rust) → runtime (alpine)

# ===== Stage 1: Frontend Build =====
FROM node:22-alpine AS frontend
WORKDIR /build/webapp
COPY webapp/package.json webapp/package-lock.json ./
RUN npm ci --prefer-offline
COPY webapp/ ./
ARG GIT_REV=unknown
RUN echo "export const GIT_REV = \"${GIT_REV}\";" > src/gitrev.ts \
 && npm run build

# ===== Stage 2: Backend Build =====
FROM rust:1.85-alpine AS backend
RUN apk add --no-cache musl-dev sqlite-dev
WORKDIR /build
# Copy dependency manifests first for caching
COPY Cargo.toml Cargo.lock ./
COPY src/ ./src/
COPY resources/configdb/ ./resources/configdb/
# Copy built frontend
COPY --from=frontend /build/webapp/dist ./resources/webapp/
RUN cargo build --release \
 && strip target/release/evebox

# ===== Stage 3: Runtime =====
FROM alpine:3.21
RUN apk add --no-cache ca-certificates tzdata sqlite-libs \
 && mkdir -p /var/lib/evebox

ENV EVEBOX_HTTP_HOST=0.0.0.0
ENV TZ=Asia/Shanghai
ENV EVEBOX_DATA_DIRECTORY=/var/lib/evebox
VOLUME /var/lib/evebox

COPY --from=backend /build/target/release/evebox /bin/evebox
EXPOSE 5636
ENTRYPOINT ["/bin/evebox", "server"]
