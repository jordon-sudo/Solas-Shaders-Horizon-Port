// The lit colour of every point of terrain.
//
// On emission, deliberately: a surface shines only where Horizon itself says the block is a
// light source (`input.emission`), or where a LabPBR specular map explicitly carries emission
// AND the resource packs actually ship those maps (`block_pbr_maps()`). Nothing here infers
// "this looks bright, make it glow" from the albedo. That guess is what makes plain blocks
// like dirt light up when a pack's heuristics and an engine's block ids disagree, and this
// pack cannot do it: with no PBR maps loaded, `block_specular_map` returns zeros and the
// emission term is exactly 0 for every block that is not a real light source.

override shadows_on: bool = true;
override shadow_softness: f32 = 1.0;
override block_light_strength: f32 = 1.0;
override block_light_color_on: bool = true;
override ambient_strength: f32 = 1.0;
override ao_strength: f32 = 0.85;
override sss_strength: f32 = 0.7;
override specular_on: bool = true;
override specular_strength: f32 = 0.6;
override emission_strength: f32 = 1.0;

// Sprite tags from the manifest, in order.
const TAG_FOLIAGE: u32 = 1u;   // bit 0: leaves, grass, crops
const TAG_WATER: u32 = 2u;     // bit 1

// Torchlight: warm, and warmer still as it gets stronger, like Solas's.
fn torch_color(level: f32) -> vec3<f32> {
    let cool = vec3<f32>(1.0, 0.62, 0.34);
    let hot = vec3<f32>(1.0, 0.78, 0.52);
    return mix(cool, hot, level * level);
}

// Percentage-closer filtering on a small disc. `shadow_sampler` is already bilinear, so a
// handful of taps is enough to take the staircase off an edge.
fn shadow_at(position: vec3<f32>, n_dot_l: f32) -> f32 {
    if !shadows_on || frame.has_shadow == 0u {
        return 1.0;
    }
    var p = shadow_position(position);
    if p.z <= 0.0 || p.z >= 1.0 || p.x < 0.0 || p.x > 1.0 || p.y < 0.0 || p.y > 1.0 {
        return 1.0;
    }
    // Bias scaled by how much ground one texel covers and how slanted the surface is, so
    // flat ground does not self-shadow into stripes.
    let slope = clamp(1.0 - n_dot_l, 0.05, 1.0);
    let bias = (frame.shadow_center_texel * 0.9 + 0.02) * slope * 0.0025 + 0.00004;
    p.z += bias;

    let radius = shadow_softness / max(frame.shadow_resolution, 1.0);
    var sum = 0.0;
    // Eight taps on two rings plus the centre.
    sum += textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy, p.z);
    for (var i = 0; i < 8; i++) {
        let angle = f32(i) * 0.7853982;
        let r = select(1.0, 2.0, (i & 1) == 1) * radius;
        let o = vec2<f32>(cos(angle), sin(angle)) * r;
        sum += textureSampleCompareLevel(shadow_map, shadow_sampler, p.xy + o, p.z);
    }
    return sum / 9.0;
}

// Light that passes through stained glass or water keeps that colour.
fn shadow_tint(position: vec3<f32>, lit: f32) -> vec3<f32> {
    if !shadows_on || frame.has_shadow == 0u || lit <= 0.0 {
        return vec3<f32>(1.0);
    }
    let p = shadow_position(position);
    let through = textureSampleCompareLevel(shadow_map_translucent, shadow_sampler, p.xy, p.z);
    // Lit in the solid map but blocked in the translucent one: something coloured is above.
    if through >= lit - 0.02 {
        return vec3<f32>(1.0);
    }
    let texel = vec2<i32>(p.xy * vec2<f32>(textureDimensions(shadow_color)));
    let c = textureLoad(shadow_color, texel, 0);
    return mix(vec3<f32>(1.0), c.rgb, saturate(c.a));
}

