# Systower V2 plan

Systower 2.0.0 is the current implementation. This plan records the completed Rust rewrite and its remaining hardening work.

## Architecture

```text
systower (CLI + daemon)
  config       typed environment configuration and validation
  policy       inclusion, exclusion, and safety decisions
  state        durable JSONL transaction journal and lock
  docker       Docker Engine API adapter and immutable container snapshots
  update       plan, prepare, health-check, commit, rollback state machine
  host         optional, separately privileged Linux package agent
  notify       bounded, redacted event delivery
```

The current slice contains typed configuration, policy, native Docker discovery, verified image pulls, inspected safety facts, transaction journaling, health evaluation, real replacement and rollback, cron daemon wiring, notifications, host update planning, and a V2 container image.

## V1 findings driving the design

- V1 reconstructs containers with `docker run`; this is not an exact Compose-compatible round trip.
- Rollback is best effort and has no persistent transaction journal.
- Health checks accept a long-running container without a healthcheck and may accept `starting` after timeout.
- Dry-run still pulls images and host update access is not positively verified.
- The current tests do not exercise Docker recreation, rollback, notifications, or host package commands.

## Implementation order

1. Typed configuration, CLI validation, and policy tests.
2. Docker API adapter with inspected safety facts and a read-only `docker check` command. **Done.**
3. Persistent transaction journal, process lock, and explicit update state machine. **Done.**
4. Image resolution, pull verification, container replacement, health policy, and verified rollback. **Done for manual updates; automatic discovery still needs registry comparison.**
5. Compose detection with safe exclusion when the original project files are unavailable. **Safe exclusion done; Compose source resolution remains.**
6. Notifications, retention, and V1 environment migration documentation. **Done for notifications, retention, and migration docs.**
7. Optional host agent with namespace verification and simulation mode. **Planning and simulation done; privileged execution remains deliberately disabled.**
8. Integration tests against an isolated Docker Engine, CI, multi-architecture image, and measured benchmarks. **Docker tests, CI, and benchmark harness done; multi-architecture rebuild and benchmark measurements remain.**

## Initial V1 compatibility contract

The Rust configuration keeps the principal `SYSTOWER_*` variables and preserves V1's default schedule, startup run, Docker enablement, and disabled host updates. V2 defaults safety protections to enabled and self-update to disabled until transactional self-update is implemented.