#!/usr/bin/env python3
"""Verify CEF runtime, CefGlue, WebView, and consumer output layouts."""
from __future__ import annotations

import argparse
import hashlib
import os
import stat
import zipfile
from pathlib import Path
from xml.etree import ElementTree

from cef_line_config import load_cef_line

RIDS = ("win-x64", "win-arm64", "osx-x64", "osx-arm64", "linux-x64", "linux-arm64")
RUNTIME_PREFIX = {rid: "runtimes/%s/native/" % rid if rid.startswith("win-") else "CEF/" for rid in RIDS}
NATIVE_LIBRARY = {rid: "libcef.dll" if rid.startswith("win-") else "libcef.dylib" if rid.startswith("osx-") else "libcef.so" for rid in RIDS}
IME_FIX_PATH = "native/osx-arm64/libFixIME.dylib"
IME_FIX_SHA256 = "bbf45fd8ee8941248d806cea89366db14eb8802219111b3b1c8eeecefe573a7a"


def fail(target: Path, message: str) -> None:
    raise SystemExit(f"{target}: {message}")


def read_archive(package: Path) -> tuple[set[str], dict[str, bytes]]:
    if not package.is_file():
        fail(package, "package does not exist")
    try:
        with zipfile.ZipFile(package) as archive:
            names = {name.replace("\\", "/") for name in archive.namelist() if not name.endswith("/")}
            contents = {name.replace("\\", "/"): archive.read(name) for name in names}
    except zipfile.BadZipFile as error:
        fail(package, f"not a valid NuGet/ZIP archive: {error}")
    return names, contents


def verify_runtime(package: Path, line: str, rid: str, allow_synthetic: bool) -> None:
    names, contents = read_archive(package)
    prefix = RUNTIME_PREFIX[rid]
    if f"{prefix}{NATIVE_LIBRARY[rid]}" not in names:
        fail(package, f"missing {prefix}{NATIVE_LIBRARY[rid]}")
    if not any(name.startswith(prefix) and name.lower().endswith(".pak") for name in names):
        fail(package, f"missing .pak resource under {prefix}")
    if "CEF_CODEC_BUILD_INFO.txt" not in names:
        fail(package, "missing codec build marker")
    config = load_cef_line(line)
    marker = contents["CEF_CODEC_BUILD_INFO.txt"].decode("utf-8", errors="replace")
    if "SYNTHETIC_FIXTURE=true" in marker and not allow_synthetic:
        fail(package, "synthetic fixture package is test-only; pass --allow-synthetic only for smoke tests")
    expected = [
        f"CEF_LINE={line}", f"CEF_BRANCH={config['cef_branch']}", f"CEF_CHECKOUT={config['cef_checkout']}",
        f"CHROMIUM_CHECKOUT={config['chromium_checkout']}", f"CEF_ARCH={'arm64' if rid.endswith('arm64') else 'x64'}",
        f"CEF_PLATFORM={'Windows' if rid.startswith('win-') else 'macOS' if rid.startswith('osx-') else 'Linux'}",
        *config["gn_defines"],
    ]
    missing = [value for value in expected if value not in marker]
    if missing:
        fail(package, f"invalid codec marker; missing {', '.join(missing)}")
    print(f"verified CEF {line} codec runtime ({rid}): {package}")


