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

Packages keep Alpine's own signatures; only the index is signed by us, so
clients need our public key.

Site layout:

```
keys/<key>.rsa.pub
v3.21/snapshots.txt                          # available dates, newest last
v3.21/<date>/manifest.txt                    # repo, name, version per package
v3.21/<date>/{main,community}/aarch64/APKINDEX.tar.gz
v3.21/<date>/{main,community}/aarch64/*.apk
```

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
python3 snapshot.py --seeds seeds/v3.21.txt --site site \
  --key-file test-key.rsa --key-name test-key
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
