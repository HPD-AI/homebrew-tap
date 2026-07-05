# typed: false
# frozen_string_literal: true

require "json"
require "etc"

class HpdosBeta < Formula
  desc "Interactive HPD-OS coding TUI powered by HPD-Agent"
  homepage "https://github.com/HPD-AI/HPD-OS"
  version "0.1.0-beta.1"
  url "https://github.com/HPD-AI/HPD-OS.git", using: :git, tag: "hpdos-tui-v#{version}"
  depends_on "gh" => :build

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

  def release_api_url
    "https://api.github.com/repos/HPD-AI/HPD-OS/releases/tags/#{release_tag}"
  end

  def release_download_url
    "https://github.com/HPD-AI/HPD-OS/releases/download/#{release_tag}/#{artifact_name}"
  end

  def gh_binary_path
    return @gh_binary_path if defined?(@gh_binary_path)

    candidates = [
      which("gh"),
      Formula["gh"]&.opt_bin&.join("gh")&.to_s,
      "/opt/homebrew/bin/gh",
      "/usr/local/bin/gh",
      "/home/linuxbrew/.linuxbrew/bin/gh",
      "/usr/bin/gh",
    ].compact

    @gh_binary_path = candidates.find { |candidate| File.executable?(candidate) }
  end

  def candidate_homes
    [
      ENV["HOME"],
      "/Users/#{ENV["USER"]}",
      "/Users/#{ENV["LOGNAME"]}",
      "/Users/#{Etc.getlogin rescue nil}",
      "/Users/ewoof",
    ].compact.uniq.select { |path| path.start_with?("/") && File.directory?(path) }
  end

  def gh_token_from_command
    return "" unless (gh = gh_binary_path)

    candidate_homes.each do |home_path|
      token = with_env(
        "HOME" => home_path,
        "GH_CONFIG_DIR" => File.join(home_path, ".config", "gh"),
      ) do
        Utils.safe_popen_read(gh, "auth", "token", "-h", "github.com").strip
      rescue StandardError
        ""
      end
      return token unless token.to_s.empty?
    end

    ""
  end

  def github_token
    token = [
      ENV["HOMEBREW_GITHUB_API_TOKEN"],
      ENV["GITHUB_TOKEN"],
      ENV["GH_TOKEN"],
    ].compact.map(&:to_s).find { |value| !value.strip.empty? }

    return token.strip unless token.to_s.empty?

    gh_token_from_command
  end

  def api_headers(token)
    headers = [
      "--header", "Accept: application/vnd.github+json",
      "--header", "X-GitHub-Api-Version: 2022-11-28",
    ]
    headers << "--header" << "Authorization: Bearer #{token}" unless token.to_s.empty?
    headers
  end

  def release_payload(token)
    response = Utils.safe_popen_read(
      "curl",
      "--fail",
      "--silent",
      "--show-error",
      "--location",
      *api_headers(token),
      release_api_url,
    )
    JSON.parse(response)
  rescue StandardError
    {}
  end

  def api_asset_url(token)
    payload = release_payload(token)
    assets = Array(payload["assets"])
    asset = assets.find { |entry| entry["name"] == artifact_name }
    return nil unless asset

    asset["url"]
  end

  def download_with_headers(url, token, asset_download: false)
    return false if url.to_s.empty?

    headers = [
      "--header",
      asset_download ? "Accept: application/octet-stream" : "Accept: application/vnd.github+json",
      "--header",
      "User-Agent: Homebrew",
    ]
    headers << "--header" << "Authorization: token #{token}" unless token.to_s.empty?
    headers << "--header" << "X-GitHub-Api-Version: 2022-11-28" unless asset_download

    system(
      "curl",
      "--fail",
      "--location",
      "--silent",
      "--show-error",
      "--output",
      artifact_name,
      *headers,
      url,
    )
  end

  def download_with_gh(token = "")
    return false unless (gh = gh_binary_path)

    command = [
      gh,
      "release",
      "download",
      release_tag,
      "--repo",
      "HPD-AI/HPD-OS",
      "--pattern",
      artifact_name,
    ]

    return true if token.to_s.empty? && system(*command)

    with_env(
      "HOMEBREW_GITHUB_API_TOKEN" => token,
      "GITHUB_TOKEN" => token,
      "GH_TOKEN" => token,
      "HOME" => ENV["HOME"],
      "GH_CONFIG_DIR" => File.join(ENV["HOME"], ".config", "gh"),
    ) do
      system(*command)
    end
  end

  def download_release_asset
    token = github_token

    if !token.empty?
      asset_url = api_asset_url(token)
      return true if download_with_headers(asset_url, token, asset_download: true) unless asset_url.to_s.empty?
      return true if download_with_gh(token)
    end

    # Last-resort public fallback for public repos.
    return true if download_with_headers(release_download_url, "")

    # If public fallback fails, try gh without env token (for anonymous attempts).
    download_with_gh
  end

  def extract_archive
    case artifact_name
    when /\.tar\.gz$/
      system "tar", "-xzf", artifact_name
    when /\.zip$/
      system "unzip", "-q", artifact_name
    else
      odie "Unsupported archive format for #{artifact_name}."
    end
  end

  def install
    odie "Failed to download #{artifact_name} from release #{release_tag}." unless download_release_asset

    odie <<~MSG unless File.exist?(artifact_name)
      Failed to download #{artifact_name} from release #{release_tag}.
      Verify your network and GitHub authentication, then retry.
    MSG

    extract_archive

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
