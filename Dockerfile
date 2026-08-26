# ============================================================================
# Systower — Ultra-lightweight Docker Image (v2)
# ============================================================================
# Based on Alpine Linux with Node.js Web UI & OIDC SSO.
# Includes: docker-cli, openssh-client, jq, bash, curl, nodejs, npm
# ============================================================================

FROM alpine:3.20

LABEL maintainer="Mael"
LABEL org.opencontainers.image.title="Systower"
LABEL org.opencontainers.image.description="Lightweight Docker container and system updater with Web UI & OIDC SSO — an improved Watchtower alternative"
LABEL org.opencontainers.image.source="https://github.com/Mael/Systower"
LABEL org.opencontainers.image.licenses="MIT"

# Install required packages in a single layer to minimize image size
RUN apk add --no-cache \
    bash \
    curl \
    docker-cli \
    docker-cli-compose \
    jq \
    nodejs \
    npm \
    openssh-client \
    tzdata \
    && mkdir -p /config/ssh /scripts /app /var/log

# Copy web application and install dependencies
COPY app/ /app/
RUN cd /app && npm install --omit=dev --no-audit --no-fund

# Copy scripts
COPY scripts/ /scripts/

# Make all scripts executable
RUN chmod +x /scripts/*.sh

# Create log files
RUN touch /var/log/systower.log /var/log/systower-ui.log

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
    SYSTOWER_DOCKER_COMPOSE_AWARE="true" \
    SYSTOWER_SYSTEM_HOSTS="" \
    SYSTOWER_SYSTEM_HOSTS_FILE="/config/hosts.conf" \
    SYSTOWER_SYSTEM_SSH_KEY="/config/ssh/id_rsa" \
    SYSTOWER_SYSTEM_REBOOT="false" \
    SYSTOWER_NOTIFY_ENABLED="false" \
    SYSTOWER_NOTIFY_DISCORD="" \
    SYSTOWER_NOTIFY_SLACK="" \
    SYSTOWER_NOTIFY_TELEGRAM_TOKEN="" \
    SYSTOWER_NOTIFY_TELEGRAM_CHAT="" \
    SYSTOWER_NOTIFY_WEBHOOK="" \
    SYSTOWER_UI_ENABLED="true" \
    SYSTOWER_UI_PORT="8080" \
    SYSTOWER_OIDC_ENABLED="false" \
    SYSTOWER_OIDC_ISSUER="" \
    SYSTOWER_OIDC_CLIENT_ID="" \
    SYSTOWER_OIDC_CLIENT_SECRET="" \
    SYSTOWER_OIDC_REDIRECT_URI="" \
    SYSTOWER_LOG_LEVEL="info" \
    SYSTOWER_DRY_RUN="false" \
    TZ="UTC"

EXPOSE 8080

# Health check — verify crond is running
HEALTHCHECK --interval=60s --timeout=5s --retries=3 \
    CMD pgrep crond > /dev/null || exit 1

ENTRYPOINT ["/scripts/entrypoint.sh"]
