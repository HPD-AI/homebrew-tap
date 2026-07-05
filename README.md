# HPDOS Homebrew Tap

Homebrew formulas for HPDOS.

## Beta Channel

```bash
brew tap HPD-AI/homebrew-tap
brew install hpdos-beta
```

**Optional:** Set a GitHub token for higher API rate limits:
```bash
export HOMEBREW_GITHUB_API_TOKEN=...
# or alternatively:
export GH_TOKEN=... 
export GITHUB_TOKEN=...
```

## How the beta artifacts are published for Homebrew

HPDOS CLI binaries for Homebrew are mirrored into releases on the main repo as:

- `hpdos-tui-v<VERSION>-<SUFFIX>` (for example `hpdublic `HPD-AI/HPD-OS` release channel via GitHub API.
A GitHub token is optional but recommended for higher API rate limits. You can
- `hpdos-osx-x64.tar.gz`
- `hpdos-linux-arm64.tar.gz`
- `hpdos-linux-x64.tar.gz`

This formula downloads release artifacts from the private `HPD-AI/HPD-OS` release channel via GitHub API.
For Homebrew install to work, set one of:

- `HOMEBREW_GITHUB_API_TOKEN`
- `GH_TOKEN`
- `GITHUB_TOKEN`

> Note: The stable formula (`hpdos`) is not published yet; install via `hpdos-beta` for now.
