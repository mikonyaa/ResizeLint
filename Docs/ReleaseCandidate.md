# 1.0.1-rc.1 release candidate

This candidate repairs six consumer defects from 1.0.0. It is prepared locally; this source document does not claim that a tag, release, tap update or hosted workflow has been published. The evidence bundle accompanying the candidate records the exact commit, toolchains, commands, exit statuses, native tests and artifact hashes.

## Compatibility

RL001–RL009, configuration version 1, suppressions, include/exclude/overrides, dry-run, atomic writes, deterministic reports and the executable-only package remain supported. JSON schema 1 keeps UTF-8 byte positions. SARIF positions now follow its [2.1.0 UTF-16 contract](https://docs.oasis-open.org/sarif/sarif/v2.1.0/os/sarif-v2.1.0-os.html). The unmodified official schema is vendored in `Schemas/sarif-2.1.0.schema.json` from the OASIS 2.1.0 cos02 schema distribution and validated with Draft 7. Usage errors consistently return 2; incomplete scans return 3. [Baseline v2](Baselines.md) adds declaration identity and occurrence counts with explicit conservative v1 migration.

## Required checks

Use Swift 6.3.3 with the unchanged lockfile. Run resolve, debug/release builds, Swift tests, SwiftLint 0.65.0, the production executable consumer, machine schemas, documentation links, publication hygiene and helper self-tests. `Scripts/ci/test-release-candidate.py` needs the pinned [verification dependency](../Scripts/ci/requirements.txt); install it in a local Python virtual environment. Its `--native-uikit` gate selects the Xcode compiler and iPhoneSimulator SDK independently. `--swiftc <compiler> --sdk <macOS-SDK>` enables the separate stub type-checks.

```bash
swift package resolve
swift build
swift test
swift build -c release
python3 Scripts/ci/test-release-candidate.py .build/release/resizelint
Scripts/ci/validate-machine-contracts.py
Scripts/ci/public-artifact-scan.sh
Scripts/ci/test-public-artifact-scan.sh
Scripts/ci/check-doc-links.sh
```

On this preparation host, Swift 6.3.3 cannot evaluate even a minimal independent package against the Xcode 27 SDK. The scoped `SDKROOT` for Command Line Tools macOS 26.5 permits the declared compiler's builds. Do not change global developer selection or weaken platform protections. Native UIKit fixtures and ResizeLab use Xcode 27 independently.

## Distribution verification

The Linux builder uses the matching checksum-pinned [Swift Static Linux SDK](https://www.swift.org/documentation/articles/static-linux-getting-started.html), targets `x86_64-swift-linux-musl`, and packages a real ELF without `PT_INTERP` or `DT_NEEDED`. It builds a read-only snapshot of the Git index: commit or stage the intended candidate before building.

```bash
Scripts/release/build-linux.sh Artifacts 1.0.1-rc.1
Scripts/ci/test-linux-release-consumer.sh \
  Artifacts/ResizeLint-1.0.1-rc.1-linux-x86_64.tar.gz 1.0.1-rc.1
Scripts/release/build-source-archive.sh Artifacts 1.0.1-rc.1
Scripts/release/checksums.sh Artifacts
```

The consumer test runs the actual archive and Action in Ubuntu 22.04 and 24.04 containers without Swift or `LD_LIBRARY_PATH`; only unpublished download transport is mocked. Positive/negative JSON and Action SARIF undergo full schema checks. It also rejects a corrupted archive and prevents stale Action reports after usage errors. Packaging/identity/link helper self-tests with mocks are labelled as such and do not replace artifact consumers.

Source archives have fixed timestamps and match the indexed tree except the established `.github`, `.build`, `Artifacts` and `Formula` exclusions. Checksums bind the exact prepared artifacts. Signed macOS packaging, notarization/Gatekeeper, actual installer installation, public-tap installation, VoiceOver/keyboard use, physical devices and another machine each need their own recorded status; a source test pass is not their evidence.

## Publication hygiene

`public-artifact-scan.sh` prohibits private agent state, signing/provisioning files, private-key markers, credential-shaped content and local identity/path leakage. Documentation may mention AI tools, prompts, generated content and `AGENTS.md`. Synthetic credentials and private signing paths must fail the self-test; harmless tooling documentation must pass. A passing scan does not determine authorship or establish that arbitrary prose is secret-free.

## ResizeLab

ResizeLab and its technical illustrations remain a demonstration. Its comparison/PASS cards are hand-authored scenario explanations, not live analyzer results. Simulator build/UI/orientation checks, manual accessibility interaction and physical-device validation are separate gates.
