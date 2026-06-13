use std::{
    collections::HashMap,
    env,
    sync::{Arc, mpsc},
    time::{Duration, Instant},
};

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

pub fn compute_pass_batching_enabled() -> bool {
    match std::env::var("LANIUS_BATCH_COMPUTE_PASSES") {
        Ok(value) => !matches!(value.trim().to_ascii_lowercase().as_str(), "0" | "false"),
        Err(_) => true,
    }
}

pub(crate) fn validation_scope(
    device: &wgpu::Device,
    enabled: bool,
) -> Option<wgpu::ErrorScopeGuard> {
    enabled.then(|| device.push_error_scope(wgpu::ErrorFilter::Validation))
}

pub(crate) fn pop_validation_scope(scope: Option<wgpu::ErrorScopeGuard>) -> Option<wgpu::Error> {
    scope.and_then(|scope| pollster::block_on(scope.pop()))
}

#[derive(Clone, Copy, Debug)]
pub(crate) struct SubmitTiming {
    pub gpu_anchor: Instant,
}

pub(crate) fn submit_with_optional_validation(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    label: &str,
    command_buffer: wgpu::CommandBuffer,
    validation_enabled: bool,
    validation_label: &str,
) -> SubmitTiming {
    let scope = validation_scope(device, validation_enabled);
    let timing = submit_with_progress(queue, label, command_buffer);
    if let Some(err) = pop_validation_scope(scope) {
        eprintln!("[wgpu submit] validation while submitting {validation_label}: {err:#?}");
    }
    timing
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
    // SAFETY: Slang produced this SPIR-V module for the selected backend;
    // Lanius intentionally bypasses Naga translation for shader modules.
    let module = unsafe {
        device.create_shader_module_passthrough(wgpu::ShaderModuleDescriptorPassthrough {
            label: Some(label),
            spirv: Some(wgpu::util::make_spirv_raw(spirv)),
            ..Default::default()
        })
    };
    trace_pipeline(label, "shader_module.done");
    trace_pipeline(label, "pipeline_layout.start");
    // let module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
    //     label: Some(label),
    //     source: wgpu::util::make_spirv(spirv),
    // });
    let bind_group_layouts: Vec<_> = bgls.iter().copied().map(Some).collect();
    let pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some(&format!("pl_{label}")),
        bind_group_layouts: &bind_group_layouts,
        immediate_size: 0,
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
) -> SubmitTiming {
    trace_gpu_progress(&format!("submit.start :: {label}"));
    let start = Instant::now();
    queue.submit(Some(command_buffer));
    let end = Instant::now();
    crate::gpu::trace::record_host_span("host.submit", label, start, end);
    trace_gpu_progress(&format!("submit.done :: {label}"));
    SubmitTiming { gpu_anchor: end }
}

pub(crate) fn map_readback_for_progress(slice: &wgpu::BufferSlice<'_>, label: &str) {
    trace_gpu_progress(&format!("map.start :: {label}"));
    slice.map_async(wgpu::MapMode::Read, |_| {});
    crate::gpu::trace::record_instant(
        "host.readback",
        &format!("{label}.map_queued"),
        Instant::now(),
    );
    trace_gpu_progress(&format!("map.queued :: {label}"));
}

pub(crate) fn wait_for_map_progress(device: &wgpu::Device, label: &str, poll_type: wgpu::PollType) {
    trace_gpu_progress(&format!("poll.start :: {label}"));
    let _ = device.poll(poll_type);
    trace_gpu_progress(&format!("poll.done :: {label}"));
}

pub(crate) fn map_readback_blocking(
    device: &wgpu::Device,
    slice: &wgpu::BufferSlice<'_>,
    label: &str,
) -> Result<()> {
    let timeout = Duration::from_millis(crate::gpu::env::env_u64(
        "LANIUS_READBACK_TIMEOUT_MS",
        120_000,
    ));
    wait_for_readback_map(device, slice, label, timeout)
}

