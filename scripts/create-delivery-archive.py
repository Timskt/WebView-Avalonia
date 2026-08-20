#!/usr/bin/env python3
"""Create a platform-friendly delivery archive and SHA-256 sidecar."""
from __future__ import annotations

import argparse
import hashlib
import shutil
from pathlib import Path


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--output-base", type=Path, required=True)
    parser.add_argument("--format", choices=("zip", "gztar"), required=True)
    args = parser.parse_args()
    if not args.source.is_dir():
        raise SystemExit(f"delivery source does not exist: {args.source}")
    args.output_base.parent.mkdir(parents=True, exist_ok=True)
    archive = Path(
        shutil.make_archive(
            str(args.output_base), args.format, root_dir=args.source.resolve(), base_dir="."
        )
    )
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    sidecar = archive.with_name(archive.name + ".sha256")
    sidecar.write_text(f"{digest}  {archive.name}\n", encoding="utf-8")
    print(archive)
    print(sidecar)


if __name__ == "__main__":
    main()
