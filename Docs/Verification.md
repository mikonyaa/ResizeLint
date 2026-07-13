# Release candidate verification

Local verification completed on 2026-07-13 without publishing a repository,
tag, package, or release. It covered the Swift package, command-line contracts,
distribution scripts, an exact Linux toolchain, and simulator-only ResizeLab
behavior.

## Automated tests and coverage

- macOS: 90 of 90 Swift package tests passed.
- Ubuntu Jammy x86_64 with Swift 6.3.3: 90 of 90 tests passed under an
  unprivileged user.
- Address Sanitizer: 90 of 90 tests passed with no reported memory errors.
- Product-source coverage across 16 files: 1,884 of 2,069 lines (91.06%), 254
  of 308 functions (82.47%), and 794 of 991 regions (80.12%). Dependencies,
  tests, and generated package runners are excluded from these percentages.
- SwiftLint 0.65.0 strict mode: zero violations.

The suites include malformed YAML, plist, Swift, suppressions, and baseline
data; oversized and unreadable inputs; path and symlink containment; permission
failures; cancellation; atomic-write rollback; terminal escaping; JSON and
SARIF contracts; deterministic output; CLI snapshots; rule precision; and safe
fix behavior. The detailed defensive assessment is in the
[security review](SecurityReview.md).

## Compatibility and artifacts

- Native macOS release builds completed independently for arm64 and x86_64.
- The local universal executable reports both architectures and version 1.0.0.
- The ZIP executable and package payload matched the universal executable
  byte-for-byte; SHA-256 verification succeeded.
- The Linux release archive contained an x86_64 ELF executable that reported
  version 1.0.0 inside the Swift 6.3.3 Jammy container.
- Source-archive and checksum self-tests passed.
- The composite Action consumer fixture passed, and both workflows passed
  actionlint 1.7.12.

The local machine did not contain Developer ID Application or Developer ID
Installer identities for Team `9K594G5QQ8`. The unsigned artifacts are
engineering evidence only: signature, notarization, stapling, Gatekeeper
acceptance, and distribution remain blocked until the owner installs the
certificates and explicitly starts the protected release process.

## Precision, performance, and interface evidence

The [external corpus](ExternalCorpus.md) covered 975 Swift files from 11 public
repositories at exact revisions. All 33 error and warning findings were true
positives, for 100% measured precision at both severities, and two full machine
report passes were byte-identical.

The 250,000-line benchmark completed in at most 3.77 seconds on the final
release build. Its three SARIF outputs had the same SHA-256 digest,
`ddb1dde18b301c310fee9c74b89bf230cd050f7e764e1d5805af6ac04391a274`.
Peak memory in the measured runs stayed below 44 MB. Full timing and resource
evidence is recorded in the [security review](SecurityReview.md).

ResizeLab passed seven tests on an iPhone 17 Pro Simulator and a separate
primary flow on an iPad Pro Simulator. No physical device was used. Compact,
square, wide, portrait, landscape, accessibility text, appearance, Reduce
Motion, and Reduce Transparency evidence is documented in the
[simulator QA report](ResizeLabQA.md).

## Remaining release limitations

- Xcode 27 and Device Hub were unavailable; exact-size render tests and iOS
  26.5 simulator orientations were used instead.
- Signed and notarized installation cannot be verified without the two
  Developer ID identities.
- Advisory databases can change and must be queried again immediately before
  a release.
- Public Action, Homebrew tap, and clean-clone-from-hosting checks require an
  approved published repository and exact release tag.
