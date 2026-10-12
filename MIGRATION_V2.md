# V1 to V2 migration

This document records the migration from the former Bash implementation to Systower 2.0.0.

## Before switching

1. Validate the 2.0.0 image with `systower check` and `systower docker check` before deployment.
2. Back up the Docker volume containing the V1 logs/configuration.
3. Start V2 with a dedicated state volume. V2 does not delete V1 state.
4. Begin with `SYSTOWER_DRY_RUN=true` or `SYSTOWER_DOCKER_MONITOR_ONLY=true`.

## Important behavior changes

- V2 uses the Docker Engine API and does not require Docker CLI, jq, Bash, cron, or curl.
- Socket and network-sensitive containers are protected by default.
- Digest identity is checked before an update is planned.
- Containers without a Docker healthcheck are not accepted by default. Enable `SYSTOWER_DOCKER_ALLOW_NO_HEALTHCHECK=true` only when running-state plus stability is an acceptable policy.
- Compose-managed containers are not recreated when the original Compose project source is unavailable.
- Host package updates remain optional and are not enabled by default.
- `SYSTOWER_UPDATE_SELF` stays disabled until the supervised self-update path is complete.

## State and rollback

Mount `/var/lib/systower` as a persistent volume. V2 stores a JSONL transaction journal there and uses a lock file to prevent concurrent update processes. A rollback is only reported as successful after the previous container is started and verified running.

## Compatibility

The relevant environment variables are documented in the main README. V2-specific variables include `SYSTOWER_STATE_FILE` and `SYSTOWER_DOCKER_ALLOW_NO_HEALTHCHECK`.