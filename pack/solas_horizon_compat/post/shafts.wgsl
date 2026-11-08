// Volumetric light: shafts where the air between the camera and a surface is lit.
//
// Marches the view ray, asking the shadow map at each step whether that point sees the sun,
// and adds a little light for every step that does. Steps are dithered per pixel and per
// frame so the banding a short march would otherwise show breaks up into noise.

override shafts_on: bool = true;
override shafts_strength: f32 = 0.55;
override shafts_samples: i32 = 12;
override shafts_distance: f32 = 48.0;

fn shafts(uv: vec2<f32>, depth: f32) -> f32 {
    if !shafts_on || frame.has_shadow == 0u || shafts_strength <= 0.0 {
        return 0.0;
    }
    // Where this pixel's surface is; the sky marches the whole distance.
    let far_point = view_position(uv, max(depth, 0.000001));
    var march = select(min(length(far_point), shafts_distance), shafts_distance, depth <= 0.0);
    if march <= 0.25 {
        return 0.0;
    }
    let dir = normalize(select(far_point, view_position(uv, 0.000001), depth <= 0.0));

    let steps = clamp(shafts_samples, 2, 24);
    let step = march / f32(steps);
    // Dither the start of the march: per pixel, and rotated each frame.
    let jitter = hash12(uv * frame.resolution + f32(frame.frame_index % 16u) * 17.0);

    var sum = 0.0;
    for (var i = 0; i < steps; i++) {
        let t = (f32(i) + jitter) * step;
        let p = dir * t;
        let s = shadow_position(p);
        if s.z <= 0.0 || s.z >= 1.0 || s.x < 0.0 || s.x > 1.0 || s.y < 0.0 || s.y > 1.0 {
            continue;
        }
        sum += textureSampleCompareLevel(shadow_map, shadow_sampler, s.xy, s.z);
    }
    return sum / f32(steps);
}

fn post(input: PostInput) -> vec4<f32> {
    if !shafts_on {
        return input.color;
    }
    let amount = shafts(input.uv, input.depth);
    if amount <= 0.0 {
        return input.color;
    }

    // Shafts show against the light, not away from it: scale with how near the view ray
    // points at the sun, the way air scatters forward.
    let ray = normalize(view_position(input.uv, max(input.depth, 0.000001)));
    let toward = saturate(dot(ray, frame.light_direction));
    let forward = 0.25 + 0.75 * pow(toward, 3.0);

    // Thin in clear air, thicker in rain, and gone underwater (water has its own look).
    var density = shafts_strength * (0.6 + 0.8 * frame.rain);
    density *= 1.0 - frame.in_water;
    density *= mix(0.35, 1.0, daylight());

    let color = light_color() * amount * forward * density;
    return vec4<f32>(input.color.rgb + color, input.color.a);
}
