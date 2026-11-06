# Licensing: why no Solas source is in this repository

Solas Shader is **not** open source. Its LICENSE reads:

> Copyright (C) Septonious — All Rights Reserved unless otherwise explicitly stated.

The terms that matter for a port:

- **§1 Redistribution.** Public propagation must use the author's official links only.
  "Independently hosting a copy of this project and propagating it using this hosted version is
  prohibited."
- **§2 Private modifications.** Explicitly **allowed** without permission.
- **§3 Public modifications.** Public redistribution of a modified version "requires explicit
  permission from the original author", must credit the original, and must carry the same
  license.
- **§4 Using parts in another project.** Also requires explicit permission.

The pack also ships `drm/drm.readme`, a tripwire file:

> Solas Shader is a Minecraft shaderpack created by Septonious. It has only two official
> download sources: CurseForge and Modrinth. If you see this file in any other shaderpack, know
> that it contains STOLEN code from Solas.

So the author actively polices redistribution, and a public repository holding Solas's shaders —
ported, patched or verbatim — would be exactly what §1 and §3 prohibit.

## What follows from that

This repository contains **no Solas source**: no `.fsh`, no `.vsh`, no `.glsl`, no
`shaders.properties`, no textures, not even a patch against them. It holds a checker, a script
and this documentation. You supply your own copy of Solas, obtained from CurseForge or Modrinth,
and everything here runs against that.

Conveniently, nothing more is needed: Solas requires no modification to run on Horizon (see
[COMPATIBILITY.md](COMPATIBILITY.md)), so there is no patched fork to distribute in the first
place. The license question and the engineering answer happen to agree.

## If you want to go further

Publishing a modified or ported Solas — to a repository, a Modrinth page, a Discord, anywhere —
needs **Septonious's explicit permission** first. §3 also requires that such a version carry the
same license, credit the original clearly, and not be monetised without permission. Ask before
publishing, not after. The Discord linked from
[the Solas README](https://github.com/Septonious/Solas-Shader) is the place to ask.

Using Solas privately on Horizon, including modifying your own copy, is permitted outright by
§2 and needs no one's permission.

## Everything else here

The checker is MIT, matching Horizon. It reuses three small pieces of Horizon
(horizon-rust/horizon, MIT), each attributed in the file that carries it:

| Piece | From | Used in |
| --- | --- | --- |
| Backend writer options | `crates/horizon-shaders/tests/real_packs.rs` | `src/backends.rs` |
| Built-in uniform names and shapes | `crates/horizon-client-render/src/gfx/pack_uniforms.rs` | `src/uniforms.rs` |
| Vanilla biome order | `crates/horizon-shaders/src/biomes.rs` | `src/biomes.rs` |

This repository is not affiliated with Septonious, Horizon, Mojang or Microsoft. Nothing here is
legal advice; if you intend to publish a port, get the author's permission.
