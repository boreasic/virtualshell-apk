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
# Writes OUTPUT.tar.gz and OUTPUT.tar.gz.sha256.
set -eu

snapshot=$1
output=$2
here=$(cd "$(dirname "$0")" && pwd)
release=v3.21
minirootfs_version=3.21.0
site=https://boreasic.github.io/virtualshell-apk
packages="bash"

# GNU tar sorts entries for a reproducible archive.
apk add --no-cache tar >/dev/null

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
rootfs=$work/rootfs
mkdir -p "$rootfs"
wget -qO "$work/minirootfs.tar.gz" \
    "https://dl-cdn.alpinelinux.org/alpine/$release/releases/aarch64/alpine-minirootfs-$minirootfs_version-aarch64.tar.gz"
tar -xzf "$work/minirootfs.tar.gz" -C "$rootfs"

# The pinned snapshot first, Alpine's mirror only for explicit @alpine.
cp "$here"/../keys/*.rsa.pub "$rootfs/etc/apk/keys/"
cat > "$rootfs/etc/apk/repositories" <<EOF
$site/$release/$snapshot/main
$site/$release/$snapshot/community
@alpine https://dl-cdn.alpinelinux.org/alpine/$release/main
@alpine https://dl-cdn.alpinelinux.org/alpine/$release/community
EOF
apk --root "$rootfs" --keys-dir "$rootfs/etc/apk/keys" \
    --repositories-file "$rootfs/etc/apk/repositories" --no-cache add $packages >/dev/null

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
tar --sort=name --numeric-owner -C "$rootfs" -cf - . | gzip -9n > "$output"
(cd "$(dirname "$output")" && sha256sum "$(basename "$output")") > "$output.sha256"
echo "built $output ($(wc -c < "$output") bytes)"
