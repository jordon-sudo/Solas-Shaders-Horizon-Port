//! Every translated module through the shader writers wgpu uses on each platform.
//!
//! A module that validates under naga can still fail when a backend writes it out, and that
//! failure is what a player meets as a black screen on one GPU and not another. So each module
//! goes through SPIR-V (Vulkan), HLSL (DirectX 12), GLSL (OpenGL) and MSL (Metal), with the
//! same writer options Horizon uses.
//!
//! Adapted from the `backends` helper of `crates/horizon-shaders/tests/real_packs.rs` in
//! horizon-rust/horizon (MIT), so results line up with Horizon's own test.

/// One backend: its name, and a closure writing the current module out through it.
type Writer<'a> = (&'static str, &'a dyn Fn() -> Result<(), String>);

/// One backend's complaint about one module.
pub struct Failure {
    pub module: String,
    pub backend: &'static str,
    pub message: String,
    /// A panic in the writer rather than a returned error.
    pub panicked: bool,
}

/// What came of writing a pack's modules out.
pub struct Report {
    pub modules: usize,
    pub failures: Vec<Failure>,
}

/// Writes every module of `post` through all four backends.
pub fn check(post: &horizon_shaders::Post) -> Report {
    // The stage programs live in their own fields; `programs` holds the post chain.
    let optional = [
        &post.terrain,
        &post.terrain_cutout,
        &post.water,
        &post.sky,
        &post.sky_textured,
        &post.entities,
        &post.block,
        &post.entities_translucent,
        &post.particles,
        &post.clouds,
        &post.weather,
        &post.hand,
        &post.shadow,
        &post.shadow_water,
        &post.shadow_entities,
        &post.shadow_block,
    ];
    let mut modules: Vec<(String, &naga::Module)> = Vec::new();
    for p in post
        .programs
        .iter()
        .chain(&post.shadow_comp)
        .chain(optional.into_iter().flatten())
    {
        if let Some(program) = &p.program {
            modules.push((format!("{} vertex", p.name), &program.vertex));
            modules.push((format!("{} fragment", p.name), &program.fragment));
        }
        for (name, c) in &p.compute {
            modules.push((name.clone(), &c.module));
        }
    }

    let mut failures = Vec::new();
    for (name, module) in &modules {
        let info = match naga::valid::Validator::new(
            naga::valid::ValidationFlags::all(),
            naga::valid::Capabilities::all(),
        )
        .validate(module)
        {
            Ok(info) => info,
            Err(e) => {
                // A translated module that does not validate is a translation bug, not a
                // backend one; record it and move on rather than killing the run.
                failures.push(Failure {
                    module: name.clone(),
                    backend: "validate",
                    message: e.to_string(),
                    panicked: false,
                });
                continue;
            }
        };
        let Some(entry) = module.entry_points.first() else {
            continue;
        };
        let stage = entry.stage;
        let point = entry.name.clone();

        let writers: [Writer<'_>; 4] = [
            ("spv", &|| {
                use naga::back::spv;
                let options = spv::Options {
                    lang_version: (1, 3),
                    flags: spv::WriterFlags::LABEL_VARYINGS | spv::WriterFlags::FORCE_POINT_SIZE,
                    bounds_check_policies: naga::proc::BoundsCheckPolicies {
                        index: naga::proc::BoundsCheckPolicy::Restrict,
                        buffer: naga::proc::BoundsCheckPolicy::Restrict,
                        image_load: naga::proc::BoundsCheckPolicy::Restrict,
                        binding_array: naga::proc::BoundsCheckPolicy::Unchecked,
                    },
                    force_loop_bounding: true,
                    ..Default::default()
                };
                let pipeline = spv::PipelineOptions {
                    shader_stage: stage,
                    entry_point: point.clone(),
                };
                spv::write_vec(module, &info, &options, Some(&pipeline))
                    .map(drop)
                    .map_err(|e| e.to_string())
            }),
            ("hlsl", &|| {
                use naga::back::hlsl;
                let options = hlsl::Options {
                    shader_model: hlsl::ShaderModel::V6_0,
                    fake_missing_bindings: true,
                    ..Default::default()
                };
                let pipeline = hlsl::PipelineOptions {
                    entry_point: Some((stage, point.clone())),
                };
                let mut out = String::new();
                hlsl::Writer::new(&mut out, &options, &pipeline)
                    .write(module, &info, None)
                    .map(drop)
                    .map_err(|e| e.to_string())
            }),
            ("glsl", &|| {
                use naga::back::glsl;
                let options = glsl::Options {
                    version: glsl::Version::Desktop(430),
                    ..Default::default()
                };
                let pipeline = glsl::PipelineOptions {
                    shader_stage: stage,
                    entry_point: point.clone(),
                    multiview: None,
                };
                let mut out = String::new();
                glsl::Writer::new(
                    &mut out,
                    module,
                    &info,
                    &options,
                    &pipeline,
                    naga::proc::BoundsCheckPolicies::default(),
                )
                .and_then(|mut w| w.write().map(drop))
                .map_err(|e| e.to_string())
            }),
            ("msl", &|| {
                use naga::back::msl;
                let options = msl::Options {
                    lang_version: (2, 4),
                    fake_missing_bindings: true,
                    ..Default::default()
                };
                msl::write_string(module, &info, &options, &msl::PipelineOptions::default())
                    .map(drop)
                    .map_err(|e| e.to_string())
            }),
        ];

        for (backend, write) in writers {
            // A writer may panic rather than return an error; that is still a pack that will
            // not run, so catch it and carry on to the next module.
            match std::panic::catch_unwind(std::panic::AssertUnwindSafe(write)) {
                Ok(Ok(())) => {}
                Ok(Err(message)) => failures.push(Failure {
                    module: name.clone(),
                    backend,
                    message,
                    panicked: false,
                }),
                Err(panic) => {
                    let message = panic
                        .downcast_ref::<String>()
                        .cloned()
                        .or_else(|| panic.downcast_ref::<&str>().map(|s| s.to_string()))
                        .unwrap_or_else(|| "(no message)".into());
                    failures.push(Failure {
                        module: name.clone(),
                        backend,
                        message,
                        panicked: true,
                    });
                }
            }
        }
    }
    Report {
        modules: modules.len(),
        failures,
    }
}
