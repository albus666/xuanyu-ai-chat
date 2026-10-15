#!/usr/bin/env python3
"""Extract the canonical Dart legal copy for the pre-Flutter iOS consent gate."""

from pathlib import Path
import sys


def extract(source: str, variable: str) -> str:
    marker = f"const {variable} = '''"
    start = source.find(marker)
    if start < 0:
        raise RuntimeError(f"Cannot find {variable}")
    start += len(marker)
    if source.startswith("\r\n", start):
        start += 2
    elif source.startswith("\n", start):
        start += 1
    end = source.find("\n''';", start)
    if end < 0:
        raise RuntimeError(f"Cannot find the end of {variable}")
    return source[start:end].replace("\r\n", "\n")


def main() -> None:
    source_path = Path(sys.argv[1])
    output_dir = Path(sys.argv[2])
    source = source_path.read_text(encoding="utf-8")
    output_dir.mkdir(parents=True, exist_ok=True)
    documents = {
        "user_agreement.txt": "_userAgreement",
        "privacy_policy.txt": "_privacyPolicy",
    }
    for filename, variable in documents.items():
        (output_dir / filename).write_text(
            extract(source, variable), encoding="utf-8"
        )


if __name__ == "__main__":
    main()
