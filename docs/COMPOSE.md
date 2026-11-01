# Native Docker Compose updates (explicit CLI)

This is the **manual** foundation for Compose support, not automatic daemon-managed Compose updating. It invokes the original project files through Docker Compose rather than reconstructing a service from `docker inspect`.

## Requirements

- Run the Systower executable on a system with `docker` and `docker compose` commands.
- Project files, `.env` and relative paths must be available to the process.
- Back up persistent data separately; Compose does not reverse database schema migrations.
- The standalone Engine safety policy and opt-out labels do **not** apply to this explicitly requested Compose action. Avoid selecting sensitive services without a maintenance plan.

## Usage

Preview without mutations:

```sh
systower compose update --file /srv/apps/compose.yml --project-directory /srv/apps --service web
```

Explicitly apply:

```sh
systower compose update --file /srv/apps/compose.yml --project-directory /srv/apps --service web --apply
```

Repeat `--file` for layered configurations and `--service` for multiple explicitly selected services.

The program executes `docker compose config --quiet`, then `docker compose pull --ignore-buildable web`, then `docker compose up --detach --no-deps --pull never web`. The `--no-deps` flag avoids starting unrelated dependency services. Note that `up` can start a selected service even when it was previously stopped.

## Limitations

- No periodic Compose updates or automatic project discovery yet.
- No transactional Compose rollback; successful process exit does not guarantee application health.
- Systower's current Docker image may not ship a Docker Compose CLI. Use the host-side binary or install a compatible CLI and mount the project files.


## Scheduled updates (explicit opt-in)

You can schedule *only* configured Compose projects and services through Systower's existing cron cycle. This is **disabled by default**.

```yaml
services:
  systower:
    build:
      context: .
      args:
        WITH_COMPOSE: "true"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /srv/projects:/srv/projects:ro
      - systower-state:/var/lib/systower
    environment:
      SYSTOWER_DOCKER_ENABLED: "false"
      SYSTOWER_COMPOSE_ENABLED: "true"
      SYSTOWER_COMPOSE_TARGETS_JSON: >-
        [{"files":["/srv/projects/web/compose.yml"],
          "project_directory":"/srv/projects/web",
          "services":["web"]}]
      SYSTOWER_CRON: "0 4 * * *"
      SYSTOWER_DRY_RUN: "true"
volumes:
  systower-state:
```

**Important:** set `SYSTOWER_DRY_RUN=false` only after reviewing the selected project files and service names. The Compose CLI is included in the image only when building with `WITH_COMPOSE=true`; this intentionally increases the image size. Mounted project paths must resolve to the same paths on the Docker host for bind mounts. Docker socket access effectively grants host-level privileges.

Scheduled updates first validate the Compose project and check that **each selected service is already running**. Stopped services are not started. Then they perform the service-scoped pull/up sequence. The daemon does not automatically discover Compose projects and does not assert that an updated image was available.

**Limitations:** no transactional rollback, no automated data backups, no remote digest precheck, no guarantee of application readiness. Compose files and any referenced `.env` must be readable in the updater container. Avoid adding databases and networking components unless you have a maintenance and recovery plan.
