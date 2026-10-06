#!/usr/bin/env python3
"""Build the reviewed, source-attributed app catalog from local research.

수집 지역과 지역별 보정값(기준 좌표, 제외·대표 메뉴 지정, 주소 보정)은 research/area.json 에
둔다. research/ 는 지역이 드러나므로 저장소에 넣지 않는다.
"""
import json
import math
import re
from pathlib import Path
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
RESEARCH = ROOT / "research"
SOURCE = RESEARCH / "restaurants.json"
AREA = json.loads((RESEARCH / "area.json").read_text())
CENTER = tuple(AREA["center"])
RADIUS_M = AREA.get("radius_m", 1000)
TODAY = AREA["today"]


def distance(lat, lon):
    a = math.sin(math.radians(lat - CENTER[0]) / 2) ** 2
    a += math.cos(math.radians(CENTER[0])) * math.cos(math.radians(lat)) * math.sin(math.radians(lon - CENTER[1]) / 2) ** 2
    return 6371000 * 2 * math.atan2(math.sqrt(a), math.sqrt(max(0, 1 - a)))


def maps_query(name):
    return "https://www.google.com/maps/search/?api=1&query=" + quote(name + " 서울")


meal = re.compile(r"국밥|국수|곰탕|설렁탕|육개장|탕밥|매운탕|복지리|냉면|막국수|소면|라멘|라면|파스타|피자|콰트로 살루미|버거|샌드위치|김밥|덮밥|볶음밥|비빔밥|솥밥|찌개|샤브|정식|스튜|오코노미야끼|야끼소바|소바|초밥|스시|떡국|마라탕|뷔페|타코라이스|오므라이스|카츠|돈까스|돈가스|짬뽕|짜장|뇨끼|리조또|우동|감자탕|오코노미|비빔면|칼국수|쌀국수|반미|한상|물회|전골|도시락|김치찜|제육볶음|낙지볶음|청국장")
side = re.compile(r"추가|사리|포장|하이볼|맥주|소주|와인|칵테일|에이드|음료|커피|아메리카노|샐러드|감자튀김|튀김\(|튀김\s*$|만두\s*$|전\s*$|스테이크\s*$|그릴|\b[소중대]\b|100g|150g|160g|180g|200g|250g|2인|3인|4인|디저트|사이드|치즈바|주먹밥|볶음밥\(김치|후무스|타르타르")
skip_names = set(AREA.get("skip_names", []))
preferred = AREA.get("preferred", {})



def ratings_ok(naver, google):
    """앱의 Restaurant.ratingsOK 와 같은 기준. 공개 평점이 하나 이상, 모두 4.0 이상."""
    ratings = [r for r in (naver, google) if r is not None]
    return bool(ratings) and all(r >= 4 for r in ratings)


def valid_menu(name, price):
    return isinstance(price, int) and 0 < price < 30000 and meal.search(name) and not side.search(name)


existing = {r["id"]: r for r in json.loads(SOURCE.read_text())
            if r["id"] in set(AREA.get("keep_ids", []))}
catalog = list(existing.values())
seen = {r["id"] for r in catalog}
audit = {"source_rows": 0, "outside_radius": 0, "low_or_missing_rating": 0, "unmatched_google_place": 0, "meal_or_price_unverified": 0,
         "included_source": 0, "new_eligible": 0, "new_pending": 0}

