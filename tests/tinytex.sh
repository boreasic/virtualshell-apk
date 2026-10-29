#!/bin/sh
set -eu
# Confirm the injected kernel fault reproduces the user's GNU tar error.
apk add --no-cache tar
mkdir -p /tmp/timestamp-probe/input /tmp/timestamp-probe/output
printf 'probe\n' > /tmp/timestamp-probe/input/file
tar -cf /tmp/timestamp-probe/archive.tar -C /tmp/timestamp-probe/input .
if tar -xf /tmp/timestamp-probe/archive.tar -C /tmp/timestamp-probe/output 2>/tmp/timestamp-probe/error.log; then
    echo 'Expected the old-kernel timestamp failure, but tar succeeded' >&2
    exit 1
fi
grep -q 'Cannot utime: Not a directory' /tmp/timestamp-probe/error.log
echo 'Confirmed old-kernel Cannot utime failure before testing the installer.'
# No --allow-untrusted: this tests APK signature verification as well.
apk add --no-cache /repo/tinytex-*.apk
[ "$(cat /opt/tinytex/.virtualshell-version)" = 2026.10 ]
[ ! -e /lib/ld-linux-aarch64.so.1 ]
mkdir /tmp/tex-test
cd /tmp/tex-test
cat > hello.tex <<'TEX'
\documentclass{article}
\begin{document}
Hello VirtualShell! $e^{i\pi}+1=0$
\end{document}
TEX
for engine in pdflatex xelatex lualatex; do
	"$engine" -interaction=nonstopmode -halt-on-error -jobname="$engine" hello.tex
	test -s "$engine.pdf"
done
latexmk -pdf -interaction=nonstopmode -halt-on-error hello.tex
# Re-running the installer must preserve tlmgr-managed files.
touch /opt/tinytex/preserve-test
tinytex-install
test -f /opt/tinytex/preserve-test
# Simulate an upstream update replacing a binary's ELF interpreter.
patchelf --set-interpreter /lib/ld-linux-aarch64.so.1 /opt/tinytex/bin/aarch64-linux/pdftex
tlmgr --version
test "$(patchelf --print-interpreter /opt/tinytex/bin/aarch64-linux/pdftex)" = /opt/tinytex/runtime/lib/ld-linux-aarch64.so.1
pdflatex -interaction=nonstopmode -halt-on-error hello.tex
# Package removal preserves downloaded data; reinstallation reuses it.
apk del tinytex
hash -r
if command -v pdflatex; then
    echo 'TinyTeX command wrapper survived package removal' >&2
    exit 1
fi
test -f /opt/tinytex/preserve-test
apk add --no-cache /repo/tinytex-*.apk
test -f /opt/tinytex/preserve-test
pdflatex --version
# Failed downloads must leave no partly installed tree or staging directory.
mv /opt/tinytex /opt/tinytex-saved
cp /usr/share/tinytex/downloads.txt /tmp/downloads.txt
printf '%s\n' '0000000000000000000000000000000000000000000000000000000000000000 bad.tar.xz file:///etc/hostname' > /usr/share/tinytex/downloads.txt
if tinytex-install; then
	echo 'Installer accepted a bad checksum' >&2
	exit 1
fi
test ! -e /opt/tinytex
test -z "$(find /opt -maxdepth 1 -name '.tinytex-install.*' -print)"
mv /tmp/downloads.txt /usr/share/tinytex/downloads.txt
mv /opt/tinytex-saved /opt/tinytex
echo 'TinyTeX installation, engines, repair, reinstall and checksum failure tests passed.'
