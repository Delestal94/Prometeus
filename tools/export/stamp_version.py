#!/usr/bin/env python3
"""Write a version into project.godot's application/config/version (N-210).

Usage: stamp_version.py <project.godot> <version>

The release job runs this with the tag (v1.2.3 -> 1.2.3) before exporting, so the
main menu footer shows the build's version. It replaces the existing line, or adds
it right after config/name if it is missing.
"""
import re
import sys


def stamp(text: str, version: str) -> str:
    if not re.fullmatch(r"[0-9A-Za-z.+-]+", version):
        raise ValueError(f"not a version: {version!r}")
    line = f'config/version="{version}"'
    if re.search(r"^config/version=.*$", text, flags=re.M):
        return re.sub(r"^config/version=.*$", line, text, count=1, flags=re.M)
    new, count = re.subn(r"^(config/name=.*)$", r"\1\n" + line, text, count=1, flags=re.M)
    if count != 1:
        raise ValueError("project.godot has no config/name line")
    return new


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    path, version = sys.argv[1], sys.argv[2]
    with open(path, encoding="utf-8") as f:
        text = f.read()
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(stamp(text, version))
    print(f"{path}: config/version={version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
