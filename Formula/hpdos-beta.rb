class HpdosBeta < Formula
  desc "HPDOS command-line client and developer terminal toolchain (beta)"
  homepage "https://github.com/HPD-AI/HPD-OS"
  url "https://github.com/HPD-AI/HPD-OS/releases/download/hpdos-tui-v0.1.0-beta.1/hpdos-osx-x64.tar.gz"
  version "0.1.0-beta.1"
  sha256 "5d1067fc982bff0c6015b2a1a00899c63b574db0a923a13c4506ba8dcc5f79f7"

  on_macos do
    on_arm do
      url "https://github.com/HPD-AI/HPD-OS/releases/download/hpdos-tui-v0.1.0-beta.1/hpdos-osx-arm64.tar.gz"
      sha256 "298fcd34290496cbaec536f6bbde6bd29b8ea704f8eed5411b88428a8cc3a531"
    end

    on_intel do
      url "https://github.com/HPD-AI/HPD-OS/releases/download/hpdos-tui-v0.1.0-beta.1/hpdos-osx-x64.tar.gz"
      sha256 "5d1067fc982bff0c6015b2a1a00899c63b574db0a923a13c4506ba8dcc5f79f7"
    end
  end

  def install
    bin.install "hpdos"
  end

  test do
    system "#{bin}/hpdos", "--help"
  end
end
