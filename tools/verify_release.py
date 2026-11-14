#!/usr/bin/env python3
"""Build an install ZIP from one commit and verify its contents."""

import argparse
import hashlib
import os
import re
import stat
import subprocess
import tempfile
import zipfile
from pathlib import Path


INSTALL_FILES = (
    "AUDIT.txt", "CHANGELOG.txt", "CREDITS.txt", "DESCRIPTION.txt", "DamageTips.lua",
    "DamageTips.toc", "LICENSE.txt", "Media/icon.tga", "Media/logo.png", "README.txt",
    "SpellEstimates.lua", "SpellModifiers.lua", "SpellPowerModels.lua",
)
ADDON_PREFIX = "DamageTips/"
TAG_PATTERN = re.compile(
    r"v(?P<version>(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){2}"
    r"(?:-(?P<prerelease>[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?)"
)
TOC_VERSION = re.compile(r"^##[ \t]*Version[ \t]*:[ \t]*(.*)$", re.IGNORECASE | re.MULTILINE)


def git(*args):
    result = subprocess.run(
        ["git", *args], capture_output=True, check=False,
    )
    if result.returncode:
        raise ValueError(result.stderr.decode(errors="replace").strip() or "git command failed")
    return result.stdout


def check_version(tag, toc):
    match = TAG_PATTERN.fullmatch(tag)
    if not match:
        raise ValueError("tag must be a semantic version prefixed with v")
    prerelease = match["prerelease"]
    if prerelease and any(item.isdigit() and item.startswith("0") and len(item) > 1
                          for item in prerelease.split(".")):
        raise ValueError("numeric prerelease tag identifiers cannot start with zero")
    versions = [value.strip() for value in TOC_VERSION.findall(toc.decode("utf-8-sig"))]
    expected = match["version"]
    if versions != [expected]:
        actual = ", ".join(repr(value) for value in versions) if versions else "missing"
        raise ValueError(f"TOC version must be {expected} for tag {tag}; found {actual}")


def verify_zip(path, commit):
    expected_files = sorted(f"{ADDON_PREFIX}{name}" for name in INSTALL_FILES)
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        files = sorted(entry.filename for entry in entries if not entry.is_dir())
        directories = sorted(entry.filename for entry in entries if entry.is_dir())
        if files != expected_files or directories != [ADDON_PREFIX, f"{ADDON_PREFIX}Media/"]:
            raise ValueError(f"unexpected install ZIP layout: {files} and {directories}")
        corrupt_file = archive.testzip()
        if corrupt_file is not None:
            raise ValueError(f"install ZIP CRC failed for {corrupt_file}")
        for name in INSTALL_FILES:
            archive_path = f"{ADDON_PREFIX}{name}"
            info = archive.getinfo(archive_path)
            if stat.S_ISLNK(info.external_attr >> 16):
                raise ValueError(f"install ZIP entry is a symbolic link: {archive_path}")
            if archive.read(info) != git("cat-file", "blob", f"{commit}:{name}"):
                raise ValueError(f"install ZIP bytes differ from {commit}:{name}")


def build_verified_zip(tag, ref, output):
    commit = git("rev-parse", "--verify", "--end-of-options", f"{ref}^{{commit}}").decode().strip()
    check_version(tag, git("cat-file", "blob", f"{commit}:DamageTips.toc"))
    with tempfile.TemporaryDirectory(prefix=".verify-release-", dir=output.parent) as staging:
        candidate = Path(staging, "install.zip")
        git("-c", "core.autocrlf=false", "-c", "core.eol=lf", "archive",
            "--format=zip", f"--prefix={ADDON_PREFIX}", f"--output={candidate}", commit, "--", *INSTALL_FILES)
        verify_zip(candidate, commit)
        digest = hashlib.sha256(candidate.read_bytes()).hexdigest()
        # Publish the verified bytes atomically with exclusive destination creation.
        os.link(candidate, output)
    return commit, digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", required=True, help="expected TOC version with its v prefix")
    parser.add_argument("--ref", default="HEAD", help="Git commit or ref to archive (default HEAD)")
    parser.add_argument("--output", required=True, type=Path, help="new ZIP path in an existing directory")
    args = parser.parse_args()
    try:
        commit, digest = build_verified_zip(args.tag, args.ref, args.output.absolute())
    except (OSError, ValueError, zipfile.BadZipFile) as error:
        parser.exit(2, f"Release ZIP verification failed: {error}\n")
    print(f"Verified {args.output} with {len(INSTALL_FILES)} install files from {commit}")
    print(f"SHA-256 {digest}")


if __name__ == "__main__":
    main()
