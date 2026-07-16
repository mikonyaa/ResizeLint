# Release preparation

ResizeLint release work requires separate repository-owner approvals for
publication and distribution. The release workflow is intentionally manual,
requires an existing exact semantic-version tag, and targets a protected GitHub
Environment named `release`. It cannot run from an untagged branch.

## Protected environment

Configure the `release` environment only after the repository is published.
Require a reviewer and limit deployment branches and tags to approved release
tags. The repository
owner adds these secrets directly in GitHub; they must never be shared in an
issue, chat, commit, or workflow log:

- `RESIZELINT_APPLICATION_CERTIFICATE_P12`
- `RESIZELINT_APPLICATION_CERTIFICATE_PASSWORD`
- `RESIZELINT_INSTALLER_CERTIFICATE_P12`
- `RESIZELINT_INSTALLER_CERTIFICATE_PASSWORD`
- `RESIZELINT_NOTARY_KEY_P8`
- `RESIZELINT_NOTARY_KEY_ID`
- `RESIZELINT_NOTARY_ISSUER_ID`
- `RESIZELINT_TEAM_ID`

The certificate and private-key values are base64-encoded files. The Team ID is
validated against the Developer ID distribution team `4NGTWD262W`. Credentials
are imported into an ephemeral keychain and removed even when the workflow
fails.

## Release behavior

The protected job builds independent arm64 and x86_64 macOS binaries, combines
them, signs the universal executable and installer, notarizes both distributable
artifacts, staples the package ticket, and runs signature and Gatekeeper checks.
An Ubuntu job builds the Linux x86_64 archive in Swift 6.3.3. The protected job
also builds the deterministic source archive, verifies `SHA256SUMS`, and creates
a draft release. Publishing the draft and creating the moving `v1` tag remain
separate owner-approved actions.

For version 1.0.0, the protected workflow completed successfully on 2026-07-16.
The owner subsequently published the release, and the moving `v1` tag points to
the same release commit as exact tag `1.0.0`.

For a local first release, use the scripts under `Scripts/release` with
identities already installed in the login Keychain. Store notarization
credentials through `notarytool store-credentials`; never put a password or key
on a command line or in the repository.

## Local readiness

Run the non-mutating readiness check before a release:

```bash
Scripts/release/verify-signing-readiness.sh
```

It requires both Developer ID certificate types for Team `4NGTWD262W` and an
available `notarytool`. Missing identities block signing and notarization, but
do not invalidate unsigned local engineering verification.
