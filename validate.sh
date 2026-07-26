#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

failed=0
OPENCODE_DIR=$HOME/.config/opencode
PROFILE_FILE=$HOME/.config/caelestia-vrabko-installer/profile.conf
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/caelestia-vrabko-installer
CAELESTIA_STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/caelestia
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

lock_value() {
    awk -F= -v key="$1" '$1 == key { print $2 }' "$ROOT/versions.lock"
}

installed_version() {
    pacman -Q "$1" 2>/dev/null | cut -d' ' -f2 || true
}

AW_VERSION=$(lock_value aw_integration_version)
EXPECTED_AW_CLI="1.1.2.aw$AW_VERSION-$(lock_value aw_cli_package_release)"
EXPECTED_AW_SHELL="2.2.0.aw$AW_VERSION-$(lock_value shell_package_release)"
[[ -f "$PROFILE_FILE" ]] || { echo "FAIL  resolved installer profile is missing" >&2; exit 1; }
EXPECTED_OPENCODE=$(while IFS= read -r line; do case "$line" in INSTALL_OPENCODE=*) printf '%s' "${line#*=}"; break ;; esac; done <"$PROFILE_FILE")
EXPECTED_REMOTE=$(while IFS= read -r line; do case "$line" in REMOTE_ACCESS=*) printf '%s' "${line#*=}"; break ;; esac; done <"$PROFILE_FILE")
EXPECTED_AW=$(while IFS= read -r line; do case "$line" in INSTALL_AW=*) printf '%s' "${line#*=}"; break ;; esac; done <"$PROFILE_FILE")

check() {
    local label=$1
    shift
    if "$@" >/dev/null 2>&1; then
        printf 'PASS  %s\n' "$label"
    else
        printf 'FAIL  %s\n' "$label" >&2
        failed=1
    fi
}

check 'Hyprland installed' pacman -Q hyprland
check 'UWSM installed' pacman -Q uwsm
check 'greetd enabled' systemctl is-enabled greetd.service
check 'greetd configuration present' grep -Fq "uwsm start -e -D Hyprland hyprland.desktop" /etc/greetd/config.toml
if [[ $(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null) == */greetd.service ]]; then
    printf 'PASS  greetd owns display-manager.service\n'
else
    printf 'FAIL  greetd does not own display-manager.service\n' >&2
    failed=1
fi
check 'Hyprland Wayland session present' test -s /usr/share/wayland-sessions/hyprland.desktop
check 'hypr-user.lua present' test -s "$HOME/.config/caelestia/hypr-user.lua"
check 'hypr-vars.lua present' test -s "$HOME/.config/caelestia/hypr-vars.lua"

if [[ "$EXPECTED_AW" == yes ]]; then
    check 'AW package pair installed' pacman -Q caelestia-cli-aw caelestia-shell-aw
    check 'AW CLI version matches lock' test "$(installed_version caelestia-cli-aw)" = "$EXPECTED_AW_CLI"
    check 'AW Shell version matches lock' test "$(installed_version caelestia-shell-aw)" = "$EXPECTED_AW_SHELL"
    check 'AW CLI package integrity' bash -c "LC_ALL=C pacman -Qkk caelestia-cli-aw | grep -q '0 altered files'"
    check 'AW Shell package integrity' bash -c "LC_ALL=C pacman -Qkk caelestia-shell-aw | grep -q '0 altered files'"
else
    if pacman -Q caelestia-cli-aw >/dev/null 2>&1 || pacman -Q caelestia-shell-aw >/dev/null 2>&1; then
        printf 'FAIL  AW packages are installed despite profile selection\n' >&2
        failed=1
    fi
    check 'Official Caelestia package pair installed' pacman -Q caelestia-cli caelestia-shell
    check 'Official CLI version matches lock' test "$(installed_version caelestia-cli)" = "$(lock_value tested_caelestia_cli)"
    check 'Official Shell version matches lock' test "$(installed_version caelestia-shell)" = "$(lock_value tested_caelestia_shell)"
    check 'Official CLI package integrity' bash -c "LC_ALL=C pacman -Qkk caelestia-cli | grep -q '0 altered files'"
    check 'Official Shell package integrity' bash -c "LC_ALL=C pacman -Qkk caelestia-shell | grep -q '0 altered files'"
fi

check 'Pinned Material You package installed' pacman -Q python-materialyoucolor
check 'Pinned libcava package installed' pacman -Q libcava
check 'Pinned Rubik package installed' pacman -Q ttf-rubik-vf
check 'Pinned Material You version installed' test "$(installed_version python-materialyoucolor)" = "$(lock_value tested_materialyoucolor)"
check 'Pinned libcava version installed' test "$(installed_version libcava)" = "$(lock_value tested_libcava)"
check 'Pinned Rubik version installed' test "$(installed_version ttf-rubik-vf)" = "$(lock_value tested_rubik)"
check 'Pinned Quickshell version installed' test "$(installed_version quickshell-git)" = "$(lock_value tested_quickshell_git)"
for package in python-materialyoucolor libcava ttf-rubik-vf quickshell-git; do
    check "$package package integrity" bash -c "LC_ALL=C pacman -Qkk $package | grep -q '0 altered files'"
