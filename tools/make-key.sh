#!/bin/sh
# Creates the snapshot signing key pair in the current directory.
#   <name>.rsa      private key: store it as the APK_SIGNING_KEY secret,
#                   then delete it or keep it offline. Never commit it.
#   <name>.rsa.pub  public key: commit it under keys/ and ship it in the app
#                   (clients install it as /etc/apk/keys/<name>.rsa.pub).
set -eu
name="${1:-virtualshell-$(date +%Y%m%d)-$(openssl rand -hex 4)}"
openssl genrsa -out "$name.rsa" 4096
openssl rsa -in "$name.rsa" -pubout -out "$name.rsa.pub"
chmod 600 "$name.rsa"
echo "key name: $name"
echo "set the APK_KEY_NAME variable to: $name"
