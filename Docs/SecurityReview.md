# ResizeLint 1.0 defensive security review

Review date: 2026-07-13

This review covers local source discovery, configuration and baseline parsing,
report generation, safe fixes, cancellation, deterministic execution, and
resource use. It uses static inspection and automated regression tests. It does
not depend on analyzed projects being trusted.

## Review environment

- macOS 26.5.2 on Apple M4
- Swift 6.3.2
- Xcode 26.5
- Release binary built with `swift build -c release`

The release target remains Swift 6.3.3. A final compatibility run with that
exact toolchain is required before publication.

## Defensive controls verified

- Explicit scan paths outside the normalized project root are rejected.
- Directory and file symbolic links are not traversed during discovery.
- Baseline, report, and fix writes cannot escape through parent symlinks.
- Configuration files are capped at 1 MiB before their contents are read.
- Source and project files are capped at 10 MiB before their contents are read.
- Baselines are capped at 10 MiB before their contents are read.
- Unreadable files become operational notices; invalid UTF-8 fails safely.
- Malformed YAML, plist, Swift, suppression directives, and baseline JSON do
  not crash analysis or silently disable unknown rules.
- Cancellation is checked during discovery, between analysis batches, and
  before a project scan returns.
- Safe fixes reject overlapping edits, syntax regressions, symbolic links, and
  non-regular destinations.
- Atomic-write failures retain the original destination and remove temporary
  files. Permissions and CRLF line endings are preserved.
- Human and Xcode reports neutralize terminal control characters.
- JSON uses structured encoding; SARIF paths use percent-encoded relative URIs.
- Absolute diagnostic and invocation paths are removed from machine reports.
- Static inspection found no process execution or network API in the analysis
  path. Analyzed repositories are read as data and their scripts are not run.

## Confirmed issues remediated

The review found and fixed the following defects:

1. Atomic replacement accepted a non-regular destination and could replace a
   directory with a file.
2. Explicit input paths outside the project root were silently ignored instead
   of rejected.
3. Baseline and report destinations could escape the root through relative or
   symbolic-link paths.
4. File-size limits were enforced after opening content instead of from file
   metadata.
5. Terminal reporters and baseline-check output allowed control-character
   injection.
6. JSON invocation data could expose an absolute local path.
7. SARIF artifact locations were JSON-safe but not valid percent-encoded URIs.
8. Unknown rule IDs in configuration and suppression directives were accepted.
9. Malformed and oversized baseline documents were not mapped to bounded,
   domain-specific errors.

No known high- or critical-severity security or data-loss issue remains in the
reviewed scope.

## Dependency audit

The resolved graph contains only these direct, exact pins and no transitive
packages:

- SwiftSyntax 603.0.2 (`79e4b74a295b6eb74a8b585e3a39d29e70c1dbd1`)
- Swift Argument Parser 1.8.2 (`6a52f3251125d74daf04fcbd5e6f08a75d074382`)
- Yams 6.2.2 (`a27b21e0c81c5bf42049b897a62aaf387e80f279`)

All 71 Swift ecosystem entries returned by the GitHub Advisory Database on the
review date were checked. None named any of these three packages. The installed
SwiftPM does not provide a native `swift package audit` command, so the database
query and exact resolved graph are the audit evidence for this gate.

## Performance and determinism

Machine-readable JSON and SARIF output is byte-for-byte deterministic for the
same source tree and invocation. Wall-clock duration is shown only in the human
report and recorded separately by benchmark tooling, so runtime variance cannot
change a machine report.

A generated fixture contained exactly 250,000 Swift lines across 250 files
(8,638,890 bytes). Three release-mode runs with eight jobs produced:

| Run | Real time | User CPU | System CPU | Peak RSS |
| --- | ---: | ---: | ---: | ---: |
| 1 | 3.70 s | 12.41 s | 0.45 s | 43,745,280 bytes |
| 2 | 3.01 s | 12.61 s | 0.40 s | 43,892,736 bytes |
| 3 | 2.94 s | 12.40 s | 0.41 s | 43,876,352 bytes |

All three SARIF reports had SHA-256
`ddb1dde18b301c310fee9c74b89bf230cd050f7e764e1d5805af6ac04391a274`.
This is below the 10-second and 1-GB release thresholds on the review machine.

The fixture and threshold check are reproducible with:

```bash
swift build -c release
Scripts/benchmark/run.sh .build/release/resizelint 250000 10
```

## Residual limitations

- Cancellation cannot interrupt a synchronous SwiftParser call already in
  progress; it prevents later batches and suppresses a cancelled result.
- Exact Swift 6.3.3, Xcode 27, Linux, signing, and installer verification are
  tracked separately as release-readiness checks.
- Advisory databases change over time and must be queried again for a release.
