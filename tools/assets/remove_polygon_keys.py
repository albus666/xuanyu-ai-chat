#!/usr/bin/env python3
"""
从 JSON 中递归删除所有 "polygon" 键（常用于缩小 GeoJSON / 地图资源体积）。

用法:
  python tools/assets/remove_polygon_keys.py <输入.json> [-o 输出.json]

默认覆盖原文件，并先把原文件备份为 <输入.json>.bak
若指定 -o，则写入新文件，不改动原文件。
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path
from typing import Any


def strip_polygon(obj: Any) -> None:
    if isinstance(obj, dict):
        obj.pop("polygon", None)
        for v in obj.values():
            strip_polygon(v)
    elif isinstance(obj, list):
        for item in obj:
            strip_polygon(item)


def main() -> int:
    parser = argparse.ArgumentParser(description='从 JSON 中删除所有 "polygon" 键')
    parser.add_argument("input", type=Path, help="输入 JSON 路径")
    parser.add_argument(
        "-o",
        "--output",
        type=Path,
        default=None,
        help="输出路径（省略则覆盖输入，并生成 .bak 备份）",
    )
    parser.add_argument(
        "--indent",
        type=int,
        default=2,
        help="写入时的缩进空格数，设为 0 则紧凑输出（默认 2）",
    )
    args = parser.parse_args()

    inp = args.input.resolve()
    if not inp.is_file():
        print(f"错误: 找不到文件 {inp}", file=sys.stderr)
        return 1

    print(f"读取: {inp} …")
    with inp.open("r", encoding="utf-8") as f:
        data = json.load(f)

    strip_polygon(data)

    out = args.output.resolve() if args.output else inp
    indent = None if args.indent == 0 else args.indent

    if args.output is None:
        bak = inp.with_suffix(inp.suffix + ".bak")
        print(f"备份: {bak}")
        shutil.copy2(inp, bak)

    print(f"写入: {out} …")
    with out.open("w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, ensure_ascii=False, indent=indent)
        f.write("\n")

    print("完成。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