pub(crate) fn wait_for_readback_map(
    device: &wgpu::Device,
    slice: &wgpu::BufferSlice<'_>,
    label: &str,
    timeout: Duration,
) -> Result<()> {
    let label = label.to_string();
    let cb_label = label.clone();
    let (tx, rx) = mpsc::channel();
    trace_gpu_progress(&format!("map.start :: {label}"));
    slice.map_async(wgpu::MapMode::Read, move |result| {
        if let Err(err) = tx.send(result) {
            warn!("failed to dispatch readback status for {cb_label}: {err}");
        }
    });
    trace_gpu_progress(&format!("map.queued :: {label}"));

    let start = Instant::now();
    let mut next_progress = Duration::from_millis(500);
    loop {
        device
            .poll(wgpu::PollType::Poll)
            .map_err(|err| anyhow!("{label} readback poll failed: {err}"))?;
        match rx.try_recv() {
            Ok(Ok(())) => {
                crate::gpu::trace::record_host_span("host.readback", &label, start, Instant::now());
                trace_gpu_progress(&format!(
                    "map.done :: {label} elapsed_ms={}",
                    start.elapsed().as_millis()
                ));
                return Ok(());
            }
            Ok(Err(err)) => return Err(anyhow!("{label} readback map failed: {err}")),
            Err(mpsc::TryRecvError::Empty) => {}
            Err(mpsc::TryRecvError::Disconnected) => {
                return Err(anyhow!("{label} readback callback disconnected"));
            }
        }
        let elapsed = start.elapsed();
        if elapsed >= timeout {
            return Err(anyhow!(
                "{label} readback did not complete within {} ms",
                timeout.as_millis()
            ));
        }
        if elapsed >= next_progress {
            trace_gpu_progress(&format!(
                "map.waiting :: {label} elapsed_ms={}",
                elapsed.as_millis()
            ));
            next_progress += Duration::from_millis(500);
        }
        std::thread::sleep(Duration::from_millis(1));
    }
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
    let init_scope = validation_scope(device, validation_scopes_enabled());
    let init_result = (|| {
        let owned_bgls = bgls_from_reflection(device, &reflection)?;
        let bgl_refs: Vec<&wgpu::BindGroupLayout> = owned_bgls.iter().collect();
        let pipeline = pipeline_from_spirv_and_bgls(device, label, entry, spirv, &bgl_refs);
        Ok::<_, anyhow::Error>((owned_bgls, pipeline))
    })();
    if init_scope.is_some() {
        let _ = device.poll(wgpu::PollType::Poll);
    }
    if let Some(err) = pop_validation_scope(init_scope) {
        return Err(anyhow!(
            "validation while creating GPU pass {label}: {err:?}"
        ));
    }
    let (owned_bgls, pipeline) = init_result?;
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

macro_rules! make_shader_pass {
    ($device:expr, $label:expr, entry: $entry:expr, shader: $shader:literal) => {
        $crate::gpu::passes_core::make_pass_data(
            $device,
            $label,
            $entry,
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/", $shader, ".spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/",
                $shader,
                ".reflect.json"
            )),
        )
    };
    ($device:expr, $label:expr, entry: $entry:expr, artifacts: ($spv:literal, $reflection:literal)) => {
        $crate::gpu::passes_core::make_pass_data(
            $device,
            $label,
            $entry,
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/", $spv)),
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/", $reflection)),
        )
    };
}

macro_rules! make_main_pass {
    ($device:expr, $label:expr, shader: $shader:literal) => {
        $crate::gpu::passes_core::make_shader_pass!(
            $device,
            $label,
            entry: "main",
            shader: $shader
        )
    };
    ($device:expr, $label:expr, artifacts: ($spv:literal, $reflection:literal)) => {
        $crate::gpu::passes_core::make_shader_pass!(
            $device,
            $label,
            entry: "main",
            artifacts: ($spv, $reflection)
        )
    };
}

macro_rules! make_traced_main_pass {
    ($device:expr, $trace:expr, $stage:literal, $label:expr, shader: $shader:literal) => {{
        ($trace)(concat!($stage, ".pipeline.start"));
        let pass = $crate::gpu::passes_core::make_main_pass!(
            $device,
            $label,
            shader: $shader
        )?;
        ($trace)(concat!($stage, ".pipeline.done"));
        pass
    }};
    ($device:expr, $trace:expr, $stage:literal, $label:expr, artifacts: ($spv:literal, $reflection:literal)) => {{
        ($trace)(concat!($stage, ".pipeline.start"));
        let pass = $crate::gpu::passes_core::make_main_pass!(
            $device,
            $label,
            artifacts: ($spv, $reflection)
        )?;
        ($trace)(concat!($stage, ".pipeline.done"));
        pass
    }};
}

