#!/usr/bin/env python3
"""catalog.json(재료 분류·알레르기 묶음·레시피)을 검사하고 Sources/Hankki/CatalogData.swift 로 만든다.

    python3 scripts/build-catalog.py          # 검사 후 CatalogData.swift 갱신
    python3 scripts/build-catalog.py --check  # 검사만 하고, CatalogData.swift 가 최신이 아니면 실패 (CI)

레시피는 catalog.json 에서 고친다. CatalogData.swift 는 직접 고치지 않는다.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "catalog.json"
TARGET = ROOT / "Sources" / "Hankki" / "CatalogData.swift"
BANNED = ["햄", "굴소스", "청경채", "소시지", "베이컨", "스팸", "생굴", "꿀"]
BABY_BANNED = ["고춧가루", "청양고추", "고추장", "통견과", "날달걀", "반숙"]
KEYS = {"id", "name", "audience", "ageMonths", "minutes", "emoji", "category", "ingredients", "amounts", "steps"}


def problems(catalog):
    out = []
    groups = catalog["groups"]
    chips = [x for g in groups for x in g["items"]]
    known = set(chips)
    if len(known) != len(chips):
        out.append("재료 칩 이름이 겹칩니다: " + ", ".join(sorted({x for x in chips if chips.count(x) > 1})))
    for g in catalog["allergens"]:
        for x in g["items"]:
            if x not in known:
                out.append(f"알레르기 묶음 {g['name']}: '{x}' 는 재료 칩에 없습니다")
    categories = set(catalog["categories"])
    ids, names = set(), set()
    for r in catalog["recipes"]:
        where = f"{r.get('id', '?')} {r.get('name', '?')}"
        if set(r) != KEYS:
            out.append(f"{where}: 키가 {sorted(KEYS)} 와 달라요")
            continue
        if r["id"] in ids:
            out.append(f"{where}: id 중복")
        if r["name"] in names:
            out.append(f"{where}: 이름 중복")
        ids.add(r["id"])
        names.add(r["name"])
        if r["audience"] not in ("family", "baby"):
            out.append(f"{where}: audience")
        if r["category"] not in categories:
            out.append(f"{where}: 분류 '{r['category']}'")
        if not r["ingredients"] or not r["amounts"] or not (3 <= len(r["steps"]) <= 5):
            out.append(f"{where}: 재료·분량·단계 개수")
        for x in r["ingredients"]:
            if x not in known:
                out.append(f"{where}: 재료 '{x}' 가 재료 칩에 없습니다")
        text = " ".join([r["name"]] + r["amounts"] + r["steps"])
        for b in BANNED + (BABY_BANNED if r["audience"] == "baby" else []):
            if b in text:
                out.append(f"{where}: '{b}' 는 쓰지 않습니다")
        if re.search(r"(^|\s)가지(\s|$|볶음|나물|무침|구이|전|튀김|조림)", " ".join([r["name"]] + r["amounts"])):
            out.append(f"{where}: 가지는 쓰지 않습니다")
        if '"""' in text:
            out.append(f"{where}: 따옴표 세 개는 쓸 수 없습니다")
    return out


def render(catalog):
    body = json.dumps(catalog, ensure_ascii=False, separators=(",", ":"))
    lines = [
        "// 이 파일은 scripts/build-catalog.py 가 catalog.json 에서 만든다. 직접 고치지 말 것.",
        "",
        "enum CatalogData {",
        f"    static let recipeCount = {len(catalog['recipes'])}",
        '    static let json = #"""',
        body,
        '"""#',
        "}",
        "",
    ]
    return "\n".join(lines)


def main():
    catalog = json.loads(SOURCE.read_text(encoding="utf-8"))
    found = problems(catalog)
    for p in found[:100]:
        print(" -", p)
    if found:
        print(f"{len(found)}개 문제")
        return 1
    text = render(catalog)
    family = sum(r["audience"] == "family" for r in catalog["recipes"])
    print(f"레시피 {len(catalog['recipes'])}가지 (가족 {family} · 아기 {len(catalog['recipes']) - family})")
    if "--check" in sys.argv:
        if not TARGET.exists() or TARGET.read_text(encoding="utf-8") != text:
            print("CatalogData.swift 가 catalog.json 과 다릅니다. python3 scripts/build-catalog.py 를 실행하세요.")
            return 1
        return 0
    TARGET.write_text(text, encoding="utf-8")
    print(TARGET)
    return 0


if __name__ == "__main__":
    sys.exit(main())
