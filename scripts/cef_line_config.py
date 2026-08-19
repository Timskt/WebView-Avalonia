#!/usr/bin/env python3
"""Shared, exact CEF line configuration used by build/package/verify tooling."""
from __future__ import annotations

import argparse
import json
import shlex
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = ROOT / "config" / "cef-lines.json"


def load_cef_line(line: str) -> dict[str, Any]:
    data = json.loads(CONFIG_PATH.read_text(encoding="utf-8"))
    try:
        config = data[str(line)]
    except KeyError as error:
        raise ValueError(
            f"unsupported CEF line {line!r}; choose one of {', '.join(sorted(data))}"
        ) from error
    config = dict(config)
    config["line"] = str(line)
    return config


def environment_for_line(line: str) -> dict[str, str]:
    config = load_cef_line(line)
    return {
        "CEF_LINE": config["line"],
        "CEF_BRANCH": config["cef_branch"],
        "CEF_CHECKOUT": config["cef_checkout"],
        "CHROMIUM_CHECKOUT": config["chromium_checkout"],
        "CEF_RUNTIME_VERSION": config["cef_runtime_version"],
        "CEFGLUE_VERSION": config["cefglue_version"],
        "WEBVIEW_VERSION": config["webview_version"],
        "TARGET_FRAMEWORK": config["target_framework"],
        "CEFGLUE_DIR": "vendor/CefGlue" if config["line"] == "106" else "vendor/CefGlue-134",
        "GN_DEFINES": " ".join(config["gn_defines"]),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("line", choices=("106", "134"))
    parser.add_argument("--format", choices=("json", "shell", "github-env"), default="json")
    args = parser.parse_args()
    values = environment_for_line(args.line)

    if args.format == "json":
        print(json.dumps(values, indent=2, sort_keys=True))
    elif args.format == "shell":
        for key, value in values.items():
            print(f"{key}={shlex.quote(value)}")
    else:
        for key, value in values.items():
            if "\n" in value or "\r" in value:
                raise SystemExit(f"{key} cannot be written to GITHUB_ENV because it contains a newline")
            print(f"{key}={value}")


if __name__ == "__main__":
    main()
