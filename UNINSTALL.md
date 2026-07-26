# Uninstall and Reversal

The installer does not provide an automatic uninstall because it performs a
full system upgrade and may install packages also used by other software.
Review each action before removing anything.

## Disable Services

```bash
systemctl --user disable --now opencode.service
sudo systemctl disable --now greetd.service
```

If the installer owns the Tailscale HTTPS 8443 route, inspect it before removal:

```bash
sudo tailscale serve status
sudo tailscale serve --https=8443 off
```

Do not remove an 8443 route unless it exactly proxies
`http://127.0.0.1:4096` and belongs to this installer.

## Restore Configuration

Backups are stored below
`~/.local/state/caelestia-vrabko-installer/backups/`. Restore only files from the
specific run you are reversing. Do not copy an entire backup over newer user
data without reviewing its contents.

## Remove Installer State

After restoring configuration and confirming no data is needed, review these
paths for manual removal:

```text
~/.config/caelestia-vrabko-installer/
~/.local/state/caelestia-vrabko-installer/
~/.local/share/caelestia-vrabko-installer/
~/.config/systemd/user/opencode.service
~/.config/opencode/server.env
~/OpenCodeWorkspace/
```

The dedicated OpenCode tree may contain provider state. Back it up or revoke
provider credentials before deletion.

## Packages and System Settings

Use `pacman -Q` and `pacman -Qi` to identify package ownership before removal.
Do not bulk-remove the installer's package plan: packages may predate the
installer or be dependencies of other software. Locale changes, multilib,
greetd ownership, user lingering, Docker group membership, and full-system
upgrades require manual review and are not automatically reversible.
