# Solas Shader 3.9 on Horizon — compatibility report

**Verdict: clean.** Solas Shader 3.9 loads, preprocesses, translates and writes out for every
GPU backend Horizon targets, unmodified, with zero errors and zero notes.

## What was checked

| | |
| --- | --- |
| Pack | Solas Shader 3.9, `2ebf0cfaf1302fef5475dc0b9ec52aad3ccea852` (2026-11-02) |
| Horizon | `69fab597a6f0e8a6ce524d38d1b73e599e343034` (2026-11-06) |
| Date | 2026-11-06 |
| Tool | `tools/horizon-pack-check` in this repository |
| Mipmap level reported to the pack | 4 |
| Biome constants | vanilla's 67 biomes, in Horizon's `VANILLA_ORDER` |

## Results

```
== Solas-Shader ==
  manifest: shaders.properties 156 keys, 3 id file(s) 239 keys, lang read
  preprocess: 163 stage files, 425498 lines, 0 diagnostics
  translate: 27 composite-style programs, 0 failed
  dimension  0 (`.`):       9 post programs, shadow yes, 1 compute, 47 modules, 0 backend failure(s), 0 note(s)
  dimension  0: 14 custom uniform(s), 0 unresolved
  dimension -1 (`world-1`): 9 post programs, shadow yes, 1 compute, 47 modules, 0 backend failure(s), 0 note(s)
  dimension -1: 14 custom uniform(s), 0 unresolved
  dimension  1 (`world1`):  9 post programs, shadow yes, 1 compute, 47 modules, 0 backend failure(s), 0 note(s)
  dimension  1: 14 custom uniform(s), 0 unresolved
Solas-Shader: OK - loads and translates on Horizon
```

Identical results whether the pack is a folder or a `.zip`.

### Pack features exercised

Solas is not a simple pack, and the parts that usually break a reimplementation all work:

- **Shadow pass** — `shadow`, `shadow_water`, `shadow_entities`, plus `shadow.culling=reversed`.
- **A compute program** — `shadowcomp.csh`, dispatched before `shadowcomp`, local size 8×8×8,
  work groups 24×12×24, bound to 2 storage images.
- **Custom images** (`iris.features.optional=CUSTOM_IMAGES`) — the voxel and floodfill volumes
  behind Solas's coloured block lighting: `r8ui` and two `rgba16f` 3D images, sized by the
  `VOXEL_VOLUME_SIZE` option from 128³ up to 512×256×512.
- **All three dimensions**, each with its own program set (`world0`, `world-1`, `world1`).
- **Distant Horizons programs** (`dh_terrain`, `dh_water`) present and translated.
- **14 custom uniforms** over `sunAngle`, `cameraPosition`, `frameCounter`, `blindness` and
  biome tests, including `smooth()` and `frac()`, all resolving.
- **Options and screens** — 156 `shaders.properties` keys, 4 profiles, nested option screens,
  and a `.lang` file, all read without a note.

## Method

The checker reproduces, without a GPU, what the game does when it loads a pack:

1. Open the pack (folder or zip) and read `shaders.properties`, `block/item/entity.properties`
   and `en_us.lang`, with the standard macro set plus the renderer's at mipmap level 4.
2. Run every `.vsh`, `.fsh`, `.gsh` and `.csh` in the base and dimension folders through the
   GLSL preprocessor, following `#include` and the conditional directives.
3. Translate every composite-style program (`composite*`, `deferred*`, `final`, `prepare*`,
   `begin*`, `shadowcomp*`) into naga modules.
4. For each dimension, load the whole program set as the renderer does — terrain, cutout
   terrain, water, sky, textured sky, entities, blocks, translucent entities, particles, clouds,
   weather, hand, the shadow programs and compute — supplying the vertex inputs the renderer
   supplies, which the geometry programs cannot be translated without.
5. Write every resulting module out through all four backends wgpu uses, with Horizon's own
   writer options: SPIR-V 1.3, HLSL shader model 6.0, GLSL 430 and MSL 2.4.
6. Resolve the pack's custom uniforms against the built-ins the renderer actually provides.

Steps 1–5 mirror Horizon's own `real_packs` test, so results are directly comparable. Step 6
differs deliberately — see below.

## Two things that make a checker lie

Both of these produced false failures here before being fixed, and both will bite anyone
building pack tooling for Horizon.

### The patched naga

Horizon does not build against published naga. It vendors *"naga 30.0.1, with the fixes to its
GLSL frontend that shader packs need"* at `third_party/naga`, excluded from its workspace and
injected via `[patch.crates-io]`.

Against stock naga 30.0.1, Solas reports **6 translation failures**, all
`Unknown function 'textureGather'` — and, downstream, 2 of 9 post programs silently skipped, the
shadow pass missing and the compute program gone. None of that is real. `textureGather` is in
the vendored frontend's builtins and absent from the published one. The failure even points at
`<horizon>`, Horizon's own injected polyfill, rather than at any Solas file, which is the tell.

This checker pins naga to Horizon's copy at the same revision.

### The biome constants, and Horizon's own test stub

`BIOME_<NAME>` constants are built from the game's biome registry, which only exists once the
game has loaded its resources. A checker that supplies no biomes leaves every `BIOME_*` reading
−1, which never matches, so a pack's biome-dependent uniforms look broken. In Solas that is 27
unresolved uniforms per dimension — `isSnowy`, `isDesert`, `isCherryGrove`, `isLushCaves`,
`isDeepDark`, `isSwamp`, `isMushroom`, `isJungle`, `isPaleGarden` — all of them artifacts.
This checker supplies vanilla's biome list in Horizon's own order.

Relatedly: Horizon's `real_packs` test evaluates custom uniforms with `&|_| None`, a stub that
knows no built-in at all. It therefore prints

```
`timeAmin` reads 0: `sunAngle` is unknown to custom uniforms
`yCold1` reads 0: `cameraPosition` is unknown to custom uniforms
```

for Solas. **These are not gaps.** `sunAngle` and `cameraPosition` are both supplied by the
renderer (`pack_uniforms.rs`), and neither is on the `HIDDEN` or `NOT_GIVEN_YET` lists. Reading
those lines as missing features is the easy mistake here; this checker answers `builtin()` with
the same names and shapes the renderer does, and the notes disappear.

## Scope — what this does not establish

The check is static. It proves Solas **compiles and loads**; it does not prove it **looks
right**.

- No GPU, no Minecraft assets and no Horizon build were available, so the pack was never drawn.
  Visual correctness, pass ordering at runtime and uniform *semantics* (as opposed to presence
  and shape) are untested.
- Performance is untested.
- Only the default option values were checked. Solas ships 4 profiles and well over a hundred
  options; a setting could in principle select a code path that fails to translate. Horizon's
  own shader API checks packs at each option's minimum and maximum for this reason, and the
  equivalent sweep for `shaders/`-format packs is not done here.
- Mod-added biomes number after vanilla's, so a pack naming one still reads −1 under this
  checker.

If Solas misbehaves visually on Horizon, that is a Horizon renderer issue, not a pack issue, and
belongs in [Horizon's tracker](https://github.com/horizon-rust/horizon/issues).

## Reproducing

```bash
scripts/check-solas.sh /path/to/folder/holding/your/solas/copy
```

The tool fetches `horizon-shaders` and the patched naga from GitHub at the pinned revision, so
the only requirements are Rust 1.88+ and network access. To check against a newer Horizon, bump
both `rev` values in `tools/horizon-pack-check/Cargo.toml` — keep them identical.
