#!/bin/bash
# 앱 번들을 만든다. Supabase 연결 정보는 저장소에 두지 않고 config.local.json 에서 읽어
# 번들의 Info.plist 에만 넣는다.
#
#   config.local.json: {"supabaseURL": "https://<ref>.supabase.co", "supabaseKey": "sb_publishable_..."}
set -euo pipefail
cd "$(dirname "$0")/.."
config="${LUNCH_DRAW_CONFIG:-config.local.json}"
[[ -f "$config" ]] || { echo "$config 가 없습니다. config.example.json 을 복사해 값을 채우세요." >&2; exit 1; }
url="$(/usr/bin/plutil -extract supabaseURL raw -o - "$config")"
key="$(/usr/bin/plutil -extract supabaseKey raw -o - "$config")"
[[ "$key" != sb_secret_* ]] || { echo "secret 키는 넣을 수 없습니다. publishable 키를 쓰세요." >&2; exit 1; }

if [[ "${1:-}" != "--skip-build" ]]; then
  swift build -c release --disable-sandbox --product lunch-draw
fi
app_dir="build/Lunch Draw.app"
rm -rf "$app_dir"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp .build/release/lunch-draw "$app_dir/Contents/MacOS/lunch-draw"
cp Resources/Info.plist "$app_dir/Contents/Info.plist"
cp Resources/AppIcon.icns "$app_dir/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Add :LunchDrawSupabaseURL string $url" -c "Add :LunchDrawSupabaseKey string $key" "$app_dir/Contents/Info.plist"
codesign --force --sign - "$app_dir"
printf '%s\n' "$app_dir"
