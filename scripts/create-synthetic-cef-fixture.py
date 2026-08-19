#!/usr/bin/env python3
"""Create tiny TEST-ONLY CEF distributions for package/managed-build smoke tests.

The generated files are not CEF binaries and must never be released. Real codec
claims require the GitHub Actions source builds and media playback tests.
"""
from __future__ import annotations

import argparse
from pathlib import Path

from cef_line_config import load_cef_line

NATIVE = {
    "win-x64": "libcef.dll", "win-arm64": "libcef.dll",
    "osx-x64": "libcef.dylib", "osx-arm64": "libcef.dylib",
    "linux-x64": "libcef.so", "linux-arm64": "libcef.so",
}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--line", choices=("106", "134"), required=True)
    parser.add_argument("--rid", choices=tuple(NATIVE), required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    config = load_cef_line(args.line)
    platform = "Windows" if args.rid.startswith("win-") else "macOS" if args.rid.startswith("osx-") else "Linux"
    arch = "arm64" if args.rid.endswith("arm64") else "x64"
    root = args.output / f"cef_{args.line}_{args.rid}_minimal"
    release = root / "Release"
    resources = root / "Resources"
    release.mkdir(parents=True, exist_ok=True)
    resources.mkdir(parents=True, exist_ok=True)
    (release / NATIVE[args.rid]).write_bytes(b"TEST-ONLY synthetic native placeholder\n")
    if args.rid.startswith("osx-"):
        for name in ("libEGL.dylib", "libGLESv2.dylib", "libvk_swiftshader.dylib"):
            (release / name).write_bytes(b"TEST-ONLY synthetic macOS support library placeholder\n")
    (resources / "resources.pak").write_bytes(b"TEST-ONLY synthetic pak placeholder\n")
    (root / "LICENSE.txt").write_text("TEST-ONLY fixture; not redistributable as CEF.\n", encoding="utf-8")
    marker = "\n".join([
        f"CEF_LINE={args.line}", f"CEF_BRANCH={config['cef_branch']}", f"CEF_CHECKOUT={config['cef_checkout']}",
        f"CHROMIUM_CHECKOUT={config['chromium_checkout']}", f"CEF_ARCH={arch}", f"CEF_PLATFORM={platform}",
        f"GN_DEFINES={' '.join(config['gn_defines'])}", "SYNTHETIC_FIXTURE=true", "",
    ])
    (args.output / "CEF_CODEC_BUILD_INFO.txt").write_text(marker, encoding="utf-8")
    print(root)


if __name__ == "__main__":
    main()
