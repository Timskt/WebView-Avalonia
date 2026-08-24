#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import zipfile
from pathlib import Path


EXCLUDED_NAMES = {
    "cdb.log",
    "cdb2.log",
    "cdb-symbols.log",
    "ceflog.txt",
    "debug.log",
    "portable-startup-error.log",
}
EXCLUDED_SUFFIXES = {".lib", ".pdb"}
REQUIRED_PATHS = (
    "SampleWebView.Avalonia.exe",
    "SampleWebView.Avalonia.dll",
    "SampleWebView.Avalonia.runtimeconfig.json",
    "libcef.dll",
    "icudtl.dat",
    "resources.pak",
    "v8_context_snapshot.bin",
    "CefGlueBrowserProcess/9n1m.webview.exe",
)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def included_files(source: Path) -> list[Path]:
    return [
        path
        for path in sorted(source.rglob("*"))
        if path.is_file()
        and path.name not in EXCLUDED_NAMES
        and path.suffix.lower() not in EXCLUDED_SUFFIXES
    ]


def validate(source: Path) -> None:
    missing = [relative for relative in REQUIRED_PATHS if not (source / relative).is_file()]
    locales = source / "locales"
    if not locales.is_dir() or not any(locales.glob("*.pak")):
        missing.append("locales/*.pak")
    if missing:
        raise SystemExit("portable Demo source is incomplete: " + ", ".join(missing))


def launcher_cmd() -> str:
    return r"""@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Run-SampleDemo.ps1" %*
if errorlevel 1 (
  echo.
  echo Startup failed. Check portable-startup-error.log and %%LOCALAPPDATA%%\9n1m-WebView-Avalonia\logs.
  pause
)
"""


def launcher_ps1() -> str:
    return r"""$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $PSScriptRoot
Get-ChildItem -LiteralPath $PSScriptRoot -Recurse -File |
  Where-Object { $_.Extension -in '.exe', '.dll' } |
  Unblock-File -ErrorAction SilentlyContinue
& (Join-Path $PSScriptRoot 'SampleWebView.Avalonia.exe') @args
exit $LASTEXITCODE
"""


def readme(line: str, rid: str) -> str:
    operating_system = "Windows 10/11" if line == "134" else "the supported Windows compatibility target"
    return rf"""SampleWebView.Avalonia portable Demo

CEF line: {line}
Runtime: {rid}

1. Extract this complete ZIP to a normal writable directory.
2. Run Run-SampleDemo.cmd or Run-SampleDemo.ps1.
3. Do not move only the EXE or rename CefGlueBrowserProcess/9n1m.webview.exe.

The application resolves CEF files relative to its own executable directory,
not the shell current directory. Logs are written to:
%LOCALAPPDATA%\9n1m-WebView-Avalonia\logs

This {line} build requires 64-bit {operating_system}. H.265 playback additionally
depends on the Windows HEVC component, GPU, driver and supported stream profile.
"""


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--line", choices=("106", "134"), required=True)
    parser.add_argument("--rid", choices=("win-x64", "win-arm64"), required=True)
    args = parser.parse_args()

    source = args.source.resolve()
    output = args.output.resolve()
    if not source.is_dir():
        raise SystemExit(f"portable Demo source does not exist: {source}")
    validate(source)

    files = included_files(source)
    manifest = {
        "cef_line": args.line,
        "runtime_identifier": args.rid,
        "path_independent": True,
        "files": [
            {
                "path": path.relative_to(source).as_posix(),
                "size": path.stat().st_size,
                "sha256": sha256(path),
            }
            for path in files
        ],
    }

    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        output.unlink()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in files:
            archive.write(path, path.relative_to(source).as_posix())
        archive.writestr("Run-SampleDemo.cmd", launcher_cmd())
        archive.writestr("Run-SampleDemo.ps1", launcher_ps1())
        archive.writestr("README-PORTABLE.txt", readme(args.line, args.rid))
        archive.writestr("PORTABLE-MANIFEST.json", json.dumps(manifest, indent=2) + os.linesep)

    digest = sha256(output)
    sidecar = output.with_name(output.name + ".sha256")
    sidecar.write_text(f"{digest}  {output.name}\n", encoding="utf-8")
    print(output)
    print(sidecar)


if __name__ == "__main__":
    main()
