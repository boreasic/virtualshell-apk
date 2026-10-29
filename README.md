# virtualshell-apk

Dated, signed snapshots of a subset of Alpine Linux's aarch64 packages for
Virtual Shell. Each Virtual Shell release pins one snapshot, so `apk add`
installs the package versions that release was tested with, even after
Alpine replaces them upstream.

## How it works

`seeds/v3.21.txt` lists the packages users need. Every month (or when run
by hand), the
[Snapshot workflow](.github/workflows/snapshot.yml) runs `snapshot.py`:

1. It downloads Alpine v3.21's `main` and `community` indexes and resolves
   the seeds plus all their dependencies.
2. If that set is the same as in the newest snapshot, it stops.
3. Otherwise it writes a new dated snapshot with a copy of every package
   (files already present in an earlier snapshot are reused) and an index
   holding the upstream entries for those packages, signed with our key.
4. It keeps the newest ten snapshots and publishes the site to the
   `pages` branch, which GitHub Pages serves.

Mirrored packages keep Alpine's own signatures. Custom packages and all
snapshot indexes are signed with our key, so clients need our public key.

Site layout:

```
keys/<key>.rsa.pub
v3.21/snapshots.txt                          # available dates, newest last
v3.21/<date>/manifest.txt                    # repo, name, version per package
v3.21/<date>/{main,community}/aarch64/APKINDEX.tar.gz
v3.21/<date>/{main,community}/aarch64/*.apk
```

## Following the latest packages

Use these stable repositories to follow the newest published snapshot:

```
https://boreasic.github.io/virtualshell-apk/v3.21/latest/main
https://boreasic.github.io/virtualshell-apk/v3.21/latest/community
```

On an existing VirtualShell installation, add them in a separate APK repository
file. Older app builds rewrite `/etc/apk/repositories` at startup, but leave
`repositories.d` alone. No iPhone app update is needed:

```sh
mkdir -p /etc/apk/repositories.d
printf '%s\n' \
  https://boreasic.github.io/virtualshell-apk/v3.21/latest/main \
  https://boreasic.github.io/virtualshell-apk/v3.21/latest/community \
  > /etc/apk/repositories.d/virtualshell-latest.list
apk update
```

This assumes the VirtualShell signing key is already installed, as it is in
existing managed roots. The dated repository may still appear in `apk update`
output; the added untagged `latest` repositories make newer package versions
available too. `apk update` refreshes indexes; `apk upgrade` upgrades installed
packages. Each snapshot workflow refreshes `latest`, including runs with no
new dated snapshot. `v3.21/latest/snapshot.txt` records the date currently served.
This follows published Alpine **v3.21** snapshots, not Alpine edge or every
upstream update immediately. Run the workflow to publish new packages sooner
than its monthly schedule.

The latest endpoint contains regular copies of the signed indexes and APKs;
GitHub Pages redirects or symlinks are not involved. Dated snapshot contents
remain unchanged. After a repository refresh, run `apk update` again if a
previously cached index references a version no longer available under latest.
An app update may still be necessary for emulator compatibility fixes.

## Using a snapshot

Install the public key as `/etc/apk/keys/<key>.rsa.pub` and use:

```
https://<user>.github.io/virtualshell-apk/v3.21/<date>/main
https://<user>.github.io/virtualshell-apk/v3.21/<date>/community
@alpine https://dl-cdn.alpinelinux.org/alpine/v3.21/main
@alpine https://dl-cdn.alpinelinux.org/alpine/v3.21/community
```

`apk add nodejs` installs the pinned version. Packages outside the
snapshot stay available from Alpine as an explicit choice:
`apk add postgresql@alpine`. Without the tag, apk would pick the newest
version from any repository and the pinning would be lost.

## Default root filesystem

