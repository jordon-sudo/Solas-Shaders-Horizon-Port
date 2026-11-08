# Solas Shader on Horizon

Two things live here, for [Horizon](https://github.com/horizon-rust/horizon), the Rust rewrite
of Minecraft: Java Edition:

1. **[`pack/`](pack/) — Solas Horizon**, a shader pack written in Horizon's own WGSL format,
   styled after [Solas Shader](https://github.com/Septonious/Solas-Shader). Drop
   `pack/solas_horizon-0.2.0.hshader` into `shaderpacks/` and pick it. It passes Horizon's own
   `horizon-shader check` on all three graphics backends. **[Details](pack/README.md).**
2. **[`tools/horizon-pack-check`](tools/horizon-pack-check/)** — a checker that tells you
   whether any Iris/OptiFine pack (Solas included) loads and translates on Horizon, with no GPU
   or game build needed.

## Running the original Solas on Horizon

Horizon reads the Iris/OptiFine `shaders/` pack format natively. It has a clean-room
implementation of that format — `crates/horizon-shaders`, about 22k lines — that reads a pack's
manifest, runs its GLSL through a preprocessor, and translates every program into
[naga](https://github.com/gfx-rs/wgpu/tree/trunk/naga) modules, which wgpu then writes out for
Vulkan, DirectX 12, OpenGL or Metal. The renderer side is another ~19k lines
(`horizon-client-render/src/gfx/pack_*.rs`) covering terrain, entities, the sky, weather, the
hand, the shadow pass, compute programs and custom images.

**Solas Shader 3.9 goes through all of it with zero errors**, unmodified. Checked here:

| Step | Result |
| --- | --- |
| `shaders.properties`, id files, `.lang` | 156 keys, 3 id files / 239 keys, lang read, **0 notes** |
| GLSL preprocessor, every stage file | 163 files, 425,498 lines, **0 diagnostics** |
| Composite-style programs translated | 27 programs, **0 failures** |
| Each dimension loaded as the game loads it | Overworld, Nether, End: 9 post programs, shadow pass, 1 compute program, **0 notes** each |
| Modules written out for every GPU backend | 47 per dimension (141 total) through SPIR-V, HLSL, GLSL and MSL: **0 errors, 0 panics** |
| Custom uniforms resolved | 14 uniforms, **0 unresolved** |

So the answer to "port Solas to the Rust Minecraft" is: **install it and turn it on.** The work
in this repository is the verification that says so, and the tool that re-checks it when either
project moves.

Full evidence and method: [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md).

## Getting the zip

**Download the release from [Modrinth](https://modrinth.com/shader/solas-shader) or
[CurseForge](https://www.curseforge.com/minecraft/shaders/solas-shader).** Those are the pack's
only official sources, its author asks that it not be mirrored, and this repository ships none
of it. A release zip is already built correctly — drop it straight in.

**Do not use GitHub's "Download ZIP".** It wraps everything in a `Solas-Shader-main/` folder,
so the pack ends up at `Solas-Shader-main/shaders/` instead of `shaders/`, and Horizon rejects
it with *"no shaders folder at the root of the pack"*. Verified here, not guessed.

If you do have the source — a GitHub zip, or a `git clone` — repack it:

```bash
scripts/make-pack-zip.sh ~/Downloads/Solas-Shader-main.zip
```

It finds the real pack root at whatever depth it sits, zips the contents so `shaders/` is at
the top, drops git and macOS clutter, and runs the checker on the result so you know it is good
before you move it.

It handles the shapes these downloads actually arrive in — a release zip, GitHub's wrapped zip,
a zip nested several folders deep, a zip containing the real zip, a `git clone`, or a plain pack
folder. If it can't find a pack it prints what *is* in there, so you can see why. It never
modifies the folder you point it at. Pointed at a resource pack by mistake, it says so and tells
you that belongs in `resourcepacks/`.

## Installing

1. Put the zip (or the unzipped pack folder) in `shaderpacks/`, beside `options.txt` in your
   Horizon instance.
2. In game: **Options → Video Settings → Shaders → Shader Packs…**, and pick it. Solas's own
   settings screens appear under **Shader Options…**.

Horizon's shader-pack support is being rebuilt and, per its
[ROADMAP](https://github.com/horizon-rust/horizon/blob/main/ROADMAP.md), returns "off by default,
once the best-known packs draw properly". If the Shaders page isn't there, you're on a build
that predates it — use a current Nightly.

## Checking it yourself

`tools/horizon-pack-check` is a standalone checker for any Iris/OptiFine pack on Horizon. It
needs **no GPU, no copy of Minecraft and no Horizon build** — it pulls Horizon's loader straight
from git and runs the pack through it.

```bash
scripts/check-solas.sh ~/.horizon/shaderpacks
```

or directly:

```bash
cargo run --release --manifest-path tools/horizon-pack-check/Cargo.toml -- /path/to/shaderpacks
```

It takes a folder of packs, or one pack (folder or `.zip`). Exit code 0 means clean, 1 means the
pack has problems, 2 is a usage error — so it drops into CI as-is. `--verbose` lists every
diagnostic; `--quiet` prints just the verdict.

## What this does and doesn't prove

**Proven:** Solas's GLSL is accepted, translated and written out successfully for every graphics
backend Horizon targets. A pack that clears this does not fail to compile or fail to load, which
is where format-level porting problems show up.

**Not proven:** that it *looks* right. Matching Iris pixel-for-pixel is a question about
uniform semantics and pass ordering at runtime, and answering it needs the game on a GPU with
real Minecraft assets. None of that exists in this environment, so it is untested here. Expect
to find visual differences, and report those to Horizon rather than to Septonious.

## One trap worth knowing

Horizon does not build against the published naga. It vendors a patched one —
*"naga 30.0.1, with the fixes to its GLSL frontend that shader packs need"* — at
`third_party/naga`, excluded from its workspace and wired in through `[patch.crates-io]`.

Build any pack tooling against stock naga and it will report failures the game never sees:
`textureGather` alone, which its GLSL frontend doesn't know, produced six invented failures in
Solas here before the patch was applied. The checker in this repository patches naga to
Horizon's copy at the same revision for exactly this reason. If you write your own tooling, do
the same.

## Layout

```
tools/horizon-pack-check/   the checker (Rust; pulls horizon-shaders from git)
scripts/check-solas.sh      convenience wrapper for the checker
scripts/make-pack-zip.sh    build a Horizon-ready zip from your own copy
docs/COMPATIBILITY.md       the full report, method and raw results
docs/LICENSING.md           why no Solas source is vendored here
```

## Credits and licensing

Solas Shader is © Septonious, all rights reserved, and is **not** redistributed here — not in
whole, not in part, not patched. See [docs/LICENSING.md](docs/LICENSING.md).

Horizon is MIT. The checker reuses small pieces of it (the backend-writer options, the built-in
uniform table, the vanilla biome order), each attributed in the file that carries it.

This repository is not affiliated with Septonious, Horizon, Mojang or Microsoft.
