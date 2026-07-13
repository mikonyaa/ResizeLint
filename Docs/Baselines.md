# Baselines

A baseline records accepted findings without hiding new regressions. It is deterministic, repository-relative, and safe to review in version control.

## Create

```bash
resizelint baseline create .
```

Creation refuses to overwrite an existing file. Use `--force` only after reviewing the replacement.

## Update and check

```bash
resizelint baseline check .
resizelint baseline update .
```

`check` reports duplicate entries, stale fingerprints, and unsafe paths. `update` removes stale entries and adds the current finding set.

## Format

```json
{
  "schemaVersion": 1,
  "toolVersion": "1.0.0",
  "findings": [
    {
      "ruleID": "RL006",
      "path": "Sources/ProfileViewController.swift",
      "fingerprint": "sha256:example"
    }
  ]
}
```

The formal contract is [resizelint-baseline-v1.schema.json](../Schemas/resizelint-baseline-v1.schema.json).

Fingerprints combine the rule ID, normalized path, syntax-node kind, and normalized surrounding tokens. They do not rely only on line numbers, so unrelated lines can move without reviving accepted findings.

An unchanged baseline finding remains present in JSON and SARIF but does not reach the failure threshold. A new fingerprint at the same path still fails normally.

Baseline files are limited to 10 MiB. Absolute paths, parent traversal, duplicate entries, symbolic-link destinations, and unsupported schemas are rejected or reported.