macro_rules! impl_static_shader_pass {
    ($pass:ident, label: $label:expr, entry: $entry:expr, shader: $shader:literal) => {
        impl $pass {
            pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
                let data = $crate::gpu::passes_core::make_shader_pass!(
                    device,
                    $label,
                    entry: $entry,
                    shader: $shader
                )?;
                Ok(Self { data })
            }
        }
    };
    ($pass:ident, label: $label:expr, shader: $shader:literal) => {
        $crate::gpu::passes_core::impl_static_shader_pass!(
            $pass,
            label: $label,
            entry: "main",
            shader: $shader
        );
    };
    ($pass:ident, label: $label:expr, entry: $entry:expr, artifacts: ($spv:literal, $reflection:literal)) => {
        impl $pass {
            pub fn new(device: &wgpu::Device) -> anyhow::Result<Self> {
                let data = $crate::gpu::passes_core::make_shader_pass!(
                    device,
                    $label,
                    entry: $entry,
                    artifacts: ($spv, $reflection)
                )?;
                Ok(Self { data })
            }
        }
    };
}

pub(crate) use impl_static_shader_pass;
pub(crate) use make_main_pass;
pub(crate) use make_shader_pass;
pub(crate) use make_traced_main_pass;

pub mod bind_group {
    use std::collections::HashMap;

    use anyhow::anyhow;
    use wgpu;

    use super::*;

    fn reflected_parameters_for_set(
        reflection: &SlangReflection,
        set_index: usize,
    ) -> &[ParameterReflection] {
        if let Some(pl) = reflection
            .entry_points
            .iter()
            .find(|e| e.stage.as_deref() == Some("compute"))
            .and_then(|ep| ep.program_layout.as_ref())
        {
            return pl
                .parameters
                .get(set_index)
                .map(|set| set.parameters.as_slice())
                .unwrap_or_default();
        }

        reflection.parameters.as_slice()
    }

