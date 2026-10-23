#!/bin/sh
# Builds Virtual Shell's default root filesystem: Alpine's minirootfs plus
# bash (root's login shell) and a few Virtual Shell files, installed with
# apk from a pinned snapshot so the image's apk database stays consistent.
#
# Runs inside any aarch64 Alpine system: the CI runs it in an alpine
# container on an arm64 runner; locally it runs in a Virtual Shell guest.
#
#   sh rootfs/build.sh SNAPSHOT_DATE OUTPUT.tar.gz
#
# Writes the archive, its SHA-256, and OUTPUT.tar.gz.manifest.json.
set -eu

if [ "$#" -ne 2 ]; then
    echo "usage: $0 SNAPSHOT_DATE OUTPUT.tar.gz" >&2
    exit 1
fi
snapshot=$1
output=$2
case "$snapshot" in
    ????-??-??) ;;
    *) echo "snapshot must be an explicit YYYY-MM-DD date" >&2; exit 1 ;;
esac
case "$snapshot" in
    *[!0-9-]*) echo "invalid snapshot date" >&2; exit 1 ;;
esac
[ "$(uname -m)" = aarch64 ] || { echo "build requires aarch64 Alpine" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
release=v3.21
minirootfs_version=3.21.0
minirootfs_sha256=f31202c4070c4ef7de9e157e1bd01cb4da3a2150035d74ea5372c5e86f1efac1
site=https://boreasic.github.io/virtualshell-apk

# These tools belong to the builder, not the guest filesystem.
apk add --no-cache tar jq >/dev/null

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
rootfs=$work/rootfs
mkdir -p "$rootfs"
wget -qO "$work/minirootfs.tar.gz" \
    "https://dl-cdn.alpinelinux.org/alpine/$release/releases/aarch64/alpine-minirootfs-$minirootfs_version-aarch64.tar.gz"
(cd "$work" && echo "$minirootfs_sha256  minirootfs.tar.gz" | sha256sum -c -)
tar -xzf "$work/minirootfs.tar.gz" -C "$rootfs"

# The pinned snapshot first, Alpine's mirror only for explicit @alpine.
cp "$here"/../keys/*.rsa.pub "$rootfs/etc/apk/keys/"
cat > "$rootfs/etc/apk/repositories" <<EOF
$site/$release/$snapshot/main
$site/$release/$snapshot/community
@alpine https://dl-cdn.alpinelinux.org/alpine/$release/main
@alpine https://dl-cdn.alpinelinux.org/alpine/$release/community
EOF
# Both operations target the guest: update its indexes, then install bash
# and its dependencies with apk so its package database stays consistent.
guest_apk() {
    apk --root "$rootfs" --keys-dir "$rootfs/etc/apk/keys" \
        --repositories-file "$rootfs/etc/apk/repositories" "$@"
}
guest_apk update
guest_apk add bash
guest_apk info -v > "$work/packages.txt"
rm -f "$rootfs"/var/cache/apk/*
chroot "$rootfs" /bin/bash -c 'test -n "$BASH_VERSION"'

# root logs in to bash; /bin/sh stays BusyBox ash.
sed -i 's#^root:\(.*\):/bin/sh$#root:\1:/bin/bash#' "$rootfs/etc/passwd"
grep -qx /bin/bash "$rootfs/etc/shells" || echo /bin/bash >> "$rootfs/etc/shells"

cp -R "$here/overlay/." "$rootfs/"
# macOS archive metadata, if the overlay came through a Mac's tar.
find "$rootfs" -name '._*' -exec rm -f {} +
chmod 0755 "$rootfs/usr/local/bin/clc"
for f in .bash_profile .bashrc; do
    [ -e "$rootfs/root/$f" ] || cp "$rootfs/etc/skel/$f" "$rootfs/root/$f"
done
echo "$snapshot" > "$rootfs/etc/virtualshell-rootfs"

mkdir -p "$(dirname "$output")"
# Use a temporary tar so an archiver failure cannot be hidden by a pipe.
tar --sort=name --numeric-owner --owner=0 --group=0 \
    --mtime="@${SOURCE_DATE_EPOCH:-0}" -C "$rootfs" -cf "$work/rootfs.tar" .
gzip -9n < "$work/rootfs.tar" > "$output"
(cd "$(dirname "$output")" && sha256sum "$(basename "$output")") > "$output.sha256"
LC_ALL=C sort "$work/packages.txt" > "$work/packages-sorted.txt"
jq -Rn --arg snapshot "$snapshot" --arg release "$release" \
    --arg base "$minirootfs_version" --arg base_sha256 "$minirootfs_sha256" \
    --arg revision "${SOURCE_REVISION:-unknown}" \
    --arg sha256 "$(cut -d ' ' -f 1 "$output.sha256")" \
    '{architecture: "aarch64", alpine_release: $release, snapshot: $snapshot,
      minirootfs_version: $base, minirootfs_sha256: $base_sha256,
      source_revision: $revision, sha256: $sha256, packages: [inputs]}' \
    < "$work/packages-sorted.txt" > "$output.manifest.json"
echo "built $output ($(wc -c < "$output") bytes)"
