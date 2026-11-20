# syntax=docker/dockerfile:1

FROM rust:1-bookworm AS builder

WORKDIR /build

# 依存クレートのキャッシュ効率化のため先にマニフェスト類をコピーしてダミービルド
COPY Cargo.toml Cargo.lock* ./
RUN mkdir -p src && \
    touch src/lib.rs && \
    echo 'fn main() {}' > src/main.rs && \
    cargo build --release --bin kumogakure-api && \
    rm -rf src target/release/kumogakure-api target/release/deps/kumogakure_api* target/release/deps/libkumogakure_api*

# 実ソースコードをコピーしてリリースビルド
COPY src ./src
COPY migrations ./migrations
COPY assets ./assets
RUN touch src/lib.rs src/main.rs && cargo build --release --bin kumogakure-api

FROM debian:bookworm-slim AS runtime

RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    useradd --system --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser

WORKDIR /app

COPY --from=builder /build/target/release/kumogakure-api /app/kumogakure-api
COPY --from=builder /build/assets/fonts /app/assets/fonts

USER 10001:10001

ENV PORT=8080 \
    FONTS_DIR=/app/assets/fonts

EXPOSE 8080

CMD ["/app/kumogakure-api"]
