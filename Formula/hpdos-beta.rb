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

  def gh_binary
    gh = Formula["gh"].opt_bin/"gh"
    return gh if gh.executable?

    "gh"
  end

  def github_home_candidates
    candidate_usernames = [
      ENV["SUDO_USER"],
      ENV["USER"],
      ENV["LOGNAME"],
    ].map(&:to_s).reject(&:empty?)

    candidates = []
    candidates << ENV["HOME"] if ENV["HOME"].to_s.strip != ""
    candidates << Etc.getpwuid(Process.uid).dir rescue nil
    candidate_usernames.each { |user| candidates << Etc.getpwnam(user).dir rescue nil }
    candidates.compact!

    candidates.uniq.map { |home| Pathname.new(home).expand_path }
      .select { |home| home.directory? }
  end

  def gh_config_home
    @gh_config_home ||= begin
      local_match = github_home_candidates.find { |home| (home/".config/gh/hosts.yml").exist? }
      return local_match unless local_match.nil?

      # Homebrew can run with a sanitized HOME; fall back to scanning local user homes.
      Dir.glob("/Users/*")
        .map { |home| Pathname.new(home) }
        .find { |home| (home/".config/gh/hosts.yml").exist? } ||
        github_home_candidates.first
    end
  end

  def github_token
    token = [
      ENV["HOMEBREW_GITHUB_API_TOKEN"],
      ENV["GITHUB_TOKEN"],
      ENV["GH_TOKEN"],
    ].find { |value| valid_github_token?(value) }
    return token.to_s.strip unless token.to_s.strip.empty?

    token = token_from_gh_hosts_file
    return token.to_s.strip if token.to_s.strip != ""

    token_from_gh_cli
  rescue StandardError
    ""
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
    normalized_user = current_user&.to_s
    current_host_user = users[normalized_user] || users["\"#{normalized_user}\""]

    # gh's hosts.yml may include literal quote characters in usernames in some
    # versions/configurations. Fall back to any user entry if direct lookup fails.
    current_host_user = users.values.find { |entry| entry.is_a?(Hash) && entry["oauth_token"] } if current_host_user.nil?

    return nil unless current_host_user.is_a?(Hash)

    (current_host_user["oauth_token"] || current_host_user[:oauth_token])&.to_s
  rescue StandardError
    nil
  end

  def token_from_gh_cli
    return "" if gh_config_home.nil?

    candidates = [
      { HOME: gh_config_home.to_s, XDG_CONFIG_HOME: (gh_config_home/".config").to_s },
      {},
    ]

    candidates.each do |env_overrides|
      token = with_env(env_overrides) do
        Utils.safe_popen_read(gh_binary, "auth", "token", "-h", "github.com").strip
      end
      next unless valid_github_token?(token)
      return token unless token.empty?
    end

    ""
  rescue StandardError
    ""
  end

  def download_release_asset
    token = github_token.to_s.strip
    unless token.empty?
      return if download_with_api(token)
      return if download_with_gh_release(token)
    end

    # If no token path works, we fail with clear instructions.
    odie <<~MSG
      Could not download #{artifact_name} from release #{release_tag}.

      This release is private on GitHub. Set one of these before install:
        HOMEBREW_GITHUB_API_TOKEN="$(gh auth token -h github.com)" brew install --formula hpdos-beta
        GITHUB_TOKEN=... brew install --formula hpdos-beta

      You also need:
      - active token access to repo HPD-AI/HPD-OS
      - `gh` authenticated locally (if you want CLI fallback)
    MSG
  end

  def download_with_api(token)
    return false unless valid_github_token?(token)

    return false if token.empty?

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
    assets = Array(release["assets"])
    asset = assets.find { |entry| entry["name"] == artifact_name }
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
    true
  rescue StandardError
    false
  end

  def download_with_gh_release(token)
    return false unless valid_github_token?(token)

    with_env(
      GH_PROMPT_DISABLED: "1",
      GH_TOKEN: token.to_s,
      GITHUB_TOKEN: token.to_s,
      HOMEBREW_GITHUB_API_TOKEN: token.to_s,
    ) do
      system gh_binary, "release", "download", release_tag,
             "--repo", "HPD-AI/HPD-OS",
             "--pattern", artifact_name,
             "--output", artifact_name,
             "--clobber"
    end && File.exist?(artifact_name)
  rescue StandardError
    false
  end

  def valid_github_token?(value)
    token = value.to_s.strip
    return false if token.empty?
    # GH CLI returns descriptive errors (e.g. "no oauth token found...") when
    # no credential is available; avoid treating that as a real token.
    return false if token.include?(" ")
    token.match?(/\A(?:gho_|ghp_|ghu_|ghs_|ghr_|ghl_|github_pat_)[A-Za-z0-9]+\z/)
  end

  def install
    download_release_asset
    odie <<~MSG unless File.exist?(artifact_name)
      Failed to download #{artifact_name} from release #{release_tag}.
      Verify your GitHub auth token has private-repo access and retry.
    MSG

    case artifact_name
    when /\.tar\.gz$/
      system "tar", "-xzf", artifact_name
    when /\.zip$/
      system "unzip", "-q", artifact_name
    else
      odie "Unsupported archive format for #{artifact_name}."
    end

    binary = %w[hpdos hpdos.exe hpd-tui hpd-agent].find do |candidate|
      path = Pathname.new(candidate)
      path.file? && path.executable?
    end
    odie "Downloaded archive did not contain a supported executable." unless binary

    bin.install binary
  end

  test do
    assert_predicate bin/"hpdos", :exist?
  end
end
