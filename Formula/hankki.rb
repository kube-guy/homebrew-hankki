class Hankki < Formula
  desc "Choose family meals from ingredients in your pantry"
  homepage "https://github.com/kube-guy/homebrew-hankki"
  url "https://github.com/kube-guy/homebrew-hankki/archive/5d6077d71d89a227b19a127e3690c4f63c1c7df6.tar.gz"
  version "0.2.0"
  sha256 "61c35693522cc61270cb33d60a934864e231d0d28ff4b90782c2062041a71006"

  depends_on "node"

  def install
    libexec.install "bin", "dist"
    (bin/"hankki").write <<~SH
      #!/bin/sh
      exec "#{Formula["node"].opt_bin}/node" "#{libexec}/bin/hankki.cjs" "$@"
    SH
  end

  service do
    run [opt_bin/"hankki", "--no-open"]
    keep_alive true
    log_path var/"log/hankki.log"
    error_log_path var/"log/hankki.log"
  end

  test do
    assert_match "hankki #{version}", shell_output("#{bin}/hankki --version")
    port = free_port
    pid = fork do
      exec bin/"hankki", "--no-open", "--port", port.to_s
    end
    begin
      response = shell_output("curl --fail --silent --retry 10 --retry-connrefused " \
                              "--retry-delay 1 http://127.0.0.1:#{port}/health")
      assert_equal "hankki", JSON.parse(response)["app"]
      assert_match "한 끼", shell_output("curl --fail --silent http://127.0.0.1:#{port}/")
    ensure
      Process.kill "TERM", pid
      Process.wait pid
    end
  end
end
