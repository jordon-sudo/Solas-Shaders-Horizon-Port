// Shared helpers, put before every stage.
//
// Nothing here reads a texture or declares an override that is an option: this file is
// compiled into all four stages, so anything costly lives in the stage that needs it.

const PI: f32 = 3.14159265;
const TAU: f32 = 6.28318531;

fn luminance(c: vec3<f32>) -> f32 {
    return dot(c, vec3<f32>(0.2126, 0.7152, 0.0722));
}

fn saturate(x: f32) -> f32 {
    return clamp(x, 0.0, 1.0);
}

fn saturate2(c: vec2<f32>) -> vec2<f32> {
    return clamp(c, vec2<f32>(0.0), vec2<f32>(1.0));
}

fn saturate3(c: vec3<f32>) -> vec3<f32> {
    return clamp(c, vec3<f32>(0.0), vec3<f32>(1.0));
}

// --- noise ------------------------------------------------------------------------------
// Hash-based, so the pack needs no texture file and stays one folder of WGSL.

fn hash12(p: vec2<f32>) -> f32 {
    var p3 = fract(vec3<f32>(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

fn hash13(p: vec3<f32>) -> f32 {
    var p3 = fract(p * 0.1031);
    p3 += dot(p3, p3.zyx + 31.32);
    return fract((p3.x + p3.y) * p3.z);
}

// Value noise, smoothed between lattice points.
fn noise2(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = hash12(i);
    let b = hash12(i + vec2<f32>(1.0, 0.0));
    let c = hash12(i + vec2<f32>(0.0, 1.0));
    let d = hash12(i + vec2<f32>(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

fn noise3(p: vec3<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = mix(hash13(i + vec3<f32>(0.0, 0.0, 0.0)), hash13(i + vec3<f32>(1.0, 0.0, 0.0)), u.x);
    let b = mix(hash13(i + vec3<f32>(0.0, 1.0, 0.0)), hash13(i + vec3<f32>(1.0, 1.0, 0.0)), u.x);
    let c = mix(hash13(i + vec3<f32>(0.0, 0.0, 1.0)), hash13(i + vec3<f32>(1.0, 0.0, 1.0)), u.x);
    let d = mix(hash13(i + vec3<f32>(0.0, 1.0, 1.0)), hash13(i + vec3<f32>(1.0, 1.1, 1.0)), u.x);
    return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

// Four octaves, enough for cloud and aurora shapes without a texture read.
fn fbm2(p: vec2<f32>) -> f32 {
    var sum = 0.0;
    var amp = 0.5;
    var at = p;
    for (var i = 0; i < 4; i++) {
        sum += noise2(at) * amp;
        at *= 2.02;
        amp *= 0.5;
    }
    return sum;
}

// --- time of day ------------------------------------------------------------------------

// 1 while the sun is up in the Overworld, easing out through the horizon.
fn daylight() -> f32 {
    return select(0.0, smoothstep(-0.12, 0.12, frame.sun_direction.y), frame.dimension == 0);
}

// 1 when the light is at the horizon, 0 once it is well up: the sunrise and sunset window.
fn low_sun() -> f32 {
    return 1.0 - smoothstep(0.0, 0.32, abs(frame.sun_direction.y));
}

// 1 at night, counting only the Overworld.
fn night() -> f32 {
    return select(0.0, 1.0 - smoothstep(-0.12, 0.06, frame.sun_direction.y), frame.dimension == 0);
}

// Solas's palette: the colour the sunlight takes through the day. Warm and low at dawn and
// dusk, near-white at noon, cool and dim under the moon.
fn light_color() -> vec3<f32> {
    let dawn = vec3<f32>(1.0, 0.52, 0.26);
    let noon = vec3<f32>(1.0, 0.96, 0.88);
    let moon = vec3<f32>(0.42, 0.52, 0.78);
    let day = mix(dawn, noon, smoothstep(0.0, 0.42, frame.sun_direction.y));
    return mix(moon, day, daylight());
}

// The ambient (sky) light, which stays bluer than the direct light.
fn ambient_color() -> vec3<f32> {
    let dawn = vec3<f32>(0.42, 0.40, 0.52);
    let noon = vec3<f32>(0.55, 0.66, 0.88);
    let moon = vec3<f32>(0.13, 0.17, 0.30);
    let day = mix(dawn, noon, smoothstep(0.0, 0.42, frame.sun_direction.y));
    return mix(moon, day, daylight());
}

// Rain flattens and greys both.
fn weather_fade(c: vec3<f32>) -> vec3<f32> {
    let grey = vec3<f32>(luminance(c));
    return mix(c, grey * 0.8, frame.rain * 0.7);
}
