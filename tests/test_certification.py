"""Certification drift and scope regressions using original offline fixtures."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("certification", ROOT / "tools/validate_certification.py")
cert = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cert)


class CertificationTests(unittest.TestCase):
    def setUp(self):
        self.data = json.loads(cert.MANIFEST.read_text(encoding="utf-8"))
        self.actual = {row["build"]: copy.deepcopy(row["ranks"]) for row in self.data["builds"]}

    def test_current_inventory(self):
        self.assertEqual(cert.validate(self.data, self.actual), 445)

    def test_unknown_schema(self):
        self.data["schemaVersion"] = 2
        with self.assertRaisesRegex(ValueError, "schema"):
            cert.validate(self.data, self.actual)

    def test_changed_build(self):
        self.data["builds"][0]["build"] = "70939"
        with self.assertRaisesRegex(ValueError, "coverage"):
            cert.validate(self.data, self.actual)

    def test_missing_rank(self):
        self.data["builds"][1]["ranks"].pop()
        with self.assertRaisesRegex(ValueError, "coverage"):
            cert.validate(self.data, self.actual)

    def test_duplicate_rank(self):
        self.data["builds"][1]["ranks"].append(self.data["builds"][1]["ranks"][0])
        with self.assertRaisesRegex(ValueError, "coverage"):
            cert.validate(self.data, self.actual)

    def test_changed_source_hash(self):
        self.data["sourceHashes"]["SpellEstimates.lua"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "hash drift"):
            cert.validate(self.data, self.actual)

    def test_unreviewed_live_claim(self):
        self.data["evidence"]["parser"]["deDE"] = "live certified"
        with self.assertRaisesRegex(ValueError, "evidence scope"):
            cert.validate(self.data, self.actual)

    def test_corpus_hash_drift(self):
        self.data["corpusHashes"]["70888"]["Spell.csv"] = "0" * 64
        with self.assertRaisesRegex(ValueError, "fingerprint drift"):
            cert.validate(self.data, self.actual)

    def test_missing_corpus(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(FileNotFoundError):
                cert.preflight(Path(directory), {"Spell.csv": "0" * 64})

    def test_wrong_and_matching_corpus(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Spell.csv"
            path.write_bytes(b"original synthetic CSV fixture\n")
            with self.assertRaisesRegex(ValueError, "hash mismatch"):
                cert.preflight(Path(directory), {"Spell.csv": "0" * 64})
            cert.preflight(Path(directory), {"Spell.csv": cert.hashlib.sha256(path.read_bytes()).hexdigest()})

    def test_crlf_hash_is_stable(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.txt"
            path.write_bytes(b"original\nfixture\n")
            expected = cert.digest(path)
            path.write_bytes(b"original\r\nfixture\r\n")
            self.assertEqual(cert.digest(path), expected)


if __name__ == "__main__":
    unittest.main()
