# 한 끼 꾸러미

냉장고에 있는 재료로 가족과 아기 메뉴를 고르는 macOS 앱입니다. Swift(SwiftUI)로 만든 네이티브 앱이며 Homebrew로 설치합니다.

## 설치

```sh
brew tap kube-guy/hankki
brew install hankki
hankki
```

macOS 14(Sonoma) 이상이 필요합니다. 소스에서 빌드하므로 Command Line Tools의 Swift가 있어야 합니다(`xcode-select --install`). Xcode 전체는 필요하지 않습니다.

```sh
brew update && brew upgrade hankki
hankki --version
hankki --self-check   # 내장 점검. 마지막 줄이 PASS면 정상
```

0.2.0까지의 브라우저판에서 넘어오는 경우, 브라우저에 저장된 재료는 옮겨지지 않습니다. 동기화를 쓰고 있었다면 같은 이메일로 로그인해 **클라우드 재료 불러오기**를 고르세요.

## 문장으로 재료 관리

- `당근이랑 양파 추가해줘`
- `우유는 다 먹었어`
- `달걀은 항상 있어`
- `당근 추가하고, 우유 삭제하고, 계란은 상시 재료로 등록해줘`
- `달걀은 상시 재료에서 빼줘` — 오늘의 재료로 이동

재료를 먼저, 동작을 뒤에 쓰세요. 흔한 한국어 표현을 Mac 안에서 해석하는 규칙 기반 기능이며 문장을 외부로 보내지 않습니다. 질문·조건·부정·충돌하는 요청은 적용하지 않고 다시 입력하도록 안내합니다. 수량은 추적하지 않고 재료의 보유 여부만 관리합니다. `계란`은 `달걀`로 통일합니다. 새로운 재료 이름도 등록할 수 있지만 추천은 기본 레시피 16가지에 등록된 재료를 기준으로 합니다.

상시 재료는 매번 선택할 필요가 없고, 오늘 재료를 비워도 유지됩니다. `다 먹었어` 또는 `삭제`는 상시 목록에서도 제거합니다. 방금 문장으로 변경한 내용은 되돌릴 수 있습니다.

## 장보기 목록

추천 결과나 레시피 상세에서 **부족한 재료 담기**를 누르면 그 메뉴에 없는 재료가 장보기 목록에 담깁니다. 직접 입력할 때는 `두부, 시금치`처럼 쉼표나 띄어쓰기로 구분하세요. 어느 메뉴 때문에 담았는지, 이미 냉장고에 있는지 함께 표시합니다.

산 재료를 체크하고 **산 재료 냉장고에 넣기**를 누르면 오늘 재료로 옮겨지고 목록에서 빠집니다. 상시 재료는 이미 있으므로 목록에서만 뺍니다. **목록 복사**로 메신저나 메모에 붙여 넣을 수 있습니다. 장보기 목록은 이 Mac에만 저장되며 클라우드로 동기화하지 않습니다.

## 저장과 동기화

재료·상시 재료·찜·장보기 목록은 `~/Library/Application Support/Hankki/kitchen.json`에 저장합니다. 아기 연령은 만 2세 이상으로 고정해 아기 메뉴를 모두 보여 줍니다. 알레르기 필터는 앱을 켜 둔 동안만 적용되며 저장하거나 전송하지 않습니다.

우측 위 **동기화**에서 이메일로 받은 로그인 코드를 입력하면, 같은 계정으로 로그인한 기기끼리 오늘 재료·상시 재료·찜을 공유합니다. 처음 연결할 때 이 Mac의 재료를 합치거나 클라우드 목록을 불러올 수 있습니다.

변경 사항은 바로 전송하고, 창이 앞에 있으면 10초마다 다른 기기의 변경을 확인합니다. 오프라인 변경은 계정별 전송 대기열(`sync-<사용자 ID>.json`)에 저장했다가 다시 연결되면 보냅니다. 서로 다른 재료 수정은 합치며 같은 재료를 동시에 수정하면 서버에 나중에 적용된 변경이 우선합니다. 요청 ID로 재전송을 중복 처리하지 않습니다. 로그아웃은 대기 중인 전송이 끝난 뒤 할 수 있고, 이 Mac의 재료·찜은 비웁니다. 클라우드 데이터와 장보기 목록은 유지됩니다.

로그인 세션은 macOS Keychain(`app.hankki.session.v1`)에 `/usr/bin/security`를 거쳐 저장합니다. 앱을 다시 빌드해 서명이 바뀌어도 키체인 접근 허용 창이 뜨지 않습니다.

## Supabase 프로젝트 연결

