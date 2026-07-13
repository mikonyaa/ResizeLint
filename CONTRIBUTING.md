# Contributing to ResizeLint

ResizeLint favors precise, deterministic findings over rule count. A change is ready for review when it is small enough to explain, covered by tests, and backed by an adaptive counterexample.

## Development requirements

- Swift 6.3.3
- macOS 14 or Ubuntu 22.04 or newer
- SwiftLint 0.65.0 for first-party Swift style checks
- XcodeGen for the optional ResizeLab project

## Local verification

```bash
swift package resolve
swift build
swift test
swift build -c release
swiftlint --strict
Scripts/ci/test-action-consumer.sh .build/release/resizelint
Scripts/ci/check-doc-links.sh
Scripts/ci/public-artifact-scan.sh
git diff --check
```

## Rule changes

1. Add a failing positive or false-positive regression case.
2. Confirm the test fails for the expected reason.
3. Implement the smallest syntax or project-fact change that passes.
4. Cover adaptive, comment/string, multiline, conditional-compilation, and suppression behavior where applicable.
5. Run the rule against a representative external corpus and classify every new finding.
6. Update the rule page without broadening its claim beyond the tested behavior.

Do not commit third-party source used for corpus validation. Record repository URLs and exact commit identifiers only.

## Pull requests

Keep diagnostic IDs stable. Describe any change to severity, fingerprinting, JSON, SARIF, baseline behavior, CLI flags, configuration fields, or Action inputs. Include exact verification commands and results.
