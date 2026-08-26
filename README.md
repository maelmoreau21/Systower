<div align="center">

# 🏗️ Systower

**Modern Lightweight Docker Container & System Updater with Web UI & OIDC SSO**

*An improved, state-of-the-art alternative to Watchtower*

[![Build & Push](https://github.com/Mael/Systower/actions/workflows/build.yml/badge.svg)](https://github.com/Mael/Systower/actions/workflows/build.yml)
[![Tests & Lint](https://github.com/Mael/Systower/actions/workflows/test.yml/badge.svg)](https://github.com/Mael/Systower/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker Image Size](https://img.shields.io/badge/image%20size-~40MB-brightgreen)](https://github.com/Mael/Systower/pkgs/container/systower)
[![Multi-Arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64%20%7C%20armv7%20%7C%20armv6-purple)](https://github.com/Mael/Systower)

</div>

---

## ✨ Features

- 🐳 **Docker Container Updates** — Pull latest images and recreate containers preserving full configuration (networks, volumes, ports, caps, devices, env, restart policies).
- 🖥️ **System Updates via SSH** — Remotely update Debian, Ubuntu, Raspberry Pi OS, and Alpine Linux hosts.
- 🌐 **Modern Web UI Dashboard** — Clean, responsive dark-mode dashboard to view container health, trigger updates, manage hosts, and configure settings.
- 🔐 **OIDC Single Sign-On (SSO)** — Seamless authentication with Authentik, Authelia, Keycloak, Okta, Google Workspace, etc. (Or run in open access mode).
- 🔔 **Multi-Channel Notifications** — Instant alerts to **Discord**, **Slack**, **Telegram**, and **custom JSON webhooks** on updates, errors, or rollbacks.
- 🔄 **Automatic Rollback** — If a newly updated container fails health checks or crashes, Systower automatically rolls back to the previous image.
- 🏥 **Post-Update Health Checks** — Native Docker healthcheck integration and running-state validation before retiring old images.
- 📦 **Docker Compose Aware** — Detects Compose stacks and updates services gracefully with `docker compose`.
- 🏷️ **Smart Labels & Per-Container Scheduling** — Configure custom cron schedules, pre/post hooks, and timeouts via container labels.
- 🧹 **Auto Cleanup** — Remove orphaned and dangling images after successful updates.
- 🔍 **Dry Run & Monitor Modes** — Preview updates or monitor for new versions without applying changes.
- 🪶 **Ultra-Lightweight Multi-Arch** — Alpine Linux base, supporting `amd64`, `arm64`, `arm/v7`, and `arm/v6` (all Raspberry Pi models).

---

## 📊 Comparison with Watchtower

| Feature | Watchtower (Archived) | Systower v2 |
|:---|:---:|:---:|
| Docker container auto-updates | ✅ | ✅ |
| System updates (SSH: Pi / Debian / Ubuntu / Alpine) | ❌ | ✅ |
| Web UI Dashboard | ❌ | ✅ (Port 8080) |
| OIDC Single Sign-On (SSO) | ❌ | ✅ |
| Automatic Rollback on failure | ❌ | ✅ |
| Post-update health checks | ⚠️ Basic | ✅ Native + State |
| Multi-channel notifications (Discord/Slack/Telegram/Webhook) | ⚠️ Basic | ✅ Full Rich Embeds |
| Container exclusion (Label, Env, Include-only) | ⚠️ Partial | ✅ 3 Independent Modes |
| Per-container custom cron schedule | ❌ | ✅ (`systower.schedule`) |
| Pre/Post update lifecycle hooks | ❌ | ✅ (`systower.pre-update`) |
| Docker Compose stack awareness | ❌ | ✅ |
| Raspberry Pi & multi-architecture | ⚠️ Limited | ✅ amd64, arm64, arm/v7, arm/v6 |
| Maintained & actively developed (2026+) | ❌ (Archived) | ✅ Active |

---

## 🚀 Quick Start

### Docker Compose (Recommended)

```yaml
services:
  systower:
    image: ghcr.io/mael/systower:latest
    container_name: systower
    restart: unless-stopped
    ports:
      - "8080:8080" # Web UI Dashboard
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./config:/config # Persistent settings & hosts
      # - ~/.ssh/id_rsa:/config/ssh/id_rsa:ro # Optional: SSH key for system updates
    environment:
      SYSTOWER_CRON: "0 4 * * *" # Daily at 4:00 AM
      SYSTOWER_UI_ENABLED: "true"
      TZ: "Europe/Paris"
```

Access the Web UI at **`http://localhost:8080`**.

---

## 🔐 Authentication & Security

Systower offers three flexible authentication modes:

### 1. Username & Password (Simple & Secure)

Set credentials via environment variables:

```yaml
environment:
  SYSTOWER_AUTH_USERNAME: "admin"   # or USERNAME: "admin"
  SYSTOWER_AUTH_PASSWORD: "YourStrongPassword" # or PASSWORD: "YourStrongPassword"
```

When set, the Web UI provides a secure login form, and all API endpoints support **HTTP Basic Auth** (`Authorization: Basic ...`) for automated scripts and curl.

### 2. OIDC Single Sign-On (SSO)

Integrate with any OpenID Connect identity provider (Authentik, Keycloak, Authelia, Okta, Dex, Google Workspace, etc.):

```yaml
environment:
  SYSTOWER_OIDC_ENABLED: "true"
  SYSTOWER_OIDC_ISSUER: "https://auth.example.com/application/o/systower/"
  SYSTOWER_OIDC_CLIENT_ID: "systower-client-id"
  SYSTOWER_OIDC_CLIENT_SECRET: "your-client-secret"
  SYSTOWER_OIDC_REDIRECT_URI: "https://systower.example.com/auth/callback"
```

### 3. Open Access Mode (Default)

If neither username/password nor OIDC are configured (`SYSTOWER_OIDC_ENABLED=false`), the Web UI runs without authentication — ideal for isolated home labs or when behind a reverse proxy handling auth (like Traefik ForwardAuth or Nginx Basic Auth).

---

## 🔔 Notifications

Configure notifications via environment variables or in the Web UI:

### Discord
```bash
SYSTOWER_NOTIFY_ENABLED=true
SYSTOWER_NOTIFY_DISCORD="https://discord.com/api/webhooks/YOUR/WEBHOOK/URL"
```

### Slack
```bash
SYSTOWER_NOTIFY_ENABLED=true
SYSTOWER_NOTIFY_SLACK="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
```

### Telegram
```bash
SYSTOWER_NOTIFY_ENABLED=true
SYSTOWER_NOTIFY_TELEGRAM_TOKEN="123456789:ABCdefGHIjklMNO..."
SYSTOWER_NOTIFY_TELEGRAM_CHAT="-100123456789"
```

### Custom Webhook (Home Assistant, n8n, etc.)
```bash
SYSTOWER_NOTIFY_ENABLED=true
SYSTOWER_NOTIFY_WEBHOOK="https://automation.example.com/webhook"
```

---

## 🏷️ Docker Container Labels

Add labels to your containers to customize Systower's behavior:

| Label | Example | Description |
|:---|:---|:---|
| `systower.exclude` | `"true"` | Completely exclude container from updates |
| `systower.schedule` | `"0 2 * * 0"` | Custom cron schedule for this specific container |
| `systower.stop-timeout` | `"60"` | Custom graceful stop timeout in seconds |
| `systower.pre-update` | `"curl -X POST http://localhost:80/drain"` | Command to execute in container before stopping |
| `systower.post-update` | `"curl -X POST http://localhost:80/warmup"` | Command to execute in new container after start |

### Example Container with Labels

```yaml
services:
  database:
    image: postgres:16
    labels:
      systower.exclude: "true"

  web-api:
    image: myrepo/api:latest
    labels:
      systower.schedule: "0 3 * * 1" # Update Mondays at 3 AM
      systower.stop-timeout: "45"
      systower.pre-update: "npm run pre-drain"
```

---

## 🖥️ Host System Updates

Systower can keep your host Linux operating system updated with the latest security and package patches directly — without any SSH keys, network connections, or passwords!

To enable host OS package updates, add `pid: "host"` and `privileged: true` to your compose configuration:

```yaml
services:
  systower:
    image: ghcr.io/maelmoreau21/systower:latest
    pid: "host"
    privileged: true
    environment:
      SYSTOWER_SYSTEM_ENABLED: "true"
      SYSTOWER_SYSTEM_REBOOT: "false" # Set true to auto-reboot if required by packages
```

Supported host systems:
- **Debian** (all versions)
- **Ubuntu** (all versions)
- **Raspberry Pi OS** (all versions)
- **Alpine Linux**
- **Arch Linux**
- **Fedora / RHEL**

---

## ⚙️ Full Configuration Reference

| Environment Variable | Default | Description |
|:---|:---|:---|
| `SYSTOWER_CRON` | `0 4 * * *` | Cron schedule for main update cycle |
| `SYSTOWER_RUN_ON_START` | `true` | Run update check immediately upon container startup |
| `SYSTOWER_LOG_LEVEL` | `info` | Logging verbosity: `debug`, `info`, `warn`, `error` |
| `SYSTOWER_DRY_RUN` | `false` | Dry run simulation mode (no changes made) |
| `TZ` | `UTC` | Timezone (e.g. `Europe/Paris`, `America/New_York`) |
| `SYSTOWER_DOCKER_ENABLED` | `true` | Enable Docker container updates |
| `SYSTOWER_DOCKER_EXCLUDE` | `""` | Comma-separated container names to exclude |
| `SYSTOWER_DOCKER_INCLUDE_ONLY` | `""` | If set, only these containers will be updated |
| `SYSTOWER_DOCKER_CLEANUP` | `true` | Delete previous image after successful update |
| `SYSTOWER_DOCKER_STOP_TIMEOUT` | `30` | Seconds to wait before SIGKILL |
| `SYSTOWER_DOCKER_HEALTHCHECK_TIMEOUT`| `30` | Timeout in seconds to verify container health post-update |
| `SYSTOWER_DOCKER_MONITOR_ONLY` | `false` | Detect available updates without applying |
| `SYSTOWER_SYSTEM_ENABLED` | `false` | Enable local host OS updates (requires `pid: host` and `privileged: true`) |
| `SYSTOWER_SYSTEM_REBOOT` | `false` | Auto-reboot host system if kernel/packages require it |
| `SYSTOWER_UI_ENABLED` | `true` | Enable Web UI dashboard (set `false` for minimal headless mode) |
| `SYSTOWER_UI_PORT` | `8080` | Port for Web UI dashboard |
| `USERNAME` | `""` | Username for web authentication (alias: `SYSTOWER_AUTH_USERNAME`) |
| `PASSWORD` | `""` | Password for web authentication (alias: `SYSTOWER_AUTH_PASSWORD`) |
| `SYSTOWER_OIDC_ENABLED` | `false` | Enable OIDC Single Sign-On |
| `SYSTOWER_OIDC_ISSUER` | `""` | OIDC Issuer discovery URL |
| `SYSTOWER_OIDC_CLIENT_ID` | `""` | OIDC Client ID |
| `SYSTOWER_OIDC_CLIENT_SECRET`| `""` | OIDC Client Secret |
| `SYSTOWER_OIDC_REDIRECT_URI` | `""` | OIDC Redirect URI (auto-detected if empty) |
| `SYSTOWER_NOTIFY_ENABLED` | `false` | Enable notification dispatcher |
| `SYSTOWER_NOTIFY_DISCORD` | `""` | Discord webhook URL |
| `SYSTOWER_NOTIFY_SLACK` | `""` | Slack webhook URL |
| `SYSTOWER_NOTIFY_TELEGRAM_TOKEN`| `""` | Telegram Bot Token |
| `SYSTOWER_NOTIFY_TELEGRAM_CHAT` | `""` | Telegram Chat ID |
| `SYSTOWER_NOTIFY_WEBHOOK` | `""` | Custom JSON webhook endpoint |

---

## 📁 Repository Structure

```
Systower/
├── .github/workflows/
│   ├── build.yml             # Multi-arch build & push to GHCR
│   └── test.yml              # ShellCheck lint, unit tests, and build checks
├── app/                      # Web UI Dashboard & API (Node.js Express)
│   ├── server.js             # Server entrypoint & WebSocket log streamer
│   ├── package.json          # Dependencies
│   ├── auth/
│   │   └── oidc.js           # OpenID Connect SSO module (PKCE)
│   ├── api/
│   │   ├── config.js         # Configuration API
│   │   ├── containers.js     # Docker engine API
│   │   ├── system.js         # SSH system hosts API
│   │   ├── logs.js           # Log reader API
│   │   └── notifications.js  # Notifications test API
│   └── public/               # Frontend SPA
│       ├── index.html        # Modern dashboard layout
│       ├── css/style.css     # Premium dark theme stylesheet
│       └── js/app.js         # Dynamic frontend client logic
├── scripts/                  # Core Engine Scripts (Bash)
│   ├── entrypoint.sh         # Container entrypoint
│   ├── systower.sh           # Main orchestrator
│   ├── docker-update.sh      # Docker update & rollback engine
│   ├── system-update.sh      # SSH system update engine
│   ├── health-check.sh       # Post-update health validation
│   ├── notifications.sh      # Multi-channel notification dispatcher
│   └── utils.sh              # Shared logging, config & validation helpers
├── tests/                    # Automated Test Suite (86 tests)
│   ├── run_tests.sh          # Test runner
│   ├── test_utils.sh         # Utils tests
│   ├── test_docker_update.sh # Docker update tests
│   ├── test_system_update.sh # System update tests
│   ├── test_notifications.sh # Notification tests
│   └── test_config.sh        # Config & OIDC tests
├── config/
│   └── hosts.example.conf    # Example hosts configuration
├── Dockerfile                # Multi-arch Alpine Dockerfile
├── docker-compose.yml        # Ready-to-use Docker Compose stack
├── LICENSE                   # MIT License
└── README.md
```

---

## 🧪 Running Tests Locally

```bash
# Run the complete test suite (86 unit tests)
bash tests/run_tests.sh
```

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Systower — The next-generation automated container & system updater.**

</div>
