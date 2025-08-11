// src/lexer/gpu/mod.rs
use crate::lexer::tables::{TokenKind, build_tables_for_bytes};
use crate::reflection::{
    EntryPointReflection, ParameterReflection, SlangReflection, parse_reflection_from_bytes,
    slang_category_and_type_to_wgpu,
};
use anyhow::{Result, anyhow};
use bytemuck::{Pod, Zeroable};
use encase::{ShaderType, UniformBuffer};
use wgpu::util::DeviceExt;

mod buffers;
use buffers::GpuBuffers;

#[derive(Debug, Clone)]
pub struct Token {
    pub kind: TokenKind,
    pub start: usize,
    pub len: usize,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct LexParams {
    n: u32,
    m: u32,
    identity_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct ScanParams {
    stride: u32,
    use_ping_as_src: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct GpuToken {
    kind: u32,
    start: u32,
    len: u32,
}

pub async fn lex_on_gpu(input: &str) -> Result<Vec<Token>> {
    // --- WGPU bootstrap ---
    let instance = wgpu::Instance::default();
    let adapter = instance
        .request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: None,
            force_fallback_adapter: false,
        })
        .await
        .or_else(|_| Err(anyhow!("no adapter")))?;

    let mut limits = wgpu::Limits::defaults();
    // note: do not delete these comments
    // https://web3dsurvey.com/webgpu/limits/maxStorageBuffersPerShaderStage
    // 10 is a comfortable amount to support across all platforms.
    // 16 is only supported at 8% on windows.
    // If we need more, we will need to switch some buffers to byte address and figure out how to share space.
    limits.max_storage_buffers_per_shader_stage = 10;
    // https://web3dsurvey.com/webgpu/limits/maxStorageBufferBindingSize
    // 2147483644 is supported at 91.95% on Windows.
    // On mac it's supported 96.34%.
    // On linux it's much lower at 21.27% (maybe mixing up desktop and mobile Linux? doesn't include android or chromium OS though)
    limits.max_storage_buffer_binding_size = 2147483644;
    // https://web3dsurvey.com/webgpu/limits/maxBufferSize
    // 2147483644 or 2147483647 is supported at 90%+ everywhere except Android, iOS, and Linux.
    // We will pick the same number as the max storage buffer binding size.w
    limits.max_buffer_size = 2147483644;
    let (device, queue) = adapter
        .request_device(&wgpu::DeviceDescriptor {
            label: Some("Lanius Lexer Device"),
            required_features: wgpu::Features::empty(),
            required_limits: limits,
            memory_hints: wgpu::MemoryHints::default(),
            trace: wgpu::Trace::default(),
        })
        .await?;

    #[cfg(has_prebuilt_tables)]
    const LEX_TBL_EXT: &str = env!("LEXER_TABLES_EXT");

    #[cfg(has_prebuilt_tables)]
    let prebuilt_bytes: Option<&[u8]> = Some(include_bytes!(concat!(
        env!("OUT_DIR"),
        "/lexer_tables",
        env!("LEXER_TABLES_EXT")
    )));
    #[cfg(not(has_prebuilt_tables))]
    let prebuilt_bytes: Option<&[u8]> = None;

    let tbl = if let Some(bytes) = prebuilt_bytes {
        let res = if LEX_TBL_EXT == ".bin" {
            crate::lexer::tables::load_tables_bin_bytes(bytes)
        } else {
            crate::lexer::tables::load_tables_json_bytes(bytes)
        };
        res.expect("Failed to load embedded lexer tables")
    } else {
        let t = build_tables_for_bytes(input.as_bytes());
        if std::env::var("LANIUS_DUMP_TABLES").ok().as_deref() == Some("1") {
            let _ = std::fs::create_dir_all("tables");
            let bin = std::path::Path::new("tables/lexer_tables.bin");
            if let Err(e) = crate::lexer::tables::save_tables_bin(bin, &t) {
                eprintln!("warning: failed to write {}: {e}", bin.display());
            } else {
                eprintln!("wrote {}", bin.display());
            }
        }
        t
    };

    // Input bytes as u32
    let bytes_u32: Vec<u32> = input.bytes().map(|b| b as u32).collect();
    let n = bytes_u32.len() as u32;
    let groups = n.div_ceil(128);

    // --- Buffers ---
    let (bufs, params_buf) = GpuBuffers::new(&device, &tbl, &bytes_u32);

    // --- Shader modules ---
    let mod_map = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("lex_map"),
        source: wgpu::util::make_spirv(include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/lex_map.spv"
        ))),
    });
    let mod_scan_merge = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("lex_scan_merge"),
        source: wgpu::util::make_spirv(include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/lex_scan_merge.spv"
        ))),
    });
    let mod_finalize = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("lex_finalize"),
        source: wgpu::util::make_spirv(include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/lex_finalize.spv"
        ))),
    });
    let mod_scan_sum = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("lex_scan_sum"),
        source: wgpu::util::make_spirv(include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/lex_scan_sum.spv"
        ))),
    });
    let mod_scatter = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("lex_scatter"),
        source: wgpu::util::make_spirv(include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/lex_scatter.spv"
        ))),
    });
    let mod_build = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("lex_build_tokens"),
        source: wgpu::util::make_spirv(include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/lex_build_tokens.spv"
        ))),
    });

    // --- Reflection (per shader) ---
    let refl_map: SlangReflection = parse_reflection_from_bytes(include_bytes!(concat!(
        env!("OUT_DIR"),
        "/shaders/lex_map.reflect.json"
    )))
    .map_err(|e| anyhow!(e))?;
    let refl_scan_merge: SlangReflection = parse_reflection_from_bytes(include_bytes!(concat!(
        env!("OUT_DIR"),
        "/shaders/lex_scan_merge.reflect.json"
    )))
    .map_err(|e| anyhow!(e))?;
    let refl_finalize: SlangReflection = parse_reflection_from_bytes(include_bytes!(concat!(
        env!("OUT_DIR"),
        "/shaders/lex_finalize.reflect.json"
    )))
    .map_err(|e| anyhow!(e))?;
    let refl_scan_sum: SlangReflection = parse_reflection_from_bytes(include_bytes!(concat!(
        env!("OUT_DIR"),
        "/shaders/lex_scan_sum.reflect.json"
    )))
    .map_err(|e| anyhow!(e))?;
    let refl_scatter: SlangReflection = parse_reflection_from_bytes(include_bytes!(concat!(
        env!("OUT_DIR"),
        "/shaders/lex_scatter.reflect.json"
    )))
    .map_err(|e| anyhow!(e))?;
    let refl_build: SlangReflection = parse_reflection_from_bytes(include_bytes!(concat!(
        env!("OUT_DIR"),
        "/shaders/lex_build_tokens.reflect.json"
    )))
    .map_err(|e| anyhow!(e))?;

    // --- Pipeline layouts (build just the BGLs; no resources needed here) ---
    let bgls_map = build_bgls_only(&device, &refl_map)?;
    let bgls_map_refs: Vec<&wgpu::BindGroupLayout> = bgls_map.iter().collect();
    let pl_map = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("pl_map"),
        bind_group_layouts: &bgls_map_refs,
        push_constant_ranges: &[],
    });

    let bgls_scan_merge = build_bgls_only(&device, &refl_scan_merge)?;
    let bgls_scan_merge_refs: Vec<&wgpu::BindGroupLayout> = bgls_scan_merge.iter().collect();
    let pl_scan_merge = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("pl_scan_merge"),
        bind_group_layouts: &bgls_scan_merge_refs,
        push_constant_ranges: &[],
    });

    let bgls_finalize = build_bgls_only(&device, &refl_finalize)?;
    let bgls_finalize_refs: Vec<&wgpu::BindGroupLayout> = bgls_finalize.iter().collect();
    let pl_finalize = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("pl_finalize"),
        bind_group_layouts: &bgls_finalize_refs,
        push_constant_ranges: &[],
    });

    let bgls_scan_sum = build_bgls_only(&device, &refl_scan_sum)?;
    let bgls_scan_sum_refs: Vec<&wgpu::BindGroupLayout> = bgls_scan_sum.iter().collect();
    let pl_scan_sum = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("pl_scan_sum"),
        bind_group_layouts: &bgls_scan_sum_refs,
        push_constant_ranges: &[],
    });

    let bgls_scatter = build_bgls_only(&device, &refl_scatter)?;
    let bgls_scatter_refs: Vec<&wgpu::BindGroupLayout> = bgls_scatter.iter().collect();
    let pl_scatter = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("pl_scatter"),
        bind_group_layouts: &bgls_scatter_refs,
        push_constant_ranges: &[],
    });

    let bgls_build = build_bgls_only(&device, &refl_build)?;
    let bgls_build_refs: Vec<&wgpu::BindGroupLayout> = bgls_build.iter().collect();
    let pl_build = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("pl_build"),
        bind_group_layouts: &bgls_build_refs,
        push_constant_ranges: &[],
    });

    // --- Pipelines ---
    let p_map = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("map_chars"),
        layout: Some(&pl_map),
        module: &mod_map,
        entry_point: Some("map_chars"),
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache: None,
    });
    let p_scan_merge = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("scan_step"),
        layout: Some(&pl_scan_merge),
        module: &mod_scan_merge,
        entry_point: Some("scan_step"),
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache: None,
    });
    let p_finalize = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("finalize_and_post"),
        layout: Some(&pl_finalize),
        module: &mod_finalize,
        entry_point: Some("finalize_and_post"),
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache: None,
    });
    let p_scan_sum = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("scan_sum_step"),
        layout: Some(&pl_scan_sum),
        module: &mod_scan_sum,
        entry_point: Some("scan_sum_step"),
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache: None,
    });
    let p_scatter = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("scatter_compact"),
        layout: Some(&pl_scatter),
        module: &mod_scatter,
        entry_point: Some("scatter_compact"),
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache: None,
    });
    let p_build = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("build_tokens"),
        layout: Some(&pl_build),
        module: &mod_build,
        entry_point: Some("build_tokens"),
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache: None,
    });

    // --- Bind groups (map/finalize/scatter/build: single groups) ---
    let (_bgls_map_unused, bgs_map) =
        build_reflected_bindings(&device, &refl_map, |name| bufs.resolve(name, &params_buf))?;
    let (_bgls_finalize_unused, bgs_finalize) =
        build_reflected_bindings(&device, &refl_finalize, |name| {
            bufs.resolve(name, &params_buf)
        })?;
    let (_bgls_scatter_unused, bgs_scatter) =
        build_reflected_bindings(&device, &refl_scatter, |name| {
            bufs.resolve(name, &params_buf)
        })?;
    let (_bgls_build_unused, bgs_build) =
        build_reflected_bindings(&device, &refl_build, |name| bufs.resolve(name, &params_buf))?;

    // --- Scan rounds (merge + sum): per-round bind groups with varying gScan ---
    let rounds = {
        let mut r = 0u32;
        let mut s = 1u32;
        while s < n {
            r += 1;
            s <<= 1;
        }
        r
    };
    let (scan_round_bgs_merge, last_write_pong_merge) =
        build_scan_round_bgs(&device, &refl_scan_merge, &bufs, &params_buf, rounds)?;
    let (scan_round_bgs_sum, last_write_pong_sum) =
        build_scan_round_bgs(&device, &refl_scan_sum, &bufs, &params_buf, rounds)?;

    // --- Encode ---
    let mut enc = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("lex-enc"),
    });

    // 1) map
    {
        let mut pass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("map"),
            ..Default::default()
        });
        pass.set_pipeline(&p_map);
        pass.set_bind_group(0, &bgs_map[0], &[]);
        pass.dispatch_workgroups(groups, 1, 1);
    }

    // 2) scan (merge)
    for r in 0..rounds as usize {
        let mut pass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("scan_merge"),
            ..Default::default()
        });
        pass.set_pipeline(&p_scan_merge);
        pass.set_bind_group(0, &scan_round_bgs_merge[r], &[]);
        pass.dispatch_workgroups(groups, 1, 1);
    }

    // Copy function-id scan result to f_final
    if last_write_pong_merge {
        enc.copy_buffer_to_buffer(&bufs.f_pong, 0, &bufs.f_final, 0, (n as u64) * 4);
    } else {
        enc.copy_buffer_to_buffer(&bufs.f_ping, 0, &bufs.f_final, 0, (n as u64) * 4);
    }

    // 3) finalize
    {
        let mut pass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("finalize"),
            ..Default::default()
        });
        pass.set_pipeline(&p_finalize);
        pass.set_bind_group(0, &bgs_finalize[0], &[]);
        pass.dispatch_workgroups(groups, 1, 1);
    }

    // 4) scan (sum)
    for r in 0..rounds as usize {
        let mut pass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("scan_sum"),
            ..Default::default()
        });
        pass.set_pipeline(&p_scan_sum);
        pass.set_bind_group(0, &scan_round_bgs_sum[r], &[]);
        pass.dispatch_workgroups(groups, 1, 1);
    }

    // Copy sum scan result to s_final
    if last_write_pong_sum {
        enc.copy_buffer_to_buffer(&bufs.s_pong, 0, &bufs.s_final, 0, (n as u64) * 4);
    } else {
        enc.copy_buffer_to_buffer(&bufs.s_ping, 0, &bufs.s_final, 0, (n as u64) * 4);
    }

    // 5) scatter
    {
        let mut pass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("scatter"),
            ..Default::default()
        });
        pass.set_pipeline(&p_scatter);
        pass.set_bind_group(0, &bgs_scatter[0], &[]);
        pass.dispatch_workgroups(groups, 1, 1);
    }

    // 6) build tokens
    {
        let mut pass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("build_tokens"),
            ..Default::default()
        });
        pass.set_pipeline(&p_build);
        pass.set_bind_group(0, &bgs_build[0], &[]);
        pass.dispatch_workgroups(groups, 1, 1);
    }

    // 7) read back count + tokens
    let rb_count = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb_count"),
        size: 4,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let rb_tokens = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb_tokens"),
        size: (n as u64) * (std::mem::size_of::<GpuToken>() as u64),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    enc.copy_buffer_to_buffer(&bufs.token_count, 0, &rb_count, 0, 4);
    enc.copy_buffer_to_buffer(
        &bufs.tokens_out,
        0,
        &rb_tokens,
        0,
        (n as u64) * (std::mem::size_of::<GpuToken>() as u64),
    );

    queue.submit(Some(enc.finish()));

    rb_count.slice(..).map_async(wgpu::MapMode::Read, |_| {});
    rb_tokens.slice(..).map_async(wgpu::MapMode::Read, |_| {});
    let _ = device.poll(wgpu::PollType::Wait);

    let token_count_u32 =
        bytemuck::cast_slice::<u8, u32>(&rb_count.slice(..).get_mapped_range())[0] as usize;
    let mapped_range = rb_tokens.slice(..).get_mapped_range();
    let toks_raw: &[GpuToken] = bytemuck::cast_slice(&mapped_range);

    let mut out = Vec::with_capacity(token_count_u32);
    for gt in &toks_raw[..token_count_u32.min(toks_raw.len())] {
        let kind = unsafe { std::mem::transmute::<u32, TokenKind>(gt.kind) };
        out.push(Token {
            kind,
            start: gt.start as usize,
            len: gt.len as usize,
        });
    }
    Ok(out)
}

