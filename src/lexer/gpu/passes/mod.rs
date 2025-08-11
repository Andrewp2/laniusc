// src/lexer/gpu/passes/mod.rs
use anyhow::{Result, anyhow};
use encase::{ShaderType, UniformBuffer};
use wgpu::util::DeviceExt;

use crate::reflection::{
    EntryPointReflection, ParameterReflection, SlangReflection, parse_reflection_from_bytes,
    slang_category_and_type_to_wgpu,
};

/// Shared context available to pass constructors.
pub struct PassCtx<'a> {
    pub device: &'a wgpu::Device,
    pub bufs: &'a super::buffers::GpuBuffers,
    pub params_buf: &'a wgpu::Buffer,
}

/// A single-dispatch compute stage (one pipeline, a set of bind groups).
pub struct ComputeStage {
    pub pipeline: wgpu::ComputePipeline,
    pub bind_groups: Vec<wgpu::BindGroup>,
    pub thread_group_size: [u32; 3],
}

/// A multi-dispatch compute stage (same pipeline, one bind group per round).
pub struct MultiRoundStage {
    pub pipeline: wgpu::ComputePipeline,
    pub round_bind_groups: Vec<wgpu::BindGroup>,
    /// True if the final write after all rounds is in the "pong" buffer.
    pub last_write_pong: bool,
    pub thread_group_size: [u32; 3],
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct ScanParams {
    stride: u32,
    use_ping_as_src: u32,
}

// ----------------------------- helpers (reflection → BGL/BG) -----------------------------

fn bgls_from_reflection(
    device: &wgpu::Device,
    reflection: &SlangReflection,
) -> Result<Vec<wgpu::BindGroupLayout>> {
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

    // Flat schema (rare in Slang)
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

fn bind_groups_from_reflection<'a>(
    device: &wgpu::Device,
    reflection: &SlangReflection,
    mut resource_resolver: impl FnMut(&str) -> Option<wgpu::BindingResource<'a>>,
) -> Result<Vec<wgpu::BindGroup>> {
    let ep: &EntryPointReflection = reflection
        .entry_points
        .iter()
        .find(|e| e.stage.as_deref() == Some("compute"))
        .ok_or_else(|| anyhow!("no compute entry point found in reflection"))?;

    // Per-space layout (normal in Slang)
    if let Some(layout) = ep.program_layout.as_ref() {
        use std::collections::BTreeMap;
        let mut by_space: BTreeMap<
            u32,
            Vec<Option<(wgpu::BindGroupLayoutEntry, wgpu::BindGroupEntry<'a>)>>,
        > = BTreeMap::new();

        for set in &layout.parameters {
            let space = set.space;
            for p in &set.parameters {
                let Some(binding_type) = slang_category_and_type_to_wgpu(p, &p.ty) else {
                    continue;
                };
                let Some(index) = p.binding.index else {
                    continue;
                };

                let bgl_entry = wgpu::BindGroupLayoutEntry {
                    binding: index,
                    visibility: wgpu::ShaderStages::COMPUTE,
                    ty: binding_type,
                    count: None,
                };

                let Some(resource) = resource_resolver(&p.name) else {
                    return Err(anyhow!("no resource for '{}'", p.name));
                };

                let bg_entry = wgpu::BindGroupEntry {
                    binding: index,
                    resource,
                };
                let slot_vec = by_space.entry(space).or_default();
                if slot_vec.len() <= index as usize {
                    slot_vec.resize(index as usize + 1, None);
                }
                slot_vec[index as usize] = Some((bgl_entry, bg_entry));
            }
        }

        let mut out = Vec::new();
        for (_space, slots) in by_space {
            let mut bgl_entries = Vec::<wgpu::BindGroupLayoutEntry>::new();
            let mut bg_entries = Vec::<wgpu::BindGroupEntry>::new();
            for pair in slots.into_iter().flatten() {
                bgl_entries.push(pair.0);
                bg_entries.push(pair.1);
            }
            let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                label: Some("reflected-bgl"),
                entries: &bgl_entries,
            });
            out.push(device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: Some("reflected-bg"),
                layout: &bgl,
                entries: &bg_entries,
            }));
        }
        return Ok(out);
    }

    // Flat schema fallback
    use std::collections::BTreeMap;
    let mut map: BTreeMap<u32, (wgpu::BindGroupLayoutEntry, wgpu::BindGroupEntry<'a>)> =
        BTreeMap::new();
    for p in &reflection.parameters {
        let Some(index) = p.binding.index else {
            continue;
        };
        let Some(binding_type) = slang_category_and_type_to_wgpu(p, &p.ty) else {
            continue;
        };

        let bgl_entry = wgpu::BindGroupLayoutEntry {
            binding: index,
            visibility: wgpu::ShaderStages::COMPUTE,
            ty: binding_type,
            count: None,
        };
        let Some(resource) = resource_resolver(&p.name) else {
            return Err(anyhow!("no resource for '{}'", p.name));
        };
        map.insert(
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

    let mut bgl_entries = Vec::new();
    let mut bg_entries = Vec::new();
    for (_i, (bgl, bg)) in map.into_iter() {
        bgl_entries.push(bgl);
        bg_entries.push(bg);
    }
    let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: Some("reflected-bgl-flat"),
        entries: &bgl_entries,
    });
    Ok(vec![device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("reflected-bg-flat"),
        layout: &bgl,
        entries: &bg_entries,
    })])
}

