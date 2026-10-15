# -*- coding: utf-8 -*-
"""将 assets/fengshui/环境分析文件*.txt 解析为 environment_palaces.json（可重复运行）。

合并规则：先读文件1 再读文件2，同一卦名以后者覆盖前者（如乾宫）。
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets" / "fengshui"
OUT = ASSETS / "environment_palaces.json"

PALACE_SPLIT = re.compile(r"(?=^# [乾坤震巽坎离艮兑]宫)", re.MULTILINE)
# 整行标题含「X宫」，便于展示；卦名单独一组便于 key
PALACE_HEAD = re.compile(r"^# (([乾坤震巽坎离艮兑])宫.*)$")

NUM_ITEM = re.compile(r"^(\d+)\.\s*\*\*([^*]+)\*\*\s*[：:]\s*(.*)$")
BOLD_ITEM = re.compile(r"^\*\*([^*]+)\*\*\s*[：:]\s*(.*)$")

SEC1 = "## 一、"
SEC2 = "## 二、"
SEC3 = "## 三、"


def _section_bounds(lines: list[str]) -> tuple[int | None, int | None, int | None]:
    i1 = i2 = i3 = None
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith(SEC1):
            i1 = i
        elif s.startswith(SEC2):
            i2 = i
        elif s.startswith(SEC3):
            i3 = i
    return i1, i2, i3


def _parse_numbered(block_lines: list[str]) -> list[dict]:
    items: list[dict] = []
    cur: dict | None = None
    for raw in block_lines:
        line = raw.rstrip()
        stripped = line.strip()
        if not stripped:
            continue
        if stripped == "---":
            continue
        if stripped.startswith("##"):
            break
        m = NUM_ITEM.match(line)
        if m:
            if cur is not None:
                items.append(cur)
            cur = {
                "key": m.group(2).strip(),
                "text": m.group(3).strip(),
            }
        elif cur is not None:
            cur["text"] = (cur["text"] + "\n" + line.strip()).strip()
    if cur is not None:
        items.append(cur)
    return items


def _parse_indoor(block_lines: list[str]) -> list[dict]:
    items: list[dict] = []
    cur: dict | None = None
    for raw in block_lines:
        line = raw.rstrip()
        stripped = line.strip()
        if not stripped:
            continue
        if stripped == "---":
            continue
        if stripped.startswith("##"):
            break
        m = BOLD_ITEM.match(line)
        if m:
            if cur is not None:
                items.append(cur)
            cur = {"key": m.group(1).strip(), "text": m.group(2).strip()}
        elif cur is not None:
            cur["text"] = (cur["text"] + "\n" + line.strip()).strip()
    if cur is not None:
        items.append(cur)
    return items


def parse_palace_block(block: str) -> dict | None:
    block = block.strip()
    if not block:
        return None
    lines = block.split("\n")
    hm = PALACE_HEAD.match(lines[0].strip())
    if not hm:
        return None
    gua = hm.group(2)
    title_full = hm.group(1).strip()

    i1, i2, i3 = _section_bounds(lines)

    preamble_lines: list[str] = []
    if i1 is not None:
        preamble_lines = lines[1:i1]
    else:
        preamble_lines = lines[1:]

    preamble = "\n".join(preamble_lines).strip()

    outdoor: list[dict] = []
    indoor: list[dict] = []
    malformation: list[dict] = []

    if i1 is not None and i2 is not None:
        outdoor = _parse_numbered(lines[i1 + 1 : i2])
    elif i1 is not None:
        outdoor = _parse_numbered(lines[i1 + 1 :])

    if i2 is not None and i3 is not None:
        indoor = _parse_indoor(lines[i2 + 1 : i3])
    elif i2 is not None:
        indoor = _parse_indoor(lines[i2 + 1 :])

    if i3 is not None:
        malformation = _parse_numbered(lines[i3 + 1 :])

    return {
        "gua": gua,
        "title": title_full,
        "preamble": preamble,
        "outdoor": outdoor,
        "indoor": indoor,
        "malformation": malformation,
    }


def parse_file(path: Path) -> dict[str, dict]:
    text = path.read_text(encoding="utf-8").replace("\ufeff", "")
    parts = PALACE_SPLIT.split(text)
    out: dict[str, dict] = {}
    for part in parts:
        p = parse_palace_block(part)
        if p:
            out[p["gua"]] = p
    return out


def main() -> None:
    f1 = ASSETS / "环境分析文件1.txt"
    f2 = ASSETS / "环境分析文件2.txt"
    merged: dict[str, dict] = {}
    merged.update(parse_file(f1))
    merged.update(parse_file(f2))  # 同卦以后者为准（乾宫等）

    OUT.write_text(
        json.dumps(merged, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {OUT} ({len(merged)} palaces)")


if __name__ == "__main__":
    main()
