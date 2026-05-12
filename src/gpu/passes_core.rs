use std::{collections::HashMap, env, sync::Arc};

use anyhow::{Result, anyhow};
use log::{info, warn};
use wgpu;

use crate::reflection::{
    EntryPointReflection,
    ParameterReflection,
    SlangReflection,
    get_thread_group_size,
    parse_reflection_from_bytes,
    slang_category_and_type_to_wgpu,
};

pub fn validation_scopes_enabled() -> bool {
    crate::gpu::env::env_bool_truthy("LANIUS_VALIDATION_SCOPES", false)
}

pub struct PassData {
    pub pipeline: Arc<wgpu::ComputePipeline>,
    pub bind_group_layouts: Vec<Arc<wgpu::BindGroupLayout>>,
    pub shader_id: String,
    pub thread_group_size: [u32; 3],
    pub reflection: Arc<SlangReflection>,
}

#[derive(Copy, Clone, Debug)]
pub enum DispatchDim {
    D1,
    D2,
}

#[derive(Copy, Clone, Debug)]
pub enum InputElements {
    Elements1D(u32),
    Elements2D(u32, u32),
}

pub fn bgls_from_reflection(
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

pub fn pipeline_from_spirv_and_bgls(
    device: &wgpu::Device,
    label: &str,
    entry: &str,
    spirv: &'static [u8],
    bgls: &[&wgpu::BindGroupLayout],
) -> wgpu::ComputePipeline {
    trace_pipeline(label, "shader_module.start");
    let module = if label == "codegen_wasm_body"
        || label == "codegen_wasm_functions"
        || label == "codegen_x86_elf"
    {
        device.create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some(label),
            source: wgpu::util::make_spirv(spirv),
        })
    } else {
        // SAFETY: YOLO
        unsafe {
            device.create_shader_module_passthrough(wgpu::ShaderModuleDescriptorPassthrough::SpirV(
                wgpu::ShaderModuleDescriptorSpirV {
                    label: Some(label),
                    source: wgpu::util::make_spirv_raw(spirv),
                },
            ))
        }
    };
    trace_pipeline(label, "shader_module.done");
    trace_pipeline(label, "pipeline_layout.start");
    // let module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
    //     label: Some(label),
    //     source: wgpu::util::make_spirv(spirv),
    // });
    let pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some(&format!("pl_{label}")),
        bind_group_layouts: bgls,
        push_constant_ranges: &[],
    });
    trace_pipeline(label, "pipeline_layout.done");
    trace_pipeline(label, "compute_pipeline.start");
    let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some(label),
        layout: Some(&pl),
        module: &module,
        entry_point: Some(entry),
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache: crate::gpu::device::pipeline_cache_for(device).as_deref(),
    });
    trace_pipeline(label, "compute_pipeline.done");
    pipeline
}

fn trace_pipeline(label: &str, stage: &str) {
    if crate::gpu::env::env_bool_strict("LANIUS_PIPELINE_TRACE", false) {
        eprintln!("[laniusc][pipeline][{label}] {stage}");
    }
}

fn gpu_pipeline_progress_enabled() -> bool {
    is_env_truthy("LANIUS_GPU_PIPELINE_PROGRESS")
        || is_env_truthy("LANIUS_PIPELINE_TRACE")
        || is_env_truthy("LANIUS_WASM_TRACE")
        || is_env_truthy("LANIUS_X86_TRACE")
}

fn is_env_truthy(name: &str) -> bool {
    env::var_os(name)
        .and_then(|value| value.into_string().ok())
        .is_some_and(|value| matches!(value.as_str(), "1" | "true" | "TRUE" | "True" | "on" | "ON"))
}

pub(crate) fn trace_gpu_progress(label: &str) {
    if gpu_pipeline_progress_enabled() {
        if log::log_enabled!(log::Level::Info) {
            info!("[laniusc][gpu-progress] {label}");
        } else {
            eprintln!("[laniusc][gpu-progress] {label}");
        }
    }
}

pub(crate) fn submit_with_progress(
    queue: &wgpu::Queue,
    label: &str,
    command_buffer: wgpu::CommandBuffer,
) {
    trace_gpu_progress(&format!("submit.start :: {label}"));
    queue.submit(Some(command_buffer));
    trace_gpu_progress(&format!("submit.done :: {label}"));
}

pub(crate) fn map_readback_for_progress(slice: &wgpu::BufferSlice<'_>, label: &str) {
    trace_gpu_progress(&format!("map.start :: {label}"));
    slice.map_async(wgpu::MapMode::Read, |_| {});
    trace_gpu_progress(&format!("map.queued :: {label}"));
}

