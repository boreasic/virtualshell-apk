#!/usr/bin/env python3
"""Build a dated, signed subset snapshot of the Alpine package repositories.

The snapshot holds the seed packages and everything they depend on, copied
from the official Alpine mirror. Each snapshot is a self-contained apk
repository per upstream repo:

    <site>/<release>/<date>/<repo>/<arch>/APKINDEX.tar.gz
    <site>/<release>/<date>/<repo>/<arch>/<name>-<version>.apk

The index keeps the upstream entries for those packages and is signed with
our key, so clients need our public key in /etc/apk/keys. The packages keep
Alpine's own signatures. Only the Python standard library and the openssl
command are needed.
"""
import argparse
import datetime
import gzip
import io
import os
import re
import shutil
import subprocess
import sys
import tarfile
import urllib.request

UPSTREAM = "https://dl-cdn.alpinelinux.org/alpine"
REPOS = ("main", "community")
# Git hosts reject files over 100 MB; stay clear of that limit.
MAX_PACKAGE_BYTES = 95 * 1024 * 1024


def fetch(url):
    with urllib.request.urlopen(url, timeout=120) as response:
        return response.read()


def parse_index(text):
    """Returns {name: entry}; an entry keeps its raw text for the new index."""
    packages = {}
    for block in text.split("\n\n"):
        fields = {}
        for line in block.splitlines():
            if len(line) > 2 and line[1] == ":":
                fields.setdefault(line[0], []).append(line[2:])
        if "P" not in fields:
            continue
        name = fields["P"][0]
        packages[name] = {
            "name": name,
            "version": fields["V"][0],
            "size": int(fields["S"][0]),
            "depends": fields.get("D", [""])[0].split(),
            "provides": fields.get("p", [""])[0].split(),
            "install_if": fields.get("i", [""])[0].split(),
            "priority": int(fields.get("k", ["0"])[0]),
            "raw": block.strip("\n"),
        }
    return packages


def load_upstream(mirror, release, arch):
    upstream = {}
    for repo in REPOS:
        url = f"{mirror}/{release}/{repo}/{arch}/APKINDEX.tar.gz"
        with tarfile.open(fileobj=io.BytesIO(fetch(url)), mode="r:gz") as archive:
            text = archive.extractfile("APKINDEX").read().decode()
        for name, entry in parse_index(text).items():
            entry["repo"] = repo
            # main wins over community if a name appears in both.
            upstream.setdefault(name, entry)
    return upstream


def strip_constraint(token):
    return re.split(r"[=<>~]", token, maxsplit=1)[0]


def provider_map(upstream):
    """Maps every provided name (so:, cmd:, pc:, virtual names) to the
    package that supplies it: highest provider priority, then main."""
    providers = {}
    for entry in upstream.values():
        for provided in [entry["name"]] + [strip_constraint(p) for p in entry["provides"]]:
            best = providers.get(provided)
            if best is None or (entry["priority"], entry["repo"] == "main") > (
                    best["priority"], best["repo"] == "main"):
                providers[provided] = entry
    # A real package name always resolves to that package.
    for entry in upstream.values():
        providers[entry["name"]] = entry
    return providers


def resolve(seeds, upstream):
    """The seeds and their dependencies, plus every package whose install_if
    the selection satisfies (and its dependencies). apk installs those
    automatically, from any configured repository: left out, apk picks
    them from the tagged Alpine mirror, where they are masked, and the
    whole install fails (python3 needs python3-pyc that way)."""
    providers = provider_map(upstream)
    selected = {}
    missing = []
    stack = list(seeds)
    while True:
        while stack:
            token = stack.pop()
            if token.startswith("!"):
                continue
            entry = providers.get(strip_constraint(token))
            if entry is None:
                missing.append(token)
                continue
            if entry["name"] in selected:
                continue
            selected[entry["name"]] = entry
            stack.extend(entry["depends"])
        names = set(selected)
        for entry in selected.values():
            names.update(strip_constraint(p) for p in entry["provides"])
        stack = [e["name"] for e in upstream.values()
                 if e["install_if"] and e["name"] not in selected
                 and all(strip_constraint(t) in names for t in e["install_if"])]
        if not stack:
            return selected, missing


def read_seeds(path):
    seeds = []
    with open(path) as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if line:
                seeds.append(line)
    return seeds


def manifest_lines(selected):
    return sorted(f"{e['repo']} {e['name']} {e['version']}" for e in selected.values())


def tar_member(name, data):
    """One tar entry (header and padded data) without the end-of-archive
    blocks, as apk expects for the signature stream."""
    info = tarfile.TarInfo(name)
    info.size = len(data)
    info.mode = 0o644
    info.mtime = 0
    info.uname = info.gname = "root"
    padding = (-len(data)) % tarfile.BLOCKSIZE
    return info.tobuf(format=tarfile.USTAR_FORMAT) + data + b"\0" * padding


