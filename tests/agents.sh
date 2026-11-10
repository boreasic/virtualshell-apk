#!/bin/sh
set -eu
# Reproduce the old installer's executable-only layout at the same version.
mkdir -p /opt/codex/0.167.0
printf '#!/bin/sh\nexit 0\n' > /opt/codex/0.167.0/codex
chmod 755 /opt/codex/0.167.0/codex
# No --allow-untrusted: this tests APK signature verification as well.
apk add --no-cache /repo/codex-*.apk /repo/claude-code-*.apk
codex --version
claude --version
# Re-running the installers keeps the verified binaries without downloading.
codex-install
claude-code-install
# --version alone misses incomplete packages. Exercise real daemon lifecycle
# without credentials or a model request, and leave no background processes.
CODEX_HOME=$(mktemp -d /root/codex-daemon.XXXXXX)
export CODEX_HOME
trap 'codex app-server daemon stop >/dev/null 2>&1 || true; rm -rf "$CODEX_HOME"' EXIT
codex app-server daemon start
codex app-server daemon version | grep -Eq '"status"[[:space:]]*:[[:space:]]*"running"'
codex app-server daemon stop
rm -rf "$CODEX_HOME"
trap - EXIT
# Removal deletes the downloaded binaries along with the wrappers.
apk del codex claude-code
[ ! -e /opt/codex ] && [ ! -e /opt/claude-code ]
[ ! -e /usr/bin/codex ] && [ ! -e /usr/bin/claude ]
echo 'Codex and Claude Code package tests passed.'