1. `supabase/migrations/202610010001_hankki.sql`을 SQL Editor에서 실행합니다.
2. 연결 정보를 적습니다. **publishable 또는 anon 키만** 넣으세요. `service_role`·secret 키는 앱이 거부합니다.
   ```sh
   mkdir -p ~/.config/hankki
   cp "$(brew --prefix hankki)/share/hankki/config.example.json" ~/.config/hankki/config.json
   chmod 600 ~/.config/hankki/config.json   # supabaseURL·supabaseKey 값을 채운다
   ```
   개발할 때는 환경 변수 `HANKKI_SUPABASE_URL`·`HANKKI_SUPABASE_KEY`로도 줄 수 있습니다.
3. Authentication → Email Templates의 **Magic Link** 템플릿에 `{{ .Token }}`을 넣어 6자리 로그인 코드가 메일에 보이게 합니다. 앱은 링크가 아니라 이 코드로 로그인합니다.
4. Supabase 기본 메일 발송은 수신자·발송량 제한이 있으므로 여러 사용자를 운영하려면 자체 SMTP를 설정하세요.

사용자별 RLS와 로그인 사용자만 호출 가능한 저장 함수(`apply_hankki_changes`)를 사용합니다. 공개 클라이언트 키 자체는 비밀이 아니며 데이터 접근 제어는 RLS에서 처리합니다.

## 개발

```sh
cd hankki
swift build
swift run hankki                 # 앱 실행
swift run hankki --self-check    # 문장 해석·장보기·메뉴·동기화 계산·저장 점검
```

화면과 상태는 `Sources/Hankki/`에 있습니다.

| 파일 | 내용 |
|---|---|
| `Catalog.swift` | 기본 재료 분류, 레시피 16가지, 알레르기 묶음 |
| `PantryLanguage.swift` | 한국어 문장 해석 |
| `Model.swift` | 재료 상태, 메뉴 후보 계산, 장보기 목록 |
| `Cloud.swift` | Supabase 로그인·전송, Keychain, 변경 계산 |
| `Store.swift` | 앱 상태, 저장, 동기화 대기열 |
| `Views.swift` | SwiftUI 화면 |
| `Checks.swift` | `--self-check` |

앱 아이콘은 `scripts/render-icon.py`가 그립니다(`python3 -m pip install pillow` 후 `python3 scripts/render-icon.py`). 결과인 `Resources/AppIcon.png`·`AppIcon.icns`도 커밋합니다.

### Homebrew 배포

`Formula/hankki.rb`가 설치 정의입니다. 태그 아카이브를 받아 `swift build`로 빌드하고, `Hankki.app` 번들을 만들어 ad-hoc 서명합니다. `hankki` 명령은 `open -a`로 앱을 엽니다.

1. `hankki/Sources/Hankki/Main.swift`의 `version`, `hankki/Resources/Info.plist`의 버전, Formula의 `version`·`url`을 맞춥니다.
2. main에 머지한 뒤 Formula의 `url`을 그 커밋의 아카이브(`archive/<커밋>.tar.gz`) 또는 `hankki-v<버전>` 태그 아카이브(`archive/refs/tags/hankki-v<버전>.tar.gz`)로 정합니다.
3. `curl -L <url> | shasum -a 256`으로 얻은 값을 Formula의 `sha256`에 넣어 커밋합니다.

CI(`.github/workflows/test.yml`)는 macOS에서 앱을 빌드해 `--self-check`를 돌리고, Formula의 `url`을 현재 커밋의 아카이브로 바꿔 `brew install`·`brew test`까지 확인합니다.

## 같은 tap 의 다른 앱

- **lunch-draw** — 기준 지점 근처 평점 4.0 이상 식당을 랜덤으로 추천하는 macOS 앱.
  `brew install kube-guy/hankki/lunch-draw`. 설정과 설명은 [lunch-draw/README.md](lunch-draw/README.md).

## 아기 메뉴

연령은 참고용입니다. 만 0세 메뉴는 이유식을 시작한 아이를 전제로 하며 발달·이미 먹어본 재료·음식 질감을 함께 확인해야 합니다. 레시피의 재료량은 1회 권장 섭취량이 아닙니다. 영양 처방이나 완전한 식단 구성 도구가 아닙니다.

- [CDC 이유식 시작 안내](https://www.cdc.gov/infant-toddler-nutrition/foods-and-drinks/when-what-and-how-to-introduce-solid-foods.html)
- [CDC 질식 예방](https://www.cdc.gov/infant-toddler-nutrition/foods-and-drinks/choking-hazards.html)
- [Supabase 이메일 로그인 코드](https://supabase.com/docs/guides/auth/auth-email-passwordless)
- [Homebrew Tap 안내](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)
