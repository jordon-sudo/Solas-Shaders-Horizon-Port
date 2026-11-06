#!/usr/bin/env bash
#
# Checks an Iris/OptiFine shader pack against Horizon's loader, translator and the four shader
# backends wgpu uses. Needs no GPU, no copy of Minecraft and no Horizon build — the checker
# pulls Horizon's loader from git at a pinned revision.
#
# Usage:
#   scripts/check-solas.sh [path-to-packs] [extra flags...]
#
# The path may be a folder of packs (your `shaderpacks/`), a single pack folder, or a `.zip`.
# With no path, it looks in the usual places. Extra flags go through to the checker, e.g.
# --verbose.
#
# Exits 0 when every pack checks out, 1 when one fails, 2 on a usage problem.
#
# This repository ships no Solas source: get the pack from CurseForge or Modrinth, its only
# official sources, and point this at your copy. See docs/LICENSING.md.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
manifest="$here/tools/horizon-pack-check/Cargo.toml"

if ! command -v cargo >/dev/null 2>&1; then
    echo "error: cargo not found. Install Rust 1.88 or newer: https://rustup.rs" >&2
    exit 2
fi

target="${1-}"
[ $# -gt 0 ] && shift

# No path given: try the places a Horizon instance keeps its packs.
if [ -z "$target" ]; then
    for candidate in \
        "$PWD/shaderpacks" \
        "$HOME/.horizon/shaderpacks" \
        "$HOME/.local/share/horizon/shaderpacks" \
        "$HOME/Library/Application Support/horizon/shaderpacks" \
        "$HOME/.minecraft/shaderpacks"
    do
        if [ -d "$candidate" ]; then
            target="$candidate"
            echo "Checking packs in $target"
            break
        fi
    done
fi

if [ -z "$target" ]; then
    cat >&2 <<'EOF'
error: no shaderpacks folder found, and none given.

usage: scripts/check-solas.sh <path-to-packs-or-a-pack> [--verbose|--quiet]

The path may be a folder of packs, a single pack folder, or a .zip. Get Solas Shader from
CurseForge or Modrinth (its only official sources); this repository ships none of it.
EOF
    exit 2
fi

if [ ! -e "$target" ]; then
    echo "error: no such path: $target" >&2
    exit 2
fi

# --release: the backend writers are far too slow to sit through unoptimised.
exec cargo run --release --quiet --manifest-path "$manifest" -- "$target" "$@"