done
dots_commit=$(awk -F= '$1 == "dots_commit" { print $2 }' "$ROOT/versions.lock")
check 'Pinned dots source retained' bash -c "[[ \$(git -C \"$STATE_DIR/inputs/caelestia-dots\" rev-parse HEAD) == $dots_commit ]]"
applied_rev=$(jq -r .applied_rev "$CAELESTIA_STATE_DIR/dots-state.json" 2>/dev/null || true)
check 'Pinned dots revision applied' test "$applied_rev" = "$dots_commit"
check 'Caelestia package management remains external' test -s "$CAELESTIA_STATE_DIR/externally-managed"
check 'Caelestia state recorded no upstream packages' jq -e '.packages == {} and .local_packages == {}' "$CAELESTIA_STATE_DIR/dots-state.json"
check 'Unsupported package components remain disabled' jq -e '([.enabled_components[] | select(. == "firefox" or . == "gtk" or . == "qt")] | length) == 0 and (.enabled_components | index("uwsm") != null)' "$CAELESTIA_STATE_DIR/dots-state.json"

if [[ "$EXPECTED_OPENCODE" == yes ]]; then
    check 'OpenCode package installed' pacman -Q opencode
    service_home="$HOME/.local/share/caelestia-vrabko-installer/opencode-home"
    service_config_dir="$service_home/.config/opencode"
    check 'OpenCode service config valid' jq empty "$service_config_dir/opencode.json"
    check 'OpenCode service config matches installer' cmp -s "$ROOT/templates/opencode/opencode.json" "$service_config_dir/opencode.json"
    line_count=$(wc -l <"$OPENCODE_DIR/server.env" 2>/dev/null || printf '0')
    if [[ $(stat -c %a "$OPENCODE_DIR/server.env" 2>/dev/null) == 600 ]] &&
       [[ "$line_count" == 3 ]] &&
       [[ $(grep -cE '^OPENCODE_SERVER_USERNAME=opencode$' "$OPENCODE_DIR/server.env" || true) == 1 ]] &&
       [[ $(grep -cE '^OPENCODE_SERVER_PASSWORD=[0-9a-f]{48}$' "$OPENCODE_DIR/server.env" || true) == 1 ]] &&
       [[ $(grep -c '^OPENCODE_CONFIG_CONTENT=' "$OPENCODE_DIR/server.env" || true) == 1 ]]; then
        printf 'PASS  OpenCode credentials present with mode 0600\n'
    else
        printf 'FAIL  OpenCode credentials are missing or unsafe\n' >&2
        failed=1
    fi
    check 'OpenCode user service enabled' systemctl --user is-enabled opencode.service
    check 'OpenCode user service active' systemctl --user is-active opencode.service
    check 'OpenCode service uses pure mode' grep -Fq -- 'opencode serve --pure' "$HOME/.config/systemd/user/opencode.service"
    check 'OpenCode service uses isolated workspace' grep -Fq 'WorkingDirectory=%h/OpenCodeWorkspace' "$HOME/.config/systemd/user/opencode.service"
    check 'OpenCode service disables project config' grep -Fq 'Environment=OPENCODE_DISABLE_PROJECT_CONFIG=1' "$HOME/.config/systemd/user/opencode.service"
    check 'OpenCode service uses restrictive umask' grep -Fq 'UMask=0077' "$HOME/.config/systemd/user/opencode.service"
    if ss -lnt | grep -qE '(^|[[:space:]])127\.0\.0\.1:4096[[:space:]]'; then
        printf 'PASS  OpenCode listens on loopback\n'
    else
        printf 'FAIL  OpenCode is not listening on 127.0.0.1:4096\n' >&2
        failed=1
    fi
    unauth_status=$(curl --silent --output /dev/null --write-out '%{http_code}' http://127.0.0.1:4096/global/health || true)
    if [[ "$unauth_status" == 401 ]]; then
        printf 'PASS  OpenCode rejects unauthenticated requests\n'
    else
        printf 'FAIL  OpenCode unauthenticated status is %s, expected 401\n' "$unauth_status" >&2
        failed=1
    fi
    password=$(while IFS= read -r line; do case "$line" in OPENCODE_SERVER_PASSWORD=*) printf '%s' "${line#*=}"; break ;; esac; done <"$OPENCODE_DIR/server.env")
    config_content=$(while IFS= read -r line; do case "$line" in OPENCODE_CONFIG_CONTENT=*) printf '%s' "${line#*=}"; break ;; esac; done <"$OPENCODE_DIR/server.env")
    config_content=${config_content#\'}
    config_content=${config_content%\'}
    resolved_config=$(mktemp)
    if (cd "$HOME/OpenCodeWorkspace" && env HOME="$service_home" XDG_CONFIG_HOME="$service_home/.config" XDG_DATA_HOME="$service_home/.local/share" XDG_STATE_HOME="$service_home/.local/state" XDG_CACHE_HOME="$service_home/.cache" OPENCODE_CONFIG="$service_config_dir/opencode.json" OPENCODE_CONFIG_DIR="$service_config_dir" OPENCODE_DISABLE_PROJECT_CONFIG=1 OPENCODE_CONFIG_CONTENT="$config_content" opencode debug config --pure >"$resolved_config" 2>/dev/null) &&
       jq -e '.share == "disabled" and .server.hostname == "127.0.0.1" and .server.port == 4096 and .server.mdns == false and .permission.external_directory == "deny" and .plugin == [] and .instructions == [] and (.mcp // {} | length == 0) and (.command // {} | length == 0) and ((.agent // {} | keys - ["code-reviewer", "planner"] | length) == 0) and (.tools == null) and (.formatter == null or .formatter == false) and (.lsp == null or .lsp == false)' "$resolved_config" >/dev/null; then
        printf 'PASS  OpenCode effective service policy is hardened\n'
    else
        printf 'FAIL  OpenCode effective service policy is not hardened\n' >&2
        failed=1
    fi
    rm -f -- "$resolved_config"
    netrc=$(mktemp)
    printf 'machine 127.0.0.1 login opencode password %s\n' "$password" >"$netrc"
    chmod 0600 "$netrc"
    if curl --fail --silent --netrc-file "$netrc" http://127.0.0.1:4096/global/health | jq -e '.healthy == true' >/dev/null; then
        printf 'PASS  OpenCode accepts generated credentials\n'
    else
        printf 'FAIL  OpenCode generated credentials do not authenticate\n' >&2
        failed=1
    fi
    rm -f -- "$netrc"
    serve_json=$(tailscale serve status --json 2>/dev/null || printf '{}')
    if [[ "$EXPECTED_REMOTE" == tailscale ]]; then
        if [[ -f "$STATE_DIR/tailscale-8443-owned" ]] &&
           jq -e '. as $status | ([.Web | to_entries[]? | select(.key | endswith(":8443"))]) as $routes | (.TCP["8443"].HTTPS? == true) and ($routes | length == 1) and ($routes[0].value.Handlers | keys == ["/"]) and ($routes[0].value.Handlers["/"].Proxy == "http://127.0.0.1:4096") and (($status.AllowFunnel[$routes[0].key]? // false) == false)' <<<"$serve_json" >/dev/null; then
            printf 'PASS  Tailscale Serve owns dedicated OpenCode route\n'
        else
            printf 'FAIL  requested Tailscale OpenCode route is missing\n' >&2
            failed=1
        fi
    elif [[ -f "$STATE_DIR/tailscale-8443-owned" ]] || jq -e '(.TCP["8443"].HTTPS? == true) and ([.Web | to_entries[]? | select(.key | endswith(":8443")) | .value.Handlers[]?.Proxy] | any(. == "http://127.0.0.1:4096"))' <<<"$serve_json" >/dev/null; then
        printf 'FAIL  installer ownership marker remains in %s mode\n' "$EXPECTED_REMOTE" >&2
        failed=1
    fi
else
    if systemctl --user is-active --quiet opencode.service; then
        printf 'FAIL  OpenCode service is active despite profile selection\n' >&2
        failed=1
    else
        printf 'PASS  OpenCode service is inactive as selected\n'
    fi
    serve_json=$(tailscale serve status --json 2>/dev/null || printf '{}')
    if [[ -f "$STATE_DIR/tailscale-8443-owned" ]] || jq -e '(.TCP["8443"].HTTPS? == true) and ([.Web | to_entries[]? | select(.key | endswith(":8443")) | .value.Handlers[]?.Proxy] | any(. == "http://127.0.0.1:4096"))' <<<"$serve_json" >/dev/null; then
        printf 'FAIL  OpenCode Tailscale ownership remains despite disabled service\n' >&2
        failed=1
    fi
fi

system_failed=$(systemctl --failed --no-legend || true)
user_failed=$(systemctl --user --failed --no-legend || true)
[[ -z "$system_failed" ]] && printf 'PASS  no failed system units\n' || printf 'WARN  pre-existing or new failed system units require review\n'
[[ -z "$user_failed" ]] && printf 'PASS  no failed user units\n' || printf 'WARN  pre-existing or new failed user units require review\n'

exit "$failed"