fn pipeline_from_spirv_and_bgls(
    device: &wgpu::Device,
    label: &str,
    entry: &str,
    spirv: &'static [u8],
    bgls: &[wgpu::BindGroupLayout],
) -> wgpu::ComputePipeline {
    let module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some(label),
        source: wgpu::util::make_spirv(spirv),
    });
    let pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some(&format!("pl_{label}")),
        bind_group_layouts: &bgls.iter().collect::<Vec<_>>(),
        push_constant_ranges: &[],
    });
    device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some(label),
        layout: Some(&pl),
        module: &module,
        entry_point: Some(entry),
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache: None,
    })
}

// ----------------------------- simple single-dispatch stages -----------------------------

fn make_simple_stage<'a>(
    label: &str,
    entry: &str,
    spirv: &'static [u8],
    reflection_json: &'static [u8],
    ctx: &PassCtx<'a>,
    mut resolver: impl FnMut(&str) -> Option<wgpu::BindingResource<'a>>,
) -> Result<ComputeStage> {
    let reflection: SlangReflection =
        parse_reflection_from_bytes(reflection_json).map_err(anyhow::Error::msg)?;
    let bgls = bgls_from_reflection(ctx.device, &reflection)?;
    let pipeline = pipeline_from_spirv_and_bgls(ctx.device, label, entry, spirv, &bgls);
    let bgs = bind_groups_from_reflection(ctx.device, &reflection, resolver)?;
    let tgs = crate::reflection::get_thread_group_size(&reflection).unwrap_or([1, 1, 1]);
    Ok(ComputeStage {
        pipeline,
        bind_groups: bgs,
        thread_group_size: tgs,
    })
}

pub fn make_map_stage<'a>(ctx: &PassCtx<'a>) -> Result<ComputeStage> {
    make_simple_stage(
        "map_chars",
        "map_chars",
        include_bytes!(concat!(env!("OUT_DIR"), "/shaders/lex_map.spv")),
        include_bytes!(concat!(env!("OUT_DIR"), "/shaders/lex_map.reflect.json")),
        ctx,
        |name| ctx.bufs.resolve(name, ctx.params_buf),
    )
}

pub fn make_block_scan_stage<'a>(ctx: &PassCtx<'a>) -> Result<ComputeStage> {
    make_simple_stage(
        "block_scan",
        "block_scan",
        include_bytes!(concat!(env!("OUT_DIR"), "/shaders/lex_block_scan.spv")),
        include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/lex_block_scan.reflect.json"
        )),
        ctx,
        |name| ctx.bufs.resolve(name, ctx.params_buf),
    )
}

pub fn make_fixup_stage<'a>(ctx: &PassCtx<'a>) -> Result<ComputeStage> {
    make_simple_stage(
        "fixup_prefix",
        "fixup_prefix",
        include_bytes!(concat!(env!("OUT_DIR"), "/shaders/lex_fixup.spv")),
        include_bytes!(concat!(env!("OUT_DIR"), "/shaders/lex_fixup.reflect.json")),
        ctx,
        |name| ctx.bufs.resolve(name, ctx.params_buf),
    )
}

pub fn make_finalize_stage<'a>(ctx: &PassCtx<'a>) -> Result<ComputeStage> {
    make_simple_stage(
        "finalize_and_post",
        "finalize_and_post",
        include_bytes!(concat!(env!("OUT_DIR"), "/shaders/lex_finalize.spv")),
        include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/lex_finalize.reflect.json"
        )),
        ctx,
        |name| ctx.bufs.resolve(name, ctx.params_buf),
    )
}

pub fn make_scatter_stage<'a>(ctx: &PassCtx<'a>) -> Result<ComputeStage> {
    make_simple_stage(
        "scatter_compact",
        "scatter_compact",
        include_bytes!(concat!(env!("OUT_DIR"), "/shaders/lex_scatter.spv")),
        include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/lex_scatter.reflect.json"
        )),
        ctx,
        |name| ctx.bufs.resolve(name, ctx.params_buf),
    )
}

pub fn make_build_tokens_stage<'a>(ctx: &PassCtx<'a>) -> Result<ComputeStage> {
    make_simple_stage(
        "build_tokens",
        "build_tokens",
        include_bytes!(concat!(env!("OUT_DIR"), "/shaders/lex_build_tokens.spv")),
        include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/lex_build_tokens.reflect.json"
        )),
        ctx,
        |name| ctx.bufs.resolve(name, ctx.params_buf),
    )
}

