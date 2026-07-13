# Configuration reference

ResizeLint reads YAML configuration schema version 1. Unknown keys, unknown rule IDs, unsupported versions, invalid severities, and nonpositive job counts are errors.

## Discovery and precedence

For project commands, ResizeLint walks from the current directory to the nearest ancestor containing `.git`. That directory is the scan root. If no marker exists, the current directory is the root.

Configuration is applied in this order, with later values winning:

1. built-in defaults;
2. `.resizelint.yml` at the repository root;
3. the nearest `.resizelint.yml` between the current directory and the root;
4. CLI flags.

Omitted fields in a nearer file preserve values from the repository file. Rule dictionaries merge by rule ID, and override arrays append in order.

`--config <path>` selects one explicit configuration file instead of the discovered repository and nearest files. The path is resolved from the current directory and must remain inside the scan root.

## Complete example

```yaml
version: 1

include:
  - "**/*.swift"
  - "**/Info.plist"
  - "**/*.xcodeproj/project.pbxproj"

exclude:
  - ".git/**"
  - ".build/**"
  - "DerivedData/**"
  - "Pods/**"
  - "Carthage/**"
  - "**/Generated/**"

baseline: ".resizelint-baseline.json"
fail_on: error
jobs: 4

rules:
  RL002:
    severity: warning
  RL009:
    enabled: true

overrides:
  - files:
      - "Sources/Game/**"
    rules:
      RL009:
        enabled: false
```

Paths and globs use repository-relative forward slashes. `**` crosses directory boundaries, `*` matches within one path component, and `?` matches one non-separator character.

## Built-in defaults

- Include Swift source, `Info.plist`, and `project.pbxproj` files.
- Exclude Git metadata, SwiftPM build products, DerivedData, Pods, Carthage, and generated-source directories.
- Use `.resizelint-baseline.json` at the repository root.
- Fail on errors.
- Use half the active logical processors, with a minimum of one and a maximum of eight jobs.

`--jobs` overrides configured concurrency. `--strict` is equivalent to `--fail-on warning`.

## Suppressions

Suppress one reviewed line with a rule ID and reason:

```swift
// resizelint:disable-next-line RL007 -- Camera coordinates require device orientation.
```

Suppress a complete file only before its first declaration:

```swift
// resizelint:disable-file RL009 -- Full-screen behavior is required by the game design.
```

There is no wildcard or region-wide suppression in 1.0. Malformed directives remain visible as operational notices and do not hide findings.

Configuration files are limited to 1 MiB and must be UTF-8.
