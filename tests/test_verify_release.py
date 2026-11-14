import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "verify_release.py"
FILES = (
    "AUDIT.txt", "CHANGELOG.txt", "CREDITS.txt", "DESCRIPTION.txt", "DamageTips.lua",
    "DamageTips.toc", "LICENSE.txt", "Media/icon.tga", "Media/logo.png", "README.txt",
    "SpellEstimates.lua", "SpellModifiers.lua", "SpellPowerModels.lua",
)


class ReleaseTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.repo = Path(temp.name, "repo")
        self.repo.mkdir()
        self.output = Path(temp.name, "DamageTips.zip")
        self.git("init", "--quiet")
        self.git("config", "core.autocrlf", "true")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "user.name", "Release fixture")
        (self.repo / "Media").mkdir()
        for name in FILES:
            content = b"Fixture text\n" if not name.startswith("Media/") else b"\x00\x80\r\n"
            (self.repo / name).write_bytes(content)
        (self.repo / "DamageTips.toc").write_bytes(
            b"## Interface: 16001\n## Version: 1.6.2\nDamageTips.lua\n"
        )
        (self.repo / "UnpackagedSource.py").write_bytes(b"# belongs in the checkout\n")
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "Fixture addon")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), *args], stderr=subprocess.PIPE)

    def verify(self, tag, *args):
        return subprocess.run(
            [sys.executable, "-B", str(SCRIPT), "--tag", tag, "--output", str(self.output), *args],
            cwd=self.repo, capture_output=True, text=True, check=False,
        )

    def test_package_matches_the_requested_commit_blobs_and_allowlist(self):
        sha = self.git("rev-parse", "HEAD").decode().strip()
        (self.repo / "DamageTips.lua").write_bytes(b"New working copy\n")
        self.git("add", "DamageTips.lua")
        self.git("commit", "--quiet", "-m", "Change unselected commit")
        report = self.verify("v1.6.2", "--ref", sha)
        self.assertEqual(report.returncode, 0, report.stdout + report.stderr)
        with zipfile.ZipFile(self.output) as archive:
            names = [item.filename for item in archive.infolist() if not item.is_dir()]
            self.assertCountEqual(names, [f"DamageTips/{name}" for name in FILES])
            self.assertIsNone(archive.testzip())
            for name in FILES:
                with self.subTest(path=name):
                    self.assertEqual(archive.read(f"DamageTips/{name}"), self.git("cat-file", "blob", f"{sha}:{name}"))

    def test_wrong_tag_version_rejects_and_does_not_create_output(self):
        report = self.verify("v1.6.1")
        self.assertNotEqual(report.returncode, 0, report.stdout + report.stderr)
        self.assertIn("version", report.stderr.lower())
        self.assertFalse(self.output.exists())

    def test_missing_install_file_rejects_and_does_not_create_output(self):
        self.git("rm", "SpellEstimates.lua")
        self.git("commit", "--quiet", "-m", "Incomplete fixture")
        report = self.verify("v1.6.2")
        self.assertNotEqual(report.returncode, 0, report.stdout + report.stderr)
        self.assertIn("SpellEstimates.lua", report.stderr)
        self.assertFalse(self.output.exists())

    def test_archive_substitution_cannot_change_committed_install_bytes(self):
        (self.repo / ".gitattributes").write_text("AUDIT.txt export-subst\n", encoding="utf-8")
        (self.repo / "AUDIT.txt").write_bytes(b"Archive commit: $Format:%H$\n")
        self.git("add", ".gitattributes", "AUDIT.txt")
        self.git("commit", "--quiet", "-m", "Substitute archive text")
        report = self.verify("v1.6.2")
        self.assertNotEqual(report.returncode, 0, report.stdout + report.stderr)
        self.assertIn("bytes differ", report.stderr)
        self.assertFalse(self.output.exists())

    def test_existing_output_is_preserved(self):
        self.output.write_bytes(b"Existing output")
        report = self.verify("v1.6.2")
        self.assertNotEqual(report.returncode, 0, report.stdout + report.stderr)
        self.assertEqual(self.output.read_bytes(), b"Existing output")


if __name__ == "__main__":
    unittest.main()