// ---------- helpers ----------

fn build_bgls_only(
    device: &wgpu::Device,
    reflection: &SlangReflection,
) -> anyhow::Result<Vec<wgpu::BindGroupLayout>> {
    // Build just the BindGroupLayouts from reflection; do not require resources.
    let ep: &EntryPointReflection = reflection
        .entry_points
        .iter()
        .find(|e| e.stage.as_deref() == Some("compute"))
        .ok_or_else(|| anyhow!("no compute entry point found in reflection"))?;

    if let Some(layout) = ep.program_layout.as_ref() {
        let mut out = Vec::with_capacity(layout.parameters.len());
        for set in &layout.parameters {
            let entries: Vec<_> = set
                .parameters
                .iter()
                .filter_map(|p| {
                    let ty = slang_category_and_type_to_wgpu(p, &p.ty)?;
                    let idx = p.binding.index?;
                    Some(wgpu::BindGroupLayoutEntry {
                        binding: idx,
                        visibility: wgpu::ShaderStages::COMPUTE,
                        ty,
                        count: None,
                    })
                })
                .collect();
            out.push(
                device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                    label: Some("reflected-bgl"),
                    entries: &entries,
                }),
            );
        }
        return Ok(out);
    }

    // Flat reflection fallback.
    let entries: Vec<_> = reflection
        .parameters
        .iter()
        .filter_map(|p| {
            let ty = slang_category_and_type_to_wgpu(p, &p.ty)?;
            let idx = p.binding.index?;
            Some(wgpu::BindGroupLayoutEntry {
                binding: idx,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty,
                count: None,
            })
        })
        .collect();

    Ok(vec![device.create_bind_group_layout(
        &wgpu::BindGroupLayoutDescriptor {
            label: Some("reflected-bgl-flat"),
            entries: &entries,
        },
    )])
}

