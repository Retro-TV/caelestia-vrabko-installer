#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -Eeuo pipefail
umask 077

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/caelestia-vrabko-installer
CONFIG_DIR=${XDG_CONFIG_HOME:-$HOME/.config}/caelestia-vrabko-installer
CAELESTIA_STATE_DIR=${XDG_STATE_HOME:-$HOME/.local/state}/caelestia
BACKUP_DIR="$STATE_DIR/backups/$(date -u +%Y%m%dT%H%M%S%NZ)"
LOG_FILE="$STATE_DIR/install.log"
PREPARED_DOTS_DIR=
PREPARED_DOTS_REPO=
DRY_RUN=false
ASSUME_YES=false
PROFILE_PATH=
ALLOW_EXPERIMENTAL=false

PROFILE_VERSION=2
PRESET=generic
LOCALE=en_US.UTF-8
KEYBOARD_LAYOUT=us
KEYBIND_PRESET=default
BROWSER=firefox
GAMING=none
COMMUNICATION=none
DEVELOPMENT=basic
INSTALL_AW=yes
INSTALL_OPENCODE=yes
REMOTE_ACCESS=local
CURRENT_STAGE=preflight

usage() {
    cat <<'EOF'
Usage: ./install.sh [options]

Options:
  --profile FILE        Load a non-secret preference profile
  --dry-run             Print the resolved plan without mutation
  --yes                 Accept the final plan (requires --profile)
  --allow-experimental  Permit Manjaro or unknown pacman-based distributions
  -h, --help            Show this help
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    printf 'Installation stopped during: %s\n' "$CURRENT_STAGE" >&2
    printf 'Review %s and backups under %s before rebooting.\n' "$LOG_FILE" "$BACKUP_DIR" >&2
    exit 1
}

on_error() {
    local status=$?
    [[ -z "$PREPARED_DOTS_DIR" ]] || rm -rf -- "$PREPARED_DOTS_DIR"
    printf '\nInstallation stopped during: %s\n' "$CURRENT_STAGE" >&2
    printf 'Review %s and backups under %s before rebooting.\n' "$LOG_FILE" "$BACKUP_DIR" >&2
    exit "$status"
}

trap on_error ERR

note() {
    printf '\n==> %s\n' "$*"
}

stage() {
    printf '%s\t%s\n' "$(date --iso-8601=seconds)" "$1" >>"$LOG_FILE"
    note "$1"
}

yes_no() {
    local prompt=$1 default=$2 answer
    while true; do
        if [[ "$default" == yes ]]; then
            read -r -p "$prompt [Y/n]: " answer
            answer=${answer:-y}
        else
            read -r -p "$prompt [y/N]: " answer
            answer=${answer:-n}
        fi
        case "$answer" in
            y|Y|yes|YES) printf 'yes\n'; return ;;
            n|N|no|NO) printf 'no\n'; return ;;
        esac
    done
}

choose() {
    local prompt=$1
    shift
    local option
    printf '\n%s\n' "$prompt" >&2
    select option in "$@"; do
        [[ -n "$option" ]] && { printf '%s\n' "$option"; return; }
        printf 'Choose a listed number.\n' >&2
    done
}

valid_choice() {
    local value=$1
    shift
    local allowed
    for allowed in "$@"; do
        [[ "$value" == "$allowed" ]] && return 0
    done
    return 1
}

load_profile() {
    local file=$1 line key value
    [[ -f "$file" ]] || die "Profile does not exist: $file"
    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" || "$line" == \#* ]] && continue
        [[ "$line" == *=* ]] || die "Invalid profile line: $line"
        key=${line%%=*}
        value=${line#*=}
        case "$key" in
            PROFILE_VERSION|PRESET|LOCALE|KEYBOARD_LAYOUT|KEYBIND_PRESET|BROWSER|GAMING|COMMUNICATION|DEVELOPMENT|INSTALL_AW|INSTALL_OPENCODE|REMOTE_ACCESS)
                printf -v "$key" '%s' "$value"
                ;;
            *) die "Unknown profile key: $key" ;;
        esac
    done <"$file"
}