fn material(input: MaterialInput) -> Surface {
    let albedo = input.albedo * input.tint;
    let is_foliage = (input.tags & TAG_FOLIAGE) != 0u;

    // --- surface normal -----------------------------------------------------------------
    var normal = input.normal;
    if block_pbr_maps() {
        let n = block_normal_map(input.uv);
        // LabPBR stores xy; rebuild z and bring it into world axes with the tangent frame.
        let nxy = n.xy * 2.0 - 1.0;
        let nz = sqrt(saturate(1.0 - dot(nxy, nxy)));
        let t = input.tangent.xyz;
        let b = cross(input.normal, t) * input.tangent.w;
        normal = normalize(t * nxy.x + b * nxy.y + input.normal * nz);
    }

    // --- direct light -------------------------------------------------------------------
    let l = frame.light_direction;
    var n_dot_l = dot(normal, l);
    // Foliage is lit from both sides: leaves are thin.
    if is_foliage {
        n_dot_l = mix(n_dot_l, abs(n_dot_l), 0.55);
    }
    let facing = saturate(n_dot_l);
    let lit = shadow_at(input.position, facing) * input.light.y;
    let sun = light_color() * facing * lit * shadow_tint(input.position, lit);

    // Subsurface: light coming through foliage from behind, strongest looking into the sun.
    var sss = vec3<f32>(0.0);
    if is_foliage && sss_strength > 0.0 {
        let view = normalize(-input.position);
        let back = saturate(dot(view, -l)) * saturate(-n_dot_l + 0.35);
        sss = light_color() * back * lit * sss_strength * 0.8;
    }

    // --- ambient ------------------------------------------------------------------------
    // Vanilla's lightmap carries the sky's own gradient; keep its shape, take our colour.
    let sky_amount = input.light.y * input.light.y * 0.85 + input.light.y * 0.15;
    var ambient = ambient_color() * sky_amount * ambient_strength;
    // Ambient occlusion and face shade already ride in `input.tint`, which multiplied the
    // albedo above. `ao_strength` deepens it on the ambient term only, where contact shade
    // reads most: a corner loses sky light faster than it loses direct light.
    let shade = saturate(luminance(input.tint.rgb));
    ambient *= mix(1.0, shade, ao_strength);

    // --- block light --------------------------------------------------------------------
    var block = torch_color(input.light.x) * input.light.x * input.light.x * block_light_strength;
    if block_light_color_on {
        let tint = block_light_color(input.position);
        block *= mix(vec3<f32>(1.0), tint.rgb, saturate(tint.a));
    }
    // Lights carried or dropped nearby, and mod lights.
    block += input.colored_light * block_light_strength;

    // --- emission -----------------------------------------------------------------------
    // Only real light sources. See the note at the top of this file.
    var emission = input.emission;
    if block_pbr_maps() {
        let s = block_specular_map(input.uv);
        // LabPBR: alpha 1.0 means "no emission here", below that it is the amount.
        emission = max(emission, select(s.a, 0.0, s.a >= 0.999));
    }
    emission *= emission_strength;

    // --- put it together ----------------------------------------------------------------
    var light = sun + sss + ambient + block;
    // Night vision and the Brightness slider lift the floor, as vanilla's lightmap does.
    light += vec3<f32>(0.08 * frame.brightness + 0.45 * frame.night_vision);
    light *= 1.0 - saturate(frame.blindness + frame.darkness * 0.6);

    var color = albedo.rgb * light;
    // Emission keeps the texture's own colour and ignores the lighting above it.
    color = mix(color, albedo.rgb, saturate(emission));

    // --- specular -----------------------------------------------------------------------
    var smoothness = 0.0;
    if specular_on {
        if block_pbr_maps() {
            smoothness = block_specular_map(input.uv).r;
        }
        if (input.tags & TAG_WATER) != 0u || input.fluid == 1u {
            smoothness = max(smoothness, 0.92);
        }
        if smoothness > 0.0 && lit > 0.0 {
            let view = normalize(-input.position);
            let h = normalize(view + l);
            let power = exp2(2.0 + smoothness * 10.0);
            let spec = pow(saturate(dot(normal, h)), power) * smoothness;
            color += light_color() * spec * lit * facing * specular_strength;
        }
    }

    // Hand the post passes this point's normal and smoothness for light shafts and
    // reflections; `data` carries emission so bloom can find real light sources.
    set_surface(normal, smoothness, emission);

    return Surface(vec4<f32>(color, albedo.a));
}
