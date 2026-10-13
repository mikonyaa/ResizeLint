# Command-line reference

Running `resizelint` without a subcommand is equivalent to `resizelint lint .`.

```text
resizelint lint [paths...]
resizelint fix [paths...]
resizelint baseline create [paths...]
resizelint baseline update [paths...]
resizelint baseline check [paths...]
resizelint baseline migrate [paths...]
resizelint rules
resizelint init
resizelint version
```

Common analysis options:

```text
--config <path>
--baseline <path>
--format human|xcode|json|sarif
--output <path>
--fail-on error|warning|info
--strict
--jobs <positive-count>
--no-color
--quiet
--verbose
```

`fix` accepts `--dry-run`. `baseline create` and `init` accept `--force`. Run a command with `--help` for its exact supported options. Production and the test helper use the same ArgumentParser command tree and validation.

## Exit codes

- `0`: completed with no new finding at the configured threshold, or a successful help/version/write operation.
- `1`: findings reached the threshold, or baseline check found drift/new debt.
- `2`: invalid arguments, configuration, baseline or input path.
- `3`: cancellation, unreadable input, operational or internal failure.

Invalid `--fail-on`, unknown options, unsupported formats and zero/negative `--jobs` return 2. Help returns 0. ArgumentParser's usage status is normalized to the documented 2. User-controlled terminal error text escapes control characters, including ESC and embedded newlines.

`--strict` sets the threshold to warning. Color respects `NO_COLOR` and `--no-color`. Explicit missing config/baseline files are errors; the absent default baseline does not prevent initial adoption.

## Machine reports and incomplete scans

JSON keeps schema version 1 and one-based UTF-8 byte columns. SARIF 2.1.0 declares `columnKind: utf16CodeUnits` and uses one-based UTF-16 columns, including exclusive end columns. JSON fingerprints are opaque values; v2 identity is described in [Baselines](Baselines.md). SARIF uses the versioned `resizelint/v2` partial fingerprint key.

Valid finding runs return 1 with a parseable report. An unreadable file may produce a partial parseable report, a notice on stderr and exit 3: consumers must check the exit status. Baseline and fix operations refuse incomplete input. Usage errors produce no machine stdout. `--quiet` suppresses stdout; use `--output` when a report is required in quiet mode.

Reports remove absolute home paths by default. Output files, explicit config and baseline destinations must remain inside the discovered project root. The analysis does not execute the scanned Swift source.
