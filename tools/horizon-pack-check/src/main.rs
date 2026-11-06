//! Checks whether an Iris/OptiFine shader pack loads and translates on Horizon's renderer.
//!
//! Horizon reads the `shaders/` pack format with its own clean-room loader
//! (`horizon-shaders`) and translates each program's GLSL into naga modules, which wgpu then
//! writes out for Vulkan, DirectX 12, OpenGL or Metal. Everything up to that last step can be
//! checked without a GPU, a copy of Minecraft, or the game itself — which is what this does:
//!
//! 1. the pack's `shaders.properties`, its id files and its `.lang`
//! 2. every stage file through the GLSL preprocessor
//! 3. every composite-style program translated
//! 4. each dimension loaded as the game loads it (terrain, water, sky, entities, hand,
//!    shadow, compute), with the game's vertex inputs
//! 5. every resulting module written out by all four backends
//! 6. the pack's custom uniforms resolved against the built-ins the renderer really provides
//!
//! What it cannot tell you is whether the result *looks* right: that needs the game on a GPU.
//! A clean run means the pack builds and runs, not that every pixel matches Iris.
//!
//! Usage:
//!   horizon-pack-check <folder-of-packs-or-a-pack> [--verbose] [--quiet]

mod backends;
mod biomes;
mod uniforms;

use std::path::{Path, PathBuf};
use std::process::ExitCode;

use horizon_shaders::{
    GameInputs, GbuffersInputs, GeometryInputs, Lang, Macros, Pack, Properties, Target,
    dimension_folder, discover, load_post, preprocess, translate_composite,
};

/// The dimensions the game loads a pack for: the Overworld, the Nether and the End.
const DIMENSIONS: [i32; 3] = [0, -1, 1];

/// Mipmap level the renderer reports to packs; matches Horizon's own test.
const MIPMAP_LEVELS: u32 = 4;

fn main() -> ExitCode {
    let mut args = std::env::args_os().skip(1);
    let mut root: Option<PathBuf> = None;
    let (mut verbose, mut quiet) = (false, false);
    for a in args.by_ref() {
        match a.to_string_lossy().as_ref() {
            "--verbose" | "-v" => verbose = true,
            "--quiet" | "-q" => quiet = true,
            "--help" | "-h" => {
                println!("{}", HELP);
                return ExitCode::SUCCESS;
            }
            s if s.starts_with('-') => {
                eprintln!("unknown option `{s}`\n\n{HELP}");
                return ExitCode::from(2);
            }
            _ => root = Some(PathBuf::from(a)),
        }
    }
    let Some(root) = root else {
        eprintln!("{HELP}");
        return ExitCode::from(2);
    };
    if !root.exists() {
        eprintln!("no such path: {}", root.display());
        return ExitCode::from(2);
    }

    // A path given straight at one pack — a zip, or a folder with `shaders/` in it — rather
    // than at a folder of packs. `discover` only scans a directory, so ask it about the
    // parent and keep the one entry the user meant.
    let one_pack = root.is_file() || root.join("shaders").is_dir();
    let mut found = if one_pack {
        let name = root.file_name().unwrap_or_default().to_owned();
        root.parent()
            .map(|parent| {
                discover(parent)
                    .into_iter()
                    .filter(|f| f.path.file_name().unwrap_or_default() == name)
                    .collect()
            })
            .unwrap_or_default()
    } else {
        discover(&root)
    };

    // Anything `discover` rejected at the level the user pointed at is worth saying: they
    // meant it to be a pack. Entries found by looking further down are not.
    for f in found.iter().filter(|f| f.problem.is_some()) {
        eprintln!(
            "{}: cannot read: {}",
            f.name,
            f.problem.as_deref().unwrap_or("unknown")
        );
    }

    // Then one level down, so a folder of folders of packs works too. A pack's own
    // subfolders (`shaders/`, `drm/`...) are not packs, so only keep what reads cleanly —
    // and don't go looking inside a pack the user pointed at directly.
    let known: Vec<PathBuf> = found.iter().map(|f| f.path.clone()).collect();
    if let Some(entries) = std::fs::read_dir(&root).ok().filter(|_| !one_pack) {
        for sub in entries.flatten() {
            let path = sub.path();
            if path.is_dir() && !known.contains(&path) {
                found.extend(discover(&path).into_iter().filter(|f| f.problem.is_none()));
            }
        }
    }

    let usable: Vec<_> = found.iter().filter(|f| f.problem.is_none()).collect();
    if usable.is_empty() {
        eprintln!("no readable shader packs under {}", root.display());
        return ExitCode::from(2);
    }

    let mut all_ok = true;
    for f in usable {
        match check_pack(&f.path, &f.name, verbose, quiet) {
            Ok(ok) => all_ok &= ok,
            Err(e) => {
                eprintln!("{}: {e}", f.name);
                all_ok = false;
            }
        }
    }
    if all_ok {
        ExitCode::SUCCESS
    } else {
        ExitCode::FAILURE
    }
}

