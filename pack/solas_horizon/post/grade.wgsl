// The last pass: bloom in, then exposure, tonemap, colour and the lens.
//
// This is where the picture stops being light values and becomes an image, so everything
// that should happen in linear light happens before the tonemap, and everything that is a
// property of the lens (vignette, aberration) happens after it.

override bloom_strength: f32 = 0.45;
override exposure: f32 = 1.0;
override auto_exposure: bool = true;
override saturation: f32 = 1.12;
override contrast: f32 = 1.06;
override vignette_on: bool = true;
override vignette_strength: f32 = 0.35;
override aberration: f32 = 0.25;

// Narkowicz's ACES fit: filmic, keeps highlights from clipping to white flat.
fn tonemap(x: vec3<f32>) -> vec3<f32> {
    let a = 2.51;
    let b = 0.03;
    let c = 2.43;
    let d = 0.59;
    let e = 0.14;
    return saturate3((x * (a * x + b)) / (x * (c * x + d) + e));
}

fn post(input: PostInput) -> vec4<f32> {
    // --- the lens: sample the picture, splitting the channels toward the edges -----------
    var color: vec3<f32>;
    if aberration > 0.0 {
        let off = (input.uv - 0.5) * aberration * 0.004;
        color = vec3<f32>(
            textureSampleLevel(previous, linear_sampler, saturate2(input.uv + off), 0.0).r,
            input.color.g,
            textureSampleLevel(previous, linear_sampler, saturate2(input.uv - off), 0.0).b,
        );
    } else {
        color = input.color.rgb;
    }

    // --- bloom ---------------------------------------------------------------------------
    if bloom_strength > 0.0 {
        let glow = textureSampleLevel(bloom, linear_sampler, input.uv, 0.0).rgb;
        color += glow * bloom_strength;
    }

    // --- exposure, in linear light -------------------------------------------------------
    var ev = exposure;
    if auto_exposure {
        // The light at the camera, eased, stands in for a meter: walking into a cave opens
        // up, stepping into noon sun stops down. `eye_light_smooth` is already time-eased,
        // so this does not flicker.
        let eye = max(frame.eye_light_smooth.x, frame.eye_light_smooth.y * daylight());
        ev *= mix(1.45, 0.85, smoothstep(0.1, 0.9, eye));
    }
    color *= ev;

    // Underwater and lava take the whole picture, before the tonemap so it reads as light.
    color = mix(color, color * vec3<f32>(0.28, 0.60, 0.92), frame.in_water * 0.75);
    color = mix(color, color * vec3<f32>(1.25, 0.42, 0.10), frame.in_lava * 0.85);

    color = tonemap(color);

    // --- colour --------------------------------------------------------------------------
    let grey = vec3<f32>(luminance(color));
    color = saturate3(mix(grey, color, saturation));
    color = saturate3((color - 0.5) * contrast + 0.5);

    // --- vignette ------------------------------------------------------------------------
    if vignette_on && vignette_strength > 0.0 {
        // Measured in a square space so it stays round on a wide window.
        let d = (input.uv - 0.5) * vec2<f32>(frame.resolution.x / max(frame.resolution.y, 1.0), 1.0);
        let v = 1.0 - smoothstep(0.35, 0.95, length(d)) * vignette_strength;
        color *= v;
    }

    // Blindness and darkness close the picture down last of all.
    color *= 1.0 - saturate(frame.blindness * 0.9);

    // The alpha the HDR path reads to find light sources.
    return vec4<f32>(color, input.color.a);
}