validate_profile() {
    [[ "$PROFILE_VERSION" == 2 ]] || die "Unsupported profile version: $PROFILE_VERSION"
    [[ "$LOCALE" =~ ^[a-z]{2}_[A-Z]{2}\.UTF-8$ ]] || die "Invalid locale: $LOCALE"
    [[ "$KEYBOARD_LAYOUT" =~ ^[a-z0-9_-]+$ ]] || die "Invalid keyboard layout: $KEYBOARD_LAYOUT"
    valid_choice "$PRESET" generic vrabko || die "Invalid preset: $PRESET"
    valid_choice "$KEYBIND_PRESET" default vrabko || die "Invalid keybind preset: $KEYBIND_PRESET"
    valid_choice "$BROWSER" firefox chromium none || die "Invalid browser: $BROWSER"
    valid_choice "$GAMING" none basic full || die "Invalid gaming bundle: $GAMING"
    valid_choice "$COMMUNICATION" none basic full || die "Invalid communication bundle: $COMMUNICATION"
    valid_choice "$DEVELOPMENT" none basic full || die "Invalid development bundle: $DEVELOPMENT"
    valid_choice "$INSTALL_AW" yes no || die "INSTALL_AW must be yes or no"
    valid_choice "$INSTALL_OPENCODE" yes no || die "INSTALL_OPENCODE must be yes or no"
    valid_choice "$REMOTE_ACCESS" local tailscale cloudflare || die "Invalid remote mode: $REMOTE_ACCESS"
    [[ "$INSTALL_OPENCODE" == yes || "$REMOTE_ACCESS" == local ]] || die "Remote access requires OpenCode"
}

interactive_profile() {
    PRESET=$(choose 'Choose a starting preset:' generic vrabko)
    if [[ "$PRESET" == vrabko ]]; then
        LOCALE=sl_SI.UTF-8
        KEYBOARD_LAYOUT=si
        KEYBIND_PRESET=vrabko
        GAMING=full
        COMMUNICATION=full
        DEVELOPMENT=full
    fi

    read -r -p "Locale [$LOCALE]: " answer
    LOCALE=${answer:-$LOCALE}
    read -r -p "Hyprland keyboard layout [$KEYBOARD_LAYOUT]: " answer
    KEYBOARD_LAYOUT=${answer:-$KEYBOARD_LAYOUT}
    KEYBIND_PRESET=$(choose 'Choose keybind preset:' default vrabko)
    BROWSER=$(choose 'Choose browser:' firefox chromium none)
    GAMING=$(choose 'Choose gaming bundle:' none basic full)
    COMMUNICATION=$(choose 'Choose communication bundle:' none basic full)
    DEVELOPMENT=$(choose 'Choose development bundle:' none basic full)
    INSTALL_AW=$(yes_no 'Install pinned animated-wallpaper support?' yes)
    INSTALL_OPENCODE=$(yes_no 'Install authenticated OpenCode localhost service?' yes)
    if [[ "$INSTALL_OPENCODE" == yes ]]; then
        REMOTE_ACCESS=$(choose 'Choose OpenCode access:' local tailscale cloudflare)
    else
        REMOTE_ACCESS=local
    fi
}

detect_distribution() {
    [[ -r /etc/os-release ]] || die '/etc/os-release is missing'
    # shellcheck disable=SC1091
    source /etc/os-release
    DISTRO_ID=${ID:-unknown}
    case "$DISTRO_ID" in
        arch|cachyos|endeavouros) DISTRO_STATUS=supported ;;
        manjaro) DISTRO_STATUS=experimental ;;
        *) DISTRO_STATUS=experimental ;;
    esac
    command -v pacman >/dev/null || die 'pacman is required'
    command -v systemctl >/dev/null || die 'systemd is required'
    [[ $(uname -m) == x86_64 ]] || die 'The initial release supports x86_64 only'
    [[ $USER =~ ^[a-z_][a-z0-9_-]*$ ]] || die 'Unsupported username format'
    [[ ${XDG_CONFIG_HOME:-$HOME/.config} == "$HOME/.config" ]] || die 'The initial release requires the default XDG_CONFIG_HOME'
    getent hosts archlinux.org >/dev/null || die 'Working DNS and internet access are required'
    local available
    available=$(df --output=avail -B1 "$HOME" | tail -n 1)
    ((available >= 12 * 1024 * 1024 * 1024)) || die 'At least 12 GiB free space is required on the home/build filesystem'

    if systemctl is-enabled display-manager.service >/dev/null 2>&1; then
        local display_manager
        display_manager=$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)
        [[ "$display_manager" == */greetd.service ]] || die "Another display manager is enabled: ${display_manager:-unknown}"
    fi
}

detect_graphics() {
    GPU_AMD=false
    GPU_INTEL=false
    GPU_NVIDIA=false
    GPU_UNKNOWN=false
    GPU_VIRTUAL=false
    GPU_COUNT=0
    local vendor vendor_file
    shopt -s nullglob
    for vendor_file in /sys/class/drm/card*/device/vendor; do
        ((GPU_COUNT += 1))
        vendor=$(<"$vendor_file")
        case "$vendor" in
            0x1002) GPU_AMD=true ;;
            0x8086) GPU_INTEL=true ;;
            0x10de) GPU_NVIDIA=true ;;
            0x1af4|0x1234|0x1b36|0x15ad|0x80ee|0x1414)
                if systemd-detect-virt --vm --quiet; then
                    GPU_VIRTUAL=true
                else
                    GPU_UNKNOWN=true
                fi
                ;;
            *) GPU_UNKNOWN=true ;;
        esac
    done
}

