#!/usr/bin/env python3
"""Export/check the exact privacy text used by Flutter and its native consent gate."""

import argparse
from hashlib import sha256
from pathlib import Path
import re
import zipfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend-root", type=Path)
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    source = (root / "lib/features/profile/legal_document_page.dart").read_text()
    match = re.search(r"const _privacyPolicy = '''([\s\S]*?)''';", source)
    if not match:
        parser.error("Flutter privacy policy literal was not found")
    text = match[1].strip()
    if args.backend_root:
        target = args.backend_root / "apps/system/legal/privacy_policy.txt"
        if args.check:
            if target.read_text().strip() != text:
                parser.exit(1, "Website privacy policy differs from the app\n")
        else:
            target.write_text(text + "\n", encoding="utf-8")
    if args.apk:
        with zipfile.ZipFile(args.apk) as apk:
            native = apk.read("assets/legal/privacy_policy.txt").decode().strip()
        if native != text:
            parser.exit(1, "APK consent policy differs from the app\n")
    print("Privacy policy SHA256:", sha256(text.encode()).hexdigest())


if __name__ == "__main__":
    main()