The rootfs builder lives here alongside the package snapshots and public
keys it consumes. The [Dockerfile](Dockerfile) builds an ARM64 default
filesystem: Alpine's checksum-pinned minirootfs plus `bash` (root's login shell; `/bin/sh` stays
BusyBox), installed with apk from a pinned snapshot, and the files in
`rootfs/overlay/` (`clc`, `/etc/profile.d` and `/etc/bash` defaults, bash
startup files). `rootfs/build.sh` runs `apk update` and `apk add bash`
against the guest filesystem and verifies that Bash can execute. Builder
tools and package caches are excluded from the archive.

After each snapshot the [Rootfs workflow](.github/workflows/rootfs.yml)
builds it for the newest snapshot with Docker on an arm64 runner and creates
an immutable GitHub Release tagged `rootfs-v3.21-<date>`. Each release has:

```
virtualshell-rootfs-aarch64.tar.gz
virtualshell-rootfs-aarch64.tar.gz.sha256
virtualshell-rootfs-aarch64.tar.gz.manifest.json
```

Build locally with Docker (ARM64 execution or emulation is required):

```sh
docker buildx build --platform linux/arm64 \
  --build-arg SNAPSHOT=2026-10-23 \
  --build-arg SOURCE_REVISION="$(git rev-parse HEAD)" \
  --build-arg SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)" \
  --output type=local,dest=out .
(cd out && shasum -a 256 -c virtualshell-rootfs-aarch64.tar.gz.sha256)
```

Choose a date listed in `v3.21/snapshots.txt` on the published site.
The final Docker stage exports only the three release files; it is not a
runnable container. The tarball has filesystem paths at its root, ready
for the app's importer. The manifest records all installed package
versions, the snapshot, base checksum, archive checksum, and source commit.
Archive ownership and timestamps are normalized; full byte-for-byte
reproducibility also depends on package scripts and the builder image.
The Docker context includes only the rootfs sources and public keys.

The app should pin a release-asset URL and verify its SHA-256 before bundling
it; switching the app from Alpine's stock image is a separate integration
step. Retain the APK snapshots used by supported app releases so `apk add`
continues to resolve the package set the rootfs was tested with.

For a direct build, the script also runs as root in an aarch64 Alpine system:
`sh rootfs/build.sh <snapshot-date> out/rootfs.tar.gz`.

## Setup

1. Create a **public** GitHub repository named `virtualshell-apk` and push
   this one. GitHub Pages is only free for public repositories.
2. Create the signing key:
   ```sh
   tools/make-key.sh
   ```
   - Add the contents of `<key>.rsa` as the repository secret
     `APK_SIGNING_KEY`, then delete the file or store it offline.
   - Add the repository variable `APK_KEY_NAME` with the printed key name.
   - Commit `<key>.rsa.pub` under `keys/`.
3. Run the Snapshot workflow once (Actions → Snapshot → Run workflow). It
   creates the `pages` branch.
4. Enable Pages: Settings → Pages → Deploy from a branch → `pages`, `/`.

## Building locally

```sh
tools/make-key.sh test-key
tools/build-custom.sh test-key.rsa test-key out/custom
python3 snapshot.py --seeds seeds/v3.21.txt --site site \
  --key-file test-key.rsa --key-name test-key --local-repo out/custom/aarch64
```

Then point a test root's `/etc/apk/repositories` at
`site/v3.21/<date>/main` and `.../community`, copy `test-key.rsa.pub` to
`/etc/apk/keys/`, and run `apk update && apk add <seeds>`. Without the key,
apk reports the indexes as `UNTRUSTED signature` and ignores them.

## Limits

- GitHub Pages serves up to about 1 GB per site. One snapshot of the
  current seeds is about 80 MB, and ten are kept (`--keep 10`).
- An app release pinned to a pruned snapshot can no longer install
  packages. Monthly snapshots with ten kept give each release about ten
  months. Run the workflow by hand when preparing a release instead of
  waiting for the schedule, and move the site to object storage (for
  example Cloudflare R2) when more seeds or a longer window are needed.
- Pruned files stay in the `pages` branch history. Squash that branch from
  time to time if the repository grows too large.
- Files over 95 MB are rejected because Git hosts refuse files over 100 MB.
- Mirrored packages keep their own licenses. The site serves Alpine's
  unmodified packages; their sources are in Alpine's aports repository.