    pub fn create_bind_group_from_reflection<'a>(
        device: &wgpu::Device,
        label: Option<&str>,
        bgl: &Arc<wgpu::BindGroupLayout>,
        reflection: &Arc<SlangReflection>,
        set_index: usize,
        resources: &HashMap<String, wgpu::BindingResource<'a>>,
    ) -> Result<wgpu::BindGroup> {
        let mut entries = Vec::<wgpu::BindGroupEntry>::new();
        for p in reflected_parameters_for_set(reflection, set_index) {
            if let (Some(idx), Some(_ty)) = (p.binding.index, p.ty.kind.as_ref()) {
                if let Some(res) = resources.get(&p.name) {
                    entries.push(wgpu::BindGroupEntry {
                        binding: idx,
                        resource: res.clone(),
                    });
                } else {
                    return Err(anyhow!(
                        "no resource provided for '{}' in bind group '{}'",
                        p.name,
                        label.unwrap_or("<unnamed>")
                    ));
                }
            }
        }

        Ok(device.create_bind_group(&wgpu::BindGroupDescriptor {
            label,
            layout: bgl,
            entries: &entries,
        }))
    }

    pub fn create_bind_group_from_bindings<'a>(
        device: &wgpu::Device,
        label: Option<&str>,
        pass: &PassData,
        set_index: usize,
        bindings: &[(&str, wgpu::BindingResource<'a>)],
    ) -> Result<wgpu::BindGroup> {
        let params = reflected_parameters_for_set(&pass.reflection, set_index);
        let mut entries = Vec::<wgpu::BindGroupEntry>::with_capacity(params.len());

        let mut ordered_bindings = bindings.iter();
        let mut in_reflected_order = true;
        for p in params {
            if let (Some(idx), Some(_ty)) = (p.binding.index, p.ty.kind.as_ref()) {
                let Some((name, resource)) = ordered_bindings.next() else {
                    in_reflected_order = false;
                    break;
                };
                if *name != p.name {
                    in_reflected_order = false;
                    break;
                }
                entries.push(wgpu::BindGroupEntry {
                    binding: idx,
                    resource: resource.clone(),
                });
            }
        }

        if !in_reflected_order {
            entries.clear();
            for p in params {
                if let (Some(idx), Some(_ty)) = (p.binding.index, p.ty.kind.as_ref()) {
                    let Some((_, resource)) = bindings.iter().find(|(name, _)| *name == p.name)
                    else {
                        return Err(anyhow!(
                            "no resource provided for '{}' in bind group '{}'",
                            p.name,
                            label.unwrap_or("<unnamed>")
                        ));
                    };
                    entries.push(wgpu::BindGroupEntry {
                        binding: idx,
                        resource: resource.clone(),
                    });
                };
            }
        }

        Ok(device.create_bind_group(&wgpu::BindGroupDescriptor {
            label,
            layout: &pass.bind_group_layouts[set_index],
            entries: &entries,
        }))
    }

    #[cfg(test)]
    mod tests {
        use super::*;
        use crate::reflection::{
            BindingInfo,
            EntryPointReflection,
            ParameterReflection,
            ParameterSetReflection,
            ProgramLayoutReflection,
            TypeLayout,
        };

        fn parameter(name: &str, binding: u32) -> ParameterReflection {
            ParameterReflection {
                name: name.to_string(),
                binding: BindingInfo {
                    kind: "descriptorTableSlot".to_string(),
                    index: Some(binding),
                    offset: None,
                    size: None,
                },
                ty: TypeLayout {
                    kind: Some("resource".to_string()),
                    base_shape: Some("structuredBuffer".to_string()),
                    access: Some("Read".to_string()),
                    ..TypeLayout::default()
                },
                user_attribs: Vec::new(),
            }
        }

        #[test]
        fn reflected_parameters_borrow_program_layout_set_without_flattening() {
            let reflection = SlangReflection {
                parameters: vec![parameter("flat", 9)],
                entry_points: vec![EntryPointReflection {
                    stage: Some("compute".to_string()),
                    program_layout: Some(ProgramLayoutReflection {
                        parameters: vec![
                            ParameterSetReflection {
                                parameters: vec![parameter("set0", 0)],
                                space: 0,
                            },
                            ParameterSetReflection {
                                parameters: vec![parameter("set1a", 1), parameter("set1b", 2)],
                                space: 1,
                            },
                        ],
                    }),
                    ..EntryPointReflection::default()
                }],
                ..SlangReflection::default()
            };

            let params = reflected_parameters_for_set(&reflection, 1);
            let names = params
                .iter()
                .map(|param| param.name.as_str())
                .collect::<Vec<_>>();
            assert_eq!(names, vec!["set1a", "set1b"]);
        }
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

    pub fn remove(&mut self, shader_id: &str) {
        self.map.remove(shader_id);
    }
}

fn bind_groups_for_pass<P, Buffers, DebugOutput>(
    device: &wgpu::Device,
    pass: &P,
    buffers: &Buffers,
    cache: Option<&mut BindGroupCache>,
) -> Result<Vec<Arc<wgpu::BindGroup>>, anyhow::Error>
where
    P: Pass<Buffers, DebugOutput> + ?Sized,
{
    let pd = pass.data();
    let resources = pass.create_resource_map(buffers);
    let mut cached_entries: Option<Vec<Arc<wgpu::BindGroup>>> = None;
    if let Some(cache) = cache.as_ref()
        && let Some(v) = cache.map.get(&pd.shader_id)
        && v.len() == pd.bind_group_layouts.len()
    {
        cached_entries = Some(v.clone());
    }
    if let Some(v) = cached_entries {
        return Ok(v);
    }

    let mut bind_groups = Vec::with_capacity(pd.bind_group_layouts.len());
    for (set_idx, bgl) in pd.bind_group_layouts.iter().enumerate() {
        let bg = bind_group::create_bind_group_from_reflection(
            device,
            Some(P::NAME),
            bgl,
            &pd.reflection,
            set_idx,
            &resources,
        )?;
        bind_groups.push(Arc::new(bg));
    }
    if let Some(cache) = cache {
        cache.map.insert(pd.shader_id.clone(), bind_groups.clone());
    }
    Ok(bind_groups)
}

pub struct ComputePassBatch<'encoder> {
    pass: wgpu::ComputePass<'encoder>,
    retained_bind_groups: Vec<Vec<Arc<wgpu::BindGroup>>>,
}

