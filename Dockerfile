FROM rust:1.88-alpine AS builder

RUN apk add --no-cache musl-dev
WORKDIR /build
COPY Cargo.toml Cargo.lock ./
COPY src ./src
COPY benches ./benches
RUN cargo build --release

FROM alpine:3.20
RUN apk add --no-cache ca-certificates tzdata
COPY --from=builder /build/target/release/systower /usr/local/bin/systower

ENV SYSTOWER_CRON="0 4 * * *" \
    SYSTOWER_RUN_ON_START="true" \
    SYSTOWER_DOCKER_ENABLED="true" \
    SYSTOWER_SYSTEM_ENABLED="false" \
    SYSTOWER_DOCKER_HEALTHCHECK_TIMEOUT="60" \
    SYSTOWER_DOCKER_STOP_TIMEOUT="30" \
    SYSTOWER_DOCKER_ALLOW_NO_HEALTHCHECK="false" \
    SYSTOWER_STATE_FILE="/var/lib/systower/state.jsonl" \
    SYSTOWER_LOG_LEVEL="info"

RUN mkdir -p /var/lib/systower
VOLUME ["/var/lib/systower"]
ENTRYPOINT ["/usr/local/bin/systower"]
CMD ["run"]