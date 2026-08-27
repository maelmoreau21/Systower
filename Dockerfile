# ============================================================================
# Stage 1: Build & install production dependencies with pnpm
# ============================================================================
FROM node:20-alpine AS app-builder

WORKDIR /app
RUN corepack enable pnpm

COPY app/package.json ./
RUN pnpm install --prod --no-optional

# ============================================================================
# Stage 2: Ultra-lightweight Final Runtime Image (v1.0.0)
# ============================================================================
FROM alpine:3.20

LABEL maintainer="Mael"
LABEL org.opencontainers.image.title="Systower"
LABEL org.opencontainers.image.description="Lightweight Docker container and local host system updater with Web UI & Auth — an improved Watchtower alternative"
LABEL org.opencontainers.image.source="https://github.com/maelmoreau21/Systower"
LABEL org.opencontainers.image.licenses="MIT"

# Install packages without any npm/pnpm overhead in the final runtime
RUN apk add --no-cache \
    bash \
    curl \
    docker-cli \
    jq \
    nodejs \
    tzdata \
    util-linux \
    && mkdir -p /config /scripts /app /var/log

# Copy web application and pnpm production node_modules from builder
COPY app/ /app/
COPY --from=app-builder /app/node_modules /app/node_modules

# Copy scripts
COPY scripts/ /scripts/

# Make all scripts executable
RUN chmod +x /scripts/*.sh

# Create log files
RUN touch /var/log/systower.log /var/log/systower-ui.log

# Memory optimization for Node.js engine (< 15MB RAM)
ENV NODE_OPTIONS="--max-old-space-size=32 --optimize_for_size"

# Default environment variables
ENV SYSTOWER_CONFIG_FILE="/config/systower.json" \
    SYSTOWER_CRON="0 4 * * *" \
    SYSTOWER_RUN_ON_START="true" \
    SYSTOWER_DOCKER_ENABLED="true" \
    SYSTOWER_SYSTEM_ENABLED="false" \
    SYSTOWER_DOCKER_EXCLUDE="" \
    SYSTOWER_DOCKER_INCLUDE_ONLY="" \
    SYSTOWER_DOCKER_CLEANUP="true" \
    SYSTOWER_DOCKER_STOP_TIMEOUT="30" \
    SYSTOWER_DOCKER_MONITOR_ONLY="false" \
    SYSTOWER_DOCKER_HEALTHCHECK_TIMEOUT="30" \
    SYSTOWER_SYSTEM_REBOOT="false" \
    SYSTOWER_NOTIFY_ENABLED="false" \
    SYSTOWER_NOTIFY_DISCORD="" \
    SYSTOWER_NOTIFY_SLACK="" \
    SYSTOWER_NOTIFY_TELEGRAM_TOKEN="" \
    SYSTOWER_NOTIFY_TELEGRAM_CHAT="" \
    SYSTOWER_NOTIFY_WEBHOOK="" \
    SYSTOWER_UI_ENABLED="true" \
    SYSTOWER_UI_PORT="8080" \
    SYSTOWER_AUTH_USERNAME="" \
    SYSTOWER_AUTH_PASSWORD="" \
    SYSTOWER_OIDC_ENABLED="false" \
    SYSTOWER_OIDC_ISSUER="" \
    SYSTOWER_OIDC_CLIENT_ID="" \
    SYSTOWER_OIDC_CLIENT_SECRET="" \
    SYSTOWER_OIDC_REDIRECT_URI="" \
    SYSTOWER_LOG_LEVEL="info" \
    SYSTOWER_DRY_RUN="false" \
    TZ="UTC"

EXPOSE 8080

# Health check — fast start-period and interval to become healthy in 2s
HEALTHCHECK --interval=10s --timeout=2s --start-period=2s --retries=2 \
    CMD pgrep crond > /dev/null || exit 1

ENTRYPOINT ["/scripts/entrypoint.sh"]