pub(crate) fn wait_for_map_progress(device: &wgpu::Device, label: &str, poll_type: wgpu::PollType) {
    trace_gpu_progress(&format!("poll.start :: {label}"));
    let _ = device.poll(poll_type);
    trace_gpu_progress(&format!("poll.done :: {label}"));
}

pub fn make_pass_data(
    device: &wgpu::Device,
    label: &str,
    entry: &str,
    spirv: &'static [u8],
    reflection_json: &'static [u8],
) -> Result<PassData> {
    let reflection: SlangReflection =
        parse_reflection_from_bytes(reflection_json).map_err(anyhow::Error::msg)?;
    let owned_bgls = bgls_from_reflection(device, &reflection)?;
    let bgl_refs: Vec<&wgpu::BindGroupLayout> = owned_bgls.iter().collect();
    let pipeline = pipeline_from_spirv_and_bgls(device, label, entry, spirv, &bgl_refs);
    let tgs = get_thread_group_size(&reflection).unwrap_or_else(|| {
        warn!("missing thread_group_size in reflection for {label}; defaulting to [1,1,1]");
        [1, 1, 1]
    });
    debug_assert!(
        tgs[0] > 0 && tgs[1] > 0 && tgs[2] > 0,
        "thread_group_size must be non-zero"
    );
    Ok(PassData {
        pipeline: Arc::new(pipeline),
        bind_group_layouts: owned_bgls.into_iter().map(Arc::new).collect(),
        shader_id: label.to_string(),
        thread_group_size: tgs,
        reflection: Arc::new(reflection),
    })
}

pub mod bind_group {
    use std::collections::HashMap;

    use anyhow::anyhow;
    use wgpu;

    use super::*;

    pub fn create_bind_group_from_reflection<'a>(
        device: &wgpu::Device,
        label: Option<&str>,
        bgl: &Arc<wgpu::BindGroupLayout>,
        reflection: &Arc<SlangReflection>,
        set_index: usize,
        resources: &HashMap<String, wgpu::BindingResource<'a>>,
    ) -> Result<wgpu::BindGroup> {
        let params: Vec<ParameterReflection> = if let Some(pl) = reflection
            .entry_points
            .iter()
            .find(|e| e.stage.as_deref() == Some("compute"))
            .and_then(|ep| ep.program_layout.clone())
        {
            pl.parameters
                .get(set_index)
                .map(|s| s.parameters.clone())
                .unwrap_or_default()
        } else {
            reflection.parameters.clone()
        };

        let mut entries = Vec::<wgpu::BindGroupEntry>::new();
        for p in &params {
            if let (Some(idx), Some(_ty)) = (p.binding.index, p.ty.kind.as_ref()) {
                if let Some(res) = resources.get(&p.name) {
                    entries.push(wgpu::BindGroupEntry {
                        binding: idx,
                        resource: res.clone(),
                    });
                } else {
                    return Err(anyhow!("no resource provided for '{}'", p.name));
                }
            }
        }

        Ok(device.create_bind_group(&wgpu::BindGroupDescriptor {
            label,
            layout: bgl,
            entries: &entries,
        }))
    }
}

pub const MAX_GROUPS_PER_DIM: u32 = 65_535;

/// Compute (gx, gy, gz) for a pass, reusing the same rules everywhere.
/// This is the *only* place that knows about the 65_535 limit and D1→D2 tiling.
pub fn plan_workgroups(
    dim: DispatchDim,
    input: InputElements,
    [tgsx, tgsy, _tgsz]: [u32; 3],
) -> anyhow::Result<(u32, u32, u32)> {
    use anyhow::anyhow;

    match (dim, input) {
        (DispatchDim::D1, InputElements::Elements1D(n)) => {
            let nb = n.div_ceil(tgsx).max(1);
            if nb <= MAX_GROUPS_PER_DIM {
                Ok((nb, 1, 1))
            } else {
                // Tile across Y
                let gx = MAX_GROUPS_PER_DIM;
                let gy = nb.div_ceil(MAX_GROUPS_PER_DIM).max(1);
                Ok((gx, gy, 1))
            }
        }
        (DispatchDim::D2, InputElements::Elements2D(w, h)) => {
            let gx = w.div_ceil(tgsx).max(1);
            let gy = h.div_ceil(tgsy).max(1);
            Ok((gx, gy, 1))
        }
        (DispatchDim::D2, InputElements::Elements1D(n)) => {
            let nb = n.div_ceil(tgsx).max(1);
            if nb <= MAX_GROUPS_PER_DIM {
                Ok((nb, 1, 1))
            } else {
                let gx = MAX_GROUPS_PER_DIM;
                let gy = nb.div_ceil(MAX_GROUPS_PER_DIM).max(1);
                Ok((gx, gy, 1))
            }
        }
        _ => Err(anyhow!("dimension/input mismatch")),
    }
}