for row in json.loads((RESEARCH / "within-radius.json").read_text()):
    audit["source_rows"] += 1
    if distance(row["lat"], row["lon"]) > RADIUS_M:
        audit["outside_radius"] += 1
        continue
    if not ratings_ok(row.get("naver_visitor_score"), row.get("google_rating")):
        audit["low_or_missing_rating"] += 1
        continue
    if (row.get("google_match_distance_m") or 0) > 100:
        audit["unmatched_google_place"] += 1
        continue
    if row["name"] in skip_names:
        audit["meal_or_price_unverified"] += 1
        continue
    choices = [m for m in row.get("menus", []) if valid_menu(m["name"], m.get("price_krw"))]
    choice = next((m for m in choices if m["name"] == preferred.get(row["name"])), None)
    if choice is None:
        choice = next((m for m in choices if "대표" in m["name"] or "점심" in m["name"]), None)
    if choice is None and choices:
        choice = choices[0]
    if choice is None:
        audit["meal_or_price_unverified"] += 1
        continue
    data = {
        "id": row["id"], "name": row["name"], "category": row["category"],
        "address": row["address_road"], "menu": choice["name"],
        "price": choice["price_krw"], "latitude": row["lat"], "longitude": row["lon"],
        "naverRating": row.get("naver_visitor_score"), "googleRating": row.get("google_rating"),
        "naverReviews": row.get("naver_visitor_reviews"), "googleReviews": row.get("google_reviews"),
        "naverURL": "https://m.search.naver.com/search.naver?query=" + quote(row["name"]),
        "googleURL": maps_query(row["name"]),
        "priceURL": row.get("url") or "https://seoulrestaurants.com/data/",
        "ratingSourceURL": row.get("url") or "https://seoulrestaurants.com/data/",
        "checkedAt": row["verified"],
        "priceCheckedAt": row["verified"],
        "note": "SeoulRestaurants 2026-08 검증 자료 · CC BY 4.0. 방문 전 메뉴와 평점을 확인하세요.",
    }
    if data["id"] not in seen:
        catalog.append(data)
        seen.add(data["id"])
        audit["included_source"] += 1

# Naver explicitly marks these places as 새로오픈.  A missing
# Google score may be null; those restaurants enter the draw on their Naver
# score alone, and stay pending only when neither score is public yet.
for line in (RESEARCH / "newly-opened.tsv").read_text().splitlines():
    if not line.strip():
        continue
    fields = line.split("|")
    if len(fields) != 10:
        raise ValueError(f"Expected 10 columns, got {len(fields)}: {fields[0]}")
    ident, name, lat, lon, naver, nreviews, menu_name, price, google, greviews = fields
    lat, lon, price = float(lat), float(lon), int(price)
    if distance(lat, lon) > RADIUS_M:
        raise ValueError(f"Outside radius: {name}")
    if ident in AREA.get("never_recommend", []):
        # Keep the research row, but never recommend it or label it 'pending'.
        audit["low_or_missing_rating"] += 1
        continue
    google_rating = float(google) if google else None
    naver_rating = float(naver) if naver else None
    url = f"https://m.place.naver.com/restaurant/{ident}/home"
    menu_url = f"https://m.place.naver.com/restaurant/{ident}/menu/list"
    data = {
        "id": "naver-" + ident, "name": name, "category": "새로오픈",
        "address": "서울 · 정확한 주소는 네이버 지도에서 확인", "menu": menu_name or "메뉴·가격 확인 중",
        "price": price, "latitude": lat, "longitude": lon,
        "naverRating": naver_rating, "googleRating": google_rating,
        "naverReviews": int(nreviews), "googleReviews": int(greviews) if greviews else None,
        "naverURL": url, "googleURL": maps_query(name), "priceURL": menu_url,
        "ratingSourceURL": maps_query(name) if google_rating is not None else None,
        "checkedAt": TODAY, "priceCheckedAt": TODAY if price else None,
        "newOpenCheckedAt": TODAY, "openingURL": url, "tags": ["새로오픈"],
        "note": "네이버 새로오픈 표시 확인. 구글 평점이 없으면 네이버 평점으로 판단합니다.",
    }
    if ident in AREA.get("addresses", {}):
        data["address"] = AREA["addresses"][ident]
    if ident in AREA.get("price_pending", []):
        data["note"] = "네이버 새로오픈 확인. 1인 식사 메뉴의 정확한 가격 확인 중."
    if data["id"] not in seen:
        catalog.append(data)
        seen.add(data["id"])
        audit["new_eligible" if ratings_ok(naver_rating, google_rating) and 0 < price < 30000 else "new_pending"] += 1

