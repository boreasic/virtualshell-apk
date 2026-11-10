#!/bin/sh
set -eu
# No --allow-untrusted: this tests APK signature verification as well.
apk add --no-cache /repo/codex-*.apk /repo/claude-code-*.apk
codex --version
claude --version
# Re-running the installers keeps the verified binaries without downloading.
codex-install
claude-code-install
# Removal deletes the downloaded binaries along with the wrappers.
apk del codex claude-code
[ ! -e /opt/codex ] && [ ! -e /opt/claude-code ]
[ ! -e /usr/bin/codex ] && [ ! -e /usr/bin/claude ]
echo 'Codex and Claude Code package tests passed.'
