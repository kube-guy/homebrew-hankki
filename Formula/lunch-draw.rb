class LunchDraw < Formula
  desc "Random lunch picks near a chosen origin, synced with Supabase"
  homepage "https://github.com/kube-guy/homebrew-hankki/tree/main/lunch-draw"
  url "https://github.com/kube-guy/homebrew-hankki/archive/refs/tags/lunch-draw-v0.4.0.tar.gz"
  version "0.4.0"
  sha256 "dffc8f38ec64d6b88fc1aff4bc05567c85ad8e8db952db0d062d5f42e2f12b31"

  depends_on xcode: ["16.0", :build]
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
