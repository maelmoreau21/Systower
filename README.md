<div align="center">

# 🏗️ Systower

**Lightweight Docker Container & System Updater**

*An improved, modern alternative to Watchtower*

[![Build & Push](https://github.com/Mael/Systower/actions/workflows/build.yml/badge.svg)](https://github.com/Mael/Systower/actions/workflows/build.yml)
[![Tests & Lint](https://github.com/Mael/Systower/actions/workflows/test.yml/badge.svg)](https://github.com/Mael/Systower/actions/workflows/test.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Docker Image Size](https://img.shields.io/badge/image%20size-~30MB-brightgreen)](https://github.com/Mael/Systower/pkgs/container/systower)

</div>

---

## ✨ Features

- 🐳 **Docker Container Updates** — Automatically pull latest images and recreate containers with preserved configuration
- 🖥️ **System Updates** — Update remote Debian, Ubuntu, and Raspberry Pi OS systems via SSH
- 🏷️ **Smart Exclusions** — Exclude containers by name, label, or use include-only mode
- 📅 **Flexible Scheduling** — Cron-based scheduling with timezone support
- 👁️ **Monitor Mode** — Detect available updates without applying them
- 🔍 **Dry Run** — Preview what would happen without making any changes
- 🧹 **Auto Cleanup** — Remove old images after updates to save disk space
- 🪶 **Ultra-Lightweight** — Based on Alpine Linux (~30MB image size)
- 🔄 **Multi-Architecture** — Supports `amd64`, `arm64`, `arm/v7`, and `arm/v6` (all Raspberry Pi models)

## 📊 Comparison with Watchtower

| Feature | Watchtower | Systower |
|:---|:---:|:---:|
| Docker container updates | ✅ | ✅ |
| System updates (SSH) | ❌ | ✅ |
| Container exclusion by label | ✅ | ✅ |
| Container exclusion by name | ✅ | ✅ |
| Include-only mode | ❌ | ✅ |
| Monitor-only mode | ✅ | ✅ |
| Dry run mode | ❌ | ✅ |
| Multi-arch (amd64/arm64/arm/v7/v6) | ⚠️ | ✅ |
| Auto cleanup old images | ✅ | ✅ |
| Still maintained (2026+) | ❌ (archived) | ✅ |

---

## 🚀 Quick Start

### Docker Run

```bash
docker run -d \
  --name systower \
  --restart unless-stopped \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -e TZ=Europe/Paris \
  ghcr.io/mael/systower:latest
```

### Docker Compose

```yaml
services:
  systower:
    image: ghcr.io/mael/systower:latest
    container_name: systower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    environment:
      SYSTOWER_CRON: "0 4 * * *"
      TZ: Europe/Paris
```

---

## ⚙️ Configuration

All configuration is done through environment variables.

### General

| Variable | Default | Description |
|:---|:---|:---|
| `SYSTOWER_CRON` | `0 4 * * *` | Cron schedule expression (default: 4 AM daily) |
| `SYSTOWER_RUN_ON_START` | `true` | Run a check immediately when the container starts |
| `SYSTOWER_LOG_LEVEL` | `info` | Log verbosity: `debug`, `info`, `warn`, `error` |
| `SYSTOWER_DRY_RUN` | `false` | Preview mode — shows what would be done without applying changes |
| `TZ` | `UTC` | Timezone for cron scheduling |

### Docker Updates

| Variable | Default | Description |
|:---|:---|:---|
| `SYSTOWER_DOCKER_ENABLED` | `true` | Enable Docker container updates |
| `SYSTOWER_DOCKER_EXCLUDE` | *(empty)* | Comma-separated list of container names to exclude |
| `SYSTOWER_DOCKER_INCLUDE_ONLY` | *(empty)* | If set, **only** these containers will be updated |
| `SYSTOWER_DOCKER_CLEANUP` | `true` | Remove old images after successful updates |
| `SYSTOWER_DOCKER_STOP_TIMEOUT` | `30` | Seconds to wait before force-stopping a container |
| `SYSTOWER_DOCKER_MONITOR_ONLY` | `false` | Detect updates without applying them |

### System Updates (SSH)

| Variable | Default | Description |
|:---|:---|:---|
| `SYSTOWER_SYSTEM_ENABLED` | `false` | Enable system updates via SSH |
| `SYSTOWER_SYSTEM_HOSTS` | *(empty)* | Comma-separated hosts: `user@host:port` |
| `SYSTOWER_SYSTEM_HOSTS_FILE` | `/config/hosts.conf` | Path to hosts config file |
| `SYSTOWER_SYSTEM_SSH_KEY` | `/config/ssh/id_rsa` | Path to SSH private key |
| `SYSTOWER_SYSTEM_REBOOT` | `false` | Auto-reboot systems if needed after update |

---

## 🏷️ Container Exclusion

Systower provides three ways to control which containers are updated:

### 1. Exclude by Name (Environment Variable)

```bash
SYSTOWER_DOCKER_EXCLUDE=postgres,redis,my-critical-app
```

### 2. Exclude by Label

Add a label to any container you want to exclude:

```bash
docker run -d --label systower.exclude=true nginx
```

Or in Docker Compose:

```yaml
services:
  my-db:
    image: postgres:16
    labels:
      systower.exclude: "true"
```

### 3. Include-Only Mode

Only update specific containers, ignore everything else:

```bash
SYSTOWER_DOCKER_INCLUDE_ONLY=webapp,api,frontend
```

> **Note:** Include-only takes priority over the exclude list.

---

## 🖥️ System Updates

Systower can update remote Linux systems via SSH. It supports:

- **Debian** (all versions)
- **Ubuntu** (all versions)
- **Raspberry Pi OS**
- **Alpine Linux**

### Setup

1. **Mount your SSH key:**
```bash
-v ~/.ssh/id_rsa:/config/ssh/id_rsa:ro
```

2. **Define hosts** via environment variable:
```bash
SYSTOWER_SYSTEM_HOSTS=pi@192.168.1.100,admin@debian.local:2222
```

3. **Or mount a hosts file:**
```bash
-v ./hosts.conf:/config/hosts.conf:ro
```

Hosts file format:
```conf
# Raspberry Pi cluster
pi@192.168.1.100
pi@192.168.1.101:2222

# Debian server
admin@debian-server.local
```

### Full Example with System Updates

```yaml
services:
  systower:
    image: ghcr.io/mael/systower:latest
    container_name: systower
    restart: unless-stopped
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ~/.ssh/id_rsa:/config/ssh/id_rsa:ro
      - ./hosts.conf:/config/hosts.conf:ro
    environment:
      SYSTOWER_CRON: "0 3 * * 0"   # Every Sunday at 3 AM
      SYSTOWER_DOCKER_ENABLED: "true"
      SYSTOWER_DOCKER_EXCLUDE: "postgres"
      SYSTOWER_SYSTEM_ENABLED: "true"
      SYSTOWER_SYSTEM_REBOOT: "false"
      TZ: Europe/Paris
```

---

## 📅 Scheduling Examples

| Cron Expression | Description |
|:---|:---|
| `0 4 * * *` | Every day at 4:00 AM |
| `0 */6 * * *` | Every 6 hours |
| `0 3 * * 0` | Every Sunday at 3:00 AM |
| `0 2 1 * *` | First day of each month at 2:00 AM |
| `*/30 * * * *` | Every 30 minutes |
| `0 22 * * 1-5` | Weekdays at 10:00 PM |

---

## 🔍 Modes

### Monitor Mode

Detect updates without applying them — useful for notifications or dashboards:

```bash
SYSTOWER_DOCKER_MONITOR_ONLY=true
```

### Dry Run Mode

Preview all actions without making any changes:

```bash
SYSTOWER_DRY_RUN=true
```

---

## 📁 Project Structure

```
Systower/
├── .github/workflows/
│   ├── build.yml           # CI: Build + push Docker image to GHCR
│   └── test.yml            # CI: ShellCheck lint + unit tests
├── scripts/
│   ├── entrypoint.sh       # Container entrypoint
│   ├── systower.sh         # Main orchestrator
│   ├── docker-update.sh    # Docker container update engine
│   ├── system-update.sh    # System update engine (SSH)
│   └── utils.sh            # Shared utilities (logging, parsing, etc.)
├── tests/
│   ├── run_tests.sh        # Test runner
│   ├── test_utils.sh       # Utility function tests
│   ├── test_docker_update.sh   # Docker update logic tests
│   └── test_system_update.sh   # System update logic tests
├── config/
│   └── hosts.example.conf  # Example hosts configuration
├── Dockerfile              # Ultra-lightweight Alpine image
├── docker-compose.yml      # Example Docker Compose
├── LICENSE
└── README.md
```

---

## 🛡️ Security

- **Docker Socket**: Systower requires read access to the Docker socket (`/var/run/docker.sock`). Mount it as read-only (`:ro`) when possible.
- **SSH Keys**: Mount SSH keys as read-only. Never embed them in the image.
- **Least Privilege**: Use non-root SSH users with `sudo` configured for `apt-get` operations on remote hosts.

---

## 🤝 Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

### Development

```bash
# Run tests locally
bash tests/run_tests.sh

# Build Docker image locally
docker build -t systower:dev .

# Test with dry run
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  -e SYSTOWER_DRY_RUN=true \
  -e SYSTOWER_RUN_ON_START=true \
  systower:dev
```

---

## 📄 License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.

---

<div align="center">

**Built with ❤️ as a modern replacement for Watchtower**

</div>
