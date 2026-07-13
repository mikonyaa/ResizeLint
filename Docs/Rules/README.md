# ResizeLint rules

ResizeLint 1.0 ships nine stable diagnostics. Rule IDs and their meanings are part of the 1.x public contract.

- [RL001 — main-screen-bounds](RL001.md) · error
- [RL002 — main-screen-scale](RL002.md) · warning
- [RL003 — main-screen-reference](RL003.md) · warning
- [RL004 — global-window-access](RL004.md) · error
- [RL005 — global-status-bar-geometry](RL005.md) · error
- [RL006 — idiom-layout-decision](RL006.md) · warning
- [RL007 — orientation-layout-decision](RL007.md) · warning
- [RL008 — legacy-app-lifecycle](RL008.md) · error
- [RL009 — fullscreen-requirement-review](RL009.md) · info

Change a default severity or disable a rule in [configuration](../Configuration.md). Suppress a single reviewed case only when the source must retain the pattern:

```swift
// resizelint:disable-next-line RL006 -- Layout is intentionally hardware-specific.
```

A nonempty reason is required. File-level suppression must appear before the first declaration.