# Restaurants within the radius collected by collect-naver.py: Naver visitor
# score 4.0+ with 50+ reviews.  Google is not checked here, so the app judges
# them on the Naver score alone.  Places already in the catalog under another
# source id are matched by a nearby location and a shared name prefix.
def distance_between(lat1, lon1, lat2, lon2):
    a = math.sin(math.radians(lat2 - lat1) / 2) ** 2
    a += math.cos(math.radians(lat1)) * math.cos(math.radians(lat2)) * math.sin(math.radians(lon2 - lon1) / 2) ** 2
    return 6371000 * 2 * math.atan2(math.sqrt(a), math.sqrt(max(0, 1 - a)))


def same_place(a, lat, lon, name):
    key = lambda s: re.sub(r"\s|본점|직영점|\S+점$", "", s)[:4]
    return distance_between(a["latitude"], a["longitude"], lat, lon) < 80 and key(a["name"]) == key(name)


nearby_file = RESEARCH / "naver-nearby.json"
nearby = json.loads(nearby_file.read_text()) if nearby_file.exists() else {"restaurants": []}
for key in ("nearby_rows", "nearby_duplicate", "nearby_no_meal_price", "nearby_included"):
    audit[key] = 0
for row in nearby["restaurants"]:
    audit["nearby_rows"] += 1
    ident = "naver-" + row["id"]
    if ident in seen or any(same_place(r, row["lat"], row["lon"], row["name"]) for r in catalog):
        audit["nearby_duplicate"] += 1
        continue
    menus = row.get("menus") or []
    # 고깃집의 2~3천원 볶음밥·마라탕 100g 기본값처럼 한 끼가 아닌 값을 거른다. 김밥·분식집만 예외.
    floor = 0 if re.search(r"김밥|분식|오니기리", row["category"] or "") else 5000
    choices = [m for m in menus if valid_menu(m["name"], m.get("price_krw")) and m["price_krw"] >= floor]
    choice = next((m for m in choices if m.get("representative")), None) or (choices[0] if choices else None)
    if choice is None:
        # 식사 메뉴 이름 규칙에 안 맞아도 네이버가 '대표'로 표시한 단품이면 받아준다.
        choice = next((m for m in menus if m.get("representative") and m.get("price_krw")
                       and 5000 <= m["price_krw"] < 30000 and not side.search(m["name"])), None)
    if choice is None:
        audit["nearby_no_meal_price"] += 1
        continue
    url = f"https://m.place.naver.com/restaurant/{row['id']}/home"
    data = {
        "id": ident, "name": row["name"], "category": row["category"] or "기타",
        "address": row.get("address") or "서울 · 정확한 주소는 네이버 지도에서 확인",
        "menu": choice["name"], "price": choice["price_krw"],
        "latitude": row["lat"], "longitude": row["lon"],
        "naverRating": row["naver_visitor_score"], "googleRating": None,
        "naverReviews": row["naver_visitor_reviews"], "googleReviews": None,
        "naverURL": url, "googleURL": maps_query(row["name"]),
        "priceURL": f"https://m.place.naver.com/restaurant/{row['id']}/menu/list",
        "ratingSourceURL": url,
        "checkedAt": nearby["collected"], "priceCheckedAt": nearby["collected"],
        "note": "네이버 플레이스 방문자 평점·메뉴 기준. 구글 평점은 아직 대조하지 않았습니다.",
    }
    if row.get("new_opening"):
        data["tags"] = ["새로오픈"]
        data["newOpenCheckedAt"] = nearby["collected"]
        data["openingURL"] = url
    catalog.append(data)
    seen.add(ident)
    audit["nearby_included"] += 1

catalog.sort(key=lambda r: (distance(r["latitude"], r["longitude"]), r["name"]))
SOURCE.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n")
audit["total_catalog"] = len(catalog)
audit["eligible"] = sum(0 < r["price"] < 30000 and distance(r["latitude"], r["longitude"]) <= RADIUS_M and ratings_ok(r.get("naverRating"), r.get("googleRating")) for r in catalog)
(RESEARCH / "scan-summary.json").write_text(json.dumps(audit, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(audit, ensure_ascii=False))
