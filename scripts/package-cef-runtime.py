#!/usr/bin/env python3
"""Package one exact, codec-enabled CEF line as a runtime NuGet package."""
from __future__ import annotations

import argparse
import shutil
import tempfile
import zipfile
from pathlib import Path
from typing import List, Optional, Tuple
from xml.sax.saxutils import escape

from cef_line_config import load_cef_line

RUNTIME_IDS = {
    "win-x64": "chromiumembeddedframework.runtime.win-x64",
    "win-arm64": "chromiumembeddedframework.runtime.win-arm64",
    "osx-x64": "cef.redist.osx64",
    "osx-arm64": "cef.redist.osx.arm64",
    "linux-x64": "cef.redist.linux64",
    "linux-arm64": "cef.redist.linuxarm64",
}
EXPECTED_NATIVE = {
    "win-x64": "libcef.dll", "win-arm64": "libcef.dll",
    "osx-x64": "libcef.dylib", "osx-arm64": "libcef.dylib",
    "linux-x64": "libcef.so", "linux-arm64": "libcef.so",
}
MARKER_NAME = "CEF_CODEC_BUILD_INFO.txt"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--line", choices=("106", "134"), default="134")
    parser.add_argument("--rid", required=True, choices=sorted(RUNTIME_IDS))
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--codec-enabled", action="store_true")
    parser.add_argument("--allow-synthetic", action="store_true", help="TEST ONLY: allow a synthetic fixture marker")
    return parser.parse_args()


def candidate_roots(source: Path) -> List[Path]:
    if not source.is_dir():
        raise SystemExit(f"CEF source directory does not exist: {source}")
    children = [path for path in source.iterdir() if path.is_dir()]
    children.sort(key=lambda path: ("_minimal" not in path.name.lower(), path.name.lower()))
    return [source, *children]


def find_payload(source: Path) -> Tuple[Path, Optional[Path], Path]:
    for candidate in candidate_roots(source.resolve()):
        if (candidate / "CEF").is_dir():
            root = candidate / "CEF"
            resources = root / "Resources"
            return root, resources if resources.is_dir() else None, candidate
        if ((candidate / "Release").is_dir() or any((candidate / name).is_file() for name in EXPECTED_NATIVE.values())):
            resources = candidate / "Resources"
            return candidate, resources if resources.is_dir() else None, candidate
    raise SystemExit(f"Could not find CEF payload under {source}")


def find_upwards(start: Path, filename: str, stop: Path) -> Optional[Path]:
    current, stop = start.resolve(), stop.resolve()
    while True:
        candidate = current / filename
        if candidate.is_file():
            return candidate
        if current == stop or current.parent == current:
            return None
        current = current.parent


def validate_marker(distribution_root: Path, source_root: Path, line: str, rid: str, allow_synthetic: bool) -> Path:
    marker = find_upwards(distribution_root, MARKER_NAME, source_root)
    if marker is None:
        raise SystemExit(f"--codec-enabled requires {MARKER_NAME} under {source_root}")
    config = load_cef_line(line)
    platform = "Windows" if rid.startswith("win-") else "macOS" if rid.startswith("osx-") else "Linux"
    expected = [
        f"CEF_LINE={line}", f"CEF_BRANCH={config['cef_branch']}",
        f"CEF_CHECKOUT={config['cef_checkout']}", f"CHROMIUM_CHECKOUT={config['chromium_checkout']}",
        f"CEF_ARCH={'arm64' if rid.endswith('arm64') else 'x64'}", f"CEF_PLATFORM={platform}",
        *config["gn_defines"],
    ]
    text = marker.read_text(encoding="utf-8")
    if "SYNTHETIC_FIXTURE=true" in text and not allow_synthetic:
        raise SystemExit("synthetic CEF fixtures are test-only; pass --allow-synthetic only in local/CI smoke tests")
    missing = [value for value in expected if value not in text]
    if missing:
        raise SystemExit(f"invalid codec marker; missing {', '.join(missing)}")
    return marker


def copy_tree_contents(source: Path, destination: Path) -> None:
    if not source.is_dir():
        return
    destination.mkdir(parents=True, exist_ok=True)
    for item in source.iterdir():
        target = destination / item.name
        if item.is_dir():
            shutil.copytree(item, target, dirs_exist_ok=True)
        else:
            shutil.copy2(item, target)


def stage_payload(payload: Path, resources: Optional[Path], rid: str, stage: Path) -> None:
    if rid.startswith("win-"):
        target = stage / "runtimes" / rid / "native"
        release = payload / "Release"
        if release.is_dir():
            copy_tree_contents(release, target)
        else:
            copy_tree_contents(payload, target)
        if resources:
            copy_tree_contents(resources, target / "Resources")
        return
    target = stage / "CEF"
    release = payload / "Release"
    copy_tree_contents(release if release.is_dir() else payload, target)
    if resources:
        copy_tree_contents(resources, target / "Resources" if not (target / "Resources").exists() else target / "Resources")


def locate_license(distribution_root: Path, source_root: Path) -> Optional[Path]:
    for name in ("LICENSE.txt", "LICENSE", "cef/LICENSE.txt"):
        candidate = distribution_root / name
        if candidate.is_file():
            return candidate
    return find_upwards(distribution_root, "LICENSE.txt", source_root)


