# GitHub Action integration

The candidate runner supports macOS arm64, macOS x86_64 and Linux x86_64. Its default binary version is `1.0.1-rc.1`. Those assets are prepared locally and have not been published by this work. The existing public `v1` tag still uses the older runner/release; do not interpret this checkout's tests as an update to that tag. In particular, the published 1.0.0 Linux binary requires Swift runtime libraries.

## Workflow after publication

Pin a reviewed exact Action commit/tag and the exact published binary version. This example becomes usable only after the candidate tag and assets are published:

```yaml
name: ResizeLint
on:
  pull_request:
permissions:
  contents: read
jobs:
  lint:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0
        with:
          persist-credentials: false
      - id: resizelint
        uses: mikonyaa/ResizeLint@1.0.1-rc.1
        with:
          path: .
          fail-on: error
          version: 1.0.1-rc.1
```

## Inputs and output

- `path`: one file or directory relative to the workspace; default `.`.
- `config`: optional config path; default discovery. An explicit missing file fails with 2.
- `fail-on`: `error`, `warning` or `info`; default `error`; invalid values fail with 2.
- `version`: exact release version; candidate default `1.0.1-rc.1`.
- `sarif` output: the absolute path to `.resizelint-results.sarif` after a completed analysis (status 0 or finding status 1).

The runner downloads the platform archive and `SHA256SUMS` over HTTPS, checks the archive, extracts the fixed root-level executable and runs the analyzer. The candidate Linux ELF statically links Swift, Foundation and musl, so a consumer does not need Swift or developer `LD_LIBRARY_PATH`. The analysis does not execute project scripts and needs only repository read access.

An existing report is removed before execution. Usage errors return 2; download/checksum/runtime or incomplete-scan failures return 3 and expose no report output. The runner only exposes completed SARIF for exit 0/1. This prevents later steps uploading a stale report after failure.

## Optional SARIF upload

Code scanning is a separate policy choice and requires `security-events: write`:

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
    uses: mikonyaa/ResizeLint@1.0.1-rc.1
    with:
      version: 1.0.1-rc.1
  - name: Upload ResizeLint SARIF
    if: always() && steps.resizelint.outputs.sarif != ''
    uses: github/codeql-action/upload-sarif@1ad29ea4a422cce9a242a9fae469541dcd08addc
    with:
      sarif_file: ${{ steps.resizelint.outputs.sarif }}
  - name: Preserve lint failure
    if: steps.resizelint.outcome == 'failure'
    run: exit 1
```

## Local consumer evidence

`Scripts/ci/test-action-consumer.sh` checks the host executable with mocked download transport. `Scripts/ci/test-linux-release-consumer.sh` checks the exact real archive, checksum, extraction and Action execution in Swift-free Ubuntu 22.04/24.04; only unpublished HTTPS download transport is replaced by a copy of that archive. Neither test proves a public hosted download or hosted GitHub workflow run.