/// Generic per-dispatch context shared across passes (lexer, parser, etc.).
/// `B` is the concrete buffers type for the pipeline; `D` is the debug output type.
pub struct PassContext<'a, B, D> {
    pub device: &'a wgpu::Device,
    pub encoder: &'a mut wgpu::CommandEncoder,
    pub buffers: &'a B,
    pub maybe_timer: &'a mut Option<&'a mut crate::gpu::timer::GpuTimer>,
    pub maybe_dbg: &'a mut Option<&'a mut D>,
    /// Optional bind group cache: when present, record_pass will reuse cached
    /// bind groups keyed by shader id and set index, and populate it on miss.
    pub bg_cache: Option<&'a mut BindGroupCache>,
}

#[derive(Default)]
pub struct BindGroupCache {
    // Keyed by shader id (label) to its vector of bind groups (per set index)
    map: HashMap<String, Vec<Arc<wgpu::BindGroup>>>,
}

impl BindGroupCache {
    pub fn new() -> Self {
        Self {
            map: HashMap::new(),
        }
    }
    pub fn clear(&mut self) {
        self.map.clear();
    }
}

pub trait Pass<Buffers, DebugOutput> {
    const NAME: &'static str;

    const DIM: DispatchDim;

    fn from_data(data: PassData) -> Self
    where
        Self: Sized;

    fn data(&self) -> &PassData;

    fn create_resource_map<'a>(
        &self,
        buffers: &'a Buffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>>;

    /// New, context-based API: pass fewer args via a shared struct.
    /// Default implementation forwards to the same logic as `record_pass`.
    fn record_pass<'a>(
        &self,
        ctx: &mut PassContext<'a, Buffers, DebugOutput>,
        input: InputElements,
    ) -> Result<(), anyhow::Error> {
        let use_scopes = validation_scopes_enabled(); // enable per-pass validation only when asked

        if use_scopes {
            ctx.device.push_error_scope(wgpu::ErrorFilter::Validation);
        }

        let pd = self.data();
        let resources = self.create_resource_map(ctx.buffers);
        // Try cache first if provided
        let mut cached_entries: Option<Vec<Arc<wgpu::BindGroup>>> = None;
        if let Some(cache) = ctx.bg_cache.as_mut() {
            if let Some(v) = cache.map.get(&pd.shader_id) {
                if v.len() == pd.bind_group_layouts.len() {
                    cached_entries = Some(v.clone());
                }
            }
        }
        let bind_groups: Vec<Arc<wgpu::BindGroup>> = if let Some(v) = cached_entries {
            v
        } else {
            let mut v = Vec::with_capacity(pd.bind_group_layouts.len());
            for (set_idx, bgl) in pd.bind_group_layouts.iter().enumerate() {
                let bg = bind_group::create_bind_group_from_reflection(
                    ctx.device,
                    Some(Self::NAME),
                    bgl,
                    &pd.reflection,
                    set_idx,
                    &resources,
                )?;
                v.push(Arc::new(bg));
            }
            if let Some(cache) = ctx.bg_cache.as_mut() {
                cache.map.insert(pd.shader_id.clone(), v.clone());
            }
            v
        };

        let [tgsx, tgsy, _tgsz] = pd.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(Self::DIM, input, [tgsx, tgsy, 1])?;

        assert!(gx <= MAX_GROUPS_PER_DIM);
        assert!(gy <= MAX_GROUPS_PER_DIM);
        debug_assert!(
            gx >= 1 && gy >= 1 && gz >= 1,
            "dispatch must issue at least one group"
        );

        let mut pass = ctx
            .encoder
            .begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some(Self::NAME),
                timestamp_writes: None,
            });
        pass.set_pipeline(&pd.pipeline);
        for (i, bg) in bind_groups.iter().enumerate() {
            pass.set_bind_group(i as u32, Option::<&wgpu::BindGroup>::Some(&*bg), &[]);
        }
        pass.dispatch_workgroups(gx, gy, gz);
        drop(pass);

        if let Some(t) = ctx.maybe_timer.as_deref_mut() {
            t.stamp(ctx.encoder, Self::NAME.to_string());
        }

        if use_scopes {
            if let Some(err) = pollster::block_on(ctx.device.pop_error_scope()) {
                return Err(anyhow!("validation in pass {}: {err:?}", Self::NAME));
            }
        }

        if let Some(d) = ctx.maybe_dbg.as_deref_mut() {
            self.record_debug(ctx.device, ctx.encoder, ctx.buffers, d);
        }
        Ok(())
    }

    fn record_debug(
        &self,
        _device: &wgpu::Device,
        _encoder: &mut wgpu::CommandEncoder,
        _b: &Buffers,
        _dbg: &mut DebugOutput,
    ) {
        warn!("debug output not implemented for pass {}", Self::NAME);
    }
}
