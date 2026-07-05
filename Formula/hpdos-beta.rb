# typed: false
# frozen_string_literal: true

class HpdosBeta < Formula
  desc "Interactive HPD-OS coding TUI powered by HPD-Agent"
  homepage "https://github.com/HPD-AI/HPD-OS"
  version "0.1.0-beta.1"

  on_macos do
    if Hardware::CPU.arm?
      url "https://github.com/HPD-AI/HPD-OS/releases/download/hpdos-tui-v#{version}/hpdos-osx-arm64.tar.gz"
      sha256 "298fcd34290496cbaec536f6bbde6bd29b8ea704f8eed5411b88428a8cc3a531"
    else
      url "https://github.com/HPD-AI/HPD-OS/releases/download/hpdos-tui-v#{version}/hpdos-osx-x64.tar.gz"
      sha256 "5d1067fc982bff0c6015b2a1a00899c63b574db0a923a13c4506ba8dcc5f79f7"
    end
  end

  on_linux do
    if Hardware::CPU.arm? && Hardware::CPU.is_64_bit?
      url "https://github.com/HPD-AI/HPD-OS/releases/download/hpdos-tui-v#{version}/hpdos-linux-arm64.tar.gz"
      sha256 "f1d92da27810d5d17ae894b67d56c6e47c4b9d3f37a408ced0b36f4d5b5aa078"
    else
      url "https://github.com/HPD-AI/HPD-OS/releases/download/hpdos-tui-v#{version}/hpdos-linux-x64.tar.gz"
      sha256 "174c5f38ac7fc22cccb6f1f6777fca70cb09f447f1062585395bd2a09e683061"
    end
  end

  def install
    bin.install "hpdos" => "hpdos-beta"
    bin.install_symlink "hpdos-beta" => "hpdos"
    bin.install_symlink "hpdos-beta" => "hpd"
  end

  test do
    assert_predicate bin/"hpdos-beta", :exist?
    assert_match version.to_s, shell_output("#{bin}/hpdos-beta update")
  end
end
