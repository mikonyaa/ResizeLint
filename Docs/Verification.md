# Version 1.0 verification

Local engineering verification completed on 2026-07-13. The protected release
workflow then completed successfully for exact tag `1.0.0` on 2026-07-16, and
the release was published with signed macOS, Linux, source, and checksum
assets. This document combines the pre-release engineering evidence with the
published-artifact verification.

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
- The published ZIP contains a universal arm64 and x86_64 executable that
  passes strict code-signature verification and Apple's notarization
  requirement.
- All four published archives match the release `SHA256SUMS` file.
- The published installer is signed by `Developer ID Installer` for Team
  `4NGTWD262W`, carries a trusted timestamp, has a valid stapled notarization
  ticket, and is accepted by Gatekeeper as `Notarized Developer ID`.
- The Linux release archive contained an x86_64 ELF executable that reported
  version 1.0.0 inside the Swift 6.3.3 Jammy container.
- Source-archive and checksum self-tests passed.
- The formula in the public
  [`mikonyaa/homebrew-tap`](https://github.com/mikonyaa/homebrew-tap)
  repository passed `brew audit --strict`, built and installed version 1.0.0
  from the published source archive, returned `1.0.0` from the installed
  executable, and passed its `brew test` block. The tap's
  [`brew test-bot` workflow](https://github.com/mikonyaa/homebrew-tap/actions/runs/29587928810)
  passed on macOS Intel, macOS 26, and Ubuntu. The temporary local installation
  and tap were removed after verification.
- The composite Action consumer fixture passed, and both workflows passed
  actionlint 1.7.12.

The protected [release workflow](https://github.com/mikonyaa/ResizeLint/actions/runs/29513460101)
completed successfully at commit `cde1a7b5165cd6dc225166e6e0a7614a32ebce28`.
Published assets were independently downloaded and rechecked on 2026-07-17
with `shasum`, `pkgutil`, `stapler`, `spctl`, `codesign`, and `file`.

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

## Remaining limitations

- Xcode 27 and Device Hub were unavailable; exact-size render tests and iOS
  26.5 simulator orientations were used instead.
- Advisory databases can change and must be queried again immediately before
  a future release.
- Physical-device iPhone Mirroring was not used or claimed; ResizeLab evidence
  is simulator-only.
