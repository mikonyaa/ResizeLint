# Changelog

All notable changes to ResizeLint are documented here. The project follows semantic versioning for its public CLI, configuration, diagnostics, machine reports, baseline format, and Action interface.

## Unreleased

### Added

- Nine resizing-focused diagnostics for UIKit, SwiftUI-hosted UIKit, project settings, and lifecycle facts.
- Human, Xcode, JSON, and SARIF 2.1.0 reports.
- Deterministic baselines and rule-specific suppressions.
- A conservative, atomic RL002 fix with dry-run support.
- macOS and Linux release preparation, a composite Action, and a source-build Homebrew formula.
- ResizeLab, a simulator-only legacy/adaptive example.

### Security

- Bounded input reads, root-confined path handling, symbolic-link rejection for writes, terminal escaping, cancellation checks, and interrupted-write recovery.