fn build_scan_round_bgs<'a>(
    device: &wgpu::Device,
    reflection: &SlangReflection,
    bufs: &'a GpuBuffers,
    params_buf: &'a wgpu::Buffer,
    rounds: u32,
) -> anyhow::Result<(Vec<wgpu::BindGroup>, bool)> {
    // Extract params for space 0
    let params_for_group: Vec<ParameterReflection> = if !reflection.parameters.is_empty() {
        reflection.parameters.clone()
    } else {
        let ep = reflection
            .entry_points
            .iter()
            .find(|e| e.stage.as_deref() == Some("compute"))
            .ok_or_else(|| anyhow!("no compute entry point found in reflection"))?;
        let sets = ep
            .program_layout
            .as_ref()
            .ok_or_else(|| anyhow!("no program_layout in reflection entry point"))?
            .parameters
            .clone();
        if sets.is_empty() {
            Vec::new()
        } else {
            sets[0].parameters.clone()
        }
    };

    let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("scan-bgl"),
        entries: &params_for_group
            .iter()
            .filter_map(|p| {
                let idx = p.binding.index?;
                let ty = slang_category_and_type_to_wgpu(p, &p.ty)?;
                Some(wgpu::BindGroupLayoutEntry {
                    binding: idx,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty,
                    count: None,
                })
            })
            .collect::<Vec<_>>(),
    });

    let mut r_bgs = Vec::with_capacity(rounds as usize);
    let mut last_write_pong = false;

    for r in 0..rounds {
        let stride = 1u32 << r;
        let use_ping_as_src = if r % 2 == 0 { 1u32 } else { 0u32 };

        let mut ub = UniformBuffer::new(Vec::new());
        ub.write(&ScanParams {
            stride,
            use_ping_as_src,
        })?;
        let ubuf = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some(&format!("ScanParams[stage][{r}]")),
            contents: ub.as_ref(),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        let mut entries: Vec<wgpu::BindGroupEntry> = Vec::new();
        for p in &params_for_group {
            if let Some(idx) = p.binding.index {
                let res = bufs.resolve_scan(&p.name, params_buf, &ubuf);
                if let Some(resource) = res {
                    entries.push(wgpu::BindGroupEntry {
                        binding: idx,
                        resource,
                    });
                }
            }
        }

        let bg_r = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some(&format!("scan-bg[{r}]")),
            layout: &bgl,
            entries: &entries,
        });
        r_bgs.push(bg_r);
        last_write_pong = (rounds % 2) == 1;
    }

    Ok((r_bgs, last_write_pong))
}

