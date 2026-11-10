#!/bin/sh
# Native ARM64 Alpine integration test of the Codex and Claude Code APKs.
set -eu
repo=$1
public_key=$2
container=$(docker create --platform linux/arm64 alpine:3.21 sh /test-agents.sh)
trap 'docker rm -f "$container" >/dev/null' EXIT
trap 'exit 1' HUP INT TERM
docker cp "$repo" "$container:/repo"
docker cp "$public_key" "$container:/etc/apk/keys/$(basename "$public_key")"
docker cp tests/agents.sh "$container:/test-agents.sh"
docker start -a "$container"
[ "$(docker inspect -f '{{.State.ExitCode}}' "$container")" = 0 ]
