# Security Policy

## Supported Versions

Only the latest GitHub release receives security fixes. Older tags and source
snapshots are unsupported.

## Reporting a Vulnerability

Use [GitHub private vulnerability reporting](https://github.com/Retro-TV/caelestia-vrabko-installer/security/advisories/new).
Do not open a public issue or pull request containing exploit details,
credentials, private domains, or network information.

Include the affected version or commit, supported distribution, impact,
reproduction steps, and a minimal sanitized proof of concept. Expect an initial
acknowledgement within seven days. Please allow reasonable time for a fix and
coordinated disclosure before publishing details.

Credentials must be revoked or rotated immediately; deleting them from Git
history is not a substitute for revocation.

## Trust Boundaries

The installer runs reviewed local code and invokes pacman plus local PKGBUILDs.
Repository packages retain the distribution's normal signature trust. Caelestia,
Quickshell and Arch-only dependency sources are pinned by commit/version and
SHA-256 checksum. The exact dots commit is verified before package mutation and
the patched Caelestia CLI does not invoke an AUR helper.

The installer disables dots components whose packages are not supplied by its
repository-only plan and records an external-management marker. The patched CLI
refuses ordinary `caelestia update`, preventing that lifecycle command from
bootstrapping an AUR helper or moving the locked dots revision.

Review the plan before approving a privileged installation. This initial release
is not an atomic package rollback system.

## OpenCode

OpenCode listens only on `127.0.0.1:4096` and requires a generated 48-character
hex password. Sharing and mDNS are disabled. It starts in an isolated
`~/OpenCodeWorkspace`, runs in pure mode, disables project configuration
loading, and uses a dedicated HOME/XDG tree. Existing interactive OpenCode
plugins, commands, configuration and provider state are not inherited. The
service denies external-directory tools and asks before tool operations.

These settings reduce accidental access; they do not sandbox OpenCode.
Possession of the HTTP Basic password should be treated as equivalent to access
to the user's account because an authenticated API client can drive an agent
and answer permission requests. Do not publish it directly to a LAN or the
internet.

Tailscale mode reserves HTTPS port 8443 and remains tailnet-only. Use Tailscale
ACLs to limit clients. Cloudflare users must configure their own named tunnel
and Cloudflare Access policy before publication.

## Secrets

Profiles contain preferences only. Never commit:

- `~/.config/opencode/server.env`
- Provider API keys or OAuth state
- Tailscale or Cloudflare credentials
- SSH private keys
- Browser/session data

## Session Lock

The AW package removes the upstream same-user `unlock` shortcut and IPC method.
Interactive unlocking continues through Caelestia's PAM path. Desktop autologin
is not configured by this installer.
