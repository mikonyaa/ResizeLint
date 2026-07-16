class Resizelint < Formula
  desc "Static analysis for Swift apps that need to work in every window size"
  homepage "https://github.com/mikonyaa/ResizeLint"
  url "https://github.com/mikonyaa/ResizeLint/releases/download/1.0.0/ResizeLint-1.0.0-source.tar.gz"
  sha256 "4cea87f9dcc2e418f97cd3b4f5c2ac8d66f817b3a74962d92e8cef4f7328f173"
  license "MIT"

  depends_on "swift" => :build

  on_macos do
    depends_on macos: :sonoma
  end

  def install
    system "swift", "build", "--disable-sandbox", "--configuration", "release"
    bin.install ".build/release/resizelint"
  end

  test do
    assert_equal version.to_s, shell_output("#{bin}/resizelint version").strip
  end
end
