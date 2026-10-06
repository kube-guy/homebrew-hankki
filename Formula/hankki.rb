class Hankki < Formula
  desc "Choose family and baby meals from ingredients in your pantry"
  homepage "https://github.com/kube-guy/homebrew-hankki"
  url "https://github.com/kube-guy/homebrew-hankki/archive/refs/tags/hankki-v0.3.0.tar.gz"
  version "0.3.0"
  # 태그를 만든 뒤 아카이브의 SHA-256 으로 바꾼다. README 의 "Homebrew 배포" 참고.
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  # Command Line Tools 의 Swift 로 빌드된다. Xcode 전체를 요구하지 않는다.
  depends_on macos: :sonoma

  def install
    cd "hankki" do
      system "swift", "build", "-c", "release", "--disable-sandbox", "--product", "hankki"
      app = libexec/"Hankki.app"
      (app/"Contents/MacOS").mkpath
      (app/"Contents/MacOS").install ".build/release/hankki"
      (app/"Contents").install "Resources/Info.plist"
      # Supabase 연결 정보는 설치본에 넣지 않는다. ~/.config/hankki/config.json 에서 읽는다.
      system "codesign", "--force", "--sign", "-", app
      pkgshare.install "config.example.json"
    end

    (bin/"hankki").write <<~SH
      #!/bin/bash
      app="#{libexec}/Hankki.app"
      case "${1:-}" in
        --version|--help|--self-check)
          exec "$app/Contents/MacOS/hankki" "$@" ;;
        *) exec /usr/bin/open -a "$app" --args "$@" ;;
      esac
    SH
  end

  def caveats
    <<~EOS
      실행: hankki

      기기 간 동기화를 쓰려면 Supabase 연결 정보를 한 번 설정하세요:
        mkdir -p ~/.config/hankki
        cp #{opt_pkgshare}/config.example.json ~/.config/hankki/config.json
        chmod 600 ~/.config/hankki/config.json   # supabaseURL·supabaseKey 값을 채웁니다
      설정하지 않아도 이 Mac 에 저장하며 사용할 수 있습니다.
    EOS
  end

  test do
    assert_match "hankki #{version}", shell_output("#{bin}/hankki --version")
    assert_match "PASS", shell_output("#{bin}/hankki --self-check")
  end
end
