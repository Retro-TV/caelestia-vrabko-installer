#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
installer_version=$(awk -F= '$1 == "installer_version" { print $2 }' "$ROOT/versions.lock")

[[ "$installer_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]

if [[ ${GITHUB_REF_TYPE:-} == tag ]]; then
    [[ ${GITHUB_REF_NAME:-} == "v$installer_version" ]]
fi

if grep -R -E 'INSTALL_WALLPAPERS|vrabko-grid|vrabko-mandelbrot|generated starter wallpapers' \
    "$ROOT/install.sh" "$ROOT/profiles" "$ROOT/README.md"; then
    echo 'Removed starter-wallpaper behavior or content was reintroduced' >&2
    exit 1
fi

payload=$(awk -F= '/^payload=[0-9a-f]{40}$/ { print $2; exit }' "$ROOT/README.md")
[[ "$payload" =~ ^[0-9a-f]{40}$ ]]
[[ "$payload" != 0000000000000000000000000000000000000000 ]]

git -C "$ROOT" cat-file -e "$payload^{commit}"
git -C "$ROOT" merge-base --is-ancestor "$payload" HEAD
