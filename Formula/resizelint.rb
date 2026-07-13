class Resizelint < Formula
  desc "Static analysis for Swift apps that need to work in every window size"
  homepage "https://github.com/mikonyaa/ResizeLint"
  url "https://github.com/mikonyaa/ResizeLint/releases/download/1.0.0/ResizeLint-1.0.0-source.tar.gz"
  sha256 "fea82e67b1c23fbfea201d7d326b553d98847bdfed8cf2164053f2e1be33fac1"
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
