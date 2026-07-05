# HPDOS Homebrew Tap

Homebrew formulas for HPDOS.

## Stable

```bash
brew tap HPD-AI/tap
brew install hpdos
```

## Beta

```bash
brew tap HPD-AI/tap
brew install hpdos-beta
```

This repository is updated by the HPDOS release workflow.

### How the beta artifacts are published for Homebrew

HPDOS CLI binaries for Homebrew are mirrored into releases on the main HPDOS repo as:

- `hpdos-tui-v<VERSION>-<SUFFIX>` (for example `hpdos-tui-v0.1.0-beta.1`)
- `hpdos-osx-arm64.tar.gz`
- `hpdos-osx-x64.tar.gz`

The tap must stay public so Homebrew can download artifacts without auth.