fn build_reflected_bindings<'a>(
    device: &wgpu::Device,
    reflection: &SlangReflection,
    mut resource_resolver: impl FnMut(&str) -> Option<wgpu::BindingResource<'a>>,
) -> anyhow::Result<(Vec<wgpu::BindGroupLayout>, Vec<wgpu::BindGroup>)> {
    let ep: &EntryPointReflection = reflection
        .entry_points
        .iter()
        .find(|e| e.stage.as_deref() == Some("compute"))
        .ok_or_else(|| anyhow!("no compute entry point found in reflection"))?;

    if let Some(layout) = ep.program_layout.as_ref() {
        use std::collections::BTreeMap;
        let mut per_space: BTreeMap<
            u32,
            Vec<Option<(wgpu::BindGroupLayoutEntry, wgpu::BindGroupEntry<'a>)>>,
        > = BTreeMap::new();

        for set in &layout.parameters {
            let space = set.space;
            for param in &set.parameters {
                let ty = &param.ty;
                let Some(binding_type) = slang_category_and_type_to_wgpu(param, ty) else {
                    continue;
                };
                let Some(index) = param.binding.index else {
                    continue;
                };

                let bgl_entry = wgpu::BindGroupLayoutEntry {
                    binding: index,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: binding_type,
                    count: None,
                };

                let Some(resource) = resource_resolver(&param.name) else {
                    return Err(anyhow!("no resource for '{}'", param.name));
                };

                let bg_entry = wgpu::BindGroupEntry {
                    binding: index,
                    resource,
                };
                let v = per_space.entry(space).or_default();
                if v.len() <= index as usize {
                    v.resize(index as usize + 1, None);
                }
                v[index as usize] = Some((bgl_entry, bg_entry));
            }
        }

        let mut bgls = Vec::new();
        let mut bgs = Vec::new();
        for (_space, slots) in per_space {
            let (mut bgl_entries, mut bg_entries) = (Vec::new(), Vec::new());
            for pair in slots.into_iter().flatten() {
                bgl_entries.push(pair.0);
                bg_entries.push(pair.1);
            }
            let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("reflected-bgl"),
                entries: &bgl_entries,
            });
            let bg = device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("reflected-bg"),
                layout: &bgl,
                entries: &bg_entries,
            });
            bgls.push(bgl);
            bgs.push(bg);
        }
        return Ok((bgls, bgs));
    }

    // Flat schema (rare in Slang)
    let mut by_index: std::collections::BTreeMap<
        u32,
        (wgpu::BindGroupLayoutEntry, wgpu::BindGroupEntry<'a>),
    > = std::collections::BTreeMap::new();

    for param in &reflection.parameters {
        let Some(index) = param.binding.index else {
            continue;
        };
        let Some(binding_type) = slang_category_and_type_to_wgpu(param, &param.ty) else {
            continue;
        };

        let bgl_entry = wgpu::BindGroupLayoutEntry {
            binding: index,
            visibility: wgpu::ShaderStages::COMPUTE,
            ty: binding_type,
            count: None,
        };

        let Some(resource) = resource_resolver(&param.name) else {
            return Err(anyhow!("no resource for '{}'", param.name));
        };

        by_index.insert(
            index,
            (
                bgl_entry,
                wgpu::BindGroupEntry {
                    binding: index,
                    resource,
                },
            ),
        );
    }

    let mut bgl_entries = Vec::with_capacity(by_index.len());
    let mut bg_entries = Vec::with_capacity(by_index.len());
    for (_idx, (bgl, bg)) in by_index.into_iter() {
        bgl_entries.push(bgl);
        bg_entries.push(bg);
    }

    let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("reflected-bgl-flat"),
        entries: &bgl_entries,
    });
    let bg = device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("reflected-bg-flat"),
        layout: &bgl,
        entries: &bg_entries,
    });
    Ok((vec![bgl], vec![bg]))
}
