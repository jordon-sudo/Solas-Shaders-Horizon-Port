// Rain and snow streaks. Horizon applies neither its light nor its fog here, so the streak
// takes the sky's own light and fades into the distance itself.

override rain_opacity: f32 = 0.8;

fn weather(input: WeatherInput) -> vec4<f32> {
    // Streaks are lit by the sky, not by torches: rain in a dark cave stays dark.
    let sky = input.light.y * input.light.y;
    var tint = mix(ambient_color(), light_color(), 0.35 * daylight());
    tint *= 0.55 + 0.45 * sky;

    // Snow keeps more of its own white and falls softer; rain is thin and takes the sky.
    var color = input.color.rgb * tint;
    var alpha = input.color.a * rain_opacity;
    if input.snow {
        color = mix(color, input.color.rgb * mix(tint, vec3<f32>(1.0), 0.5), 0.7);
        alpha *= 0.85;
    } else {
        alpha *= 0.75;
    }

    // Fade the far ones out so the curtain has depth instead of a hard wall.
    let distance = length(input.position);
    alpha *= 1.0 - smoothstep(14.0, 32.0, distance);

    return vec4<f32>(color, saturate(alpha));
}
