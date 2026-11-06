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

# A zip holding the real zip is a common way for a pack to arrive: a browser or a file
# manager repacks the download, or the uploader zipped the folder they downloaded. Unpack
# any zips found inside, a couple of rounds deep, so that case just works.
#
# Only ever inside our own temp copy: this deletes the zips it expands, and must never
# touch the user's folder. A folder input is left exactly as it was found.
if [ "$search_root" = "$work/unpacked" ] && command -v unzip >/dev/null 2>&1; then
    for _ in 1 2; do
        inner="$(find "$search_root" -type f -name '*.zip' -print -quit 2>/dev/null)"
        [ -n "$inner" ] || break
        # Unpack each beside itself, then drop the zip so it is not found again.
        while IFS= read -r z; do
            unzip -q -o "$z" -d "${z%.zip}-unpacked" 2>/dev/null || true
            rm -f "$z"
        done < <(find "$search_root" -type f -name '*.zip' 2>/dev/null)
    done
fi

# Find the folder that holds `shaders/` — the pack root. Downloads nest it to varying
# depths: a release zip not at all, GitHub's one deep, and a zip someone re-zipped (or a
# browser that unpacked and repacked it) deeper still. So search at any depth and take the
# shallowest real match.
#
# "Real" matters: a RESOURCE pack has `assets/<namespace>/shaders/` holding core shaders,
# which is not a shader pack root. A shader pack's `shaders/` holds stage files or
# `shaders.properties`, and is never under `assets/`.
looks_like_a_pack() {
    local dir="$1"
    case "$dir" in */assets/*) return 1 ;; esac
    [ -f "$dir/shaders.properties" ] && return 0
    [ -n "$(find "$dir" -maxdepth 1 -type f \
        \( -name '*.fsh' -o -name '*.vsh' -o -name '*.gsh' -o -name '*.csh' \) \
        -print -quit 2>/dev/null)" ]
}

pack_root=""
best_depth=-1
while IFS= read -r candidate; do
    looks_like_a_pack "$candidate" || continue
    # Depth = number of path separators, so the shallowest match wins.
    depth=$(printf '%s' "${candidate#"$search_root"}" | tr -cd '/' | wc -c)
    if [ "$best_depth" -lt 0 ] || [ "$depth" -lt "$best_depth" ]; then
        best_depth="$depth"
        pack_root="$(dirname "$candidate")"
    fi
done < <(find "$search_root" -type d -name shaders 2>/dev/null | sort)

if [ -z "$pack_root" ]; then
    {
        echo "error: no shader pack found in $source_path"
        echo
        echo "Looked for a 'shaders' folder holding stage files (.fsh/.vsh) or"
        echo "shaders.properties, at any depth. What is actually in there:"
        echo
        find "$search_root" -maxdepth 3 \( -type d -o -type f \) 2>/dev/null \
            | sed "s|^$search_root/\{0,1\}||" | grep -v '^$' | sort | head -25 \
            | sed 's/^/  /'
        total=$(find "$search_root" -mindepth 1 2>/dev/null | wc -l)
        [ "$total" -gt 25 ] && echo "  ... $((total - 25)) more"
        echo
        echo "If this is a shader pack, it may be double-zipped: unzip it and point this at"
        echo "the folder instead. If it is a RESOURCE pack (it has an 'assets' folder and a"
        echo "pack.mcmeta), it belongs in resourcepacks/, not shaderpacks/."
    } >&2
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
