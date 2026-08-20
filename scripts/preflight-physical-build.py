#!/usr/bin/env python3
"""Fail-fast checks for a native CEF build on a physical machine."""
from __future__ import annotations

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from cef_line_config import load_cef_line

HOST_PREFIX = {"Windows": "win", "Linux": "linux", "Darwin": "osx"}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--line", choices=("106", "134"), required=True)
    parser.add_argument(
        "--rid",
        choices=("win-x64", "win-arm64", "linux-x64", "linux-arm64", "osx-x64", "osx-arm64"),
        required=True,
    )
    parser.add_argument("--cache", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--skip-native", action="store_true")
    parser.add_argument("--allow-low-disk", action="store_true")
    parser.add_argument("--json-output", type=Path)
    return parser.parse_args()


def command_output(args: List[str]) -> str:
    try:
        return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unavailable"


def memory_gib() -> Optional[float]:
    if sys.platform.startswith("linux"):
        try:
            for line in Path("/proc/meminfo").read_text(encoding="utf-8").splitlines():
                if line.startswith("MemTotal:"):
                    return int(line.split()[1]) / 1024 / 1024
        except (OSError, ValueError, IndexError):
            return None
    if sys.platform == "darwin":
        value = command_output(["sysctl", "-n", "hw.memsize"])
        try:
            return int(value) / 1024**3
        except ValueError:
            return None
    if os.name == "nt":
        try:
            import ctypes

            class MEMORYSTATUSEX(ctypes.Structure):
                _fields_ = [
                    ("dwLength", ctypes.c_ulong),
                    ("dwMemoryLoad", ctypes.c_ulong),
                    ("ullTotalPhys", ctypes.c_ulonglong),
                    ("ullAvailPhys", ctypes.c_ulonglong),
                    ("ullTotalPageFile", ctypes.c_ulonglong),
                    ("ullAvailPageFile", ctypes.c_ulonglong),
                    ("ullTotalVirtual", ctypes.c_ulonglong),
                    ("ullAvailVirtual", ctypes.c_ulonglong),
                    ("ullAvailExtendedVirtual", ctypes.c_ulonglong),
                ]

            status = MEMORYSTATUSEX()
            status.dwLength = ctypes.sizeof(status)
            if ctypes.windll.kernel32.GlobalMemoryStatusEx(ctypes.byref(status)):
                return status.ullTotalPhys / 1024**3
        except (AttributeError, OSError):
            return None
    return None


def dotnet_sdks() -> List[str]:
    output = command_output(["dotnet", "--list-sdks"])
    if output == "unavailable":
        return []
    return [line.split()[0] for line in output.splitlines() if line.strip()]


def windows_toolchain(line: str) -> Tuple[Dict[str, object], List[str]]:
    details: Dict[str, object] = {}
    errors: List[str] = []
    program_files_x86 = os.environ.get("ProgramFiles(x86)", r"C:\Program Files (x86)")
    vswhere = Path(program_files_x86) / "Microsoft Visual Studio" / "Installer" / "vswhere.exe"
    required_major = "16" if line == "106" else "17"
    version_range = "[16.0,17.0)" if line == "106" else "[17.0,18.0)"
    required_name = "Visual Studio 2019" if line == "106" else "Visual Studio 2022"
    vswhere_common = [
        str(vswhere), "-latest", "-products", "*", "-version", version_range,
        "-requires", "Microsoft.VisualStudio.Workload.NativeDesktop",
        "Microsoft.VisualStudio.Component.VC.ATLMFC",
    ]
    if vswhere.is_file():
        version = command_output(vswhere_common + ["-property", "installationVersion"])
        path = command_output(vswhere_common + ["-property", "installationPath"])
        details["visual_studio_version"] = version
        details["visual_studio_path"] = path
        if version == "unavailable" or not version.startswith(required_major + "."):
            errors.append(f"{required_name} with Desktop development with C++ and MFC/ATL is required")
    else:
        details["visual_studio_version"] = "vswhere.exe not found"
        errors.append(f"{required_name} was not detected because vswhere.exe is missing")

    sdk_root = Path(program_files_x86) / "Windows Kits" / "10"
    sdk_floor = (10, 0, 20348, 0) if line == "106" else (10, 0, 22621, 0)

    def sdk_version(path: Path) -> Optional[Tuple[int, ...]]:
        try:
            parts = tuple(int(part) for part in path.name.split("."))
        except ValueError:
            return None
        return parts if len(parts) == 4 else None

    sdk_candidates = []
    include_root = sdk_root / "Include"
    if include_root.is_dir():
        for candidate in include_root.iterdir():
            version = sdk_version(candidate)
            if candidate.is_dir() and version is not None and version >= sdk_floor:
                sdk_candidates.append((version, candidate))
    sdk_candidates.sort(reverse=True)
    sdk_include = sdk_candidates[0][1] if sdk_candidates else include_root / ".".join(map(str, sdk_floor))
    debugger = sdk_root / "Debuggers" / "x64" / "cdb.exe"
    details["windows_sdk_minimum"] = ".".join(map(str, sdk_floor))
    details["windows_sdk_detected"] = sdk_include.name if sdk_candidates else "not found"
    details["windows_sdk_include"] = str(sdk_include)
    details["debugging_tools"] = str(debugger)
    if not sdk_candidates:
        errors.append(
            f"Windows SDK {'.'.join(map(str, sdk_floor))} or newer is required for CEF line {line}"
        )
    if not debugger.is_file():
        errors.append("Debugging Tools for Windows (x64 cdb.exe) is required")
    return details, errors


def main() -> None:
    args = parse_args()
    if sys.version_info < (3, 8):
        raise SystemExit(
            f"Python 3.8 or newer is required by the physical-build preflight; "
            f"detected {sys.version.split()[0]}"
        )
    config = load_cef_line(args.line)
    host = platform.system()
    expected_prefix = HOST_PREFIX.get(host)
    errors: List[str] = []
    warnings: List[str] = []

    if expected_prefix is None:
        errors.append(f"unsupported build host: {host}")
    elif not args.rid.startswith(f"{expected_prefix}-"):
        errors.append(f"{args.rid} must be built on a {expected_prefix} host, not {host}")

    machine = platform.machine().lower()
    requested_arch = args.rid.rsplit("-", 1)[1]
    host_arch = "arm64" if machine in {"arm64", "aarch64"} else "x64" if machine in {"x86_64", "amd64"} else machine
    if requested_arch != host_arch:
        warnings.append(
            f"host architecture is {host_arch}, target is {requested_arch}; this path requires a supported native cross-architecture CEF build"
        )

    required_commands = ["git", "curl", "dotnet"]
    if not args.skip_native:
        required_commands.extend(["bash"])
    missing_commands = [name for name in required_commands if shutil.which(name) is None]
    if missing_commands:
        errors.append(f"missing commands: {', '.join(missing_commands)}")

    sdks = dotnet_sdks()
    required_sdk = "6" if args.line == "106" else "8"
    if not any(version.split(".", 1)[0] == required_sdk for version in sdks):
        errors.append(f".NET SDK {required_sdk}.x is required for CEF line {args.line}; installed: {sdks or ['none']}")

    args.cache.mkdir(parents=True, exist_ok=True)
    args.output.mkdir(parents=True, exist_ok=True)
    free_gib = shutil.disk_usage(args.cache).free / 1024**3
    min_free_gib = float(os.environ.get("CEF_MIN_FREE_GB", "120"))
    recommended_free_gib = float(os.environ.get("CEF_RECOMMENDED_FREE_GB", "250"))
    if not args.skip_native and free_gib < min_free_gib:
        message = (
            f"only {free_gib:.1f} GiB is free on the cache volume; "
            f"at least {min_free_gib:.0f} GiB is required by this preflight and {recommended_free_gib:.0f} GiB is recommended"
        )
        if args.allow_low_disk:
            warnings.append(message + " (override accepted)")
        else:
            errors.append(message + "; use --allow-low-disk only if an existing checkout makes this safe")
    elif not args.skip_native and free_gib < recommended_free_gib:
        warnings.append(f"{free_gib:.1f} GiB free; {recommended_free_gib:.0f} GiB is recommended for a fresh checkout/build")

    toolchain: Dict[str, object] = {}
    if host == "Windows" and not args.skip_native:
        toolchain, toolchain_errors = windows_toolchain(args.line)
        errors.extend(toolchain_errors)

    total_memory = memory_gib()
    if total_memory is not None and total_memory < 16:
        warnings.append(f"only {total_memory:.1f} GiB RAM detected; 32 GiB or more is recommended")
    elif total_memory is not None and total_memory < 32:
        warnings.append(f"{total_memory:.1f} GiB RAM detected; the build can be slow or memory constrained below 32 GiB")

    report = {
        "schema": 1,
        "ok": not errors,
        "cef_line": args.line,
        "purpose": config["purpose"],
        "rid": args.rid,
        "host_os": host,
        "host_arch": host_arch,
        "python": sys.version.split()[0],
        "python_minimum": "3.8",
        "git": command_output(["git", "--version"]),
        "dotnet_sdks": sdks,
        "cache": str(args.cache.resolve()),
        "output": str(args.output.resolve()),
        "cache_free_gib": round(free_gib, 1),
        "memory_gib": round(total_memory, 1) if total_memory is not None else None,
        "skip_native": args.skip_native,
        "windows_toolchain": toolchain or None,
        "warnings": warnings,
        "errors": errors,
    }

    print("=== Physical machine CEF build preflight ===")
    print(json.dumps(report, indent=2, ensure_ascii=False))
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    if errors:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
