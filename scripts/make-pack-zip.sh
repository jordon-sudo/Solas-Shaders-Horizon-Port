#!/usr/bin/env bash
#
# Builds a Horizon-ready shader pack zip from your own copy of a pack, then checks it.
#
# Horizon (like Iris) needs `shaders/` at the ROOT of the zip. A "Download ZIP" from GitHub
# wraps everything in a folder named after the repo and branch, so the pack is at
# `Solas-Shader-main/shaders/` and Horizon rejects it with "no shaders folder at the root of
# the pack". This repacks it correctly.
#
# You do not need this for a release download from Modrinth or CurseForge: those are already
# built right. Use it when you have the source — a git clone, or GitHub's ZIP.
#
# Usage:
#   scripts/make-pack-zip.sh <folder-or-zip> [output.zip]
#
# This repository ships no Solas source: bring your own copy. See docs/LICENSING.md.

set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ $# -lt 1 ]; then
    cat >&2 <<'EOF'
usage: scripts/make-pack-zip.sh <folder-or-zip> [output.zip]

  <folder-or-zip>  a pack folder, a git clone, or a GitHub "Download ZIP"
  [output.zip]     where to write it (default: <name>-horizon.zip here)

Get Solas Shader from CurseForge or Modrinth, its only official sources.
EOF
    exit 2
fi

source_path="$1"
output="${2-}"

if [ ! -e "$source_path" ]; then
    echo "error: no such path: $source_path" >&2
    exit 2
fi
command -v zip >/dev/null 2>&1 || { echo "error: 'zip' not found; install it" >&2; exit 2; }

work="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf '$work'" EXIT

# A zip in: unpack it and work from there.
if [ -f "$source_path" ]; then
    command -v unzip >/dev/null 2>&1 || { echo "error: 'unzip' not found; install it" >&2; exit 2; }
    unzip -q "$source_path" -d "$work/unpacked"
    search_root="$work/unpacked"
else
    search_root="$source_path"
fi

# Find the folder that holds `shaders/` — the pack root. It is either the folder itself or,
# for a GitHub zip or a clone sitting in a parent, one level down.
pack_root=""
if [ -d "$search_root/shaders" ]; then
    pack_root="$search_root"
else
    while IFS= read -r candidate; do
        pack_root="$(dirname "$candidate")"
        break
    done < <(find "$search_root" -maxdepth 2 -type d -name shaders 2>/dev/null | sort)
fi

if [ -z "$pack_root" ]; then
    echo "error: no 'shaders' folder found in $source_path" >&2
    echo "       that path does not look like an Iris/OptiFine shader pack." >&2
    exit 2
fi

# Name the output after the pack, not after the wrapper folder's branch suffix.
if [ -z "$output" ]; then
    base="$(basename "$(cd "$pack_root" && pwd)")"
    base="${base%-main}"
    base="${base%-master}"
    output="$PWD/${base}-horizon.zip"
fi
# Make it absolute, since we cd into the pack to zip.
case "$output" in
    /*) ;;
    *) output="$PWD/$output" ;;
esac

rm -f "$output"

# Zip the CONTENTS of the pack root, so `shaders/` lands at the zip root. Drop git metadata
# and macOS clutter, which are no part of a pack.
(
    cd "$pack_root"
    zip -qr "$output" . \
        -x '.git/*' '.git' '.github/*' '.gitattributes' '.gitignore' \
           '__MACOSX/*' '*.DS_Store'
)

echo "Wrote $output"
unzip -l "$output" | sed -n '1,6p'

# Prove it: the zip has to pass the same check the game's loader applies.
echo
echo "Checking it..."
if "$here/scripts/check-solas.sh" "$output" --quiet; then
    echo
    echo "Ready. Drop it in your Horizon instance's shaderpacks/ folder, then pick it under"
    echo "Options -> Video Settings -> Shaders -> Shader Packs..."
else
    echo
    echo "The zip was built but did not check out; see the problems above." >&2
    exit 1
fi
