//! The built-in uniforms Horizon's renderer gives a shader pack, and their shapes.
//!
//! Custom uniforms in `shaders.properties` are expressions over built-in uniforms. To judge
//! whether a pack's custom uniforms resolve, a checker has to answer the same `builtin(name)`
//! queries the game answers. Horizon's own `real_packs` test passes `&|_| None`, so every
//! custom uniform that reads a built-in is reported "unknown" there; those notes are artifacts
//! of the stub, not pack problems.
//!
//! This table mirrors `NAMES` and `components()` in Horizon's
//! `crates/horizon-client-render/src/gfx/pack_uniforms.rs` (MIT, horizon-rust/horizon), so the
//! shapes match what a real frame supplies. Three internal dotted entries of `NAMES`
//! (`gbuffers.fogMode`, `gbuffers.fogShape`, `gbuffers.centerDepthSmooth`) are left out: a pack
//! cannot name them.

/// Every built-in uniform the renderer provides, in `NAMES` order.
pub const NAMES: &[&str] = &[
    "cameraPosition",
    "previousCameraPosition",
    "eyeAltitude",
    "upPosition",
    "sunPosition",
    "moonPosition",
    "shadowLightPosition",
    "sunAngle",
    "shadowAngle",
    "worldTime",
    "worldDay",
    "moonPhase",
    "frameCounter",
    "frameTime",
    "frameTimeCounter",
    "viewWidth",
    "viewHeight",
    "aspectRatio",
    "near",
    "far",
    "rainStrength",
    "wetness",
    "thunderStrength",
    "fogColor",
    "skyColor",
    "fogMode",
    "fogStart",
    "fogEnd",
    "fogDensity",
    "fogShape",
    "isEyeInWater",
    "blindness",
    "nightVision",
    "darknessFactor",
    "darknessLightFactor",
    "screenBrightness",
    "hideGUI",
    "eyeBrightness",
    "eyeBrightnessSmooth",
    "heldItemId",
    "heldItemId2",
    "heldBlockLightValue",
    "heldBlockLightValue2",
    "renderStage",
    "biome",
    "biome_category",
    "biome_precipitation",
    "temperature",
    "rainfall",
    "gbufferModelView",
    "gbufferModelViewInverse",
    "gbufferProjection",
    "gbufferProjectionInverse",
    "gbufferPreviousModelView",
    "gbufferPreviousProjection",
    "atlasSize",
    "shadowModelView",
    "shadowModelViewInverse",
    "shadowProjection",
    "shadowProjectionInverse",
    "cameraPositionInt",
    "cameraPositionFract",
    "previousCameraPositionInt",
    "previousCameraPositionFract",
    "eyePosition",
    "relativeEyePosition",
    "playerLookVector",
    "playerBodyVector",
    "firstPersonCamera",
    "currentPlayerHealth",
    "maxPlayerHealth",
    "currentPlayerHunger",
    "maxPlayerHunger",
    "currentPlayerAir",
    "maxPlayerAir",
    "currentPlayerArmor",
    "maxPlayerArmor",
    "isSpectator",
    "isRiding",
    "feetInWater",
    "inSwimmingAnimation",
    "is_burning",
    "is_hurt",
    "is_invisible",
    "is_sneaking",
    "is_sprinting",
    "endFlashIntensity",
    "endFlashPosition",
    "ambientLight",
    "playerMood",
    "constantMood",
    "centerDepthSmooth",
    "alphaTestRef",
    "entityId",
    "blockEntityId",
    "entityColor",
    "isRightHanded",
    "is_on_ground",
    "bedrockLevel",
    "heightLimit",
    "logicalHeightLimit",
    "hasSkylight",
    "hasCeiling",
    "cloudTime",
    "isElytraFlying",
    "cloudHeight",
];

/// How many components `name` carries, as `components()` in `pack_uniforms.rs`.
pub fn components(name: &str) -> usize {
    match name {
        "cameraPosition"
        | "previousCameraPosition"
        | "cameraPositionInt"
        | "cameraPositionFract"
        | "previousCameraPositionInt"
        | "previousCameraPositionFract"
        | "eyePosition"
        | "relativeEyePosition"
        | "playerLookVector"
        | "playerBodyVector"
        | "upPosition"
        | "sunPosition"
        | "moonPosition"
        | "shadowLightPosition"
        | "fogColor"
        | "skyColor"
        | "endFlashPosition" => 3,
        "eyeBrightness" | "eyeBrightnessSmooth" | "atlasSize" => 2,
        "entityColor" => 4,
        n if n.starts_with("gbuffer") || n.starts_with("shadow") && n != "shadowAngle" => 16,
        _ => 1,
    }
}

/// What a built-in gives custom uniforms, at its real shape: zeros, as Horizon's `zero()` does
/// before the first frame. Shapes are what the resolver checks, so zeros are enough.
pub fn zero(name: &str) -> Option<horizon_shaders::Val> {
    if !NAMES.contains(&name) {
        return None;
    }
    Some(horizon_shaders::Val::vector(&[0.0; 16][..components(name)]))
}
