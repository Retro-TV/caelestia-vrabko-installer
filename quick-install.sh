#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -Eeuo pipefail

payload=3fcf784f9f18835f87397d66df9d645e82672c59
install_dir="$HOME/.local/src/caelestia-vrabko-installer-${payload:0:7}"
repo=https://github.com/Retro-TV/caelestia-vrabko-installer.git

[[ $EUID -ne 0 ]] || { echo 'Run this as your normal user, not root.' >&2; exit 1; }

echo 'Starting the interactive Caelestia installer.'
echo 'You will choose every installation option before changes are made.'

sudo pacman -Syu --needed --noconfirm git
mkdir -p "$install_dir"
if [[ ! -d "$install_dir/.git" ]]; then
    git -C "$install_dir" init
    git -C "$install_dir" remote add origin "$repo"
else
    git -C "$install_dir" remote set-url origin "$repo"
fi
git -C "$install_dir" fetch --depth 1 origin "$payload"
git -C "$install_dir" checkout --detach FETCH_HEAD
[[ $(git -C "$install_dir" rev-parse HEAD) == "$payload" ]] || {
    echo 'Fetched installer does not match the pinned payload.' >&2
    exit 1
}

exec "$install_dir/install.sh" </dev/tty
