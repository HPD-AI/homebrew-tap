# typed: false
# frozen_string_literal: true

require "json"

class HpdosBeta < Formula
  desc "Interactive HPD-OS coding TUI powered by HPD-Agent"
  homepage "https://github.com/HPD-AI/HPD-OS"
  version "0.1.0-beta.1"
  url "https://github.com/HPD-AI/homebrew-tap", using: :git, branch: "main"

  def release_tag
    "hpdos-tui-v#{version}"
  end

  def artifact_name
    if OS.mac?
      Hardware::CPU.arm? ? "hpdos-osx-arm64.tar.gz" : "hpdos-osx-x64.tar.gz"
    elsif OS.linux?
      Hardware::CPU.arm? ? "hpdos-linux-arm64.tar.gz" : "hpdos-linux-x64.tar.gz"
    else
      odie "Unsupported platform for HPDOS release binary."
    end
  end

  def github_token
    env_token = ENV["HOMEBREW_GITHUB_API_TOKEN"] || ENV["GITHUB_TOKEN"] || ENV["GH_TOKEN"]
    return env_token.to_s.strip unless env_token.to_s.strip.empty?

    return "" unless which("gh")

    token = Utils.safe_popen_read("gh", "auth", "token", "-h", "github.com").strip
    token.empty? ? "" : token
  rescue StandardError
    ""
  end

  def github_headers
    token = github_token
    headers = [
      "--header", "Accept: application/vnd.github+json",
      "--header", "X-GitHub-Api-Version: 2022-11-28",
    ]
    headers << "--header" << "Authorization: Bearer #{token}" unless token.empty?
    headers
  end

  def download_from_gh
    return false unless which("gh")

    system(
      "gh",
      "release",
      "download",
      release_tag,
      "--repo",
      "HPD-AI/HPD-OS",
      "--pattern",
      artifact_name,
      "--output",
      artifact_name,
      "--clobber",
    )
  end

  def download_from_api
    release_url = "https://api.github.com/repos/HPD-AI/HPD-OS/releases/tags/#{release_tag}"
    release_json = Utils.safe_popen_read(
      "curl",
      "--fail",
      "--silent",
      "--show-error",
      "--location",
      *github_headers,
      release_url,
    )
    release = JSON.parse(release_json)

    asset = Array(release["assets"]).find { |entry| entry["name"] == artifact_name }
    odie "Release asset #{artifact_name} was not found in #{release_tag}." unless asset

    Utils.safe_popen_read(
      "curl",
      "--fail",
      "--location",
      "--silent",
      "--show-error",
      "--output",
      artifact_name,
      "--header",
      "Accept: application/octet-stream",
      *github_headers,
      asset["url"],
    )
  end

  def install
    downloaded = download_from_gh

    unless downloaded && File.exist?(artifact_name)
      begin
        download_from_api
      rescue StandardError => error
        token = github_token
        token_hint = if token.empty?
          <<~HINT
            
            This repo appears to require authenticated access. Set one of these before install:
              HOMEBREW_GITHUB_API_TOKEN
              GITHUB_TOKEN
              GH_TOKEN

            Example:
              export GITHUB_TOKEN="$(gh auth token -h github.com)"
              brew install hpdos-beta
          HINT
        else
          ""
        end

        odie <<~MSG
          Failed to download #{artifact_name} from #{release_tag}: #{error.message}#{token_hint}
        MSG
      end
    end

    odie <<~MSG unless File.exist?(artifact_name)
      Failed to download #{artifact_name} from release #{release_tag}.
      Ensure your network and GitHub authentication are available, then retry.
    MSG

    case artifact_name
    when /\.tar\.gz$/
      system "tar", "-xzf", artifact_name
    when /\.zip$/
      system "unzip", "-q", artifact_name
    else
      odie "Unsupported archive format for #{artifact_name}."
    end

    binary = Dir["**/hpdos", "**/hpdos.exe"].find do |path|
      File.file?(path) && File.executable?(path)
    end
    odie "Downloaded archive did not contain an executable binary." unless binary

    bin.install binary
  end

  test do
    assert_match "HPDOS", shell_output("#{bin}/hpdos --help")
  end
end
