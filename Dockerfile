# ============================================================================
# Systower — Ultra-lightweight Docker Image
# ============================================================================
# Based on Alpine Linux for minimal footprint (~25-30MB final image).
# Includes: docker-cli, openssh-client, jq, bash, curl
# ============================================================================

FROM alpine:3.20

LABEL maintainer="Mael"
LABEL org.opencontainers.image.title="Systower"
LABEL org.opencontainers.image.description="Lightweight Docker container and system updater — an improved Watchtower alternative"
LABEL org.opencontainers.image.source="https://github.com/Mael/Systower"
LABEL org.opencontainers.image.licenses="MIT"

# Install required packages in a single layer to minimize image size
RUN apk add --no-cache \
    bash \
    curl \
    docker-cli \
    jq \
    openssh-client \
    tzdata \
    && mkdir -p /config/ssh /scripts /var/log

# Copy scripts
COPY scripts/ /scripts/

# Make all scripts executable
RUN chmod +x /scripts/*.sh

# Create log file
RUN touch /var/log/systower.log

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
    SYSTOWER_SYSTEM_HOSTS="" \
    SYSTOWER_SYSTEM_HOSTS_FILE="/config/hosts.conf" \
    SYSTOWER_SYSTEM_SSH_KEY="/config/ssh/id_rsa" \
    SYSTOWER_SYSTEM_REBOOT="false" \
    SYSTOWER_LOG_LEVEL="info" \
    SYSTOWER_DRY_RUN="false" \
    TZ="UTC"

# Health check — verify crond is running
HEALTHCHECK --interval=60s --timeout=5s --retries=3 \
    CMD pgrep crond > /dev/null || exit 1

ENTRYPOINT ["/scripts/entrypoint.sh"]