## TinyTeX

New snapshots include a signed `tinytex` installer package:

```sh
apk update
apk add tinytex
pdflatex document.tex
# Also available: xelatex, lualatex, latexmk, bibtex, and tlmgr.
tlmgr install <latex-package>
```

An existing VirtualShell installation remains pinned to its original snapshot.
To use newly added packages, change **both** VirtualShell snapshot URLs in
`/etc/apk/repositories` to a new date listed in
<https://boreasic.github.io/virtualshell-apk/v3.21/snapshots.txt>, then run
`apk update`. Keep the `@alpine` repository tags and the installed signing key.
Old snapshots are not retroactively modified.

The small APK downloads TinyTeX-1 **2026.10** (about 54 MB) and about 4 MB of
private runtime archives from upstream during installation. Allow roughly
500 MB free for download, extraction and the installed tree. All downloads
are pinned and verified with SHA-256 before extraction. An interrupted or
failed installation can be retried with `tinytex-install`; it will not replace
an existing unmanaged `/opt/tinytex` or overwrite an older installation.

TinyTeX upstream does not provide an aarch64-musl build. Its ARM64 glibc
binaries are therefore paired with a private Debian Bookworm runtime under
`/opt/tinytex/runtime`, including fontconfig dependencies. Only TinyTeX ELF
executables are patched to use that loader and library directory. Alpine's
system libraries and loader are unchanged. `gcompat` alone fails the LuaTeX
and XeTeX compilation tests and is deliberately not used.

`tlmgr` runs through a wrapper that repairs the private ELF interpreter and
library paths before and after updates. Use the packaged `/usr/bin/tlmgr`,
not the underlying script's absolute path. TeX Live upgrades across annual
releases require a fresh TinyTeX installation. The package owns command
wrappers; the downloaded tree is managed by TinyTeX, not APK. `apk del tinytex`
removes the wrappers but retains `/opt/tinytex`, including packages installed
with `tlmgr`. Remove that directory separately if you want to delete the
installation. Reinstalling the same version reuses it without downloading.

The wrapper APK is MIT licensed. Downloaded TinyTeX/TeX Live components keep
their upstream licenses; Debian copyright notices are retained under
`/opt/tinytex/runtime/licenses`. No upstream binaries are vendored in this
repository. The exact runtime URLs and checksums live in
`packages/tinytex/downloads.txt`; maintain these pins as upstream packages
receive security updates or are retired from mirrors.

The Snapshot workflow builds custom APKs using Alpine `abuild` on ARM64 and
tests the signed TinyTeX APK in a clean Alpine 3.21 container before publishing.
Tests compile PDFs with all three engines and latexmk, exercise runtime repair,
verify reinstall preserves data, and reject a corrupted download. Run locally:

```sh
python3 -m unittest discover -s tests -v
tools/test-tinytex.sh out/custom/aarch64 test-key.rsa.pub
```

pdfLaTeX, XeLaTeX and LuaLaTeX were also checked through VirtualShell's local
ARM64 emulator with a one-page document. This requires VirtualShell's
`fstatat(..., AT_EMPTY_PATH)` fix: older app builds fail in glibc's loader with
“cannot stat shared object: Error 20”. Update the app as well as its snapshot
before using this package. The app's `APK_SNAPSHOT` should be `2026-10-28` or
later. The native container tests remain part of each snapshot workflow.


### Retrying an installer timestamp error

Installer `2026.10-r1` extracts with `tar --touch` and copies runtime files
without preserving timestamps. This avoids older VirtualShell's
`utimensat(fd, NULL, ...)` bug. With the rolling repository configured, run:

```sh
apk update
apk add --upgrade tinytex
```

The installer regression test denies that syscall form with `ENOTDIR` using
seccomp, then runs the complete installation and PDF tests. This workaround
addresses extraction only: the older app's separate `fstatat(AT_EMPTY_PATH)`
loader bug still requires the app compatibility fix described above.
