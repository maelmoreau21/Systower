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
