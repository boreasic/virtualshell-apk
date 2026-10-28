#!/bin/sh
# Build signed aarch64 APKs without persisting the signing key in an image.
# Usage: tools/build-custom.sh private.rsa key-name output-directory
set -eu
key_file=$1
key_name=$2
output=$3
case "$key_name" in ''|*[!a-zA-Z0-9._-]*) echo 'Invalid key name' >&2; exit 1 ;; esac
mkdir -p "$output"
container=$(docker create --platform linux/arm64 -e APK_KEY_NAME="$key_name" \
	alpine:3.21 sh /input/build-custom-container.sh)
trap 'docker rm -f "$container" >/dev/null' EXIT
trap 'exit 1' HUP INT TERM
docker cp packages "$container:/input"
docker cp tools/build-custom-container.sh "$container:/input/build-custom-container.sh"
docker cp "$key_file" "$container:/input/$key_name.rsa"
docker start -a "$container"
[ "$(docker inspect -f '{{.State.ExitCode}}' "$container")" = 0 ]
docker cp "$container:/out/." "$output/"
