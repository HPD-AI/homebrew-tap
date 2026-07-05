# HPDOS Homebrew Tap

Homebrew formulas for HPDOS.

## Beta Channel

```bash
brew tap HPD-AI/tap
export HOMEBREW_GITHUB_API_TOKEN=...
# alternatively export GH_TOKEN or GITHUB_TOKEN
brew install hpdos-beta
```

## How the beta artifacts are published for Homebrew

HPDOS CLI binaries for Homebrew are mirrored into releases on the main repo as:

- `hpdos-tui-v<VERSION>-<SUFFIX>` (for example `hpdos-tui-v0.1.0-beta.1`)
- `hpdos-osx-arm64.tar.gz`
- `hpdos-osx-x64.tar.gz`
- `hpdos-linux-arm64.tar.gz`
- `hpdos-linux-x64.tar.gz`

This formula downloads release artifacts from the private `HPD-AI/HPD-OS` release channel via GitHub API.
For Homebrew install to work, set one of:

- `HOMEBREW_GITHUB_API_TOKEN`
- `GH_TOKEN`
- `GITHUB_TOKEN`

> Note: The stable formula (`hpdos`) is not published yet; install via `hpdos-beta` for now.
