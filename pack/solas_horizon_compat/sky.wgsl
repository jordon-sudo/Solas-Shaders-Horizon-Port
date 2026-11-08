// The sky along each view ray: a deeper gradient than vanilla's, a warm band around a low
// sun, and at night stars, the Milky Way and an aurora.
//
// Horizon draws the sun, moon and vanilla clouds over whatever this returns, so the result is
// the backdrop only. Alpha is ignored.

override sky_brightness: f32 = 1.0;
override sunset_intensity: f32 = 0.8;
override stars_on: bool = true;
override star_brightness: f32 = 0.7;
override milky_way_on: bool = true;
override aurora_on: bool = true;
override aurora_brightness: f32 = 0.6;

// Stars on a lattice: one candidate per cell, jittered, so they do not sit in rows. Size is
// in cells, which keeps them round and the same size at any resolution.
fn stars(dir: vec3<f32>) -> f32 {
    if !stars_on {
        return 0.0;
    }
    // Project onto a cube face so the lattice does not pinch at the poles.
    let a = abs(dir);
    var uv: vec2<f32>;
    if a.y >= a.x && a.y >= a.z {
        uv = dir.xz / a.y;
    } else if a.x >= a.z {
        uv = dir.yz / a.x;
    } else {
        uv = dir.xy / a.z;
    }
    let grid = uv * 110.0;
    let cell = floor(grid);
    let here = fract(grid);
    let seed = hash12(cell);
    // Only some cells hold a star.
    if seed < 0.955 {
        return 0.0;
    }
    let jitter = vec2<f32>(hash12(cell + 11.3), hash12(cell + 27.7));
    let d = distance(here, jitter * 0.6 + 0.2);
    let star = 1.0 - smoothstep(0.0, 0.10, d);
    // A slow twitch, out of phase per star.
    let twinkle = 0.75 + 0.25 * sin(frame.time * 1.7 + seed * TAU * 8.0);
    return star * star * twinkle * (0.4 + seed * 0.6);
}

// A broad dusty band, brightest along its spine, with holes knocked out of it.
fn milky_way(dir: vec3<f32>) -> vec3<f32> {
    if !milky_way_on {
        return vec3<f32>(0.0);
    }
    // A plane tilted off the horizon; distance from it is the band's cross-section.
    let axis = normalize(vec3<f32>(0.42, 0.80, 0.42));
    let across = dot(dir, axis);
    let band = exp(-across * across * 26.0);
    if band < 0.004 {
        return vec3<f32>(0.0);
    }
    let along = vec2<f32>(atan2(dir.z, dir.x) * 2.2, across * 9.0);
    let dust = fbm2(along * 2.4);
    let holes = smoothstep(0.30, 0.78, fbm2(along * 1.1 + 13.0));
    let strength = band * dust * holes;
    // Cooler at the edges, warmer in the core, as Solas's is.
    let core = vec3<f32>(0.72, 0.68, 0.86);
    let edge = vec3<f32>(0.30, 0.40, 0.72);
    return mix(edge, core, saturate(strength * 1.6)) * strength * 0.5;
}

// Curtains: a vertical falloff over a band of moving noise, green low and violet high.
fn aurora(dir: vec3<f32>) -> vec3<f32> {
    if !aurora_on || dir.y <= 0.02 {
        return vec3<f32>(0.0);
    }
    // Where the ray crosses a shell well above the world.
    let height = 0.22;
    let t = height / dir.y;
    if t > 14.0 {
        return vec3<f32>(0.0);
    }
    let at = dir.xz * t;
    let drift = frame.time * 0.035;
    // Two bands at different speeds read as folding curtains.
    let n1 = fbm2(at * 2.6 + vec2<f32>(drift, drift * 0.6));
    let n2 = fbm2(at * 5.2 - vec2<f32>(drift * 1.7, drift));
    var curtain = smoothstep(0.52, 0.86, n1 * 0.7 + n2 * 0.4);
    // Fade with the ray's angle so it thins out toward the horizon and overhead.
    curtain *= smoothstep(0.02, 0.22, dir.y) * (1.0 - smoothstep(0.55, 1.0, dir.y));
    if curtain <= 0.0 {
        return vec3<f32>(0.0);
    }
    let low = vec3<f32>(0.18, 1.0, 0.52);
    let high = vec3<f32>(0.42, 0.30, 0.95);
    let tint = mix(low, high, saturate(n2 * 0.8 + dir.y * 0.7));
    return tint * curtain;
}

fn sky(input: SkyInput) -> vec4<f32> {
    let d = input.direction;
    let day = daylight();
    let dark = night();

    // Start from vanilla's own colour so biome and weather still read, then deepen the
    // zenith: vanilla's gradient is flat compared with Solas's.
    var color = input.color.rgb;
    let up = saturate(d.y);
    let deepen = smoothstep(0.05, 0.95, up) * day * (1.0 - frame.rain * 0.8);
    color *= 1.0 - deepen * vec3<f32>(0.42, 0.26, 0.02);

    // The warm band around a low sun, strongest along the ray toward it and near the horizon.
    let toward = max(dot(d, frame.sun_direction), 0.0);
    let near_horizon = 1.0 - smoothstep(0.0, 0.42, abs(d.y));
    let halo = pow(toward, 7.0) * 0.7 + near_horizon * toward * toward * 0.5;
    let warm = vec3<f32>(1.0, 0.46, 0.18) * halo * low_sun() * day
        * sunset_intensity * (1.0 - frame.rain);
    color += warm;

    // Night sky, faded out by daylight, rain and the moon's own glow near it.
    if dark > 0.002 {
        let clear = dark * (1.0 - frame.rain);
        let moon_glow = 1.0 - 0.6 * pow(max(dot(d, frame.moon_direction), 0.0), 6.0);
        color += milky_way(d) * clear * moon_glow;
        color += vec3<f32>(0.85, 0.90, 1.0) * stars(d) * star_brightness * clear * moon_glow;
        color += aurora(d) * aurora_brightness * clear * 0.5;
    }

    return vec4<f32>(weather_fade(color) * sky_brightness, input.color.a);
}
