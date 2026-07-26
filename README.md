# Caelestia Vrabko Installer

[![CI](https://github.com/Retro-TV/caelestia-vrabko-installer/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/Retro-TV/caelestia-vrabko-installer/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/Retro-TV/caelestia-vrabko-installer)](https://github.com/Retro-TV/caelestia-vrabko-installer/releases/latest)

An unofficial, security-focused installer that turns a networked Arch-based TTY
into a Caelestia workstation with optional animated-wallpaper support,
application bundles, and an isolated OpenCode service.

The installer does not partition disks, install Arch, modify the bootloader,
enable desktop autologin, or install personal wallpapers.

The interactive wizard uses labeled choices and lists the applications included
in each optional bundle before anything is installed.

## Quick Install

Log in as your normal user with sudo access. Review the immutable payload before
running it, then execute:

```bash
payload=2a6003962a1a1a97d7436d6c57f3214216fbdded
install_dir="$HOME/.local/src/caelestia-vrabko-installer-${payload:0:7}"

sudo pacman -Syu --needed git
mkdir -p "$install_dir"
git -C "$install_dir" init
git -C "$install_dir" remote add origin \
  https://github.com/Retro-TV/caelestia-vrabko-installer.git
git -C "$install_dir" fetch --depth 1 origin "$payload"
git -C "$install_dir" checkout --detach FETCH_HEAD
test "$(git -C "$install_dir" rev-parse HEAD)" = "$payload"
"$install_dir/install.sh"
```

The bootstrap fetches and verifies an immutable commit. It never executes a
mutable branch or tag.

## What It Installs

- Pinned official or animated-wallpaper Caelestia Shell and CLI packages.
- Pinned Quickshell, Material You color, libcava, and Rubik dependencies.
- Hyprland, UWSM, greetd, portals, PipeWire, utilities, and selected app bundles.
- AMD or Intel Mesa support; NVIDIA only when a compatible driver already exists.
- Known virtual GPUs only when the system is positively identified as a VM.
- An optional OpenCode service bound to localhost with generated authentication.
- Optional tailnet-only OpenCode access through Tailscale Serve on HTTPS 8443.

You supply and manage your own wallpapers after installation.

## Requirements

- x86_64 Arch Linux, CachyOS, or EndeavourOS.
- A normal user with sudo, systemd, pacman, working DNS, and internet access.
- At least 12 GiB available on the home/build filesystem.
- The standard `~/.config` path for this release.

| Distribution | Status |
|---|---|
| Arch Linux | Supported |
| CachyOS | Supported; optimized repositories are preserved |
| EndeavourOS | Supported |
| Manjaro | Experimental; requires `--allow-experimental` |
| Other pacman systems | Experimental; requires `--allow-experimental` |

VirtIO, QEMU, QXL, VMware, VirtualBox, and Hyper-V graphics are supported only
inside a detected virtual machine and use Mesa software rendering.

## Usage

Use the interactive wizard:

```bash
./install.sh
```

Use a bundled non-secret profile:

```bash
./install.sh --profile profiles/minimal.profile
./install.sh --profile profiles/vrabko.profile
```

Inspect without mutation:

```bash
./install.sh --profile profiles/minimal.profile --dry-run
```

Run post-install validation:

```bash
./validate.sh
```

`--yes` skips the final confirmation and requires `--profile`. Profiles contain
preferences only and must never contain credentials, domains, or API keys.

## Security Model

- Source-built packages use local PKGBUILDs with commit/version pins and SHA-256
  checksums. No AUR helper or moving AUR metadata executes.
- Caelestia dots are fetched at an exact commit and verified before package
  mutation. The managed CLI refuses ordinary `caelestia update` operations.
- OpenCode uses a dedicated HOME/XDG tree, pure mode, disabled project config,
  localhost binding, generated authentication, restrictive permissions, and no
  inherited plugins, MCP servers, commands, or provider state.
- Tailscale mode owns one exact tailnet-only route and rejects Funnel exposure.
- Existing configuration is copied into a new timestamped backup on every run.

OpenCode is not sandboxed. Anyone with its generated password can drive an
agent and approve tool requests. See [SECURITY.md](SECURITY.md) before enabling
remote access.

## Updates

Do not run `caelestia update`; both CLI variants intentionally refuse it while
the installation is externally managed. To update:

1. Read [CHANGELOG.md](CHANGELOG.md) and the latest release notes.
2. Fetch the new immutable payload into a new directory.
3. Run its dry-run with your saved profile.
4. Run the installer and then `./validate.sh`.

The installer builds both replacement packages before switching between the AW
and official package sets.

## Recovery

Installer-owned configuration is copied under
`~/.local/state/caelestia-vrabko-installer/backups/`. If a run stops, inspect the
reported stage and `install.log`, correct the cause, and rerun the same profile.
Package and system changes are not atomically rolled back.

See [UNINSTALL.md](UNINSTALL.md) for reversal limits and manual cleanup.

## Troubleshooting

Before opening a bug report, collect and sanitize:

```bash
uname -a
cat /etc/os-release
systemctl --failed --no-pager
systemctl --user --failed --no-pager
tail -n 100 ~/.local/state/caelestia-vrabko-installer/install.log
```

Remove usernames, hostnames, tokens, passwords, domains, and private Tailscale
details. Use the structured [bug report](https://github.com/Retro-TV/caelestia-vrabko-installer/issues/new?template=bug_report.yml)
for installer defects and follow [SECURITY.md](SECURITY.md) for vulnerabilities.

## Project Documents

- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
- [Support](SUPPORT.md)
- [Security](SECURITY.md)
- [Uninstall and reversal](UNINSTALL.md)
- [Code of Conduct](CODE_OF_CONDUCT.md)

## Upstream Projects

- [Caelestia](https://github.com/caelestia-dots/caelestia)
- [Caelestia CLI](https://github.com/caelestia-dots/cli)
- [Caelestia AW](https://github.com/AdiAmbassador/caelestia-aw)
- [OpenCode](https://opencode.ai/docs/)

This project is unofficial and is not endorsed by the Caelestia maintainers.
