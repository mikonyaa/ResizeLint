# GitHub Action integration

The composite Action supports macOS arm64, macOS x86_64, and Linux x86_64. It becomes usable after the 1.0 release and moving `v1` tag exist.

## Basic workflow

```yaml
name: ResizeLint

on:
  pull_request:

permissions:
  contents: read

jobs:
  lint:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0
        with:
          persist-credentials: false

      - id: resizelint
        uses: mikonyaa/ResizeLint@v1
        with:
          path: .
          config: .resizelint.yml
          fail-on: error
```

## Inputs

- `path` — one file or directory relative to the workspace; default `.`.
- `config` — optional configuration path; default is discovery.
- `fail-on` — `error`, `warning`, or `info`; default `error`.
- `version` — exact release version downloaded by the Action; default `1.0.0`.

## Output

`sarif` is the absolute path to `.resizelint-results.sarif` in the workspace.

The Action detects the runner platform, downloads the matching release archive and `SHA256SUMS` over HTTPS, verifies the selected archive, extracts a fixed root-level executable, and runs ResizeLint. It does not execute project scripts and does not require repository write access.

## Optional SARIF upload

Uploading to code scanning is a separate policy choice. It requires `security-events: write`; the ResizeLint step itself still needs only read access.

```yaml
permissions:
  contents: read
  security-events: write

steps:
  - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0
    with:
      persist-credentials: false

  - id: resizelint
    continue-on-error: true
    uses: mikonyaa/ResizeLint@v1

  - name: Upload ResizeLint SARIF
    if: always() && steps.resizelint.outputs.sarif != ''
    uses: github/codeql-action/upload-sarif@1ad29ea4a422cce9a242a9fae469541dcd08addc
    with:
      sarif_file: ${{ steps.resizelint.outputs.sarif }}

  - name: Preserve lint failure
    if: steps.resizelint.outcome == 'failure'
    run: exit 1
```

Pin the ResizeLint `version` input when a workflow must remain on one exact binary while the moving major tag receives compatible updates.
