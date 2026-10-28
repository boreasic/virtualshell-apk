#!/bin/sh
set -eu
apk add --update-cache alpine-sdk >/dev/null
export PACKAGER_PRIVKEY="/input/$APK_KEY_NAME.rsa"
chmod 600 "$PACKAGER_PRIVKEY"
openssl rsa -in "$PACKAGER_PRIVKEY" -pubout -out "/etc/apk/keys/$APK_KEY_NAME.rsa.pub"
cp "/etc/apk/keys/$APK_KEY_NAME.rsa.pub" "$PACKAGER_PRIVKEY.pub"
export REPODEST=/out
for recipe in /input/*/APKBUILD; do
	(cd "$(dirname "$recipe")" && abuild -F -r)
done
# abuild derives the repository name from the parent directory (/input).
mv /out/input/aarch64 /out/aarch64
rmdir /out/input
