# 한 끼 꾸러미

냉장고에 있는 재료로 가족과 아기 메뉴를 고르는 작은 앱입니다. macOS에서 Homebrew로 설치하고 브라우저로 사용합니다.

## 설치

```sh
brew tap kube-guy/hankki
brew install hankki
hankki
```

`http://localhost:4173`이 열립니다. 종료는 터미널에서 `Ctrl+C`를 누르세요.

```sh
brew services start hankki   # 로그인 시 자동 실행
brew services stop hankki    # 자동 실행 중지
brew update && brew upgrade hankki
```

이미 4173 포트를 쓰는 앱이 있으면 `hankki --port 4174`를 사용할 수 있습니다. 클라우드 로그인은 Supabase에 등록한 리다이렉트 주소에서만 사용할 수 있습니다.

## 문장으로 재료 관리

- `당근이랑 양파 추가해줘`
- `우유는 다 먹었어`
- `달걀은 항상 있어`
- `당근 추가하고, 우유 삭제하고, 계란은 상시 재료로 등록해줘`
- `달걀은 상시 재료에서 빼줘` — 오늘의 재료로 이동

재료를 먼저, 동작을 뒤에 쓰세요. 흔한 한국어 표현을 기기에서 해석하는 규칙 기반 기능입니다. 외부 AI API로 문장을 전송하지 않습니다. 질문·조건·부정·충돌하는 요청은 적용하지 않고 다시 입력하도록 안내합니다. 수량은 재고 수량으로 추적하지 않으며 재료의 보유 여부만 관리합니다. `계란`은 `달걀`로 통일합니다. 새로운 재료 이름도 등록할 수 있지만 추천은 기본 레시피 16가지에 등록된 재료를 기준으로 합니다.

상시 재료는 매번 선택할 필요가 없고, 오늘 재료를 비워도 유지됩니다. `다 먹었어` 또는 `삭제`는 상시 목록에서도 제거합니다. 방금 문장으로 변경한 내용은 되돌릴 수 있습니다.

## 장보기 목록

추천 결과나 레시피 상세에서 **부족한 재료 담기**를 누르면 그 메뉴에 없는 재료가 장보기 목록에 담깁니다. 직접 입력할 때는 `두부, 시금치`처럼 쉼표나 띄어쓰기로 구분하세요. 어느 메뉴 때문에 담았는지, 이미 냉장고에 있는지 함께 표시합니다.

산 재료를 체크하고 **산 재료 냉장고에 넣기**를 누르면 오늘 재료로 옮겨지고 목록에서 빠집니다. 상시 재료는 이미 있으므로 목록에서만 뺍니다. **목록 복사**로 메신저나 메모에 붙여 넣을 수 있습니다. 장보기 목록은 이 기기에만 저장되며 클라우드로 동기화하지 않습니다.

## 동기화

우측 위 **동기화**에서 이메일 로그인 링크를 받으세요. 같은 Supabase 프로젝트와 같은 계정으로 로그인한 기기끼리 오늘 재료·상시 재료·찜을 공유합니다. 처음 연결할 때 기기 목록을 합치거나 클라우드 목록을 불러올 수 있습니다. 로그인하지 않아도 기기 내 저장 기능은 작동합니다.

변경 사항은 바로 전송하고, 화면이 열려 있으면 10초마다 다른 기기의 변경 사항을 확인합니다. 오프라인 변경은 해당 계정의 전송 대기열에 저장했다가 재연결 시 반영합니다. 서로 다른 재료 수정은 합치며 같은 재료를 동시에 수정하면 서버에 나중에 적용된 변경이 우선합니다. 요청 ID로 재전송을 중복 처리하지 않습니다. 로그아웃은 대기 중인 전송이 끝난 뒤 할 수 있고, 이 기기의 재료·찜은 비웁니다. 클라우드 데이터는 유지됩니다.

브라우저 데이터 삭제 시 아직 전송하지 못한 변경은 사라질 수 있습니다. 아기 연령과 알레르기 필터는 방문 중에만 적용되며 클라우드로 전송하지 않습니다.

