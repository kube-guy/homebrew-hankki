#!/usr/bin/env python3
"""기준 지점 반경 안의 식당을 네이버 플레이스에서 모아 research/naver-nearby.json 에 남긴다.

기준 좌표와 반경은 research/area.json 의 center, radius_m 에서 읽는다.

목록(평점·리뷰 수·좌표)은 플레이스 목록 API 에서, 대표 메뉴 가격은 각 식당의 메뉴 페이지에서
읽는다. 네이버에 부담을 주지 않도록 요청 사이에 1초씩 쉰다. 결과 파일을 build-catalog.py 가
읽어 restaurants.json 에 합친다.

    python3 scripts/collect-naver.py            # 목록 + 메뉴
    python3 scripts/collect-naver.py --no-menu  # 목록만 (빠른 확인용)
"""
import json
import math
import re
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "research/naver-nearby.json"
AREA = json.loads((ROOT / "research/area.json").read_text())
CENTER = tuple(AREA["center"])
RADIUS_M = AREA.get("radius_m", 1000)
# 반경을 덮는 사각형 (경도;위도 순서)
_dlat = RADIUS_M / 111_000 * 1.1
_dlon = RADIUS_M / (111_000 * math.cos(math.radians(CENTER[0]))) * 1.1
BOUNDS = f"{CENTER[1] - _dlon:.4f};{CENTER[0] - _dlat:.4f};{CENTER[1] + _dlon:.4f};{CENTER[0] + _dlat:.4f}"
QUERIES = ["음식점", "한식", "일식", "중식", "양식", "아시아음식", "분식", "국밥", "면요리", "고기"]
PAGE = 50
MAX_PER_QUERY = 300
MIN_REVIEWS = 50
UA = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"
# 점심 한 끼로 고르기 어려운 업종
SKIP_CATEGORY = re.compile(r"카페|디저트|베이커리|제과|빵|떡|아이스크림|도넛|와인|칵테일|바\(BAR\)|^바$|위스키|전통주|술집|포장마차|이자카야|맥주|요리주점|케이크|샐러드바|뷔페")

GRAPHQL = "https://api.place.naver.com/graphql"
LIST_QUERY = (
    "query getRestaurants($input: RestaurantListInput) { restaurants: restaurantList(input: $input) "
    "{ total items { id name category x y roadAddress commonAddress visitorReviewScore visitorReviewCount newOpening } } }"
)


def distance(lat, lon):
    a, b = map(math.radians, CENTER)
    la, lo = map(math.radians, (lat, lon))
    h = math.sin((la - a) / 2) ** 2 + math.cos(la) * math.cos(a) * math.sin((lo - b) / 2) ** 2
    return 6371000 * 2 * math.asin(math.sqrt(h))


def post(payload):
    req = urllib.request.Request(
        GRAPHQL, data=json.dumps(payload).encode(),
        headers={"User-Agent": UA, "Content-Type": "application/json", "Referer": "https://m.place.naver.com/"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return json.load(r)


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Referer": "https://m.place.naver.com/"})
    with urllib.request.urlopen(req, timeout=20) as r:
        return r.read().decode("utf-8", "replace")


def number(text):
    if text in (None, ""):
        return None
    return float(str(text).replace(",", ""))


def list_places():
    found = {}
    for query in QUERIES:
        for start in range(1, MAX_PER_QUERY + 1, PAGE):
            variables = {"input": {"query": query, "x": str(CENTER[1]), "y": str(CENTER[0]), "start": start,
                                   "display": PAGE, "bounds": BOUNDS, "deviceType": "mobile", "isNmap": False}}
            data = post([{"operationName": "getRestaurants", "variables": variables, "query": LIST_QUERY}])
            items = (data[0].get("data") or {}).get("restaurants", {}).get("items") or []
            for it in items:
                found.setdefault(it["id"], it)
            print(f"  {query} {start}: {len(items)}곳 (누적 {len(found)})", file=sys.stderr)
            time.sleep(1)
            if len(items) < PAGE:
                break
    return list(found.values())


def menus(place_id):
    html = get(f"https://m.place.naver.com/restaurant/{place_id}/menu/list")
    m = re.search(r"window.__APOLLO_STATE__\s*=\s*(\{.*?\});\s*window\.", html, re.S)
    if not m:
        return []
    state = json.loads(m.group(1))
    out = []
    for key, value in state.items():
        if not key.startswith("PlaceMenuItem:") or not value.get("name"):
            continue
        # price: {"priceType": "fixed", "displayText": "18,000원"} — 변동가·시가는 숫자가 없다
        price = value.get("price") or {}
        digits = re.sub(r"[^0-9]", "", price.get("displayText") or "") if price.get("priceType") == "fixed" else ""
        out.append({"name": value["name"].strip(), "price_krw": int(digits) if digits else None,
                    "representative": "repr" in (value.get("badges") or [])})
    return out


def main():
    with_menu = "--no-menu" not in sys.argv
    rows = []
    for it in list_places():
        lat, lon = float(it["y"]), float(it["x"])
        score, reviews = number(it.get("visitorReviewScore")), number(it.get("visitorReviewCount"))
        if distance(lat, lon) > RADIUS_M or score is None or score < 4 or (reviews or 0) < MIN_REVIEWS:
            continue
        if SKIP_CATEGORY.search(it.get("category") or ""):
            continue
        rows.append({
            "id": it["id"], "name": it["name"], "category": it.get("category") or "",
            "lat": lat, "lon": lon,
            "address": " ".join(p for p in (it.get("commonAddress"), it.get("roadAddress")) if p),
            "naver_visitor_score": score, "naver_visitor_reviews": int(reviews),
            "new_opening": bool(it.get("newOpening")),
        })
    rows.sort(key=lambda r: distance(r["lat"], r["lon"]))
    print(f"반경·평점·리뷰 조건 통과: {len(rows)}곳", file=sys.stderr)
    if with_menu:
        for i, row in enumerate(rows, 1):
            try:
                row["menus"] = menus(row["id"])
            except Exception as error:  # 한 곳 실패로 전체를 멈추지 않는다
                row["menus"] = []
                row["menu_error"] = str(error)
            print(f"  메뉴 {i}/{len(rows)} {row['name']}: {len(row['menus'])}개", file=sys.stderr)
            time.sleep(1)
    OUT.write_text(json.dumps({"collected": time.strftime("%Y-%m-%d"), "radius_m": RADIUS_M,
                               "min_score": 4.0, "min_reviews": MIN_REVIEWS, "restaurants": rows},
                              ensure_ascii=False, indent=1) + "\n")
    print(f"저장: {OUT.relative_to(ROOT)}", file=sys.stderr)


if __name__ == "__main__":
    main()
