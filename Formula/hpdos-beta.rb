# typed: false
# frozen_string_literal: true

require "json"
require "yaml"
require "etc"

class HpdosBeta < Formula
  desc "Interactive HPD-OS coding TUI powered by HPD-Agent"
  homepage "https://github.com/HPD-AI/HPD-OS"
  version "0.1.0-beta.1"
  env :std

  # Private releases are attached to the same repository, so we fetch from the GitHub
  # release endpoint when installing from Homebrew.
  url "https://github.com/HPD-AI/HPD-OS.git", using: :git, tag: "hpdos-tui-v#{version}"

  depends_on "gh" => :build

  def release_tag
    "hpdos-tui-v#{version}"
  end

  def release_repo
    "HPD-AI/HPD-OS"
  end

  def release_api_url
    "https://api.github.com/repos/#{release_repo}/releases/tags/#{release_tag}"
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

  def gh_binary
    gh = Formula["gh"].opt_bin/"gh"
    return gh if gh.executable?
    "gh"
  end

  def github_home_candidates
    names = [
      ENV["SUDO_USER"],
      ENV["USER"],
      ENV["LOGNAME"],
    ].map(&:to_s).reject(&:empty?)

    candidates = [ENV["HOME"]]
    candidates << "/Users/#{ENV["USER"]}" unless ENV["USER"].to_s.empty?
    candidates << "/Users/#{ENV["SUDO_USER"]}" unless ENV["SUDO_USER"].to_s.empty?

    begin
      candidates << Etc.getpwuid(Process.uid).dir
    rescue StandardError
    end

    names.each do |name|
      begin
        candidates << Etc.getpwnam(name).dir
      rescue StandardError
      end
    end

    candidates.compact!
    candidates.uniq.map { |home| Pathname.new(home).expand_path }
      .select { |home| home.directory? }
  end

  def gh_config_home
    @gh_config_home ||= begin
      direct_match = github_home_candidates.find { |home| (home/".config/gh/hosts.yml").exist? }
      return direct_match unless direct_match.nil?

      # Homebrew can run with a sanitized HOME; fall back to scanning user homes.
      Dir.glob("/Users/*")
        .map { |home| Pathname.new(home) }
        .find { |home| (home/".config/gh/hosts.yml").exist? } || github_home_candidates.first
    end
  end

  def token_from_gh_hosts_file
    return nil if gh_config_home.nil?

    config_path = gh_config_home/".config/gh/hosts.yml"
    return nil unless config_path.exist?

    data = YAML.load_file(config_path)
    return nil unless data.is_a?(Hash)

    host_data = data["github.com"]
    return nil unless host_data.is_a?(Hash)

    return host_data["oauth_token"]&.to_s if host_data["oauth_token"]

    users = host_data["users"]
    return nil unless users.is_a?(Hash)

    current_user = host_data["user"] || host_data[:user]
    key = current_user&.to_s

    entry = users[key] || users["\"#{key}\""]
    entry = users.values.find { |v| v.is_a?(Hash) && v["oauth_token"] } if entry.nil?
    return nil unless entry.is_a?(Hash)

    (entry["oauth_token"] || entry[:oauth_token])&.to_s
  rescue StandardError
    nil
  end

  def token_from_gh_cli
    return "" if gh_binary.to_s.empty?

    candidates = [{}, { HOME: "/", XDG_CONFIG_HOME: "/.config" }]
    github_home_candidates.each do |home|
      candidates.unshift({ HOME: home.to_s, XDG_CONFIG_HOME: (home/".config").to_s })
    end

    candidates.each do |env_overrides|
      token = with_env(env_overrides) do
        Utils.safe_popen_read(gh_binary, "auth", "token", "-h", "github.com").strip
      end
      return token if valid_github_token?(token)
    end

    ""
  rescue StandardError
    ""
  end

  def github_token
    tokens = [
      ENV["HOMEBREW_GITHUB_API_TOKEN"],
      ENV["GITHUB_TOKEN"],
      ENV["GH_TOKEN"],
      token_from_gh_hosts_file,
      token_from_gh_cli,
    ].compact.map(&:strip).reject(&:empty?).uniq

    tokens.find { |token| valid_github_token?(token) }.to_s
  rescue StandardError
    ""
  end

  def download_with_api(token)
    return false unless valid_github_token?(token)

    begin
      payload = Utils.safe_popen_read(
        "curl",
        "--fail",
        "--silent",
        "--show-error",
        "--location",
        "--header",
        "Accept: application/vnd.github+json",
        "--header",
        "X-GitHub-Api-Version: 2022-11-28",
        "--header",
        "Authorization: token #{token}",
        release_api_url,
      )

      release = JSON.parse(payload)
      asset = Array(release["assets"]).find { |entry| entry["name"] == artifact_name }
      return false unless asset

      asset_url = asset["url"]
      return false unless asset_url

      Utils.safe_popen_read(
        "curl",
        "--fail",
        "--silent",
        "--show-error",
        "--location",
        "--header",
        "Accept: application/octet-stream",
        "--header",
        "Authorization: token #{token}",
        "--header",
        "X-GitHub-Api-Version: 2022-11-28",
        "--output",
        artifact_name,
        asset_url,
      )

      return true
    rescue StandardError
      false
    end
  end

  def download_with_gh_release(token)
    return false unless valid_github_token?(token)

    with_env(
      GH_PROMPT_DISABLED: "1",
      GH_TOKEN: token,
      GITHUB_TOKEN: token,
      HOMEBREW_GITHUB_API_TOKEN: token,
    ) do
      system gh_binary, "release", "download", release_tag,
             "--repo", release_repo,
             "--pattern", artifact_name,
             "--output", artifact_name,
             "--clobber"
    end && File.exist?(artifact_name)
  rescue StandardError
    false
  end

  def download_release_asset
    token = github_token

    if valid_github_token?(token)
      return if download_with_api(token)
      return if download_with_gh_release(token)
    end

    if gh_binary.executable?
      direct_token = ENV["HOMEBREW_GITHUB_API_TOKEN"]&.strip || ENV["GITHUB_TOKEN"]&.strip || ENV["GH_TOKEN"]&.strip
      return if download_with_gh_release(direct_token) if valid_github_token?(direct_token)
    end

    odie <<~MSG
      Could not download #{artifact_name} from release #{release_tag}.

      This release is private on GitHub. Set one of these before install:
        export HOMEBREW_GITHUB_API_TOKEN="$(gh auth token -h github.com)"
        export GITHUB_TOKEN="$(gh auth token -h github.com)"
        export GH_TOKEN="$(gh auth token -h github.com)"
        Then retry:
          brew install --formula hpdos-beta
    MSG
  end

  def valid_github_token?(value)
    token = value.to_s.strip
    return false if token.empty?
    return false if token.include?(" ")
    token.match?(/\A(?:gho_|ghp_|ghu_|ghs_|ghr_|ghl_|github_pat_)[A-Za-z0-9_+\-]+\z/)
  end

  def install
    download_release_asset
    odie <<~MSG unless File.exist?(artifact_name)
      Failed to download #{artifact_name} from release #{release_tag}.
      Verify your GitHub token has private-repo access and retry.
    MSG

    case artifact_name
    when /\.tar\.gz$/
      system "tar", "-xzf", artifact_name
    when /\.zip$/
      system "unzip", "-q", artifact_name
    else
      odie "Unsupported archive format for #{artifact_name}."
    end

    binary = Dir["**/hpdos", "**/hpdos.exe", "**/hpd-tui", "**/hpd-agent"].find do |candidate|
      path = Pathname.new(candidate)
      path.file? && path.executable?
    end
    odie "Downloaded archive did not contain a supported executable." unless binary

    bin.install Pathname.new(binary)
  end

  test do
    files = ["hpdos", "hpdos.exe", "hpd-tui", "hpd-agent"]
    assert(files.any? { |name| (bin/name).exist? }, "Expected one HPDOS executable (hpdos, hpdos.exe, hpd-tui, hpd-agent)")
  end
end
