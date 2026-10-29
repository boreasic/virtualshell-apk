#!/usr/bin/env python3
"""Materialize the newest signed snapshot at a stable URL for GitHub Pages."""
import argparse
from pathlib import Path
import shutil
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from snapshot import snapshot_dirs


def publish_latest(release_dir):
    release_dir = Path(release_dir)
    dates = snapshot_dirs(release_dir)
    if not dates:
        raise ValueError(f"no snapshots in {release_dir}")
    date = dates[-1]
    source = release_dir / date
    # Copy the signed bytes verbatim; Pages cannot serve symlink aliases.
    for repo in ("main", "community"):
        if not list((source / repo).glob("*/APKINDEX.tar.gz")):
            raise ValueError(f"missing signed {repo} index in {source}")
    stage = Path(tempfile.mkdtemp(prefix=".latest-", dir=release_dir))
    try:
        shutil.copytree(source, stage, dirs_exist_ok=True)
        (stage / "snapshot.txt").write_text(date + "\n")
        latest = release_dir / "latest"
        if latest.is_symlink():
            latest.unlink()
        elif latest.exists():
            shutil.rmtree(latest)
        stage.rename(latest)
    finally:
        if stage.exists():
            shutil.rmtree(stage)
    return date


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--site", required=True)
    parser.add_argument("--release", default="v3.21")
    args = parser.parse_args()
    print(f"latest -> {publish_latest(Path(args.site) / args.release)}")