validate_graphics() {
    ((GPU_COUNT > 0)) || die 'No supported DRM graphics device was detected; refusing desktop mutation'
    [[ "$GPU_UNKNOWN" == false ]] || die 'An unsupported graphics vendor was detected; refusing desktop mutation'
    if [[ "$GPU_NVIDIA" == true ]]; then
        local vendor_file driver module_path module_owner driver_package
        for vendor_file in /sys/class/drm/card*/device/vendor; do
            [[ $(<"$vendor_file") == 0x10de ]] || continue
            driver=$(readlink -f "${vendor_file%/vendor}/driver" 2>/dev/null || true)
            [[ ${driver##*/} == nvidia ]] || die 'NVIDIA GPU is not bound to the nvidia kernel driver'
        done
        module_path=$(modinfo -n nvidia 2>/dev/null || true)
        [[ -f "$module_path" ]] || die 'The loaded NVIDIA driver has no persistent kernel module on disk'
        module_owner=$(pacman -Qoq "$module_path" 2>/dev/null || true)
        if [[ -n "$module_owner" ]]; then
            [[ "$module_owner" =~ ^(nvidia(-open)?|linux[^[:space:]]*-nvidia(-open)?)$ ]] || \
                die "NVIDIA module is owned by an unrecognized package: $module_owner"
        else
            driver_package=$(pacman -Qq | grep -E '^(nvidia(-open)?-dkms|nvidia-[0-9]+xx(-open)?-dkms)$' || true)
            [[ -n "$driver_package" && "$module_path" == */updates/dkms/nvidia.ko* ]] || \
                die 'NVIDIA module is neither package-owned nor backed by a recognized DKMS package'
        fi
    fi
}

resolve_packages() {
    REPO_PACKAGES=(base-devel git curl jq openssl ca-certificates pciutils greetd greetd-tuigreet uwsm
        hyprland xdg-desktop-portal-hyprland xdg-desktop-portal-gtk ttf-jetbrains-mono-nerd
        fish eza zoxide direnv foot fastfetch btop micro thunar starship lazygit
        gnome-keyring polkit-gnome networkmanager
        bluez bluez-utils pipewire pipewire-pulse pipewire-audio pipewire-alsa pipewire-jack
        wireplumber pavucontrol wl-clipboard cliphist noto-fonts noto-fonts-cjk noto-fonts-emoji
        trash-cli bat ripgrep ydotool hyprpicker xdg-user-dirs)
    SOURCE_PACKAGES=(python-materialyoucolor libcava ttf-rubik-vf quickshell-git)
    SKIPPED_PACKAGES=()

    if [[ "$GPU_AMD" == true ]]; then
        REPO_PACKAGES+=(mesa vulkan-radeon)
        if pacman -Si libva-mesa-driver >/dev/null 2>&1; then
            REPO_PACKAGES+=(libva-mesa-driver)
        fi
    fi
    [[ "$GPU_INTEL" == true ]] && REPO_PACKAGES+=(mesa vulkan-intel intel-media-driver)
    [[ "$GPU_VIRTUAL" == true ]] && REPO_PACKAGES+=(mesa vulkan-swrast)
    if [[ "$GPU_NVIDIA" == true ]]; then
        if [[ -z $(pacman -Qq | grep -E '^(nvidia(-open)?(-dkms)?|nvidia-[0-9]+xx(-open)?-dkms|linux[^[:space:]]*-nvidia(-open)?)$' || true) ]]; then
            die 'NVIDIA GPU detected without a recognized driver. Install the distro-appropriate NVIDIA driver first.'
        fi
        REPO_PACKAGES+=(nvidia-utils egl-wayland)
    fi

    [[ "$BROWSER" != none ]] && REPO_PACKAGES+=("$BROWSER")
    case "$GAMING" in
        basic)
            REPO_PACKAGES+=(lutris gamemode mangohud)
            if pacman -Si steam >/dev/null 2>&1; then
                REPO_PACKAGES+=(steam)
            else
                SKIPPED_PACKAGES+=(steam)
            fi
            ;;
        full)
            REPO_PACKAGES+=(lutris gamemode mangohud wine-staging winetricks)
            if pacman -Si steam >/dev/null 2>&1; then
                REPO_PACKAGES+=(steam)
            else
                SKIPPED_PACKAGES+=(steam)
            fi
            if pacman -Si heroic-games-launcher-bin >/dev/null 2>&1; then
                REPO_PACKAGES+=(heroic-games-launcher-bin)
            else
                SKIPPED_PACKAGES+=(heroic-games-launcher-bin)
            fi
            ;;
    esac
    case "$COMMUNICATION" in
        basic) REPO_PACKAGES+=(telegram-desktop) ;;
        full)
            REPO_PACKAGES+=(telegram-desktop signal-desktop)
            if pacman -Si vesktop-bin >/dev/null 2>&1; then
                REPO_PACKAGES+=(vesktop-bin)
            else
                REPO_PACKAGES+=(discord)
                SKIPPED_PACKAGES+=(vesktop-bin)
            fi
            ;;
    esac
    case "$DEVELOPMENT" in
        basic) REPO_PACKAGES+=(code github-cli) ;;
        full) REPO_PACKAGES+=(code github-cli docker docker-compose lazygit shellcheck) ;;
    esac
    if [[ "$INSTALL_OPENCODE" == yes ]]; then
        pacman -Si opencode >/dev/null 2>&1 || die 'OpenCode is unavailable from this distribution repository; refusing an unpinned fallback'
        REPO_PACKAGES+=(opencode)
    fi
    [[ "$REMOTE_ACCESS" == tailscale ]] && REPO_PACKAGES+=(tailscale)
    [[ "$REMOTE_ACCESS" == cloudflare ]] && REPO_PACKAGES+=(cloudflared)
    return 0
}

