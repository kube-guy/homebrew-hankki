# Lunch Draw · 오늘 뭐 먹지

기준 지점 근처에서 대표 식사 메뉴가 1인 30,000원 미만이고 평점이 4.0 이상인 식당을 랜덤으로 추천하는 macOS 앱입니다.

- **평점 기준:** 네이버·구글 중 공개된 평점이 하나 이상 있어야 하고, 공개된 평점은 모두 4.0 이상이어야 합니다. 구글 평점이 아직 없는 신상은 네이버 평점으로 판단합니다.
- **기준 지점:** 모두에게 적용되는 기본 지점은 Supabase 에 저장돼 있습니다. 왼쪽 **기준 지점 → 변경**에서 Apple 지도로 장소를 검색해 바꿀 수 있고, 반경(500m~2km)도 고를 수 있습니다. 고른 지점은 내 저장 상태와 함께 Supabase 에 저장되며, **기본 지점으로 되돌리기**로 원래대로 돌아갑니다.
- **랜덤 추천:** 목록을 한 바퀴 돌 때까지 중복 추천을 줄입니다.
- **필터:** 즐겨찾기, 추천 제외, 방문 기록, 음식 종류(한식·중식·일식·양식·아시아·기타), 검색, 새로오픈만 추천을 제공합니다.
- **목록 재설정:** Supabase 에 저장된 최신 식당 목록을 다시 가져오고 제외·뽑기 기록을 초기화합니다. 이전 목록은 복원할 수 있습니다. 네이버·구글을 실시간으로 다시 검색하는 기능은 아닙니다.
- **지도:** 추천 카드 옆에 기준 지점과 추천 식당의 위치를 Apple 지도로 표시합니다.
- **자동 저장:** Mac 에 먼저 저장하고 Supabase 에 저장합니다. 연결에 실패하면 로컬 데이터를 유지하고 재시도 버튼을 표시합니다.

거리는 기준 지점에서 식당까지의 직선거리입니다. 도보거리가 아닙니다. 식당 목록은 관리자가 수집한 지역만 담고 있으므로, 기준 지점을 멀리 옮기면 추천할 식당이 없을 수 있습니다.

## 설치

```sh
brew tap kube-guy/hankki
brew install lunch-draw
mkdir -p ~/.config/lunch-draw
cp "$(brew --prefix lunch-draw)/share/lunch-draw/config.example.json" ~/.config/lunch-draw/config.json
chmod 600 ~/.config/lunch-draw/config.json   # supabaseURL·supabaseKey 값을 채운다
lunch-draw
```

소스에서 빌드하므로 Swift 6 이상이 필요합니다 (Command Line Tools 로 충분합니다). Supabase 연결 정보는 설치본에 들어 있지 않고,
`~/.config/lunch-draw/config.json` 에서 읽습니다.

## 개인정보를 저장소에 두지 않는다

이 저장소는 공개 저장소입니다. 아래 정보는 저장소에 넣지 않습니다.

| 정보 | 있는 곳 |
|---|---|
| 기본 기준 지점 (이름·좌표) | Supabase `lunch_settings` |
| 식당 목록 | Supabase `restaurants` |
| Supabase URL·publishable 키 | `~/.config/lunch-draw/config.json` (설치본) 또는 `config.local.json` (`.gitignore`, 직접 패키징할 때 Info.plist 에 들어감) |
| 수집 지역·수집 자료·지역별 보정값 | `research/` (`.gitignore`) |

publishable 키 자체는 비밀이 아니지만, 키가 있으면 익명 로그인으로 기본 지점과 식당 목록을 읽을 수 있어 공개하지 않습니다.

## Supabase

- `restaurants`: 검증한 식당 목록. 앱에서는 읽기만 가능합니다.
- `lunch_settings`: `default_origin` 행에 기본 기준 지점을 둡니다. 앱에서는 읽기만 가능합니다.
- `lunch_states`: 즐겨찾기·방문·뽑기 기록·이전 목록·내가 고른 기준 지점. 사용자별 RLS 가 적용됩니다.
- 인증 토큰은 macOS Keychain 에 저장합니다. 저장 버전이 다르면 덮어쓰지 않습니다.

처음 설정할 때는 `database/` 의 SQL 을 번호 순서대로 SQL Editor 에서 실행합니다. 기본 지점은 `002_default_origin.sql` 맨 아래 주석의 insert 문에 값을 채워 실행하면 저장되고, 같은 문장으로 언제든 바꿀 수 있습니다.

## 식당 목록 갱신 (관리자)

`research/area.json` 에 수집 기준 좌표(`center`)와 반경(`radius_m`)을 적은 뒤 실행합니다.

```sh
python3 scripts/collect-naver.py    # 네이버 플레이스: 반경 안, 방문자 평점 4.0+, 리뷰 50개+ (요청 간 1초 휴식)
python3 scripts/build-catalog.py    # 수집 자료를 research/restaurants.json 으로 합침
python3 scripts/make-upsert.py      # SQL Editor 에 붙여 넣을 research/upsert-N.sql 생성
```

카페·디저트·술집 업종은 제외합니다. 대표 메뉴는 식사 메뉴 이름 규칙에 맞는 30,000원 미만 메뉴 중 네이버가 '대표'로 표시한 것을 먼저 고릅니다. 앱의 **목록 재설정**으로 반영됩니다.

## 빌드 및 확인

```sh
cp config.example.json config.local.json   # 값 채우기
swift build -c release --disable-sandbox
bash scripts/package-app.sh --skip-build
build/'Lunch Draw.app'/Contents/MacOS/lunch-draw --self-check
build/'Lunch Draw.app'/Contents/MacOS/lunch-draw --cloud-check
```

`swift run` 으로 개발할 때는 `LUNCH_DRAW_SUPABASE_URL`, `LUNCH_DRAW_SUPABASE_KEY` 환경 변수로 연결 정보를 넘깁니다. 자체 검사(`--self-check`)는 가상의 지점과 식당으로 돌기 때문에 연결 정보 없이도 됩니다.

Apple Silicon, macOS 14 이상. 개발자 서명 인증서 없이 로컬 ad-hoc 서명을 사용합니다.
