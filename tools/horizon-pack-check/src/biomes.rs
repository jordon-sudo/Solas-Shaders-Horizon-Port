//! Vanilla's biomes, in the order custom uniforms number them.
//!
//! `BIOME_<NAME>` in `shaders.properties` is a constant whose value is the biome's number.
//! Horizon builds those constants from the game's biome registry, which only exists once the
//! game has loaded its resources. A checker that passes no biomes leaves every `BIOME_*`
//! reading -1, so a pack's biome-dependent uniforms look broken when they are not.
//!
//! This is `VANILLA_ORDER` from `crates/horizon-shaders/src/biomes.rs` in horizon-rust/horizon
//! (MIT): vanilla's biomes in the order its `Biomes` class declares them, which is how Iris
//! numbers them (forest 8, ocean 46, soul_sand_valley 60, the_end 62). Horizon's module is
//! private, so the list is copied rather than imported.
//!
//! A pack checked against this sees vanilla's biomes only. A world adding biomes numbers them
//! after these, so a pack naming a modded biome still reads -1 here.

/// Vanilla's biome identifiers, without the `minecraft:` namespace, in declaration order.
pub const VANILLA_ORDER: [&str; 67] = [
    "the_void",
    "plains",
    "sunflower_plains",
    "snowy_plains",
    "ice_spikes",
    "desert",
    "swamp",
    "mangrove_swamp",
    "forest",
    "flower_forest",
    "birch_forest",
    "dappled_forest",
    "dark_forest",
    "pale_garden",
    "old_growth_birch_forest",
    "old_growth_pine_taiga",
    "old_growth_spruce_taiga",
    "taiga",
    "snowy_taiga",
    "savanna",
    "savanna_plateau",
    "windswept_hills",
    "windswept_gravelly_hills",
    "windswept_forest",
    "windswept_savanna",
    "jungle",
    "sparse_jungle",
    "bamboo_jungle",
    "badlands",
    "eroded_badlands",
    "wooded_badlands",
    "meadow",
    "cherry_grove",
    "grove",
    "snowy_slopes",
    "frozen_peaks",
    "jagged_peaks",
    "stony_peaks",
    "river",
    "frozen_river",
    "beach",
    "snowy_beach",
    "stony_shore",
    "warm_ocean",
    "lukewarm_ocean",
    "deep_lukewarm_ocean",
    "ocean",
    "deep_ocean",
    "cold_ocean",
    "deep_cold_ocean",
    "frozen_ocean",
    "deep_frozen_ocean",
    "mushroom_fields",
    "dripstone_caves",
    "lush_caves",
    "deep_dark",
    "sulfur_caves",
    "nether_wastes",
    "warped_forest",
    "crimson_forest",
    "soul_sand_valley",
    "basalt_deltas",
    "the_end",
    "end_highlands",
    "end_midlands",
    "small_end_islands",
    "end_barrens",
];

/// The identifiers to hand `Custom::set_biomes`, namespaced as the registry lists them.
pub fn registry_identifiers() -> Vec<String> {
    VANILLA_ORDER
        .iter()
        .map(|b| format!("minecraft:{b}"))
        .collect()
}