## 자체 Supabase 프로젝트에 연결

1. `supabase/migrations/202610010001_hankki.sql`을 SQL Editor에서 실행합니다.
2. `dist/config.js`의 `supabaseUrl`과 `supabasePublishableKey`를 설정합니다. **publishable 또는 anon 키만** 넣으세요. 관리자 `service_role`, secret 키, 데이터베이스 비밀번호는 넣지 마세요.
3. Authentication → URL Configuration에서 Site URL을 `http://localhost:4173`으로, Redirect URLs에 `http://localhost:4173/`을 등록합니다.
4. 기본 이메일 로그인은 Magic Link 방식입니다. Supabase 기본 발송 서비스는 수신자·발송량에 제한이 있으므로 여러 사용자를 운영하려면 자체 SMTP를 설정하세요.

사용자별 RLS와 로그인 사용자만 호출 가능한 저장 함수를 사용합니다. 원격 사용자나 관리자 인증정보는 설치 파일에 들어가지 않습니다. 공개 클라이언트 키 자체는 비밀이 아니며 데이터 접근 제어는 RLS에서 처리합니다.

## 개발

Node.js 22 이상을 권장합니다.

```sh
npm ci
npm test
npm run build
npm start
```

설치본은 미리 빌드된 정적 파일과 Node 서버를 사용하므로 `npm install`이 필요하지 않습니다. 서버는 `127.0.0.1`에만 바인딩하며 허용되지 않은 Host 헤더를 거부합니다.

### Homebrew 배포

`Formula/hankki.rb`가 설치 정의입니다. Node.js를 의존성으로 설치하고, 저장소의 `bin`과 미리 빌드된 `dist`를 사용합니다. 자동 실행 시에는 브라우저를 열지 않습니다.

현재 Formula는 앱 버전 0.2.0의 커밋 아카이브와 SHA-256을 고정합니다. 다음 버전을 배포할 때는 먼저 테스트와 빌드를 완료하고 앱 코드를 공개한 뒤, Formula의 `url`, `version`, `sha256`을 해당 아카이브에 맞게 갱신하세요. `dist/sync.js`도 빌드 결과를 함께 커밋해야 합니다.

Formula 변경을 검증하려면 변경 브랜치를 tap으로 연결한 환경에서 아래를 실행합니다.

```sh
brew install --build-from-source kube-guy/hankki/hankki
brew test kube-guy/hankki/hankki
```

## 같은 tap 의 다른 앱

- **lunch-draw** — 기준 지점 근처 평점 4.0 이상 식당을 랜덤으로 추천하는 macOS 앱.
  `brew install kube-guy/hankki/lunch-draw`. 설정과 설명은 [lunch-draw/README.md](lunch-draw/README.md).

## 아기 메뉴

연령은 참고용입니다. 만 0세 메뉴는 이유식을 시작한 아이를 전제로 하며 발달·이미 먹어본 재료·음식 질감을 함께 확인해야 합니다. 레시피의 재료량은 1회 권장 섭취량이 아닙니다. 영양 처방이나 완전한 식단 구성 도구가 아닙니다.

- [CDC 이유식 시작 안내](https://www.cdc.gov/infant-toddler-nutrition/foods-and-drinks/when-what-and-how-to-introduce-solid-foods.html)
- [CDC 질식 예방](https://www.cdc.gov/infant-toddler-nutrition/foods-and-drinks/choking-hazards.html)
- [사진: Vicky Ng / Unsplash](https://unsplash.com/photos/8hCcjf2BxTk)
- [Supabase 이메일 로그인](https://supabase.com/docs/guides/auth/auth-email-passwordless)
- [Homebrew Tap 안내](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)

글꼴과 사진은 외부 서비스에서 불러옵니다. 앱 기능은 인터넷 없이도 사용할 수 있지만 클라우드 동기화와 외부 이미지는 연결이 필요합니다.