def verify_executable_format(data: bytes, rid: str, target: Path | str) -> None:
    expected_arch = "arm64" if rid.endswith("arm64") else "x64"
    actual_platform = "unknown"
    actual_arch = "unknown"

    if data.startswith(b"MZ") and len(data) >= 0x40:
        pe_offset = int.from_bytes(data[0x3C:0x40], "little")
        if len(data) >= pe_offset + 6 and data[pe_offset:pe_offset + 4] == b"PE\0\0":
            actual_platform = "win"
            machine = int.from_bytes(data[pe_offset + 4:pe_offset + 6], "little")
            actual_arch = {0x8664: "x64", 0xAA64: "arm64"}.get(machine, f"machine-0x{machine:04x}")
    elif data.startswith(b"\x7fELF") and len(data) >= 20:
        actual_platform = "linux"
        byteorder = "little" if data[5] == 1 else "big"
        machine = int.from_bytes(data[18:20], byteorder)
        actual_arch = {0x3E: "x64", 0xB7: "arm64"}.get(machine, f"machine-0x{machine:04x}")
    elif len(data) >= 8 and data[:4] in {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"}:
        actual_platform = "osx"
        byteorder = "little" if data[:4] == b"\xcf\xfa\xed\xfe" else "big"
        cpu_type = int.from_bytes(data[4:8], byteorder)
        actual_arch = {0x01000007: "x64", 0x0100000C: "arm64"}.get(cpu_type, f"cpu-0x{cpu_type:08x}")

    expected_platform = rid.split("-", 1)[0]
    if (actual_platform, actual_arch) != (expected_platform, expected_arch):
        fail(Path(target), f"wrong executable format for {rid}: got {actual_platform}/{actual_arch}")


def verify_cefglue(package: Path, line: str, rid: str) -> None:
    names, contents = read_archive(package)
    executable = "9n1m.webview.exe" if rid.startswith("win-") else "9n1m.webview"
    old = "Xilium.CefGlue.BrowserProcess.exe" if rid.startswith("win-") else "Xilium.CefGlue.BrowserProcess"
    executable_path = f"bin/{rid}/{executable}"
    if executable_path not in names:
        fail(package, f"missing {executable_path}")
    if f"bin/{rid}/{old}" in names:
        fail(package, f"old subprocess remains: bin/{rid}/{old}")
    verify_executable_format(contents[executable_path], rid, package)
    print(f"verified CefGlue {line} subprocess package ({rid}): {package}")


def nuspec_dependency_versions(contents: dict[str, bytes]) -> dict[str, str]:
    nuspecs = [name for name in contents if name.lower().endswith(".nuspec")]
    if len(nuspecs) != 1:
        raise ValueError(f"expected one .nuspec, found {len(nuspecs)}")
    root = ElementTree.fromstring(contents[nuspecs[0]])
    return {d.attrib["id"]: d.attrib["version"].strip("[]") for d in root.findall(".//{*}dependency") if "id" in d.attrib and "version" in d.attrib}


def verify_webview(package: Path, arch: str, cefglue_version: str) -> None:
    names, contents = read_archive(package)
    dependency_id = "CefGlue.Avalonia.ARM64" if arch == "arm64" else "CefGlue.Avalonia"
    try:
        actual = nuspec_dependency_versions(contents).get(dependency_id)
    except (ValueError, ElementTree.ParseError) as error:
        fail(package, f"cannot parse nuspec dependencies: {error}")
    if actual != cefglue_version:
        fail(package, f"expected dependency {dependency_id}={cefglue_version}, got {actual!r}")
    target_text = "\n".join(contents[name].decode("utf-8", errors="replace") for name in names if name.lower().endswith(".targets"))
    if "9n1m.webview" not in target_text or "Xilium.CefGlue.BrowserProcess" in target_text:
        fail(package, "MSBuild targets do not consistently deploy the renamed subprocess")
    if "PatchCefExtensionDropdownHandler" not in target_text or "_CopyImeFixDylib" not in target_text:
        fail(package, "macOS ObjC/IME compatibility targets are missing")
    ime_path = IME_FIX_PATH
    if arch == "arm64":
        if ime_path not in names:
            fail(package, f"missing {ime_path}")
        ime = contents[ime_path]
        if not ime.startswith(b"\xcf\xfa\xed\xfe") or int.from_bytes(ime[4:8], "little") != 0x0100000C:
            fail(package, f"{ime_path} is not an arm64 Mach-O dylib")
        actual_hash = hashlib.sha256(ime).hexdigest()
        if actual_hash != IME_FIX_SHA256:
            fail(package, f"{ime_path} changed: expected SHA-256 {IME_FIX_SHA256}, got {actual_hash}")
    print(f"verified WebView package ({arch}): {package}")


def verify_consumer_output(output: Path, rid: str) -> None:
    if not output.is_dir():
        fail(output, "consumer output directory does not exist")
    executable = "9n1m.webview.exe" if rid.startswith("win-") else "9n1m.webview"
    process = output / "CefGlueBrowserProcess" / executable
    if not process.is_file():
        fail(output, f"missing CefGlueBrowserProcess/{executable}")
    verify_executable_format(process.read_bytes(), rid, process)
    if (output / "CefGlueBrowserProcess" / ("Xilium.CefGlue.BrowserProcess.exe" if rid.startswith("win-") else "Xilium.CefGlue.BrowserProcess")).exists():
        fail(output, "old subprocess executable remains")
    native_candidates = [output / NATIVE_LIBRARY[rid], output / "CefGlueBrowserProcess" / NATIVE_LIBRARY[rid]]
    if not any(path.is_file() for path in native_candidates) or not any(path.is_file() for path in output.rglob("*.pak")):
        fail(output, "missing CEF native library or .pak resources")
    if rid == "osx-arm64":
        ime = output / "libFixIME.dylib"
        if not ime.is_file():
            fail(output, "missing preserved macOS IME fix: libFixIME.dylib")
        ime_bytes = ime.read_bytes()
        if not ime_bytes.startswith(b"\xcf\xfa\xed\xfe"):
            fail(output, "libFixIME.dylib is not a Mach-O dylib")
        actual_hash = hashlib.sha256(ime_bytes).hexdigest()
        if actual_hash != IME_FIX_SHA256:
            fail(output, f"libFixIME.dylib changed: expected SHA-256 {IME_FIX_SHA256}, got {actual_hash}")
    if not rid.startswith("win-") and os.name != "nt" and not process.stat().st_mode & stat.S_IXUSR:
        fail(output, f"{process} is not executable")
    print(f"verified consumer output ({rid}): {output}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("target", type=Path)
    parser.add_argument("--kind", choices=("runtime", "cefglue", "webview", "consumer"), default="runtime")
    parser.add_argument("--line", choices=("106", "134"), default="134")
    parser.add_argument("--rid", choices=RIDS)
    parser.add_argument("--arch", choices=("x64", "arm64"))
    parser.add_argument("--cefglue-version")
    parser.add_argument("--allow-synthetic", action="store_true", help="TEST ONLY: accept synthetic runtime markers")
    args = parser.parse_args()
    if args.kind in {"runtime", "cefglue", "consumer"} and not args.rid:
        parser.error(f"--rid is required for --kind {args.kind}")
    if args.kind == "webview" and not args.arch:
        parser.error("--arch is required for --kind webview")
    if args.cefglue_version is None:
        args.cefglue_version = load_cef_line(args.line)["cefglue_version"]
    return args


def main() -> None:
    args = parse_args()
    if args.kind == "runtime": verify_runtime(args.target, args.line, args.rid, args.allow_synthetic)
    elif args.kind == "cefglue": verify_cefglue(args.target, args.line, args.rid)
    elif args.kind == "webview": verify_webview(args.target, args.arch, args.cefglue_version)
    else: verify_consumer_output(args.target, args.rid)


if __name__ == "__main__":
    main()
