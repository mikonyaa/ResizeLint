# Changelog

All notable changes to ResizeLint are documented here. The project follows semantic versioning for its public CLI, configuration, diagnostics, machine reports, baseline format, and Action interface.

## 1.0.1-rc.1 — local candidate, 2026-10-13

### Fixed

- Package a standalone static Linux x86_64 executable using Swift 6.3.3's matching musl SDK; verify the exact archive and Action in Swift-free Ubuntu 22.04 and 24.04.
- Restrict RL002 autofix through SwiftSyntax declaration ancestry; static/class members, closures and unknown contexts cannot receive instance-member edits.
- Prevent baseline false green results with declaration-aware v2 fingerprints and occurrence budgets. Writers aggregate duplicate identities deterministically; explicit v1 migration refuses ambiguous or stale debt.
- Share production/test ArgumentParser validation, reject invalid thresholds/jobs, normalize usage exits to 2 and escape terminal controls. Incomplete reads return 3 and block writes.
- Preserve JSON UTF-8 columns while emitting SARIF UTF-16 columns and explicit `columnKind`; validate full SARIF schema and Unicode ranges.
- Allow harmless tooling documentation and AGENTS.md while retaining private signing-file and credential checks.

### Compatibility

- RL001–RL009, configuration and JSON report schema 1 remain supported. Baseline writers now emit schema/fingerprint version 2; see [migration](Docs/Baselines.md). Opaque report fingerprints also change to v2.
- This candidate has not been published. Hosted CI, tap installation and notarization are separate acceptance steps recorded with the artifact evidence.

## 1.0.0 — historical release

### Added

- Nine resizing-focused diagnostics for UIKit, SwiftUI-hosted UIKit, project settings, and lifecycle facts.
- Human, Xcode, JSON, and SARIF 2.1.0 reports.
- Deterministic baselines and rule-specific suppressions.
- A conservative, atomic RL002 fix with dry-run support.
- macOS and Linux release preparation, a composite Action, and a source-build Homebrew formula.
- ResizeLab, a simulator-only legacy/adaptive example.

### Changed

- Refined the public brand system, README explanation, terminal demonstration,
  and social preview for a clearer 1.0 presentation.

### Security

- Bounded input reads, root-confined path handling, symbolic-link rejection for writes, terminal escaping, cancellation checks, and interrupted-write recovery.
