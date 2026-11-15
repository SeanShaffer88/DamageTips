# Publish a verified DamageTips ZIP

1. In GitHub Actions, open the successful **Verify DamageTips** run for the
   version tag you intend to release. Under **Artifacts**, download the
   `DamageTips-tag-v<version>-attempt-<number>` artifact from that attempt.
   Artifacts named `DamageTips-preview-…` come from manual test runs.
2. Extract the Actions download. In the extracted directory, run
   `sha256sum --check DamageTips-<version>.zip.sha256` to verify the install ZIP.
   In PowerShell, compare the SHA-256 from
   `Get-FileHash DamageTips-<version>.zip` with the first field in its
   `.zip.sha256` file.
3. Attach the verified `DamageTips-<version>.zip` to the GitHub release for
   that tag. Add the release notes and publish when ready.
4. Download the ZIP from the public release and verify it against the same
   checksum.
