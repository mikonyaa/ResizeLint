# Architecture

ResizeLint is a Swift Package with one executable product and two first-party targets.

## Targets

`ResizeLintCLI` owns argument parsing, working-directory and repository-root behavior, reporter selection, terminal I/O, and exit-code mapping.

`ResizeLintCore` owns configuration, source discovery, Swift parsing, narrow project facts, diagnostics, baselines, fixes, and report models. It does not import AppKit or UIKit and is not published as a library product.

## Analysis pipeline

1. Discover the project root and merge configuration layers.
2. Normalize explicit paths and reject paths outside the root.
3. Enumerate supported files without following directory symbolic links.
4. Apply include and exclude globs.
5. Read bounded UTF-8 inputs and collect operational notices.
6. Parse Swift through SwiftSyntax and inspect property-list and project facts.
7. Run rules in bounded batches and sort diagnostics by path, line, column, and rule ID.
8. Apply suppressions and baseline state.
9. Render human, Xcode, JSON, or SARIF output.

The analyzer has no network client, subprocess runner, plugin loader, server, telemetry, or persistent cache. Source content remains in memory except when the user explicitly writes a report, baseline, or safe fix.

## Rule precision

Rules combine lexical masking, Swift syntax, enclosing declaration context, and conservative project facts. A specific rule suppresses a generic match on the same syntax range. Ambiguous project mapping becomes a verbose notice rather than an RL008 error.

## Fix safety

The fix engine accepts only nonoverlapping edits with proven context. It applies edits from the end of a file, reparses the complete result, preserves permissions and line endings, writes through atomic replacement, and reruns analysis. A failed file never receives a partial edit.

## Public contracts

The CLI, configuration, RL001–RL009 semantics, report schema, SARIF behavior, baseline schema, and Action inputs/outputs are compatibility surfaces for 1.x. Internal Swift types are free to evolve without source compatibility.
