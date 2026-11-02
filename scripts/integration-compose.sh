#!/usr/bin/env bash
set -euo pipefail

# Use a disposable project and never target a user's real Compose stack.
ROOT="$(mktemp -d)"
PROJECT="$ROOT/systower-compose-ci-$$"
mkdir -p "$PROJECT"
BIN="${SYSTOWER_BIN:-./target/debug/systower}"
COMPOSE_FILE="$PROJECT/compose.yml"
STATE_FILE="$ROOT/state.jsonl"

cleanup() {
  docker compose --file "$COMPOSE_FILE" --project-directory "$PROJECT" down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -rf "$ROOT"
}
trap cleanup EXIT

cat >"$COMPOSE_FILE" <<'YAML'
services:
  web:
    image: alpine:3.20
    command: ["sh", "-c", "sleep 3600"]
  dormant:
    image: alpine:3.20
    command: ["sh", "-c", "sleep 3600"]
YAML

docker compose --file "$COMPOSE_FILE" --project-directory "$PROJECT" up -d web
test -n "$(docker compose --file "$COMPOSE_FILE" --project-directory "$PROJECT" ps --status running -q web)"
test -z "$(docker compose --file "$COMPOSE_FILE" --project-directory "$PROJECT" ps --status running -q dormant)"

# A dry-run must not execute any Docker command.
"$BIN" compose update --file "$COMPOSE_FILE" --project-directory "$PROJECT" --service web

# Stopped services are never started by an update, even when explicitly named.
if "$BIN" compose update --file "$COMPOSE_FILE" --project-directory "$PROJECT" --service dormant --apply; then
  echo "A stopped Compose service was unexpectedly started" >&2
  exit 1
fi
test -z "$(docker compose --file "$COMPOSE_FILE" --project-directory "$PROJECT" ps --status running -q dormant)"

# The selected running service can be safely checked with Compose-native commands.
"$BIN" compose update --file "$COMPOSE_FILE" --project-directory "$PROJECT" --service web --apply
test -n "$(docker compose --file "$COMPOSE_FILE" --project-directory "$PROJECT" ps --status running -q web)"
test -z "$(docker compose --file "$COMPOSE_FILE" --project-directory "$PROJECT" ps --status running -q dormant)"

export SYSTOWER_STATE_FILE="$STATE_FILE"
export SYSTOWER_DOCKER_ENABLED=false
export SYSTOWER_SYSTEM_ENABLED=false
export SYSTOWER_RUN_ON_START=true
export SYSTOWER_DRY_RUN=false
export SYSTOWER_COMPOSE_ENABLED=true
export SYSTOWER_COMPOSE_TARGETS_JSON
SYSTOWER_COMPOSE_TARGETS_JSON="$(printf '[{"files":["%s"],"project_directory":"%s","services":["web"]}]' "$COMPOSE_FILE" "$PROJECT")"

"$BIN" config validate
"$BIN" run >"$ROOT/daemon.log" 2>&1 &
daemon_pid=$!
done_flag=false
for _ in $(seq 1 40); do
  if grep -q "Compose update commands completed" "$ROOT/daemon.log"; then
    done_flag=true
    break
  fi
  if ! kill -0 "$daemon_pid" 2>/dev/null; then
    break
  fi
  sleep 1
done
kill "$daemon_pid" 2>/dev/null || true
wait "$daemon_pid" 2>/dev/null || true
if [ "$done_flag" != true ]; then
  cat "$ROOT/daemon.log" >&2
  echo "Scheduled Compose update failed" >&2
  exit 1
fi

echo "PASS native Compose CLI, stopped-service protections and opt-in scheduling"
