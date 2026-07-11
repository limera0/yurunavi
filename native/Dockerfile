# yurunavi_server — stateless fun-road scoring HTTP API
#
# Talks to Valhalla (separate container) over plain http://localhost:8002,
# hardcoded in src/main.rs. Because of that, this image is intended to be
# run with `network_mode: host` so "localhost" inside the container still
# reaches the host's published Valhalla port, exactly like the old
# systemd-run binary did. See docker/docker-compose.yml.

# ---- Build stage ------------------------------------------------------
# Pinned to the host toolchain version (rustc/cargo 1.95.0) for
# reproducibility.
FROM rust:1.95.0-slim-bookworm AS builder

WORKDIR /app

COPY Cargo.toml Cargo.lock ./
COPY src ./src

# Only the yurunavi_server bin is needed at runtime; the cdylib/staticlib
# target (Flutter FFI bridge) is irrelevant here and is not built.
RUN cargo build --release --locked --bin yurunavi_server

# ---- Runtime stage ------------------------------------------------------
FROM debian:bookworm-slim

# ca-certificates for robustness (outbound HTTP client is rustls-based and
# currently only ever calls plain http://localhost:8002, but this keeps the
# image ready for https without surprises). curl is used by HEALTHCHECK.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN useradd --system --no-create-home --shell /usr/sbin/nologin yurunavi

COPY --from=builder /app/target/release/yurunavi_server /usr/local/bin/yurunavi_server

USER yurunavi

EXPOSE 8003

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -fsS http://localhost:8003/health || exit 1

CMD ["/usr/local/bin/yurunavi_server"]
