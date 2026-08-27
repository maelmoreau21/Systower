# ============================================================================
# Systower — Ultra-lightweight Docker Image (v1.0.0)
# ============================================================================
# Based on Alpine Linux. Total image size ~25-30MB, RAM usage < 2MB.
# Includes: docker-cli, jq, bash, curl, tzdata, util-linux (nsenter)
# ============================================================================

FROM alpine:3.20

LABEL maintainer="Mael"
LABEL org.opencontainers.image.title="Systower"
LABEL org.opencontainers.image.description="Ultra-lightweight Docker container & local host system updater — an improved Watchtower alternative"
LABEL org.opencontainers.image.source="https://github.com/maelmoreau21/Systower"
LABEL org.opencontainers.image.licenses="MIT"

# Install only essential runtime tools and create directories
RUN apk add --no-cache \
    bash \
    curl \
    docker-cli \
    jq \
    tzdata \
    util-linux \
    && mkdir -p /config /scripts /var/log

# Copy scripts
COPY scripts/ /scripts/

# Make all scripts executable and create log files
RUN chmod +x /scripts/*.sh \
    && touch /var/log/systower.log

# Default environment variables
ENV SYSTOWER_CRON="0 4 * * *" \
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
    SYSTOWER_LOG_LEVEL="info" \
    SYSTOWER_DRY_RUN="false" \
    TZ="UTC"

# Health check — verify crond daemon is alive
HEALTHCHECK --interval=30s --timeout=3s --start-period=2s --retries=2 \
    CMD pgrep crond > /dev/null || exit 1

ENTRYPOINT ["/scripts/entrypoint.sh"]
