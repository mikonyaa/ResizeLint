#!/usr/bin/env python3

from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import unquote


LINK_PATTERN = re.compile(
    r"!?\[[^\]]*\]\((?:<([^>]+)>|([^\s)]+))(?:\s+[\"'][^)]*)?\)"
)
SCHEME_PATTERN = re.compile(r"^[A-Za-z][A-Za-z0-9+.-]*:")


def markdown_files(root: Path) -> list[Path]:
    return sorted(
        path
        for path in root.rglob("*.md")
        if ".build" not in path.parts and ".git" not in path.parts
    )


def local_target(root: Path, source: Path, raw_target: str) -> Path | None:
    target = raw_target.strip()
    if not target or target.startswith("#") or target.startswith("//"):
        return None
    if SCHEME_PATTERN.match(target):
        return None

    target = unquote(target.split("#", 1)[0].split("?", 1)[0])
    if not target:
        return None
    if target.startswith("/"):
        return root / target.lstrip("/")
    return source.parent / target


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()
    if not root.is_dir():
        print(f"Documentation root does not exist: {root}", file=sys.stderr)
        return 2

    missing: list[tuple[Path, str]] = []
    checked = 0
    for source in markdown_files(root):
        text = source.read_text(encoding="utf-8")
        for match in LINK_PATTERN.finditer(text):
            raw_target = match.group(1) or match.group(2)
            target = local_target(root, source, raw_target)
            if target is None:
                continue
            checked += 1
            if not target.exists():
                missing.append((source.relative_to(root), raw_target))

    if missing:
        for source, target in missing:
            print(f"Missing local documentation target: {source} -> {target}", file=sys.stderr)
        return 1

    print(f"Documentation links passed: {checked} local targets checked.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
