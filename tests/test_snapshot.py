import io
import pathlib
import sys
import tarfile
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parents[1]))
import snapshot


class CustomPackages(unittest.TestCase):
    def make_repo(self, directory, arch="aarch64"):
        raw = f"P:tinytex\nV:2026.10-r0\nA:{arch}\nS:3\nI:3\nD:perl curl\n"
        with tarfile.open(pathlib.Path(directory) / "APKINDEX.tar.gz", "w:gz") as archive:
            member = tarfile.TarInfo("APKINDEX")
            member.size = len(raw)
            archive.addfile(member, io.BytesIO(raw.encode()))
        (pathlib.Path(directory) / "tinytex-2026.10-r0.apk").write_bytes(b"apk")

    def test_custom_dependencies_are_resolved(self):
        with tempfile.TemporaryDirectory() as directory:
            self.make_repo(directory)
            upstream = snapshot.parse_index("P:perl\nV:1\nS:1\n\nP:curl\nV:1\nS:1\n")
            for entry in upstream.values():
                entry["repo"] = "main"
            snapshot.load_local(directory, "aarch64", upstream)
            selected, missing = snapshot.resolve(["tinytex"], upstream)
            self.assertEqual(set(selected), {"tinytex", "perl", "curl"})
            self.assertEqual(missing, [])
            self.assertEqual(selected["tinytex"]["repo"], "community")
            self.assertTrue(pathlib.Path(selected["tinytex"]["local_file"]).is_file())

    def test_reject_wrong_architecture_and_upstream_collision(self):
        with tempfile.TemporaryDirectory() as directory:
            self.make_repo(directory, "x86_64")
            with self.assertRaisesRegex(ValueError, "architecture"):
                snapshot.load_local(directory, "aarch64", {})
            self.make_repo(directory)
            with self.assertRaisesRegex(ValueError, "shadows"):
                snapshot.load_local(directory, "aarch64", {"tinytex": {}})

    def test_reject_damaged_package(self):
        with tempfile.TemporaryDirectory() as directory:
            self.make_repo(directory)
            (pathlib.Path(directory) / "tinytex-2026.10-r0.apk").write_bytes(b"bad apk")
            with self.assertRaisesRegex(ValueError, "size mismatch"):
                snapshot.load_local(directory, "aarch64", {})


if __name__ == "__main__":
    unittest.main()
