class LunchDraw < Formula
  desc "Random lunch picks near a chosen origin, synced with Supabase"
  homepage "https://github.com/kube-guy/homebrew-hankki/tree/main/lunch-draw"
  url "https://github.com/kube-guy/homebrew-hankki/archive/refs/tags/lunch-draw-v0.4.1.tar.gz"
  version "0.4.1"
  sha256 "e56ee6d79c913cb658e9b777a5d97b4b0be03fff449dc61fb6be732221d89e21"

  # Command Line Tools 의 Swift 6 으로 빌드된다. Xcode 전체를 요구하지 않는다.
  depends_on arch: :arm64
  depends_on macos: :sonoma

  def install
    cd "lunch-draw" do
      system "swift", "build", "-c", "release", "--disable-sandbox", "--product", "lunch-draw"
      app = libexec/"Lunch Draw.app"
      (app/"Contents/MacOS").mkpath
      (app/"Contents/MacOS").install ".build/release/lunch-draw"
      (app/"Contents").install "Resources/Info.plist"
      # Supabase 연결 정보는 설치본에 넣지 않는다. ~/.config/lunch-draw/config.json 에서 읽는다.
      system "codesign", "--force", "--sign", "-", app
      pkgshare.install "config.example.json"
    end

    (bin/"lunch-draw").write <<~SH
      #!/bin/bash
      app="#{libexec}/Lunch Draw.app"
      case "${1:-}" in
        --version|--self-check|--cloud-check)
          exec "$app/Contents/MacOS/lunch-draw" "$@" ;;
        *) exec /usr/bin/open -a "$app" --args "$@" ;;
      esac
    SH
  end

  def caveats
    <<~EOS
      Supabase 연결 정보를 한 번 설정하세요:
        mkdir -p ~/.config/lunch-draw
        cp #{opt_pkgshare}/config.example.json ~/.config/lunch-draw/config.json
        chmod 600 ~/.config/lunch-draw/config.json   # supabaseURL·supabaseKey 값을 채웁니다
      실행: lunch-draw
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/lunch-draw --version")
    assert_match "PASS", shell_output("#{bin}/lunch-draw --self-check")
  end
end