def build_index(entries, description):
    text = "\n\n".join(e["raw"] for e in sorted(entries, key=lambda e: e["name"])) + "\n\n"
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w", format=tarfile.USTAR_FORMAT) as archive:
        for name, data in (("DESCRIPTION", description.encode()), ("APKINDEX", text.encode())):
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            info.mtime = 0
            archive.addfile(info, io.BytesIO(data))
    return gzip.compress(buf.getvalue(), compresslevel=9, mtime=0)


def sign_index(index_gz, key_file, key_name):
    """Prepends the RSA-SHA1 signature stream that apk verifies against
    /etc/apk/keys/<key_name>.rsa.pub."""
    signature = subprocess.run(
        ["openssl", "dgst", "-sha1", "-sign", key_file],
        input=index_gz, capture_output=True, check=True).stdout
    member = tar_member(f".SIGN.RSA.{key_name}.rsa.pub", signature)
    return gzip.compress(member, compresslevel=9, mtime=0) + index_gz


def snapshot_dirs(release_dir):
    if not os.path.isdir(release_dir):
        return []
    return sorted(d for d in os.listdir(release_dir)
                  if re.fullmatch(r"\d{4}-\d{2}-\d{2}", d))


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--release", default="v3.21")
    parser.add_argument("--arch", default="aarch64")
    parser.add_argument("--seeds", required=True)
    parser.add_argument("--site", required=True, help="root of the published site")
    parser.add_argument("--key-file", required=True, help="private signing key (PEM)")
    parser.add_argument("--key-name", required=True, help="public key name without .rsa.pub")
    parser.add_argument("--date", default=datetime.date.today().isoformat())
    parser.add_argument("--keep", type=int, default=4, help="snapshots to keep per release")
    parser.add_argument("--mirror", default=UPSTREAM)
    parser.add_argument("--force", action="store_true", help="snapshot even if nothing changed")
    args = parser.parse_args()

    release_dir = os.path.join(args.site, args.release)
    upstream = load_upstream(args.mirror, args.release, args.arch)
    selected, missing = resolve(read_seeds(args.seeds), upstream)
    if missing:
        sys.exit(f"unresolved dependencies: {', '.join(sorted(set(missing)))}")
    too_big = [e["name"] for e in selected.values() if e["size"] > MAX_PACKAGE_BYTES]
    if too_big:
        sys.exit(f"packages over {MAX_PACKAGE_BYTES} bytes: {', '.join(too_big)}")

    manifest = manifest_lines(selected)
    previous = snapshot_dirs(release_dir)
    if previous and not args.force:
        with open(os.path.join(release_dir, previous[-1], "manifest.txt")) as f:
            if f.read().splitlines() == manifest:
                print(f"unchanged since {previous[-1]}")
                return 0

    snapshot = os.path.join(release_dir, args.date)
    total = 0
    for repo in REPOS:
        entries = [e for e in selected.values() if e["repo"] == repo]
        out_dir = os.path.join(snapshot, repo, args.arch)
        os.makedirs(out_dir, exist_ok=True)
        for entry in entries:
            filename = f"{entry['name']}-{entry['version']}.apk"
            dest = os.path.join(out_dir, filename)
            # Reuse an identical file from an earlier snapshot.
            reused = next((os.path.join(release_dir, d, repo, args.arch, filename)
                           for d in reversed(previous)
                           if os.path.isfile(os.path.join(release_dir, d, repo, args.arch, filename))),
                          None)
            if reused and os.path.abspath(reused) != os.path.abspath(dest):
                shutil.copyfile(reused, dest)
            elif not os.path.isfile(dest):
                with open(dest, "wb") as f:
                    f.write(fetch(f"{args.mirror}/{args.release}/{repo}/{args.arch}/{filename}"))
            if os.path.getsize(dest) != entry["size"]:
                sys.exit(f"{filename}: size {os.path.getsize(dest)} != index {entry['size']}")
            total += entry["size"]
        index = build_index(entries, f"virtualshell {args.release} {args.date} {repo}")
        with open(os.path.join(out_dir, "APKINDEX.tar.gz"), "wb") as f:
            f.write(sign_index(index, args.key_file, args.key_name))

    with open(os.path.join(snapshot, "manifest.txt"), "w") as f:
        f.write("\n".join(manifest) + "\n")
    dates = sorted(set(previous) | {args.date})
    for old in dates[:-args.keep] if args.keep > 0 else []:
        shutil.rmtree(os.path.join(release_dir, old))
        dates.remove(old)
    with open(os.path.join(release_dir, "snapshots.txt"), "w") as f:
        f.write("\n".join(dates) + "\n")
    print(f"snapshot {args.release}/{args.date}: {len(selected)} packages, {total / 1e6:.0f} MB")

    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as f:
            f.write(f"snapshot={args.release}/{args.date}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
