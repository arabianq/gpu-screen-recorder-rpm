#!/bin/bash
#
# Fetch latest upstream versions and update *.spec files in this repo.
# Sources:
#   - dec05eba repos:        meson.build version from cgit /plain/
#   - gpu-screen-recorder-adwaita: latest GitHub release tag
#
# Spec files use the dec05eba.com snapshot service, which resolves
# <repo>.git.<version>.tar.gz for tagged releases. We therefore pin
# %global snapshot to the bare version string so Source URLs resolve.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

log() { printf '%s\n' "$*"; }
err() { printf 'error: %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# Helper: update a spec file in-place with sed.
#   update_spec <spec> <new_version> [<new_snapshot>]
# If <new_snapshot> is omitted, %global snapshot is set to <new_version>.
# ---------------------------------------------------------------------------
update_spec() {
    local spec="$1" new_version="$2" new_snapshot="${3:-}"
    local snapshot_value="${new_snapshot:-$new_version}"

    # Replace (or insert) %global snapshot line.
    if grep -q '^%global snapshot' "$spec"; then
        sed -i -E "s|^%global snapshot .*|%global snapshot $snapshot_value|" "$spec"
    else
        # Insert near the top, before Name:
        sed -i -E "0,/^Name:/{/^Name:/i\\%global snapshot $snapshot_value\n
}" "$spec"
    fi

    # Replace Version: line.
    sed -i -E "s|^Version:[[:space:]]+.*|Version:        $new_version|" "$spec"
}

# ---------------------------------------------------------------------------
# Helper: fetch a URL, exit non-zero on HTTP failure.
# ---------------------------------------------------------------------------
fetch() {
    local url="$1"
    local body
    body="$(curl -fsSL "$url")" || { err "fetch failed: $url"; return 1; }
    printf '%s' "$body"
}

# ---------------------------------------------------------------------------
# dec05eba packages: read version from meson.build via cgit /plain/
# ---------------------------------------------------------------------------
update_dec05eba_package() {
    local repo="$1" spec="$2"
    local meson_url="https://git.dec05eba.com/${repo}/plain/meson.build"
    local version

    version="$(fetch "$meson_url" \
        | grep -oE "version[[:space:]]*:[[:space:]]*'[0-9][^']*'" \
        | head -1 \
        | sed -E "s|.*'([^']*)'.*|\1|")"

    if [ -z "$version" ]; then
        err "could not parse version from $meson_url"
        return 1
    fi

    local current
    current="$(awk '/^Version:/ {print $2; exit}' "$spec")"
    if [ "$current" = "$version" ]; then
        log "  $spec: already at $version"
        return 0
    fi

    update_spec "$spec" "$version"
    log "  $spec: $current -> $version"
}

# ---------------------------------------------------------------------------
# gpu-screen-recorder-adwaita: latest GitHub release
# ---------------------------------------------------------------------------
update_adwaita() {
    local spec="gpu-screen-recorder-adwaita.spec"
    local api_url="https://api.github.com/repos/runlevel5/gpu-screen-recorder-adwaita/releases/latest"
    local tag version

    tag="$(fetch "$api_url" \
        | grep -oE '"tag_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
        | head -1 \
        | sed -E 's|.*"([^"]*)"|\1|')"

    if [ -z "$tag" ]; then
        err "could not parse tag_name from $api_url"
        return 1
    fi

    # Strip leading 'v' for the Version: field.
    version="${tag#v}"

    local current
    current="$(awk '/^Version:/ {print $2; exit}' "$spec")"
    if [ "$current" = "$version" ]; then
        log "  $spec: already at $version"
        return 0
    fi

    # adwaita.spec has no %global snapshot line; only update Version:.
    sed -i -E "s|^Version:[[:space:]]+.*|Version:        $version|" "$spec"
    log "  $spec: $current -> $version"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "Updating specs from upstream..."

update_dec05eba_package "gpu-screen-recorder"              "gpu-screen-recorder.spec"
update_dec05eba_package "gpu-screen-recorder-ui"           "gpu-screen-recorder-ui.spec"
update_dec05eba_package "gpu-screen-recorder-gtk"          "gpu-screen-recorder-gtk.spec"
update_dec05eba_package "gpu-screen-recorder-notification" "gpu-screen-recorder-notification.spec"
update_adwaita

log "Done."
