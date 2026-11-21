#!/usr/bin/env python3
"""Check the versioned offline certification inventory; never download client data.

Hashes normalize CRLF to LF. This checks reproducible source/coverage evidence,
not live-client correctness. Historical CSV replay remains a separate validator.
"""
import argparse
import hashlib
import json
import re
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "docs" / "certification-v1.json"
SOURCES = (
    "SpellPowerModels.lua", "SpellModifiers.lua", "SpellEstimates.lua", "DamageTips.lua",
    "tools/validate_forever_models.py", "tools/validate_forever_combat_log.py",
    "tools/validate_certification.py",
    "docs/forever-70938-validation.md", "docs/wild-growth-70938-validation.md",
    "docs/forever-combat-log-validator.md", "docs/held-tooltip-inputs.md",
    "docs/german-parser.md", "tests/german.lua",
)
PROBE = r'''
local root = arg[1]
local a = {}
for _, name in ipairs({"SpellPowerModels", "SpellModifiers", "SpellEstimates"}) do
    assert(loadfile(root .. "/" .. name .. ".lua"))("DamageTips", a)
end
for _, build in ipairs({"70888", "70938"}) do
    GetBuildInfo = function() return "1.60.1", build, "", 16001 end
    local ids = {}
    for id in pairs(a.SpellPowerModels) do ids[id] = true end
    for id in pairs(a.SpellPowerModels70938) do ids[id] = true end
    for id in pairs(ids) do
        local m = a.SpellEstimates.GetSpellModel(id)
        if m then print(build .. "," .. id .. "," .. (m.expected or "scaling-only")) end
    end
    assert(a.SpellEstimates.GetSpellModel(999999999) == nil, "unknown spell enabled")
end
for _, tuple in ipairs({{"1.60.1", "70939", 16001}, {"1.60.2", "70938", 16001}, {"1.60.1", "70938", 16002}}) do
    GetBuildInfo = function() return tuple[1], tuple[2], "", tuple[3] end
    for id in pairs(a.SpellPowerModels) do assert(a.SpellEstimates.GetSpellModel(id) == nil, "unknown build enabled") end
    for id in pairs(a.SpellPowerModels70938) do assert(a.SpellEstimates.GetSpellModel(id) == nil, "unknown build enabled") end
end
'''


def digest(path):
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def coverage(lua, root=ROOT):
    result = subprocess.run([lua, "-", str(root)], input=PROBE, text=True,
                            capture_output=True, check=True, timeout=30)
    builds = {"70888": [], "70938": []}
    for line in result.stdout.splitlines():
        build, spell, mode = line.split(",")
        builds[build].append({"spellID": int(spell), "mode": mode})
    for ranks in builds.values():
        ranks.sort(key=lambda row: row["spellID"])
        if not ranks:
            raise ValueError("empty coverage")
    return builds


def fingerprints(root=ROOT):
    record = (root / "docs/forever-70938-validation.md").read_text(encoding="utf-8")
    rows = re.findall(r"^ +([A-Za-z]+) +([a-f0-9]{64}) +([a-f0-9]{64}) *$", record, re.MULTILINE)
    if len(rows) != 23 or len({row[0] for row in rows}) != 23:
        raise ValueError("historical fingerprint record must contain exactly 23 unique tables")
    return {build: {row[0] + ".csv": row[index] for row in rows}
            for build, index in (("70888", 1), ("70938", 2))}


def preflight(directory, expected):
    for name, wanted in expected.items():
        with (directory / name).open("rb") as source:
            hasher = hashlib.sha256()
            for block in iter(lambda: source.read(1024 * 1024), b""):
                hasher.update(block)
            actual = hasher.hexdigest()
        if actual != wanted:
            raise ValueError(f"historical corpus hash mismatch: {name}")


def validate(data, actual, root=ROOT):
    if data.get("schemaVersion") != 1 or data.get("hashFormat") != "sha256-text-lf":
        raise ValueError("unsupported certification schema/hash format")
    if data.get("builds") != [
        {"version": "1.60.1", "build": b, "interface": 16001, "ranks": actual[b]}
        for b in ("70888", "70938")
    ]:
        raise ValueError("exact-build rank coverage differs from runtime authority")
    if data.get("corpusHashes") != fingerprints(root):
        raise ValueError("historical corpus fingerprint drift")
    expected = {name: digest(root / name) for name in SOURCES}
    if data.get("sourceHashes") != expected:
        raise ValueError("certification source/evidence hash drift; review and refresh inventory")
    if data.get("evidence") != EVIDENCE:
        raise ValueError("evidence scope differs from approved contract")
    return sum(len(ranks) for ranks in actual.values())


EVIDENCE = {
    "modelInputs": {
        "status": "historical-documented-client-data-review",
        "record": "docs/forever-70938-validation.md",
        "csvFingerprints": "23 tables per build recorded in that document",
        "rawCorpus": "not bundled; replay requires explicitly supplied matching exports",
        "replay": "tools/validate_forever_models.py --lua LUA --baseline DIR70888 --live DIR70938 --check",
    },
    "additional70938Models": {
        "records": ["docs/wild-growth-70938-validation.md", "docs/forever-combat-log-validator.md"],
        "captureStatus": "capture procedure and synthetic validator fixtures; no new live capture certification",
    },
    "parser": {
        "locales": ["enUS", "enGB", "deDE"],
        "deDE": "bounded original synthetic fixtures; actual client wording not certified",
        "record": "docs/german-parser.md",
    },
    "nativeTooltipReplay": {
        "version": "1.60.1", "build": "70938", "interface": 16001,
        "record": "docs/held-tooltip-inputs.md",
        "status": "primary client source contract plus offline mocks; no new live taint measurement",
    },
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", required=True, help="Trusted installed Lua 5.1 executable")
    parser.add_argument("--write", action="store_true", help="Refresh inventory after reviewing source/evidence changes")
    parser.add_argument("--baseline", type=Path, help="Explicit historical 70888 CSV directory (requires --live)")
    parser.add_argument("--live", type=Path, help="Explicit historical 70938 CSV directory (requires --baseline)")
    args = parser.parse_args()
    if (args.baseline is None) != (args.live is None):
        parser.error("--baseline and --live must be supplied together")
    actual = coverage(args.lua)
    if args.write:
        data = {"schemaVersion": 1, "hashFormat": "sha256-text-lf",
                "builds": [{"version": "1.60.1", "build": b, "interface": 16001, "ranks": actual[b]}
                           for b in ("70888", "70938")],
                "sourceHashes": {name: digest(ROOT / name) for name in SOURCES},
                "corpusHashes": fingerprints(), "evidence": EVIDENCE}
        MANIFEST.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    count = validate(data, actual)
    if args.baseline is not None:
        preflight(args.baseline, data["corpusHashes"]["70888"])
        preflight(args.live, data["corpusHashes"]["70938"])
        subprocess.run([sys.executable, "-B", str(ROOT / "tools/validate_forever_models.py"),
                        "--lua", args.lua, "--baseline", str(args.baseline), "--live", str(args.live), "--check"],
                       check=True, timeout=120)
    replay = "passed" if args.baseline is not None else "not performed"
    print(f"Certification inventory passed: {count} build/rank entries; historical corpus replay {replay}")


if __name__ == "__main__":
    main()
