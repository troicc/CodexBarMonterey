#!/usr/bin/env python3
"""Validate CodexBarCLI `config providers --json` output."""

from __future__ import annotations

import argparse
import json
import sys
from typing import Any


def provider_ids(payload: Any) -> list[str]:
    if isinstance(payload, list):
        rows = payload
    elif isinstance(payload, dict):
        rows = payload.get("providers")
    else:
        rows = None

    if not isinstance(rows, list):
        raise ValueError("provider catalog must contain a JSON array")
    if not rows:
        raise ValueError("provider catalog must not be empty")

    result: list[str] = []
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("provider catalog rows must be JSON objects")
        value = row.get("provider") or row.get("id")
        if not isinstance(value, str) or not value.strip():
            raise ValueError(f"provider row is missing an ID: {row!r}")
        result.append(value.strip())
    return result


def validate(payload: Any, minimum: int) -> list[str]:
    ids = provider_ids(payload)
    if len(ids) != len(set(ids)):
        raise ValueError("provider catalog contains duplicate IDs")
    if "codex" not in ids:
        raise ValueError("provider catalog is missing codex")
    if len(ids) < minimum:
        raise ValueError(f"provider catalog unexpectedly small: {len(ids)} < {minimum}")
    return ids


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--min-count", type=int, default=60)
    args = parser.parse_args()
    try:
        payload = json.load(sys.stdin)
        ids = validate(payload, args.min_count)
    except (json.JSONDecodeError, ValueError) as exc:
        print(f"Provider catalog validation failed: {exc}", file=sys.stderr)
        return 1
    print(len(ids))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