def create_windows_meta_package(output: Path, version: str, license_file: Optional[Path]) -> Path:
    dependencies = []
    for rid in ("win-x64", "win-arm64"):
        package_id = RUNTIME_IDS[rid]
        if (output / f"{package_id}.{version}.nupkg").is_file():
            dependencies.append(package_id)
    if not dependencies:
        raise SystemExit("Cannot create Windows CEF runtime meta package without a RID package")

    package_id = "chromiumembeddedframework.runtime"
    with tempfile.TemporaryDirectory(prefix="cef-windows-runtime-meta-") as temp:
        stage = Path(temp)
        if license_file:
            shutil.copy2(license_file, stage / "LICENSE.txt")
        else:
            (stage / "LICENSE.txt").write_text(
                "CEF license information is supplied by the CEF binary distribution.\n",
                encoding="utf-8",
            )
        dependency_xml = "\n".join(
            f'      <dependency id="{dependency}" version="[{escape(version)}]" />'
            for dependency in dependencies
        )
        nuspec = f'''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">
  <metadata>
    <id>{package_id}</id><version>{escape(version)}</version><authors>9n1m</authors><owners>9n1m</owners>
    <requireLicenseAcceptance>false</requireLicenseAcceptance><license type="file">LICENSE.txt</license>
    <description>Codec-enabled CEF Windows runtime meta package.</description>
    <tags>cef chromium native runtime windows h264 h265 hevc</tags>
    <dependencies>
{dependency_xml}
    </dependencies>
  </metadata>
</package>
'''
        (stage / f"{package_id}.nuspec").write_text(nuspec, encoding="utf-8")
        package_path = output / f"{package_id}.{version}.nupkg"
        package_path.unlink(missing_ok=True)
        with zipfile.ZipFile(package_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted(stage.rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(stage).as_posix())
    print(package_path)
    return package_path


def create_package(args: argparse.Namespace) -> Path:
    config = load_cef_line(args.line)
    source_root = args.source.resolve()
    payload, resources, distribution_root = find_payload(source_root)
    marker = validate_marker(distribution_root, source_root, args.line, args.rid, args.allow_synthetic) if args.codec_enabled else None
    args.output.mkdir(parents=True, exist_ok=True)
    package_id = RUNTIME_IDS[args.rid]
    with tempfile.TemporaryDirectory(prefix=f"cef-{args.line}-runtime-") as temp:
        stage = Path(temp)
        stage_payload(payload, resources, args.rid, stage)
        prefix = stage / "runtimes" / args.rid / "native" if args.rid.startswith("win-") else stage / "CEF"
        if not (prefix / EXPECTED_NATIVE[args.rid]).is_file():
            raise SystemExit(f"CEF distribution for {args.rid} did not produce {EXPECTED_NATIVE[args.rid]}")
        if not any(path.is_file() and path.suffix.lower() == ".pak" for path in prefix.rglob("*.pak")):
            raise SystemExit(f"CEF distribution for {args.rid} contains no .pak resources")
        license_file = locate_license(distribution_root, source_root)
        shutil.copy2(license_file, stage / "LICENSE.txt") if license_file else (stage / "LICENSE.txt").write_text("CEF license information is supplied by the CEF binary distribution.\n", encoding="utf-8")
        if marker:
            shutil.copy2(marker, stage / MARKER_NAME)
        if args.rid.startswith("osx-") or args.rid.startswith("linux-"):
            item = ({"osx-x64": "CefRedistOSX64", "osx-arm64": "CefRedistOSXARM64", "linux-x64": "CefRedistLinux64", "linux-arm64": "CefRedistLinuxARM64"})[args.rid]
            write_path = stage / "build" / f"{package_id}.props"
            write_path.parent.mkdir(parents=True, exist_ok=True)
            write_path.write_text(f'''<?xml version="1.0" encoding="utf-8"?>\n<Project ToolsVersion="4.0" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">\n  <ItemGroup>\n    <{item} Include="$(MSBuildThisFileDirectory)..\\CEF\\**\\*.*" />\n  </ItemGroup>\n</Project>\n''', encoding="utf-8")
        codec_note = f"Built from pinned CEF {args.line} sources with proprietary H.264 and platform HEVC paths enabled." if args.codec_enabled else "Codec status is not asserted."
        nuspec = f'''<?xml version="1.0" encoding="utf-8"?>\n<package xmlns="http://schemas.microsoft.com/packaging/2013/05/nuspec.xsd">\n  <metadata>\n    <id>{package_id}</id><version>{escape(args.version)}</version><authors>9n1m</authors><owners>9n1m</owners>\n    <requireLicenseAcceptance>false</requireLicenseAcceptance><license type="file">LICENSE.txt</license>\n    <description>CEF {args.line} runtime for {args.rid}. {escape(codec_note)}</description>\n    <copyright>Chromium Embedded Framework Authors</copyright><tags>cef chromium native runtime {args.rid} h264 h265 hevc</tags>\n  </metadata>\n</package>\n'''
        (stage / f"{package_id}.nuspec").write_text(nuspec, encoding="utf-8")
        package_path = args.output / f"{package_id}.{args.version}.nupkg"
        package_path.unlink(missing_ok=True)
        with zipfile.ZipFile(package_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
            for path in sorted(stage.rglob("*")):
                if path.is_file():
                    archive.write(path, path.relative_to(stage).as_posix())
    print(package_path)
    if args.rid.startswith("win-"):
        create_windows_meta_package(args.output, args.version, license_file)
    return package_path


if __name__ == "__main__":
    create_package(parse_args())
