#!/usr/bin/env bash
# End-to-end tests against a disposable Docker Engine environment.
# Run on an isolated CI runner, never against a production Docker host.
set -euo pipefail

BIN="${SYSTOWER_BIN:-./target/debug/systower}"
TMPDIR_IT="$(mktemp -d)"
SUFFIX="$$-${RANDOM}"
PREFIX="systower-it-${SUFFIX}"
GOOD="${PREFIX}-good"
ROLLBACK="${PREFIX}-rollback"
ANON="${PREFIX}-anonymous"
COMPOSE="${PREFIX}-compose"
VOL="${PREFIX}-data"

cleanup() {
  docker rm -f "$GOOD" "$ROLLBACK" "$ANON" "$COMPOSE" >/dev/null 2>&1 || true
  docker volume rm "$VOL" >/dev/null 2>&1 || true
  docker image rm "${PREFIX}:v1" "${PREFIX}:v2" "${PREFIX}:broken" >/dev/null 2>&1 || true
  rm -rf "$TMPDIR_IT"
}
trap cleanup EXIT

export SYSTOWER_STATE_FILE="${TMPDIR_IT}/state.jsonl"
export SYSTOWER_DOCKER_PROTECT_NETWORK_CONTAINERS=true
export SYSTOWER_DOCKER_PROTECT_SOCKET_CONTAINERS=true
export SYSTOWER_DOCKER_ROLLBACK_HEALTHCHECK_TIMEOUT=15
export SYSTOWER_DOCKER_CLEANUP=false

cat >"${TMPDIR_IT}/Dockerfile" <<'DOCKERFILE'
FROM alpine:3.20
ARG RELEASE_ID
RUN if [ "$RELEASE_ID" != "broken" ]; then touch /tmp/ready; fi; printf '%s' "$RELEASE_ID" >/release
HEALTHCHECK --interval=1s --timeout=2s --retries=2 CMD test -f /tmp/ready
CMD ["sh", "-c", "trap 'exit 0' TERM; while :; do sleep 1; done"]
DOCKERFILE

for release in v1 v2 broken; do
  docker build --quiet \
    --build-arg "RELEASE_ID=${release}" \
    -t "${PREFIX}:${release}" "$TMPDIR_IT" >/dev/null
done
old_image="$(docker image inspect --format '{{.Id}}' "${PREFIX}:v1")"
new_image="$(docker image inspect --format '{{.Id}}' "${PREFIX}:v2")"

# A standalone named-volume container must keep both the volume and its data.
docker volume create "$VOL" >/dev/null
docker run -d --name "$GOOD" -v "${VOL}:/data" "${PREFIX}:v1" >/dev/null
docker exec "$GOOD" sh -c 'echo retained >/data/sentinel'
"$BIN" docker update --container "$GOOD" --image "${PREFIX}:v2" \
  --no-pull --health-timeout 15
test "$(docker inspect --format '{{.Image}}' "$GOOD")" = "$new_image"
test "$(docker inspect --format '{{.State.Running}}' "$GOOD")" = true
test "$(docker exec "$GOOD" cat /data/sentinel)" = retained
if docker inspect "${GOOD}_systower_bak" >/dev/null 2>&1; then
  echo "Previous container was not cleaned up" >&2
  exit 1
fi
echo "PASS standalone update and named volume preservation"

# Anonymous Docker volumes cannot silently be replaced by fresh empty volumes.
docker run -d --name "$ANON" -v /data "${PREFIX}:v1" >/dev/null
if "$BIN" docker update --container "$ANON" --image "${PREFIX}:v2" --no-pull; then
  echo "Unsafe anonymous-volume replacement was accepted" >&2
  exit 1
fi
test "$(docker inspect --format '{{.Image}}' "$ANON")" = "$old_image"
test "$(docker inspect --format '{{.State.Running}}' "$ANON")" = true
echo "PASS anonymous volume rejected without downtime"

# Labels from Docker Compose must block direct recreation, even through the CLI.
docker run -d --name "$COMPOSE" \
  --label com.docker.compose.project=integration \
  --label com.docker.compose.service=web "${PREFIX}:v1" >/dev/null
if "$BIN" docker update --container "$COMPOSE" --image "${PREFIX}:v2" --no-pull; then
  echo "Compose container was unsafely recreated" >&2
  exit 1
fi
test "$(docker inspect --format '{{.Image}}' "$COMPOSE")" = "$old_image"
test "$(docker inspect --format '{{.State.Running}}' "$COMPOSE")" = true
echo "PASS Compose-managed container rejected"

# An unhealthy replacement must restore a working original container.
docker run -d --name "$ROLLBACK" "${PREFIX}:v1" >/dev/null
if "$BIN" docker update --container "$ROLLBACK" --image "${PREFIX}:broken" \
  --no-pull --health-timeout 8; then
  echo "Broken replacement unexpectedly succeeded" >&2
  exit 1
fi
test "$(docker inspect --format '{{.Image}}' "$ROLLBACK")" = "$old_image"
test "$(docker inspect --format '{{.State.Running}}' "$ROLLBACK")" = true
if docker inspect "${ROLLBACK}_systower_bak" >/dev/null 2>&1; then
  echo "Rollback left backup container behind" >&2
  exit 1
fi
echo "PASS unhealthy image rolled back to the original"
