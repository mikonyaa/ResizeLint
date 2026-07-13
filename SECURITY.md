# Security policy

## Supported versions

Security fixes are applied to the latest published 1.x release. The unreleased main branch may contain additional defensive tests that have not yet shipped.

## Reporting a vulnerability

Use GitHub private vulnerability reporting in the ResizeLint repository when it is enabled. If private reporting is unavailable, open a minimal issue that contains no exploit details, credentials, private source, or local paths and request a private maintainer channel.

Include the affected version, platform, input category, expected safety boundary, and a minimized non-sensitive reproducer. Do not attach proprietary projects or signing material.

## Scope

Useful reports include unsafe file replacement, path escape, symbolic-link traversal, unbounded resource use, terminal or machine-report injection, analysis of files outside the selected root, and execution of analyzed project content.

ResizeLint does not make network requests during analysis and does not execute scripts from analyzed repositories.
