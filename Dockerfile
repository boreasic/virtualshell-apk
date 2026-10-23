# syntax=docker/dockerfile:1
# Build on arm64 (native or with Docker's configured emulation).
FROM alpine:3.21 AS builder
RUN apk update && apk add --no-cache tar jq
WORKDIR /build
COPY keys/*.rsa.pub keys/
COPY rootfs/ rootfs/
ARG SNAPSHOT
ARG SOURCE_REVISION=unknown
ARG SOURCE_DATE_EPOCH=0
RUN SOURCE_REVISION="$SOURCE_REVISION" SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
    sh rootfs/build.sh "$SNAPSHOT" /out/virtualshell-rootfs-aarch64.tar.gz

# `--output type=local,dest=out` exports only the release files.
FROM scratch AS artifacts
COPY --from=builder /out/ /
