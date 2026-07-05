# typed: false
# frozen_string_literal: true

require "json"
require "yaml"
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

  def release_asset_url
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

  def candidate_home_paths
    [ENV["HOME"], "/Users/#{ENV["USER"]}", "/Users/#{ENV["LOGNAME"]}", "/Users/#{Etc.getlogin}"]
      .compact
      .uniq
      .select { |path| path.start_with?("/") && File.directory?(path) }
  end

  def gh_config_home
    candidate_home_paths.find do |path|
      File.directory?(Pathname.new(path).join(".config", "gh"))
    end
  end

  def gh_token_from_file(home_path)
    hosts_file = Pathname.new(home_path).join(".config", "gh", "hosts.yml")
    return "" unless hosts_file.file?

    hosts = YAML.safe_load(hosts_file.read)
    github_host = hosts && (hosts["github.com"] || hosts["https://github.com"])
    token = github_host && github_host["oauth_token"]
    token.to_s.strip
  rescue StandardError
    ""
  end

  def gh_token_from_command
    return "" unless (gh = gh_binary_path)

    token = Utils.safe_popen_read(gh, "auth", "token", "-h", "github.com").strip
    return token unless token.empty?

    candidate_home_paths.each do |home_path|
      token = with_env("HOME" => home_path) do
        Utils.safe_popen_read(gh, "auth", "token", "-h", "github.com").strip
      end
      return token unless token.empty?
    end

    ""
  rescue StandardError
    ""
  end

  def github_token
    token = [ENV["HOMEBREW_GITHUB_API_TOKEN"], ENV["GITHUB_TOKEN"], ENV["GH_TOKEN"]]
      .compact
      .map(&:to_s)
      .find { |value| !value.strip.empty? }
    return token.strip unless token.to_s.empty?

    token = gh_token_from_command
    return token unless token.empty?

    token = gh_token_from_file(gh_config_home || ENV["HOME"].to_s)
    return token unless token.empty?

    candidate_home_paths.each do |home_path|
      file_token = gh_token_from_file(home_path)
      return file_token unless file_token.empty?
    end

    ""
  end

  def auth_headers(token)
    headers = [
      "--header", "Accept: application/vnd.github+json",
      "--header", "X-GitHub-Api-Version: 2022-11-28",
    ]
    headers << "--header" << "Authorization: Bearer #{token}" unless token.to_s.empty?
    headers
  end

  def download_with_headers(url, token = "")
    return false if url.to_s.empty?

    system(
      "curl",
      "--fail",
      "--location",
      "--silent",
      "--show-error",
      "--output",
      artifact_name,
      "--header",
      "Accept: application/octet-stream",
      *(token.to_s.empty? ? [] : auth_headers(token)),
      url,
    )
  end

  def release_payload(token)
    Utils.safe_popen_read(
      "curl",
      "--fail",
      "--silent",
      "--show-error",
      "--location",
      *auth_headers(token),
      "https://api.github.com/repos/HPD-AI/HPD-OS/releases/tags/#{release_tag}",
    )
  end

  def api_asset_url(token)
    payload = release_payload(token)
    release = JSON.parse(payload)
    assets = Array(release["assets"])
    asset = assets.find { |entry| entry["name"] == artifact_name }
    odie "Release asset #{artifact_name} was not found in #{release_tag}." unless asset

    asset["url"]
  end

  def download_with_gh(token = "")
    return false unless (gh = gh_binary_path)
    token = token.to_s

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

    if token.empty?
      return system(*command)
    end

    with_env(
      "GITHUB_TOKEN" => token,
      "GH_TOKEN" => token,
      "HOMEBREW_GITHUB_API_TOKEN" => token,
    ) do
      system(*command)
    end
  rescue StandardError
    false
  end

  def download_release_asset
    token = github_token

    return true if download_with_gh(token.to_s) if token.to_s.empty? == false
    return true if download_with_gh if token.to_s.empty?

    # Fallback for token-authenticated API download.
    unless token.to_s.empty?
      return true if download_with_headers(api_asset_url(token), token)
    end

    # Last-resort public fallback.
    download_with_headers(release_asset_url)
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
