# Baselines

A baseline records accepted occurrences without accepting later debt. Reports retain accepted findings with `baselineState: unchanged`; these do not reach the lint failure threshold.

## Create, check and update

```bash
resizelint baseline create .
resizelint baseline check .
resizelint baseline update .
```

Creation refuses an existing destination unless `--force` is supplied. `check` returns 1 for new or removed occurrences, stale fingerprints, duplicate identities or unsafe paths. Invalid documents return 2. `update` intentionally accepts the entire current unsuppressed finding set, including new debt: review the diff before committing it. An incomplete scan returns 3 and cannot write or validate a baseline.

## Version 2

```json
{
  "schemaVersion": 2,
  "fingerprintVersion": 2,
  "toolVersion": "1.0.1-rc.1",
  "findings": [
    {
      "ruleID": "RL001",
      "path": "Sources/Canvas.swift",
      "fingerprint": "sha256:example",
      "occurrences": 1
    }
  ]
}
```

The [v2 schema](../Schemas/resizelint-baseline-v2.schema.json) requires a positive occurrence count. The writer aggregates identical identities into one sorted entry, so its own output passes duplicate validation.

Fingerprints include the rule, repository-relative path, node kind, normalized expression and enclosing declaration names/signatures/binding patterns. Moving unrelated lines preserves identity. Adding the same expression to another method creates a new identity. Renaming a declaration or changing its signature intentionally creates new debt and leaves the old identity stale.

Truly identical occurrences in the same declaration share an identity and a count budget. Matching consumes that budget in source order: adding a second occurrence to a baseline of one leaves one new finding, and deleting an occurrence makes `check` stale. It cannot distinguish which of two identical occurrences was removed and replaced while the count stays equal; review such edits in the source diff. Raw line numbers are not identity.

## Migrate version 1

Keep a copy of the old baseline, then run:

```bash
resizelint baseline migrate .
resizelint baseline check .
resizelint lint .
```

Use `--baseline <relative-path>` for a nondefault file. The v1 [schema](../Schemas/resizelint-baseline-v1.schema.json) remains readable. Lint emits a migration warning. A unique legacy match can remain unchanged; ambiguous repeated legacy fingerprints leave all matching diagnostics new. This deliberately avoids v1's false green result.

`migrate` maps only the entries already accepted in v1. It never captures additional current findings. An ambiguous, stale, duplicate or unsafe legacy entry causes exit 2 and leaves the file untouched. Resolve these entries manually against reviewed source, or use `baseline update` only when intentionally accepting the full current set. An already valid v2 document is retained deterministically.

Files remain limited to 10 MiB. Absolute paths, parent traversal, controls in paths, invalid counts, duplicate identities and symbolic-link write destinations are rejected. Baseline v2 is the necessary 1.x format change; JSON reports retain schema version 1, but their opaque diagnostic fingerprint values now use v2 identity.
