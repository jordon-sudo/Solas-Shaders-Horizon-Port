// Pulls out what is bright enough to bleed and blurs it, into the pack's own quarter-size
// `bloom` target. Writing a target instead of the chain means the next pass still reads the
// full-size picture as `previous`, and reads this as `bloom`.

override bloom_on: bool = true;
override bloom_threshold: f32 = 0.72;

fn bright_at(uv: vec2<f32>) -> vec3<f32> {
    let c = textureSampleLevel(previous, linear_sampler, clamp(uv, vec2<f32>(0.0), vec2<f32>(1.0)), 0.0).rgb;
    // Soft knee: nothing pops in at the threshold, it eases in over the next quarter.
    let l = luminance(c);
    let weight = smoothstep(bloom_threshold, bloom_threshold + 0.25, l);
    return c * weight;
}

fn post(input: PostInput) -> vec4<f32> {
    if !bloom_on {
        return vec4<f32>(0.0, 0.0, 0.0, 1.0);
    }
    // One texel of this quarter-size target, in the full picture's coordinates.
    let texel = 1.0 / (frame.resolution * 0.25);

    // A 13-tap tent: the centre, an inner box and an outer box. Cheap, and wide enough at
    // quarter size to read as a glow rather than a halo.
    var sum = bright_at(input.uv) * 4.0;
    sum += bright_at(input.uv + vec2<f32>(-texel.x, -texel.y)) * 2.0;
    sum += bright_at(input.uv + vec2<f32>(texel.x, -texel.y)) * 2.0;
    sum += bright_at(input.uv + vec2<f32>(-texel.x, texel.y)) * 2.0;
    sum += bright_at(input.uv + vec2<f32>(texel.x, texel.y)) * 2.0;
    sum += bright_at(input.uv + vec2<f32>(-texel.x * 2.0, 0.0));
    sum += bright_at(input.uv + vec2<f32>(texel.x * 2.0, 0.0));
    sum += bright_at(input.uv + vec2<f32>(0.0, -texel.y * 2.0));
    sum += bright_at(input.uv + vec2<f32>(0.0, texel.y * 2.0));
    sum += bright_at(input.uv + vec2<f32>(-texel.x * 2.0, -texel.y * 2.0)) * 0.5;
    sum += bright_at(input.uv + vec2<f32>(texel.x * 2.0, -texel.y * 2.0)) * 0.5;
    sum += bright_at(input.uv + vec2<f32>(-texel.x * 2.0, texel.y * 2.0)) * 0.5;
    sum += bright_at(input.uv + vec2<f32>(texel.x * 2.0, texel.y * 2.0)) * 0.5;

    return vec4<f32>(sum / 18.0, 1.0);
}
