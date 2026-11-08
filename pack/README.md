# Solas Horizon — a shader pack for Horizon

A fantasy-stylised pack written in Horizon's **own** shader format (WGSL), styled after
[Solas Shader](https://github.com/Septonious/Solas-Shader).

**Install:** drop `solas_horizon-0.2.0.hshader` into `shaderpacks/` (Options → Video Settings →
Shaders → Open Pack Folder), then pick **Solas Horizon** in the list. Its settings are under
**Shader Options…**.

## What it does

| | |
| --- | --- |
| **Sky** | deeper gradient than vanilla, warm band around a low sun, stars on a jittered lattice, Milky Way, aurora |
| **Surfaces** | soft shadows (9-tap PCF), coloured shadows through glass and water, sky/sun colour through the day, subsurface scattering on foliage, LabPBR normal and specular maps when a resource pack ships them |
| **Block light** | coloured per block — soul torches blue, redstone red, sea lanterns green, end rods pale blue, crying obsidian violet; fireflies carry their own light |
| **Held light** | a torch or lantern you carry lights the world around you, in its own colour (OptiFine/Iris dynamic hand light) — **see below** |
| **Weather** | rain and snow lit by the sky, fading with distance |
| **Post** | volumetric light shafts marched against the shadow map, bloom with a soft knee, ACES filmic tonemap, auto exposure, vignette, chromatic aberration |

36 options across four pages, including a shadow switch that removes the shadow pass entirely.

## Held light needs one setting turned on

The pack lights whatever Horizon reports as a dynamic light source — a torch or lantern held in
either hand, an item dropped on the ground, an entity on fire — in its `[[lights]]` colour.

**Horizon's own dynamic lights are off by default**, because they are not vanilla behaviour.
Turn them on at **Options → Video Settings → Dynamic lights**. Until you do, Horizon reports no
such lights, the pack's held light is simply zero, and the option below does nothing. That is
Horizon's switch, not something a shader pack can set for you.

With it on, **Held light** and **Held light strength** on the Lighting page control how much it
contributes.

## On glowing blocks

A surface shines here only where Horizon says the block is a real light source
(`MaterialInput.emission`), or where a LabPBR specular map explicitly carries emission *and* a
resource pack actually ships those maps. Nothing infers "this looks bright, make it glow" from
the texture's colour.

That guess is a common source of plain blocks like dirt lighting up, when a pack's heuristics
and an engine's block ids disagree. This pack structurally cannot do it: with no PBR maps
loaded, `block_specular_map` returns zeros and the emission term is exactly 0 for every block
that is not a light source.

## This is not Solas

It is an original pack in Solas's spirit, not a conversion of it, and not as feature-rich —
there are no volumetric clouds, no planar clouds, no rainbows, no Ender disk, no parallax
displacement. Solas is © Septonious, all rights reserved; none of its code is here. See
[../docs/LICENSING.md](../docs/LICENSING.md).

## Verified

`horizon-shader check` passes: every stage parsed and validated by naga, checked against its
signature, and translated for Vulkan (SPIR-V), Metal (MSL) and DirectX 12 (HLSL) with every
option at its default, minimum and maximum.

```
solas_horizon 0.2.0 (shader API 0.1): ok
  sky       Sky                             651 expressions, 0 texture reads
  material  Surfaces                       1078 expressions, 5 texture reads
  weather   Rain and snow                   367 expressions, 0 texture reads
  post      Light shafts                    702 expressions, 5 texture reads
  post      Bloom                           698 expressions, 5 texture reads
  post      Grade                           692 expressions, 7 texture reads
```

Budgets are 20000 expressions and 64 texture reads per stage, so there is plenty of headroom.

**What that proves:** it compiles, loads and runs on all three backends. **What it doesn't:**
how it looks. It was never drawn — this environment has no GPU and no Minecraft assets. Tuning
values (exposure, shaft density, aurora brightness) are considered guesses until someone runs
it. Every one of them is an option you can turn down.

## Rebuilding

```bash
horizon-shader check pack/solas_horizon     # what the game checks before it runs a pack
horizon-shader pack  pack/solas_horizon     # rewrites the .hshader
```

`horizon-shader` comes from Horizon: `cargo install --path crates/horizon-shader-api`.

The game hot-reloads: with the pack as a **folder** in `shaderpacks/`, save a file and it
rebuilds in place. If it fails the check, the chat says where and the last good version keeps
drawing.