print_plan() {
    cat <<EOF

Caelestia Vrabko installation plan
----------------------------------
Distribution:       $DISTRO_ID ($DISTRO_STATUS)
Preset:             $PRESET
Locale:             $LOCALE
Keyboard:           $KEYBOARD_LAYOUT
Keybinds:           $KEYBIND_PRESET
Browser:            $BROWSER
Gaming:             $GAMING
Communication:      $COMMUNICATION
Development:        $DEVELOPMENT
Animated wallpaper: $INSTALL_AW
OpenCode:           $INSTALL_OPENCODE ($REMOTE_ACCESS)
Desktop autologin:  disabled
Graphics detected:  AMD=$GPU_AMD Intel=$GPU_INTEL NVIDIA=$GPU_NVIDIA Unknown=$GPU_UNKNOWN
Virtual graphics:   $GPU_VIRTUAL

Repository packages:
  ${REPO_PACKAGES[*]}
Pinned source packages:
  ${SOURCE_PACKAGES[*]}
Repository-only extras unavailable on this distribution:
  ${SKIPPED_PACKAGES[*]:-none}

Known installer-owned configuration will be backed up before replacement.
Package installation performs a full system upgrade. Caelestia, Quickshell and
Arch-only dependencies are built from checksum-pinned local recipes; no AUR
helper or moving AUR metadata is executed.
EOF
}