const HELP: &str = "\
horizon-pack-check <folder-of-packs-or-a-pack> [options]

Checks an Iris/OptiFine shader pack against Horizon's loader, translator and the four
shader backends wgpu uses. Needs no GPU, no Minecraft and no Horizon build.

Options:
  -v, --verbose   list every note, diagnostic and failure (default: the first few)
  -q, --quiet     only the per-pack verdict line
  -h, --help      this text

Exits 0 when every pack checks out, 1 when one fails, 2 on a usage problem.";

/// Checks one pack. Returns whether it came out clean.
fn check_pack(path: &Path, name: &str, verbose: bool, quiet: bool) -> Result<bool, String> {
    let shown = if verbose { usize::MAX } else { 8 };
    let pack = Pack::open(path).map_err(|e| format!("{e:?}"))?;

    // The macros the game reads a pack's programs with.
    let mut macros = Macros::standard();
    macros.define_renderer(MIPMAP_LEVELS);
    let (shaders, feature_notes) = horizon_shaders::read_properties(&pack, &mut macros);
    let ids: Vec<Properties> = ["block", "item", "entity", "dimension"]
        .iter()
        .filter_map(|n| pack.read_text(&format!("{n}.properties")))
        .map(|t| Properties::parse(&t, &macros))
        .collect();
    let lang = Lang::load(&pack, "en_us");

    let mut problems: Vec<String> = Vec::new();
    let mut warnings: Vec<String> = Vec::new();

    if shaders.entries.is_empty() {
        problems.push("shaders.properties: no keys read".into());
    }
    for n in &shaders.notes {
        warnings.push(format!("shaders.properties:{}: {}", n.line, n.message));
    }
    for p in &ids {
        for n in &p.notes {
            warnings.push(format!("id file:{}: {}", n.line, n.message));
        }
    }
    // A pack naming a feature Horizon does not implement yet is the one case where the pack
    // reads fine but will not behave: surface it.
    for note in &feature_notes {
        warnings.push(note.clone());
    }

    if !quiet {
        println!("== {name} ==");
        println!(
            "  manifest: shaders.properties {} keys, {} id file(s) {} keys, lang {}",
            shaders.entries.len(),
            ids.len(),
            ids.iter().map(|p| p.entries.len()).sum::<usize>(),
            if lang == Lang::default() {
                "none"
            } else {
                "read"
            }
        );
    }

    // --- every stage file through the preprocessor -------------------------------------
    let (mut stages, mut lines) = (0usize, 0usize);
    let mut diagnostics: Vec<String> = Vec::new();
    for dir in ["", "world0", "world-1", "world1"] {
        for file in pack.list(dir) {
            if ![".vsh", ".fsh", ".gsh", ".csh"]
                .iter()
                .any(|e| file.ends_with(e))
            {
                continue;
            }
            let rel = if dir.is_empty() {
                file
            } else {
                format!("{dir}/{file}")
            };
            let p = preprocess(&pack, &rel, &macros);
            stages += 1;
            lines += p.lines.len();
            diagnostics.extend(p.diagnostics.iter().map(|d| {
                let f = &p.files[d.origin.file as usize];
                format!("{f}:{}: {}", d.origin.line, d.message)
            }));
        }
    }
    diagnostics.sort();
    diagnostics.dedup();
    if !quiet {
        println!(
            "  preprocess: {stages} stage files, {lines} lines, {} diagnostics",
            diagnostics.len()
        );
    }
    problems.extend(diagnostics.iter().cloned());

    // --- composite-style programs translated -------------------------------------------
    let (mut ok, mut failed) = (0usize, 0usize);
    for dir in ["", "world0", "world-1", "world1"] {
        for file in pack.list(dir) {
            let Some(stem) = file.strip_suffix(".fsh") else {
                continue;
            };
            let is_composite = [
                "composite",
                "deferred",
                "final",
                "prepare",
                "begin",
                "shadowcomp",
            ]
            .iter()
            .any(|p| {
                stem.strip_prefix(p)
                    .is_some_and(|n| n.chars().all(|c| c.is_ascii_digit()))
            });
            if !is_composite {
                continue;
            }
            let at = |ext: &str| {
                if dir.is_empty() {
                    format!("{stem}.{ext}")
                } else {
                    format!("{dir}/{stem}.{ext}")
                }
            };
            if !pack.exists(&at("vsh")) {
                continue;
            }
            let target = if stem == "final" {
                Target::Window
            } else {
                Target::Buffers
            };
            let v = preprocess(&pack, &at("vsh"), &macros);
            let fr = preprocess(&pack, &at("fsh"), &macros);
            match translate_composite(&v, &fr, target) {
                Ok(_) => ok += 1,
                Err(errors) => {
                    failed += 1;
                    for e in errors.iter().take(1) {
                        problems.push(format!(
                            "{}: {}:{}: {}",
                            at("fsh"),
                            e.file,
                            e.line,
                            e.message
                        ));
                    }
                }
            }
        }
    }
    if !quiet {
        println!("  translate: {ok} composite-style programs, {failed} failed");
    }

    // --- each dimension loaded as the game loads it ------------------------------------
    let inputs = game_inputs();
    for id in DIMENSIONS {
        let folder = dimension_folder(&pack, id);
        let post = load_post(&pack, &folder, &shaders, &macros, &inputs);

        let notes: Vec<&String> = post.notes.iter().chain(&post.config.notes).collect();
        let report = backends::check(&post);

        if !quiet {
            println!(
                "  dimension {id:>2} (`{}`): {} post programs, shadow {}, {} compute, {} modules, {} backend failure(s), {} note(s)",
                if folder.is_empty() { "." } else { &folder },
                post.programs.len(),
                if post.shadow_pass { "yes" } else { "no" },
                post.shadow_comp.len(),
                report.modules,
                report.failures.len(),
                notes.len(),
            );
        }
        for n in &notes {
            warnings.push(format!("dimension {id}: {n}"));
        }
        for f in &report.failures {
            problems.push(format!(
                "dimension {id}: {} {}: {}{}",
                f.backend,
                f.module,
                if f.panicked { "PANIC: " } else { "" },
                f.message
            ));
        }

        // --- custom uniforms, against the built-ins the renderer really provides -------
        // Horizon's own test passes `&|_| None` here, which makes every custom uniform that
        // reads a built-in look broken. Answering as the game does is the point of this tool.
        let mut custom = post.custom;
        // `BIOME_*` constants come from the game's biome registry, which needs loaded
        // resources. Vanilla's list numbers them the same way, so a pack written against
        // vanilla resolves exactly as it would in game.
        let names = biomes::registry_identifiers();
        let names: Vec<&str> = names.iter().map(String::as_str).collect();
        custom.set_biomes(&names);
        custom.eval(0.016, &uniforms::zero);
        let count = custom.uniforms().count();
        if !quiet {
            println!(
                "  dimension {id:>2}: {count} custom uniform(s), {} unresolved",
                custom.notes.len()
            );
        }
        for n in &custom.notes {
            // A genuinely unresolved custom uniform reads 0 at runtime: a real behaviour
            // difference, though not a load failure.
            warnings.push(format!("dimension {id}: {n}"));
        }
    }

    // --- verdict ------------------------------------------------------------------------
    let clean = problems.is_empty();
    if !problems.is_empty() {
        println!("  PROBLEMS ({}):", problems.len());
        for p in problems.iter().take(shown) {
            println!("    {p}");
        }
        if problems.len() > shown {
            println!("    ... {} more (--verbose)", problems.len() - shown);
        }
    }
    if !warnings.is_empty() && !quiet {
        println!("  notes ({}):", warnings.len());
        for w in warnings.iter().take(shown) {
            println!("    {w}");
        }
        if warnings.len() > shown {
            println!("    ... {} more (--verbose)", warnings.len() - shown);
        }
    }
    println!(
        "{name}: {}",
        if clean {
            "OK - loads and translates on Horizon"
        } else {
            "FAILED"
        }
    );
    Ok(clean)
}

