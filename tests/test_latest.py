from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from publish_latest import publish_latest


class LatestRepository(unittest.TestCase):
    def snapshot(self, root, date, version):
        for repo in ("main", "community"):
            path = root / date / repo / "aarch64"
            path.mkdir(parents=True)
            (path / "APKINDEX.tar.gz").write_bytes(b"signed-index-" + version.encode())
            (path / f"package-{version}.apk").write_bytes(b"signed-package")
        (root / date / "manifest.txt").write_text(version)

    def test_latest_moves_without_changing_dated_snapshots(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.snapshot(root, "2026-10-27", "1")
            self.assertEqual(publish_latest(root), "2026-10-27")
            self.snapshot(root, "2026-10-28", "2")
            self.assertEqual(publish_latest(root), "2026-10-28")
            latest = root / "latest"
            self.assertFalse(latest.is_symlink())
            self.assertEqual((latest / "snapshot.txt").read_text(), "2026-10-28\n")
            for repo in ("main", "community"):
                target = latest / repo / "aarch64"
                self.assertEqual((target / "APKINDEX.tar.gz").read_bytes(), b"signed-index-2")
                self.assertFalse((target / "package-1.apk").exists())
                self.assertTrue((root / "2026-10-27" / repo / "aarch64/package-1.apk").exists())
            self.assertEqual(publish_latest(root), "2026-10-28")

    def test_invalid_snapshot_does_not_replace_latest(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.snapshot(root, "2026-10-27", "1")
            publish_latest(root)
            (root / "2026-10-28").mkdir()
            with self.assertRaises(ValueError):
                publish_latest(root)
            self.assertEqual((root / "latest/snapshot.txt").read_text(), "2026-10-27\n")


if __name__ == "__main__":
    unittest.main()