backup_path() {
    local path=$1 relative destination
    [[ -e "$path" || -L "$path" ]] || return 0
    relative=${path#/}
    destination="$BACKUP_DIR/$relative"
    [[ -e "$destination" || -L "$destination" ]] && return 0
    install -d -m 0700 "$BACKUP_DIR/$(dirname "$relative")"
    cp -a -- "$path" "$destination"
}

enable_multilib() {
    [[ "$GAMING" == none ]] && return 0
    if pacman -Sl multilib >/dev/null 2>&1; then
        return 0
    fi
    if ! grep -q '^#\[multilib\]$' /etc/pacman.conf; then
        note 'This distribution has no separate multilib repository; continuing with repository-available gaming packages'
        return 0
    fi
    stage 'Enabling Arch multilib repository for gaming packages'
    local temp
    backup_path /etc/pacman.conf
    temp=$(mktemp)
    awk '
        /^#\[multilib\]$/ { in_multilib=1; sub(/^#/, "") }
        /^\[/ && $0 !~ /^#?\[multilib\]$/ { in_multilib=0 }
        in_multilib && /^#Include = \/etc\/pacman.d\/mirrorlist$/ { sub(/^#/, "") }
        { print }
    ' /etc/pacman.conf >"$temp"
    sudo install -m 0644 "$temp" /etc/pacman.conf
    rm -f -- "$temp"
    awk '
        /^\[multilib\]$/ { found=1; next }
        found && /^Include = \/etc\/pacman.d\/mirrorlist$/ { usable=1 }
        found && /^\[/ { found=0 }
        END { exit !usable }
    ' /etc/pacman.conf || die 'Unable to enable a usable multilib repository safely'
}

install_packages() {
    stage 'Upgrading system and installing base packages'
    sudo pacman -Syu --needed --noconfirm "${REPO_PACKAGES[@]}"
}

build_source_package() {
    local name=$1
    build_source_archive "$name"
    sudo pacman -U --noconfirm "$BUILT_PACKAGE_FILE"
}

build_source_archive() {
    local name=$1 package_dir="$ROOT/packages/$1"
    [[ -f "$package_dir/PKGBUILD" ]] || die "Missing pinned package recipe: $name"
    (cd "$package_dir" && makepkg --cleanbuild --force --syncdeps --noconfirm)
    BUILT_PACKAGE_FILE=$(cd "$package_dir" && makepkg --packagelist)
    [[ -f "$BUILT_PACKAGE_FILE" ]] || die "Pinned build did not produce an archive: $name"
}

prepare_verified_sources() {
    stage 'Verifying pinned source inputs before package mutation'
    local name dots_commit dots_sha256 dots_archive archive_tree
    for name in "${SOURCE_PACKAGES[@]}"; do
        (cd "$ROOT/packages/$name" && makepkg --verifysource)
    done
    if [[ "$INSTALL_AW" == yes ]]; then
        (cd "$ROOT/packages/caelestia-cli-aw" && makepkg --verifysource)
        (cd "$ROOT/packages/caelestia-shell-aw" && makepkg --verifysource)
    else
        (cd "$ROOT/packages/caelestia-cli" && makepkg --verifysource)
        (cd "$ROOT/packages/caelestia-shell" && makepkg --verifysource)
    fi
    dots_commit=$(awk -F= '$1 == "dots_commit" { print $2 }' "$ROOT/versions.lock")
    dots_sha256=$(awk -F= '$1 == "dots_sha256" { print $2 }' "$ROOT/versions.lock")
    [[ "$dots_commit" =~ ^[0-9a-f]{40}$ ]] || die 'versions.lock has an invalid dots commit'
    [[ "$dots_sha256" =~ ^[0-9a-f]{64}$ ]] || die 'versions.lock has an invalid dots archive checksum'
    PREPARED_DOTS_DIR=$(mktemp -d)
    PREPARED_DOTS_REPO="$PREPARED_DOTS_DIR/repo"
    dots_archive="$PREPARED_DOTS_DIR/dots.tar.gz"
    curl --fail --location --output "$dots_archive" \
        "https://github.com/caelestia-dots/caelestia/archive/$dots_commit.tar.gz"
    [[ $(sha256sum "$dots_archive" | cut -d' ' -f1) == "$dots_sha256" ]] || die 'Pinned dots archive checksum failed'
    git -C "$PREPARED_DOTS_DIR" init --quiet repo
    git -C "$PREPARED_DOTS_REPO" remote add origin https://github.com/caelestia-dots/caelestia.git
    git -C "$PREPARED_DOTS_REPO" fetch --quiet --depth 1 origin "$dots_commit"
    git -C "$PREPARED_DOTS_REPO" checkout --quiet --detach FETCH_HEAD
    [[ $(git -C "$PREPARED_DOTS_REPO" rev-parse HEAD) == "$dots_commit" ]] || die 'Fetched dots commit does not match versions.lock'
    [[ -s "$PREPARED_DOTS_REPO/manifest.toml" ]] || die 'Pinned dots manifest is missing'
    archive_tree="$PREPARED_DOTS_DIR/archive"
    install -d -m 0700 "$archive_tree"
    bsdtar -xf "$dots_archive" -C "$archive_tree"
    diff -qr --exclude=.git "$archive_tree/caelestia-$dots_commit" "$PREPARED_DOTS_REPO" >/dev/null || \
        die 'Dots archive and Git commit trees differ'
}

install_caelestia() {
    stage 'Building pinned Caelestia package set'
    local name input_dir cli_config temp dots_commit external_marker cli_package shell_package installer_version dots_branch
    local -a opposite_packages=()
    for name in "${SOURCE_PACKAGES[@]}"; do
        build_source_package "$name"
    done
    if [[ "$INSTALL_AW" == yes ]]; then
        build_source_archive caelestia-cli-aw
        cli_package=$BUILT_PACKAGE_FILE
        build_source_archive caelestia-shell-aw
        shell_package=$BUILT_PACKAGE_FILE
        pacman -Q caelestia-cli >/dev/null 2>&1 && opposite_packages+=(caelestia-cli)
        pacman -Q caelestia-shell >/dev/null 2>&1 && opposite_packages+=(caelestia-shell)
    else
        build_source_archive caelestia-cli
        cli_package=$BUILT_PACKAGE_FILE
        build_source_archive caelestia-shell
        shell_package=$BUILT_PACKAGE_FILE
        pacman -Q caelestia-cli-aw >/dev/null 2>&1 && opposite_packages+=(caelestia-cli-aw)
        pacman -Q caelestia-shell-aw >/dev/null 2>&1 && opposite_packages+=(caelestia-shell-aw)
    fi
    if ((${#opposite_packages[@]} > 0)); then
        sudo pacman -Rdd --noconfirm "${opposite_packages[@]}"
    fi
    sudo pacman -U --noconfirm "$cli_package" "$shell_package"

    input_dir="$STATE_DIR/inputs/caelestia-dots"
    backup_path "$input_dir"
    rm -rf -- "$input_dir"
    install -d -m 0700 "$(dirname "$input_dir")"
    mv -- "$PREPARED_DOTS_REPO" "$input_dir"
    rm -rf -- "$PREPARED_DOTS_DIR"
    PREPARED_DOTS_DIR=
    PREPARED_DOTS_REPO=
    installer_version=$(awk -F= '$1 == "installer_version" { print $2 }' "$ROOT/versions.lock")
    dots_branch="installer-v$installer_version"
    git -C "$input_dir" branch --force "$dots_branch" HEAD

    backup_path "$HOME/.config"
    cli_config="$HOME/.config/caelestia/cli.json"
    backup_path "$cli_config"
    install -d -m 0700 "$(dirname "$cli_config")"
    temp=$(mktemp)
    if [[ -s "$cli_config" ]] && jq empty "$cli_config" 2>/dev/null; then
        jq --arg url "file://$input_dir" --arg branch "$dots_branch" '. * {dots: {url: $url, branch: $branch}}' "$cli_config" >"$temp"
    else
        jq -n --arg url "file://$input_dir" --arg branch "$dots_branch" '{dots: {url: $url, branch: $branch}}' >"$temp"
    fi
    install -m 0600 "$temp" "$cli_config"
    rm -f -- "$temp"

    dots_commit=$(awk -F= '$1 == "dots_commit" { print $2 }' "$ROOT/versions.lock")
    external_marker="$CAELESTIA_STATE_DIR/externally-managed"
    install -d -m 0700 "$(dirname "$external_marker")"
    printf 'Managed by caelestia-vrabko-installer at dots commit %s\n' "$dots_commit" >"$external_marker"
    chmod 0600 "$external_marker"
    CAELESTIA_DOTS_REV="$dots_commit" CAELESTIA_SKIP_PACKAGE_INSTALL=1 \
        caelestia install --enable-components uwsm --disable-components firefox,gtk,qt --noconfirm
    [[ $(jq -r '.applied_rev' "$CAELESTIA_STATE_DIR/dots-state.json") == "$dots_commit" ]] || \
        die 'Caelestia did not apply the locked dots commit'
}

configure_locale() {
    stage 'Configuring locale and keyboard preference'
    local locale_source=${LOCALE%%.*}
    sudo localedef -i "$locale_source" -f UTF-8 "$LOCALE"
    sudo localectl set-locale "LANG=$LOCALE"
}

configure_caelestia() {
    stage 'Installing Caelestia preference overlay'
    local caelestia_dir=${XDG_CONFIG_HOME:-$HOME/.config}/caelestia
    backup_path "$caelestia_dir/hypr-user.lua"
    backup_path "$caelestia_dir/hypr-vars.lua"
    install -d -m 0700 "$caelestia_dir"
    cat >"$caelestia_dir/hypr-user.lua" <<EOF
-- Generated by Caelestia Vrabko Installer.
-- Reapply the selected layout after startup and wallpaper-driven reloads.
local function apply_keyboard_layout()
    hl.exec_cmd([[hyprctl eval 'hl.config({ input = { kb_layout = "$KEYBOARD_LAYOUT" } })']])
end

hl.on("hyprland.start", apply_keyboard_layout)
hl.on("config.reloaded", apply_keyboard_layout)
EOF
    if [[ "$KEYBIND_PRESET" == vrabko ]]; then
        cat >>"$caelestia_dir/hypr-user.lua" <<'EOF'

hl.bind("code:133", hl.dsp.global("caelestia:launcher"), { release = true })
EOF
    fi

    cat >"$caelestia_dir/hypr-vars.lua" <<EOF
return {
    browser = "$BROWSER",
EOF
    if [[ "$KEYBIND_PRESET" == vrabko ]]; then
        cat >>"$caelestia_dir/hypr-vars.lua" <<'EOF'
    kbMoveWinToWs = "SUPER + SHIFT",
    kbWindowFullscreen = "ALT + Return",
    kbBrowser = "SUPER + F",
EOF
    fi
    printf '}\n' >>"$caelestia_dir/hypr-vars.lua"
    chmod 0600 "$caelestia_dir/hypr-user.lua" "$caelestia_dir/hypr-vars.lua"
}

configure_greetd() {
    stage 'Configuring greetd and UWSM'
    local config=/etc/greetd/config.toml temp
    backup_path "$config"
    temp=$(mktemp)
    cat >"$temp" <<'EOF'
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --user-menu --remember --remember-session --cmd 'uwsm start -e -D Hyprland hyprland.desktop'"
user = "greeter"
EOF
    sudo install -D -m 0644 "$temp" "$config"
    rm -f -- "$temp"
    sudo systemctl enable greetd.service
}

tailscale_status_json() {
    command -v tailscale >/dev/null || return 1
    sudo tailscale serve status --json 2>/dev/null
}

tailscale_port_8443_exists() {
    tailscale_status_json | jq -e '.TCP["8443"]? != null' >/dev/null
}

tailscale_route_matches() {
    tailscale_status_json | jq -e '
        . as $status |
        ([.Web | to_entries[]? | select(.key | endswith(":8443"))]) as $routes |
        (.TCP["8443"].HTTPS? == true) and
        ($routes | length == 1) and
        ($routes[0].value.Handlers | keys == ["/"]) and
        ($routes[0].value.Handlers["/"].Proxy == "http://127.0.0.1:4096") and
        (($status.AllowFunnel[$routes[0].key]? // false) == false)
    ' >/dev/null
}

ensure_no_unowned_opencode_route() {
    if [[ ! -f "$STATE_DIR/tailscale-8443-owned" ]] && tailscale_route_matches; then
        die 'An unowned OpenCode Tailscale route remains on HTTPS port 8443; remove it explicitly'
    fi
}

remove_owned_tailscale_route() {
    if [[ -f "$STATE_DIR/tailscale-8443-pending" ]]; then
        command -v tailscale >/dev/null || die 'Cannot resolve pending Tailscale state because tailscale is unavailable'
        tailscale_port_8443_exists && die 'Tailscale route creation was interrupted; inspect port 8443 and remove it explicitly before rerunning'
        rm -f -- "$STATE_DIR/tailscale-8443-pending"
    fi
    [[ -f "$STATE_DIR/tailscale-8443-owned" ]] || return 0
    command -v tailscale >/dev/null || die 'Cannot remove the owned Tailscale route because tailscale is unavailable'
    if ! tailscale_port_8443_exists; then
        rm -f -- "$STATE_DIR/tailscale-8443-owned"
        return 0
    fi
    tailscale_route_matches || die 'Tailscale port 8443 no longer matches the installer-owned OpenCode route; refusing deletion'
    sudo tailscale serve --https=8443 off
    if tailscale_port_8443_exists; then
        die 'Tailscale port 8443 remained configured after removal'
    fi
    rm -f -- "$STATE_DIR/tailscale-8443-owned"
}

configure_opencode() {
    local opencode_dir=$HOME/.config/opencode
    local user_unit_dir=$HOME/.config/systemd/user
    if [[ "$INSTALL_OPENCODE" != yes ]]; then
        systemctl --user disable --now opencode.service 2>/dev/null || true
        remove_owned_tailscale_route
        ensure_no_unowned_opencode_route
        return 0
    fi
    stage 'Configuring authenticated localhost OpenCode service'
    local password config_content password_count
    local service_home="$HOME/.local/share/caelestia-vrabko-installer/opencode-home"
    local service_config_dir="$service_home/.config/opencode"
    backup_path "$user_unit_dir/opencode.service"
    backup_path "$service_config_dir"
    rm -rf -- "$service_config_dir"
    install -d -m 0700 "$opencode_dir" "$service_config_dir/agents" "$user_unit_dir"
    install -d -m 0700 "$HOME/OpenCodeWorkspace"
    install -m 0600 "$ROOT/templates/opencode/opencode.json" "$service_config_dir/opencode.json"
    install -m 0600 "$ROOT/templates/opencode/agents/code-reviewer.md" "$service_config_dir/agents/code-reviewer.md"
    install -m 0600 "$ROOT/templates/opencode/agents/planner.md" "$service_config_dir/agents/planner.md"
    backup_path "$opencode_dir/server.env"
    password_count=0
    [[ -f "$opencode_dir/server.env" ]] && password_count=$(grep -cE '^OPENCODE_SERVER_PASSWORD=[0-9a-f]{48}$' "$opencode_dir/server.env" || true)
    if [[ "$password_count" == 1 ]]; then
        password=$(while IFS= read -r line; do case "$line" in OPENCODE_SERVER_PASSWORD=*) printf '%s' "${line#*=}"; break ;; esac; done <"$opencode_dir/server.env")
    else
        password=$(openssl rand -hex 24)
        printf '\nOpenCode credentials created in %s/server.env (mode 0600).\n' "$opencode_dir"
    fi
    config_content=$(jq -c . "$ROOT/templates/opencode/opencode.json")
    printf "OPENCODE_SERVER_USERNAME=opencode\nOPENCODE_SERVER_PASSWORD=%s\nOPENCODE_CONFIG_CONTENT='%s'\n" "$password" "$config_content" >"$opencode_dir/server.env"
    chmod 0600 "$opencode_dir/server.env"
    install -m 0644 "$ROOT/templates/opencode/opencode.service" "$user_unit_dir/opencode.service"
    systemctl --user daemon-reload
    systemctl --user enable opencode.service
    sudo loginctl enable-linger "$USER"
    systemctl --user restart opencode.service

    case "$REMOTE_ACCESS" in
        tailscale)
            stage 'Configuring tailnet-only OpenCode access'
            sudo systemctl enable --now tailscaled.service
            if ! tailscale status --json 2>/dev/null | jq -e '.BackendState == "Running"' >/dev/null; then
                sudo tailscale up
            fi
            if tailscale_port_8443_exists; then
                [[ -f "$STATE_DIR/tailscale-8443-owned" ]] || die 'Tailscale Serve port 8443 is already configured outside this installer'
                tailscale_route_matches || die 'Installer-owned Tailscale port 8443 no longer matches the expected OpenCode route'
            else
                rm -f -- "$STATE_DIR/tailscale-8443-pending"
                printf 'https=8443 -> http://127.0.0.1:4096\n' >"$STATE_DIR/tailscale-8443-pending"
                sudo tailscale serve --bg --https=8443 http://127.0.0.1:4096
                tailscale_route_matches || die 'Tailscale did not install a private, exact OpenCode route'
                mv -- "$STATE_DIR/tailscale-8443-pending" "$STATE_DIR/tailscale-8443-owned"
            fi
            tailscale_route_matches || die 'Tailscale did not install the expected OpenCode route'
            ;;
        local)
            remove_owned_tailscale_route
            ensure_no_unowned_opencode_route
            ;;
        cloudflare)
            remove_owned_tailscale_route
            ensure_no_unowned_opencode_route
            cat <<'EOF'

Cloudflare was installed but not published automatically. Create a named tunnel
with your own account/domain, route it only to http://127.0.0.1:4096, and place
the hostname behind Cloudflare Access before enabling its service:
https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/
EOF
            ;;
    esac
}

write_profile() {
    install -d -m 0700 "$CONFIG_DIR"
    cat >"$CONFIG_DIR/profile.conf" <<EOF
PROFILE_VERSION=2
PRESET=$PRESET
LOCALE=$LOCALE
KEYBOARD_LAYOUT=$KEYBOARD_LAYOUT
KEYBIND_PRESET=$KEYBIND_PRESET
BROWSER=$BROWSER
GAMING=$GAMING
COMMUNICATION=$COMMUNICATION
DEVELOPMENT=$DEVELOPMENT
INSTALL_AW=$INSTALL_AW
INSTALL_OPENCODE=$INSTALL_OPENCODE
REMOTE_ACCESS=$REMOTE_ACCESS
EOF
    chmod 0600 "$CONFIG_DIR/profile.conf"
}

while (($# > 0)); do
    case "$1" in
        --profile) [[ $# -ge 2 ]] || die '--profile requires a file'; PROFILE_PATH=$2; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        --yes) ASSUME_YES=true; shift ;;
        --allow-experimental) ALLOW_EXPERIMENTAL=true; shift ;;
        -h|--help) usage; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

[[ $EUID -ne 0 ]] || die 'Run as your normal user, not root'
[[ -n "$PROFILE_PATH" || "$ASSUME_YES" == false ]] || die '--yes requires --profile'

detect_distribution
detect_graphics
if [[ -n "$PROFILE_PATH" ]]; then
    load_profile "$PROFILE_PATH"
else
    interactive_profile
fi
validate_profile

if [[ "$DISTRO_STATUS" == experimental && "$ALLOW_EXPERIMENTAL" == false ]]; then
    if [[ "$ASSUME_YES" == true ]]; then
        die "$DISTRO_ID requires --allow-experimental"
    fi
    [[ $(yes_no "$DISTRO_ID is experimental. Continue with fail-closed checks?" no) == yes ]] || exit 0
fi

resolve_packages
print_plan
if [[ "$DRY_RUN" == true ]]; then
    exit 0
fi
validate_graphics
if [[ "$ASSUME_YES" == false ]]; then
    read -r -p 'Type INSTALL-CAELESTIA-VRABKO to continue: ' confirmation
    [[ "$confirmation" == INSTALL-CAELESTIA-VRABKO ]] || { echo 'Installation cancelled.'; exit 0; }
fi

install -d -m 0700 "$STATE_DIR"
: >>"$LOG_FILE"
CURRENT_STAGE='pinned source verification'
prepare_verified_sources
sudo -v
install -d -m 0700 "$BACKUP_DIR"
CURRENT_STAGE='multilib setup'
enable_multilib
CURRENT_STAGE='package installation'
install_packages
CURRENT_STAGE='locale configuration'
configure_locale
CURRENT_STAGE='Caelestia installation'
install_caelestia
CURRENT_STAGE='Caelestia preference configuration'
configure_caelestia
CURRENT_STAGE='greetd configuration'
configure_greetd
CURRENT_STAGE='OpenCode configuration'
configure_opencode
CURRENT_STAGE='profile export'
write_profile

CURRENT_STAGE='final validation'
stage 'Running final validation'
if ! "$ROOT/validate.sh"; then
    die "Validation failed. Review $LOG_FILE and do not reboot until resolved"
fi

cat <<EOF

Installation completed successfully.

Backups: $BACKUP_DIR
Profile: $CONFIG_DIR/profile.conf
Log:     $LOG_FILE

Reboot when convenient. greetd will start the UWSM-managed Hyprland session.
EOF
