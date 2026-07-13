# Command-line reference

Running `resizelint` with no subcommand is equivalent to `resizelint lint .`.

## Commands

```text
resizelint lint [paths...]
resizelint fix [paths...]
resizelint baseline create [paths...]
resizelint baseline update [paths...]
resizelint baseline check [paths...]
resizelint rules
resizelint init
resizelint version
```

Common options:

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

`fix` also accepts `--dry-run`. `baseline create` and `init` accept `--force`.

## Exit codes

- `0` — analysis completed without a new finding at the configured threshold.
- `1` — one or more policy findings reached the threshold.
- `2` — invalid arguments, configuration, baseline, or input path.
- `3` — cancellation, operational failure, or internal failure.

`--strict` sets the failure threshold to warning. Color is disabled for `NO_COLOR` and can be disabled explicitly with `--no-color`.

Machine reports remove absolute home paths by default. Output files, explicit configuration, and baseline destinations must remain inside the discovered project root.
