#!/usr/bin/env python3

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any


def resolve_reference(root_schema: dict[str, Any], reference: str) -> dict[str, Any]:
    if not reference.startswith("#/"):
        raise ValueError(f"Unsupported schema reference: {reference}")
    value: Any = root_schema
    for component in reference[2:].split("/"):
        value = value[component]
    return value


def matches_type(value: Any, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    raise ValueError(f"Unsupported schema type: {expected}")


def validate(schema: dict[str, Any], value: Any, root_schema: dict[str, Any], path: str = "$") -> None:
    if "$ref" in schema:
        validate(resolve_reference(root_schema, schema["$ref"]), value, root_schema, path)
        return
    if "const" in schema and value != schema["const"]:
        raise ValueError(f"{path}: expected constant {schema['const']!r}")
    if "enum" in schema and value not in schema["enum"]:
        raise ValueError(f"{path}: value is not in the declared enum")
    if "type" in schema and not matches_type(value, schema["type"]):
        raise ValueError(f"{path}: expected {schema['type']}")
    if "minimum" in schema and value < schema["minimum"]:
        raise ValueError(f"{path}: value is below the minimum")
    if "pattern" in schema and not re.search(schema["pattern"], value):
        raise ValueError(f"{path}: string does not match {schema['pattern']}")

    if isinstance(value, dict):
        required = schema.get("required", [])
        missing = [key for key in required if key not in value]
        if missing:
            raise ValueError(f"{path}: missing required keys {missing}")
        properties = schema.get("properties", {})
        if schema.get("additionalProperties") is False:
            extras = sorted(set(value) - set(properties))
            if extras:
                raise ValueError(f"{path}: unexpected keys {extras}")
        for key, child in value.items():
            if key in properties:
                validate(properties[key], child, root_schema, f"{path}.{key}")
    elif isinstance(value, list) and "items" in schema:
        for index, child in enumerate(value):
            validate(schema["items"], child, root_schema, f"{path}[{index}]")


def load(path: Path) -> Any:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    report_schema = load(root / "Schemas/resizelint-report-v1.schema.json")
    baseline_schema = load(root / "Schemas/resizelint-baseline-v1.schema.json")
    report = load(root / "Tests/Golden/report.json")
    baseline = load(root / "Tests/Golden/baseline.json")
    sarif = load(root / "Tests/Golden/report.sarif")

    validate(report_schema, report, report_schema)
    validate(baseline_schema, baseline, baseline_schema)

    if sarif.get("version") != "2.1.0" or not sarif.get("runs"):
        raise ValueError("SARIF golden file does not declare a 2.1.0 run")
    driver = sarif["runs"][0].get("tool", {}).get("driver", {})
    rule_ids = [rule.get("id") for rule in driver.get("rules", [])]
    expected_rule_ids = [f"RL{number:03d}" for number in range(1, 10)]
    if rule_ids != expected_rule_ids:
        raise ValueError("SARIF golden file does not contain RL001 through RL009 in order")

    print("JSON report, baseline, and SARIF contracts passed.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as error:
        print(f"Machine contract validation failed: {error}", file=sys.stderr)
        raise SystemExit(1)