// ----------------------------- multi-dispatch scan stages -----------------------------
fn make_scan_stage<'a>(
    label: &str,
    entry: &str,
    spirv: &'static [u8],
    reflection_json: &'static [u8],
    ctx: &PassCtx<'a>,
    rounds: u32,
) -> Result<MultiRoundStage> {
    let reflection: SlangReflection =
        parse_reflection_from_bytes(reflection_json).map_err(anyhow::Error::msg)?;

    let bgls = bgls_from_reflection(ctx.device, &reflection)?;
    let pipeline = pipeline_from_spirv_and_bgls(ctx.device, label, entry, spirv, &bgls);

    // parameters for the (single) space used by scan stages
    let params_for_group: Vec<ParameterReflection> = if !reflection.parameters.is_empty() {
        reflection.parameters.clone()
    } else {
        let ep = reflection
            .entry_points
            .iter()
            .find(|e| e.stage.as_deref() == Some("compute"))
            .ok_or_else(|| anyhow!("no compute EP"))?;
        ep.program_layout
            .as_ref()
            .ok_or_else(|| anyhow!("no program_layout in reflection EP"))?
            .parameters
            .get(0)
            .map(|set| set.parameters.clone())
            .unwrap_or_default()
    };

    let bgl = ctx
        .device
        .create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
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

    let mut round_bind_groups = Vec::with_capacity(rounds as usize);
    let mut last_write_pong = false;

    for r in 0..rounds {
        let stride = 1u32 << r;
        let use_ping_as_src = if r % 2 == 0 { 1 } else { 0 };

        let mut ub = UniformBuffer::new(Vec::new());
        ub.write(&ScanParams {
            stride,
            use_ping_as_src,
        })?;
        let scan_params_buf = ctx
            .device
            .create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some(&format!("ScanParams[{label}][{r}]")),
                contents: ub.as_ref(),
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            });

        let mut entries: Vec<wgpu::BindGroupEntry> = Vec::new();
        for p in &params_for_group {
            if let Some(idx) = p.binding.index {
                let res = ctx
                    .bufs
                    .resolve_scan(&p.name, ctx.params_buf, &scan_params_buf)
                    .or_else(|| ctx.bufs.resolve(&p.name, ctx.params_buf)); // fallback
                if let Some(resource) = res {
                    entries.push(wgpu::BindGroupEntry {
                        binding: idx,
                        resource,
                    });
                }
            }
        }

        round_bind_groups.push(ctx.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some(&format!("scan-bg[{label}][{r}]")),
            layout: &bgl,
            entries: &entries,
        }));
        last_write_pong = (rounds % 2) == 1;
    }

    let tgs = crate::reflection::get_thread_group_size(&reflection).unwrap_or([1, 1, 1]);
    Ok(MultiRoundStage {
        pipeline,
        round_bind_groups,
        last_write_pong,
        thread_group_size: tgs,
    })
}

pub fn make_scan_blocks_stage<'a>(ctx: &PassCtx<'a>, rounds: u32) -> Result<MultiRoundStage> {
    make_scan_stage(
        "scan_blocks_step",
        "scan_blocks_step",
        include_bytes!(concat!(env!("OUT_DIR"), "/shaders/lex_scan_blocks.spv")),
        include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/lex_scan_blocks.reflect.json"
        )),
        ctx,
        rounds,
    )
}

pub fn make_scan_sum_stage<'a>(ctx: &PassCtx<'a>, rounds: u32) -> Result<MultiRoundStage> {
    make_scan_stage(
        "scan_sum_step",
        "scan_sum_step",
        include_bytes!(concat!(env!("OUT_DIR"), "/shaders/lex_scan_sum.spv")),
        include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/lex_scan_sum.reflect.json"
        )),
        ctx,
        rounds,
    )
}

// ----------------------------- tiny dispatch helpers -----------------------------

pub fn encode_simple(
    enc: &mut wgpu::CommandEncoder,
    label: &str,
    stage: &ComputeStage,
    groups: (u32, u32, u32),
) {
    let mut pass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        ..Default::default()
    });
    pass.set_pipeline(&stage.pipeline);
    for (i, bg) in stage.bind_groups.iter().enumerate() {
        pass.set_bind_group(i as u32, bg, &[]);
    }
    pass.dispatch_workgroups(groups.0, groups.1, groups.2);
}

pub fn encode_rounds(
    enc: &mut wgpu::CommandEncoder,
    label: &str,
    stage: &MultiRoundStage,
    groups: (u32, u32, u32),
) {
    for (r, bg) in stage.round_bind_groups.iter().enumerate() {
        let mut pass = enc.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(&format!("{label}[round {r}]")),
            ..Default::default()
        });
        pass.set_pipeline(&stage.pipeline);
        pass.set_bind_group(0, bg, &[]);
        pass.dispatch_workgroups(groups.0, groups.1, groups.2);
    }
}
