// src/lexer/gpu.rs (imports)
use crate::lexer::tables::{INVALID_TOKEN, TokenKind, build_tables};
use crate::reflection::{
    EntryPointReflection, SlangReflection, parse_reflection_from_bytes,
    slang_category_and_type_to_wgpu,
};
use anyhow::{Result, anyhow};

use encase::{ShaderType, UniformBuffer};
use wgpu::util::DeviceExt;

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
        .expect("no adapter");

    //https://web3dsurvey.com/webgpu/limits/maxStorageBuffersPerShaderStage
    //         maxStorageBuffersPerShaderStage
    // 8 - 100%
    // 10 - 99.73%
    // 16 - 5.76%
    // 31 - 5.7%
    // 35 - 5.67%
    // 44 - 5.67%
    // 64 - 4.98%
    let mut limits = wgpu::Limits::defaults();
    limits.max_storage_buffers_per_shader_stage = 10;

    let (device, queue) = adapter
        .request_device(&wgpu::DeviceDescriptor {
            label: Some("Lanius Lexer Device"),
            required_features: wgpu::Features::empty(),
            required_limits: limits,
            memory_hints: wgpu::MemoryHints::default(),
            trace: wgpu::Trace::default(),
        })
        .await?;

    // Host-side tables (once per grammar)
    let tbl = build_tables();

    // Input bytes as u32
    let bytes_u32: Vec<u32> = input.bytes().map(|b| b as u32).collect();
    let n = bytes_u32.len() as u32;

    // --- Buffers we will bind (by name) ---
    let make_ro = |label: &str, bytes: &[u8]| {
        device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some(label),
            contents: bytes,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        })
    };
    let make_rw = |label: &str, size: usize| {
        device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: size as u64,
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_DST
                | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        })
    };

    let in_bytes = make_ro("in_bytes", bytemuck::cast_slice(&bytes_u32));
    let char_to_func = make_ro("char_to_func", bytemuck::cast_slice(&tbl.char_to_func));
    let merge = make_ro("merge", bytemuck::cast_slice(&tbl.merge));
    let emit_on_start = make_ro("emit_on_start", bytemuck::cast_slice(&tbl.emit_on_start));
    let token_of = make_ro("token_of", bytemuck::cast_slice(&tbl.token_of));

    let f_ping = make_rw("f_ping", (n as usize) * 4);
    let f_pong = make_rw("f_pong", (n as usize) * 4);
    let f_final = make_rw("f_final", (n as usize) * 4);
    let end_flags = make_rw("end_flags", (n as usize) * 4);
    let tok_types = make_rw("tok_types", (n as usize) * 4);

    // Uniforms via encase (no manual padding)
    let mut ub = UniformBuffer::new(Vec::new());
    ub.write(&LexParams {
        n,
        m: tbl.m,
        identity_id: tbl.identity,
    })?;
    let params_buf = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("LexParams"),
        contents: ub.as_ref(),
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
    });

    let mut scan_ub_init = UniformBuffer::new(Vec::new());
    scan_ub_init.write(&ScanParams {
        stride: 1,
        use_ping_as_src: 1,
    })?;
    let scan_params_buf = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some("ScanParams"),
        contents: scan_ub_init.as_ref(),
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
    });

    // --- Load SPIR-V & reflection JSON for lexer ---
    let spirv_bytes: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/shaders/lexer.spv"));
    let refl_bytes: &[u8] = include_bytes!(concat!(env!("OUT_DIR"), "/shaders/lexer.reflect.json"));

    let module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some("lexer.slang -> SPIR-V"),
        source: wgpu::util::make_spirv(spirv_bytes),
    });

    let reflection: SlangReflection =
        parse_reflection_from_bytes(refl_bytes).map_err(|e| anyhow!(e))?;

    // Build layouts and bind groups from reflection (grouped by space)
    let (bind_group_layouts, bind_groups) =
        build_reflected_bindings(&device, &reflection, |name| match name {
            // uniforms
            "gParams" => Some(wgpu::BindingResource::Buffer(
                params_buf.as_entire_buffer_binding(),
            )),
            "gScan" => Some(wgpu::BindingResource::Buffer(
                scan_params_buf.as_entire_buffer_binding(),
            )),
            // read-only storage
            "in_bytes" => Some(in_bytes.as_entire_binding()),
            "char_to_func" => Some(char_to_func.as_entire_binding()),
            "merge_table" => Some(merge.as_entire_binding()),
            "emit_on_start" => Some(emit_on_start.as_entire_binding()),
            "token_of" => Some(token_of.as_entire_binding()),
            // read-write storage
            "f_ping" => Some(f_ping.as_entire_binding()),
            "f_pong" => Some(f_pong.as_entire_binding()),
            "f_final" => Some(f_final.as_entire_binding()),
            "end_flags" => Some(end_flags.as_entire_binding()),
            "tok_types" => Some(tok_types.as_entire_binding()),
            // Unknown parameter name -> None, we’ll just skip it (there aren’t any for this shader)
            _ => None,
        })?;

    // Pipeline layout uses groups in ascending space order
    let pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some("lexer-pl"),
        bind_group_layouts: &bind_group_layouts.iter().collect::<Vec<_>>(),
        push_constant_ranges: &[],
    });

    // Pipelines
    let p_map = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("map_chars"),
        layout: Some(&pl),
        module: &module,
        entry_point: Some("map_chars"),
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache: None,
    });
    let p_scan = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("scan_step"),
        layout: Some(&pl),
        module: &module,
        entry_point: Some("scan_step"),
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache: None,
    });
    let p_final = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some("finalize_and_post"),
        layout: Some(&pl),
        module: &module,
        entry_point: Some("finalize_and_post"),
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache: None,
    });

    // Dispatch
    let groups = n.div_ceil(128);
    let mut enc = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("lex-enc"),
    });

    // Pass 1: map
    {
        let mut pass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("map"),
            ..Default::default()
        });
        pass.set_pipeline(&p_map);
        for (i, bg) in bind_groups.iter().enumerate() {
            pass.set_bind_group(i as u32, bg, &[]);
        }
        pass.dispatch_workgroups(groups, 1, 1);
    }

    // Pass 2: inclusive scan with doubling stride (ping↔pong)
    let mut use_ping_as_src = true;
    let mut stride = 1u32;
    while stride < n {
        let mut scan_ub = UniformBuffer::new(Vec::new());
        scan_ub.write(&ScanParams {
            stride,
            use_ping_as_src: if use_ping_as_src { 1 } else { 0 },
        })?;
        queue.write_buffer(&scan_params_buf, 0, scan_ub.as_ref());

        let mut pass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("scan"),
            ..Default::default()
        });
        pass.set_pipeline(&p_scan);
        for (i, bg) in bind_groups.iter().enumerate() {
            pass.set_bind_group(i as u32, bg, &[]);
        }
        pass.dispatch_workgroups(groups, 1, 1);

        use_ping_as_src = !use_ping_as_src;
        stride <<= 1;
    }

    // Copy the “winning” buffer into f_final
    if use_ping_as_src {
        enc.copy_buffer_to_buffer(&f_pong, 0, &f_final, 0, (n as u64) * 4);
    } else {
        enc.copy_buffer_to_buffer(&f_ping, 0, &f_final, 0, (n as u64) * 4);
    }

    // Pass 3: finalize
    {
        let mut pass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("final"),
            ..Default::default()
        });
        pass.set_pipeline(&p_final);
        for (i, bg) in bind_groups.iter().enumerate() {
            pass.set_bind_group(i as u32, bg, &[]);
        }
        pass.dispatch_workgroups(groups, 1, 1);
    }

    // Read back boundaries/types
    let rb_ends = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb_ends"),
        size: (n as u64) * 4,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let rb_types = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb_types"),
        size: (n as u64) * 4,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    enc.copy_buffer_to_buffer(&end_flags, 0, &rb_ends, 0, (n as u64) * 4);
    enc.copy_buffer_to_buffer(&tok_types, 0, &rb_types, 0, (n as u64) * 4);
    queue.submit([enc.finish()]);

    {
        let s1 = rb_ends.slice(..);
        s1.map_async(wgpu::MapMode::Read, |_| {});
        let s2 = rb_types.slice(..);
        s2.map_async(wgpu::MapMode::Read, |_| {});
        let _ = device.poll(wgpu::PollType::Wait);
    }
    let ends_vec: Vec<u32> =
        bytemuck::cast_slice::<u8, u32>(&rb_ends.slice(..).get_mapped_range()).to_vec();
    let types_vec: Vec<u32> =
        bytemuck::cast_slice::<u8, u32>(&rb_types.slice(..).get_mapped_range()).to_vec();

    // CPU compaction for MVP
    let mut tokens = Vec::new();
    let mut start_idx = 0usize;
    for i in 0..(n as usize) {
        if ends_vec[i] != 0 {
            let kind_u = types_vec[i];
            if kind_u != INVALID_TOKEN {
                let len = i + 1 - start_idx;
                let kind = unsafe { std::mem::transmute::<u32, TokenKind>(kind_u) };
                tokens.push(Token {
                    kind,
                    start: start_idx,
                    len,
                });
            }
            start_idx = i + 1;
        }
    }
    Ok(tokens)
}
// src/lexer/gpu.rs  (keep the same imports above)

