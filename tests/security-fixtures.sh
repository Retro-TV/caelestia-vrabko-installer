#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
set -euo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

# shellcheck disable=SC2016 # jq variables must remain literal.
route_filter='
    . as $status |
    ([.Web | to_entries[]? | select(.key | endswith(":8443"))]) as $routes |
    (.TCP["8443"].HTTPS? == true) and
    ($routes | length == 1) and
    ($routes[0].value.Handlers | keys == ["/"]) and
    ($routes[0].value.Handlers["/"].Proxy == "http://127.0.0.1:4096") and
    (($status.AllowFunnel[$routes[0].key]? // false) == false)
'

private_route='{"TCP":{"8443":{"HTTPS":true}},"Web":{"host:8443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:4096"}}}}}'
funnel_route='{"TCP":{"8443":{"HTTPS":true}},"Web":{"host:8443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:4096"}}}},"AllowFunnel":{"host:8443":true}}'
shared_route='{"TCP":{"8443":{"HTTPS":true}},"Web":{"host:8443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:4096"},"/other":{"Proxy":"http://127.0.0.1:8080"}}}}}'
wrong_port='{"TCP":{"8443":{"HTTPS":true},"443":{"HTTPS":true}},"Web":{"host:443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:4096"}}},"host:8443":{"Handlers":{"/":{"Proxy":"http://127.0.0.1:8080"}}}}}'

jq -e "$route_filter" <<<"$private_route" >/dev/null
if jq -e "$route_filter" <<<"$funnel_route" >/dev/null; then
    echo 'Funnel-enabled route incorrectly passed' >&2
    exit 1
fi
if jq -e "$route_filter" <<<"$shared_route" >/dev/null; then
    echo 'Shared listener incorrectly passed' >&2
    exit 1
fi
if jq -e "$route_filter" <<<"$wrong_port" >/dev/null; then
    echo 'Proxy on a different HTTPS port incorrectly passed' >&2
    exit 1
fi

lock_value() {
    awk -F= -v key="$1" '$1 == key { print $2 }' "$ROOT/versions.lock"
}

package_version() {
    local package_dir=$1
    (cd "$package_dir" && makepkg --printsrcinfo) | awk '
        $1 == "pkgver" { version=$3 }
        $1 == "pkgrel" { release=$3 }
        END { print version "-" release }
    '
}

[[ $(sha256sum "$ROOT/packages/caelestia-shell-aw/0003-remove-unauthenticated-unlock-ipc.patch" | cut -d' ' -f1) == "$(lock_value shell_security_patch_sha256)" ]]
[[ $(sha256sum "$ROOT/packages/caelestia-cli-aw/0003-cli-pinned-dots.patch" | cut -d' ' -f1) == "$(lock_value cli_pinned_patch_sha256)" ]]
[[ $(sha256sum "$ROOT/packages/caelestia-cli/0001-pinned-dots.patch" | cut -d' ' -f1) == "$(lock_value cli_pinned_patch_sha256)" ]]
grep -Fq "_commit=$(lock_value quickshell_commit)" "$ROOT/packages/quickshell-git/PKGBUILD"
grep -Fq "_commit=$(lock_value aw_cli_commit)" "$ROOT/packages/caelestia-cli-aw/PKGBUILD"
grep -Fq "_commit=$(lock_value aw_shell_commit)" "$ROOT/packages/caelestia-shell-aw/PKGBUILD"
grep -Fq "_m3_commit=$(lock_value m3shapes_commit)" "$ROOT/packages/caelestia-shell-aw/PKGBUILD"
[[ $(package_version "$ROOT/packages/caelestia-cli") == "$(lock_value tested_caelestia_cli)" ]]
[[ $(package_version "$ROOT/packages/caelestia-shell") == "$(lock_value tested_caelestia_shell)" ]]
[[ $(package_version "$ROOT/packages/quickshell-git") == "$(lock_value tested_quickshell_git)" ]]
[[ $(package_version "$ROOT/packages/python-materialyoucolor") == "$(lock_value tested_materialyoucolor)" ]]
[[ $(package_version "$ROOT/packages/libcava") == "$(lock_value tested_libcava)" ]]
[[ $(package_version "$ROOT/packages/ttf-rubik-vf") == "$(lock_value tested_rubik)" ]]
[[ $(package_version "$ROOT/packages/caelestia-cli-aw") == "1.1.2.aw$(lock_value aw_integration_version)-$(lock_value aw_cli_package_release)" ]]
[[ $(package_version "$ROOT/packages/caelestia-shell-aw") == "2.2.0.aw$(lock_value aw_integration_version)-$(lock_value shell_package_release)" ]]
if grep -R --exclude-dir=src --exclude-dir=pkg -E 'sha256sums=.*SKIP|aur\.archlinux\.org' "$ROOT/install.sh" "$ROOT/packages"; then
    echo 'Moving or unchecked package input detected' >&2
    exit 1
fi