/// The vertex inputs the renderer hands a pack's geometry programs.
///
/// Mirrors the set Horizon's `real_packs` test builds, which stands in for the real ones
/// written by `gfx/pack_post.rs`, `pack_atlas.rs` and `pack_hand.rs`. They have to be present
/// or the geometry programs cannot be translated at all.
fn game_inputs() -> GameInputs {
    let base = GbuffersInputs {
        declarations: "layout(location = 0) in vec3 hz_v_pos;".into(),
        body: "    hz_Vertex = vec4(hz_v_pos, 1.0);\n    hz_Color = vec4(1.0);\n".into(),
        attributes: vec![("mc_Entity".into(), "vec4(-1.0)".into())],
        ..Default::default()
    };
    GameInputs {
        terrain: Some(base.clone()),
        sky: Some(base.clone()),
        celestial: Some(base.clone()),
        entities: Some(base.clone()),
        clouds: Some(base.clone()),
        weather: Some(base.clone()),
        lines: Some(base.clone()),
        // The hand may read `currentRenderedItemId` undeclared.
        hand: Some(GbuffersInputs {
            item_id_declared: true,
            ..base.clone()
        }),
        // Solid, then cutout terrain.
        terrain_parts: Some([base.clone(), base.clone()]),
        terrain_geometry: Some(GeometryInputs {
            inputs: GbuffersInputs {
                declarations: format!(
                    "layout(set = 3, binding = 1) readonly buffer HzVertices {{ uint hz_vertices[]; }};\n{}",
                    base.declarations
                ),
                ..base.clone()
            },
            pull: "        hz_v_pos = uintBitsToFloat(uvec3(hz_vertices[hz_vertex_index * 6u], \
                   hz_vertices[hz_vertex_index * 6u + 1u], hz_vertices[hz_vertex_index * 6u + 2u]));\n"
                .into(),
            index: "uint(@)".into(),
        }),
        entity_geometry: Some(GeometryInputs {
            inputs: GbuffersInputs {
                declarations: format!(
                    "layout(set = 1, binding = 0) readonly buffer HzEntityVertices {{ uint hz_entity_vertices[]; }};\n{}",
                    base.declarations
                ),
                ..base.clone()
            },
            pull: "        hz_v_pos = uintBitsToFloat(uvec3(hz_entity_vertices[hz_vertex_index * 11u], \
                   hz_entity_vertices[hz_vertex_index * 11u + 1u], hz_entity_vertices[hz_vertex_index * 11u + 2u]));\n"
                .into(),
            index: "uint(@)".into(),
        }),
    }
}
