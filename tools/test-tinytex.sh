#!/bin/sh
# Native ARM64 Alpine integration test of the signed APK and its installer.
set -eu
repo=$1
public_key=$2
container=$(docker create --platform linux/arm64 alpine:3.21 sh /test-tinytex.sh)
trap 'docker rm -f "$container" >/dev/null' EXIT
trap 'exit 1' HUP INT TERM
docker cp "$repo" "$container:/repo"
docker cp "$public_key" "$container:/etc/apk/keys/$(basename "$public_key")"
docker cp tests/tinytex.sh "$container:/test-tinytex.sh"
docker start -a "$container"
[ "$(docker inspect -f '{{.State.ExitCode}}' "$container")" = 0 ]
