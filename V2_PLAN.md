# Systower V2 plan

V2 is developed on the `rust-v2` branch while the Bash implementation remains available as the V1 compatibility reference.

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

The first slice intentionally contains only configuration, policy, and CLI validation. Docker mutations will not be added until their typed snapshot and transaction contracts are tested.

## V1 findings driving the design

- V1 reconstructs containers with `docker run`; this is not an exact Compose-compatible round trip.
- Rollback is best effort and has no persistent transaction journal.
- Health checks accept a long-running container without a healthcheck and may accept `starting` after timeout.
- Dry-run still pulls images and host update access is not positively verified.
- The current tests do not exercise Docker recreation, rollback, notifications, or host package commands.

## Implementation order

1. Typed configuration, CLI validation, and policy tests.
2. Docker API adapter with complete inspect snapshots and a read-only `check` command.
3. Persistent transaction journal, process lock, and explicit update state machine.
4. Image resolution, pull verification, container replacement, health policy, and verified rollback.
5. Compose detection with safe exclusion when the original project files are unavailable.
6. Notifications, retention, and V1 environment migration documentation.
7. Optional host agent with namespace verification and simulation mode.
8. Integration tests against an isolated Docker Engine, CI, multi-architecture image, and measured benchmarks.

## Initial V1 compatibility contract

The Rust configuration keeps the principal `SYSTOWER_*` variables and preserves V1's default schedule, startup run, Docker enablement, and disabled host updates. V2 defaults safety protections to enabled and self-update to disabled until transactional self-update is implemented.