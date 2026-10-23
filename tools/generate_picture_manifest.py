#!/usr/bin/env python3
"""Build a deterministic word-picture index using only the Python standard library."""

import argparse
import json
import os
from pathlib import Path


def generate_manifest(directory: Path) -> dict:
    """Index PNG files relative to directory, rejecting ambiguous word names."""
    directory = Path(directory)
    if not directory.is_dir():
        raise ValueError(f"Picture directory does not exist: {directory}")
    images = {}
    for root, directories, files in os.walk(directory, followlinks=False):
        directories[:] = sorted(
            name for name in directories if not name.startswith(".")
        )
        for name in sorted(files):
            path = Path(root) / name
            if name.startswith(".") or path.suffix.lower() != ".png":
                continue
            if path.is_symlink() or not path.is_file():
                continue
            word = path.stem.strip().lower()
            if not word:
                raise ValueError(f"Image has an empty word name: {path}")
            relative = path.relative_to(directory).as_posix()
            if word in images:
                raise ValueError(
                    f"Normalized word collision for {word!r}: "
                    f"{images[word]['path']!r} and {relative!r}"
                )
            images[word] = {"path": relative, "bytes": path.stat().st_size}
    return {"version": 1, "images": dict(sorted(images.items()))}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path, help="Picture repository root")
    parser.add_argument(
        "--output", type=Path, help="Output JSON path (default: directory/manifest.json)"
    )
    args = parser.parse_args()
    try:
        manifest = generate_manifest(args.directory)
        output = args.output or args.directory / "manifest.json"
        output.write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
    except (OSError, ValueError) as error:
        parser.exit(1, f"Error: {error}\n")
    print(f"Indexed {len(manifest['images'])} images: {output}")


if __name__ == "__main__":
    main()
