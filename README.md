<div align="center">

# 🏗️ Systower

**Ultra-lightweight Automated Docker Container & Local Host System Updater**

*An improved, ultra-lightweight (~25MB image, < 2MB RAM) alternative to Watchtower*

[🇬🇧 English](README.md) • [🇫🇷 Français](README.fr.md)

[![Build & Push](https://github.com/maelmoreau21/Systower/actions/workflows/build.yml/badge.svg)](https://github.com/maelmoreau21/Systower/actions/workflows/build.yml)
[![Tests & Lint](https://github.com/maelmoreau21/Systower/actions/workflows/test.yml/badge.svg)](https://github.com/maelmoreau21/Systower/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker Image Size](https://img.shields.io/badge/image%20size-~25MB-brightgreen)](https://github.com/maelmoreau21/Systower)
[![RAM Usage](https://img.shields.io/badge/RAM-%3C%202MB-brightgreen)](https://github.com/maelmoreau21/Systower)
[![Multi-Arch](https://img.shields.io/badge/arch-amd64%20%7C%20arm64%20%7C%20armv7%20%7C%20armv6-purple)](https://github.com/maelmoreau21/Systower)

</div>

---

## ✨ Features

- 🐳 **Docker Container Updates** — Pull latest images and recreate containers preserving full configuration (networks, volumes, ports, caps, devices, env, restart policies).
- 🖥️ **Local Host System Updates** — Update the host OS directly (Debian, Ubuntu, Raspberry Pi OS, Alpine, Arch, Fedora) with zero SSH configuration needed.
- 🚫 **Flexible Container Exclusion** — Exclude specific containers via environment variable or Docker label.
- 🔔 **Multi-Channel Notifications** — Instant alerts to **Discord**, **Slack**, **Telegram**, and **custom JSON webhooks** on updates, errors, or rollbacks.
- 🔄 **Automatic Rollback** — If a newly updated container fails to start, Systower automatically reverts to the backup container instantaneously.
- 🧹 **Auto Cleanup** — Remove orphaned and dangling images after successful updates.
- 🪶 **Ultra-Lightweight Multi-Arch** — Alpine Linux base (~25MB image, < 2MB RAM), supporting `amd64`, `arm64`, `arm/v7`, and `arm/v6` (all Raspberry Pi models).

---

## 🚀 Quick Start

### `docker-compose.yml`

```yaml
services:
  systower:
    image: ghcr.io/maelmoreau21/systower:latest
    container_name: systower
    restart: unless-stopped
    # Optional: enable pid: "host" and privileged: true if you want host OS package updates
    # pid: "host"
    # privileged: true
    volumes:
      # Required: Docker socket
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      # Schedule (cron syntax: every day at 4:00 AM)
      SYSTOWER_CRON: "0 4 * * *"
      SYSTOWER_RUN_ON_START: "true"
      TZ: "Europe/Paris"

      # Docker Container Updates
      SYSTOWER_DOCKER_ENABLED: "true"
      SYSTOWER_DOCKER_CLEANUP: "true"

      # Optional container exclusions
      # SYSTOWER_DOCKER_EXCLUDE: "postgres,redis,my-container"

      # Host OS updates (Debian, Ubuntu, Raspberry Pi OS...)
      SYSTOWER_SYSTEM_ENABLED: "false" # Set true if pid: host is enabled
      SYSTOWER_SYSTEM_REBOOT: "false"
```

Start Systower:
```bash
docker compose up -d
```

---

## 🚫 How to Prevent Updates for Specific Containers

You have **3 simple methods**:

### Method 1: Global Exclusion Variable (Recommended)
In your `docker-compose.yml`, specify container names separated by commas:
```yaml
environment:
  SYSTOWER_DOCKER_EXCLUDE: "postgres,redis,database,my_app"
```

### Method 2: Via Docker Label on the Container
Add the `systower.exclude: "true"` label directly to the service in its own compose file:
```yaml
services:
  database:
    image: postgres:16
    labels:
      systower.exclude: "true"
```
Systower will automatically detect this label and skip updating this container.

### Method 3: Whitelist Mode (Include Only)
If you only want Systower to update specific containers and ignore everything else:
```yaml
environment:
  SYSTOWER_DOCKER_INCLUDE_ONLY: "sonarr,radarr,nginx"
```

---

## 🔔 Notifications

Enable notifications by setting the corresponding environment variables:

- **Discord**: `SYSTOWER_NOTIFY_DISCORD="https://discord.com/api/webhooks/..."`
- **Slack**: `SYSTOWER_NOTIFY_SLACK="https://hooks.slack.com/services/..."`
- **Telegram**: `SYSTOWER_NOTIFY_TELEGRAM_TOKEN="123456:ABC..."` and `SYSTOWER_NOTIFY_TELEGRAM_CHAT="-100..."`
- **Webhook**: `SYSTOWER_NOTIFY_WEBHOOK="https://automation.example.com/webhook"`

---

## ⚙️ Configuration Reference

| Environment Variable | Default | Description |
|:---|:---|:---|
| `SYSTOWER_CRON` | `0 4 * * *` | Cron schedule for main update cycle |
| `SYSTOWER_RUN_ON_START` | `true` | Run update check immediately upon container startup |
| `SYSTOWER_LOG_LEVEL` | `info` | Logging verbosity: `debug`, `info`, `warn`, `error` |
| `SYSTOWER_DRY_RUN` | `false` | Dry run simulation mode (no changes made) |
| `TZ` | `UTC` | Timezone (e.g. `Europe/Paris`, `America/New_York`) |
| `SYSTOWER_DOCKER_ENABLED` | `true` | Enable Docker container updates |
| `SYSTOWER_DOCKER_CLEANUP` | `true` | Delete previous image after successful update |
| `SYSTOWER_DOCKER_EXCLUDE` | `""` | Comma-separated container names to exclude |
| `SYSTOWER_DOCKER_INCLUDE_ONLY` | `""` | If set, only these containers will be updated |
| `SYSTOWER_DOCKER_STOP_TIMEOUT` | `30` | Seconds to wait before SIGKILL |
| `SYSTOWER_SYSTEM_ENABLED` | `false` | Enable local host OS updates (requires `pid: host` and `privileged: true`) |
| `SYSTOWER_SYSTEM_REBOOT` | `false` | Auto-reboot host system if kernel/packages require it |
| `SYSTOWER_NOTIFY_ENABLED` | `false` | Enable notifications dispatcher |

---

## 📄 License

This project is licensed under the **MIT License**.