impl<'encoder> ComputePassBatch<'encoder> {
    pub fn begin(encoder: &'encoder mut wgpu::CommandEncoder, label: &'static str) -> Self {
        let pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(label),
            timestamp_writes: None,
        });
        Self {
            pass,
            retained_bind_groups: Vec::new(),
        }
    }

    pub fn record_pass_cached<P, Buffers, DebugOutput>(
        &mut self,
        device: &wgpu::Device,
        buffers: &Buffers,
        cache: &mut BindGroupCache,
        pass: &P,
        input: InputElements,
    ) -> Result<(), anyhow::Error>
    where
        P: Pass<Buffers, DebugOutput>,
    {
        let pd = pass.data();
        let bind_groups =
            bind_groups_for_pass::<P, Buffers, DebugOutput>(device, pass, buffers, Some(cache))?;
        let [tgsx, tgsy, _tgsz] = pd.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(P::DIM, input, [tgsx, tgsy, 1])?;
        assert!(gx <= MAX_GROUPS_PER_DIM);
        assert!(gy <= MAX_GROUPS_PER_DIM);
        debug_assert!(
            gx >= 1 && gy >= 1 && gz >= 1,
            "dispatch must issue at least one group"
        );
        self.pass.set_pipeline(&pd.pipeline);
        for (i, bg) in bind_groups.iter().enumerate() {
            self.pass
                .set_bind_group(i as u32, Option::<&wgpu::BindGroup>::Some(&*bg), &[]);
        }
        self.pass.dispatch_workgroups(gx, gy, gz);
        self.retained_bind_groups.push(bind_groups);
        Ok(())
    }

    pub fn record_pass_indirect_cached<P, Buffers, DebugOutput>(
        &mut self,
        device: &wgpu::Device,
        buffers: &Buffers,
        cache: &mut BindGroupCache,
        pass: &P,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<(), anyhow::Error>
    where
        P: Pass<Buffers, DebugOutput>,
    {
        let pd = pass.data();
        let bind_groups =
            bind_groups_for_pass::<P, Buffers, DebugOutput>(device, pass, buffers, Some(cache))?;
        self.pass.set_pipeline(&pd.pipeline);
        for (i, bg) in bind_groups.iter().enumerate() {
            self.pass
                .set_bind_group(i as u32, Option::<&wgpu::BindGroup>::Some(&*bg), &[]);
        }
        self.pass.dispatch_workgroups_indirect(dispatch_args, 0);
        self.retained_bind_groups.push(bind_groups);
        Ok(())
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

        let validation_scope = validation_scope(ctx.device, use_scopes);

        let pd = self.data();
        let bind_groups = bind_groups_for_pass::<Self, Buffers, DebugOutput>(
            ctx.device,
            self,
            ctx.buffers,
            ctx.bg_cache.as_deref_mut(),
        )?;

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

        if let Some(err) = pop_validation_scope(validation_scope) {
            return Err(anyhow!("validation in pass {}: {err:?}", Self::NAME));
        }

        if let Some(d) = ctx.maybe_dbg.as_deref_mut() {
            self.record_debug(ctx.device, ctx.encoder, ctx.buffers, d);
        }
        Ok(())
    }

    fn record_pass_indirect<'a>(
        &self,
        ctx: &mut PassContext<'a, Buffers, DebugOutput>,
        dispatch_args: &wgpu::Buffer,
    ) -> Result<(), anyhow::Error> {
        let use_scopes = validation_scopes_enabled();

        let validation_scope = validation_scope(ctx.device, use_scopes);

        let pd = self.data();
        let bind_groups = bind_groups_for_pass::<Self, Buffers, DebugOutput>(
            ctx.device,
            self,
            ctx.buffers,
            ctx.bg_cache.as_deref_mut(),
        )?;

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
        pass.dispatch_workgroups_indirect(dispatch_args, 0);
        drop(pass);

        if let Some(t) = ctx.maybe_timer.as_deref_mut() {
            t.stamp(ctx.encoder, Self::NAME.to_string());
        }

        if let Some(err) = pop_validation_scope(validation_scope) {
            return Err(anyhow!("validation in pass {}: {err:?}", Self::NAME));
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