/// Build bind group layouts and bind groups from Slang reflection.
/// The resource_resolver maps parameter names -> BindingResource (buffer views).
fn build_reflected_bindings<'a>(
    device: &wgpu::Device,
    reflection: &SlangReflection,
    mut resource_resolver: impl FnMut(&str) -> Option<wgpu::BindingResource<'a>>,
) -> anyhow::Result<(Vec<wgpu::BindGroupLayout>, Vec<wgpu::BindGroup>)> {
    // Pick any compute EP (they all use the same parameter set in this project)
    let ep: &EntryPointReflection = reflection
        .entry_points
        .iter()
        .find(|e| e.stage.as_deref() == Some("compute"))
        .ok_or_else(|| anyhow!("no compute entry point found in reflection"))?;

    // -----------------------------
    // Path A: old schema (has layout)
    // -----------------------------
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
                    return Err(anyhow!(
                        "no resource found for shader param '{}'",
                        param.name
                    ));
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
            let mut bgl_entries = Vec::new();
            let mut bg_entries = Vec::new();
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

    // -----------------------------
    // Path B: flat schema (your JSON)
    // Build a single bind group (space 0) from top-level `parameters`.
    // -----------------------------
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
            return Err(anyhow!(
                "no resource found for shader param '{}'",
                param.name
            ));
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
