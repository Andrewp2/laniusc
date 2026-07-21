use std::{
    collections::HashMap,
    env,
    sync::{
        Arc,
        atomic::{AtomicU64, Ordering},
        mpsc,
    },
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

static PIPELINE_CREATION_COUNT: AtomicU64 = AtomicU64::new(0);

/// Returns the number of compute pipelines created by this process.
///
/// The daemon uses this monotonic count to enforce that compilation jobs do
/// not perform pipeline initialization after it has reported readiness.
pub(crate) fn pipeline_creation_count() -> u64 {
    PIPELINE_CREATION_COUNT.load(Ordering::Relaxed)
}

/// Returns whether selected GPU operations should use wgpu validation scopes.
pub fn validation_scopes_enabled() -> bool {
    crate::gpu::env::env_bool_truthy("LANIUS_VALIDATION_SCOPES", false)
}

/// Returns whether compatible compute passes may share one `wgpu::ComputePass`.
pub fn compute_pass_batching_enabled() -> bool {
    match std::env::var("LANIUS_BATCH_COMPUTE_PASSES") {
        Ok(value) => !matches!(value.trim().to_ascii_lowercase().as_str(), "0" | "false"),
        Err(_) => true,
    }
}

enum DeferredComputeCommand {
    Direct {
        pipeline: Arc<wgpu::ComputePipeline>,
        bind_groups: Vec<wgpu::BindGroup>,
        groups: (u32, u32, u32),
    },
    Indirect {
        pipeline: Arc<wgpu::ComputePipeline>,
        bind_groups: Vec<wgpu::BindGroup>,
        dispatch_args: wgpu::Buffer,
        dispatch_offset: u64,
        dynamic_offsets: Vec<u32>,
    },
}

#[derive(Default)]
struct DeferredComputeState {
    active: bool,
    label: Option<&'static str>,
    commands: Vec<DeferredComputeCommand>,
}

thread_local! {
    static DEFERRED_COMPUTE: std::cell::RefCell<DeferredComputeState> =
        std::cell::RefCell::new(DeferredComputeState::default());
}

/// Scope for coalescing ordered compute dispatches until the next explicit
/// encoder clear/copy boundary. GPU handles are cloned into deferred commands,
/// so their lifetimes remain valid through the eventual compute pass.
pub(crate) struct DeferredComputeBatchGuard {
    enabled: bool,
}

impl DeferredComputeBatchGuard {
    pub(crate) fn begin(enabled: bool, label: &'static str) -> Self {
        if enabled {
            DEFERRED_COMPUTE.with(|state| {
                let mut state = state.borrow_mut();
                assert!(!state.active, "deferred compute batching cannot nest");
                assert!(state.commands.is_empty());
                state.active = true;
                state.label = Some(label);
            });
        }
        Self { enabled }
    }
}

impl Drop for DeferredComputeBatchGuard {
    fn drop(&mut self) {
        if self.enabled {
            DEFERRED_COMPUTE.with(|state| {
                let mut state = state.borrow_mut();
                state.active = false;
                state.label = None;
                // Early recording errors must not leak commands into the next
                // compilation on this worker thread.
                state.commands.clear();
            });
        }
    }
}

pub(crate) fn defer_compute_direct(
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    groups: (u32, u32, u32),
) -> bool {
    DEFERRED_COMPUTE.with(|state| {
        let mut state = state.borrow_mut();
        if !state.active {
            return false;
        }
        state.commands.push(DeferredComputeCommand::Direct {
            pipeline: pass.pipeline.clone(),
            bind_groups: vec![bind_group.clone()],
            groups,
        });
        true
    })
}

pub(crate) fn defer_compute_indirect(
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    dispatch_args: &wgpu::Buffer,
    dispatch_offset: u64,
    dynamic_offsets: &[u32],
) -> bool {
    DEFERRED_COMPUTE.with(|state| {
        let mut state = state.borrow_mut();
        if !state.active {
            return false;
        }
        state.commands.push(DeferredComputeCommand::Indirect {
            pipeline: pass.pipeline.clone(),
            bind_groups: vec![bind_group.clone()],
            dispatch_args: dispatch_args.clone(),
            dispatch_offset,
            dynamic_offsets: dynamic_offsets.to_vec(),
        });
        true
    })
}

pub(crate) fn defer_compute_direct_bind_groups(
    pass: &PassData,
    bind_groups: &[Arc<wgpu::BindGroup>],
    groups: (u32, u32, u32),
) -> bool {
    DEFERRED_COMPUTE.with(|state| {
        let mut state = state.borrow_mut();
        if !state.active {
            return false;
        }
        state.commands.push(DeferredComputeCommand::Direct {
            pipeline: pass.pipeline.clone(),
            bind_groups: bind_groups.iter().map(|group| (**group).clone()).collect(),
            groups,
        });
        true
    })
}

pub(crate) fn defer_compute_indirect_bind_groups(
    pass: &PassData,
    bind_groups: &[Arc<wgpu::BindGroup>],
    dispatch_args: &wgpu::Buffer,
) -> bool {
    DEFERRED_COMPUTE.with(|state| {
        let mut state = state.borrow_mut();
        if !state.active {
            return false;
        }
        state.commands.push(DeferredComputeCommand::Indirect {
            pipeline: pass.pipeline.clone(),
            bind_groups: bind_groups.iter().map(|group| (**group).clone()).collect(),
            dispatch_args: dispatch_args.clone(),
            dispatch_offset: 0,
            dynamic_offsets: Vec::new(),
        });
        true
    })
}

/// Records one direct dispatch immediately, or appends it to the active
/// ordered compute batch.
pub(crate) fn record_or_defer_compute_direct(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &'static str,
    groups: (u32, u32, u32),
) {
    if defer_compute_direct(pass, bind_group, groups) {
        return;
    }
    flush_deferred_compute(encoder);
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), &[]);
    compute.dispatch_workgroups(groups.0, groups.1, groups.2);
}

/// Records one indirect dispatch immediately, or appends it to the active
/// ordered compute batch.
pub(crate) fn record_or_defer_compute_indirect(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &'static str,
    dispatch_args: &wgpu::Buffer,
) {
    record_or_defer_compute_indirect_offset(encoder, pass, bind_group, label, dispatch_args, 0);
}

/// Records one indirect dispatch from `dispatch_offset` immediately, or
/// appends it to the active ordered compute batch.
pub(crate) fn record_or_defer_compute_indirect_offset(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &'static str,
    dispatch_args: &wgpu::Buffer,
    dispatch_offset: u64,
) {
    if defer_compute_indirect(pass, bind_group, dispatch_args, dispatch_offset, &[]) {
        return;
    }
    flush_deferred_compute(encoder);
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), &[]);
    compute.dispatch_workgroups_indirect(dispatch_args, dispatch_offset);
}

/// Flushes all deferred dispatches as one ordered compute pass.
pub(crate) fn flush_deferred_compute(encoder: &mut wgpu::CommandEncoder) {
    let (label, commands) = DEFERRED_COMPUTE.with(|state| {
        let mut state = state.borrow_mut();
        (
            state.label.unwrap_or("compute.batch"),
            std::mem::take(&mut state.commands),
        )
    });
    if commands.is_empty() {
        return;
    }
    let host_timing = crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false);
    let started = host_timing.then(Instant::now);
    let command_count = commands.len();
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    for command in &commands {
        match command {
            DeferredComputeCommand::Direct {
                pipeline,
                bind_groups,
                groups,
            } => {
                compute.set_pipeline(pipeline);
                for (index, bind_group) in bind_groups.iter().enumerate() {
                    compute.set_bind_group(index as u32, bind_group, &[]);
                }
                compute.dispatch_workgroups(groups.0, groups.1, groups.2);
            }
            DeferredComputeCommand::Indirect {
                pipeline,
                bind_groups,
                dispatch_args,
                dispatch_offset,
                dynamic_offsets,
            } => {
                compute.set_pipeline(pipeline);
                for (index, bind_group) in bind_groups.iter().enumerate() {
                    let offsets = if index == 0 {
                        dynamic_offsets.as_slice()
                    } else {
                        &[]
                    };
                    compute.set_bind_group(index as u32, bind_group, offsets);
                }
                compute.dispatch_workgroups_indirect(dispatch_args, *dispatch_offset);
            }
        }
    }
    drop(compute);
    if let Some(started) = started {
        eprintln!(
            "[gpu_compile_host_timer] compute_batch.flush: label={label} commands={command_count} elapsed_ms={:.3}",
            started.elapsed().as_secs_f64() * 1000.0,
        );
    }
}

/// Pushes a validation scope when `enabled` is true.
pub(crate) fn validation_scope(
    device: &wgpu::Device,
    enabled: bool,
) -> Option<wgpu::ErrorScopeGuard> {
    enabled.then(|| device.push_error_scope(wgpu::ErrorFilter::Validation))
}

/// Pops an optional validation scope and returns any captured wgpu error.
pub(crate) fn pop_validation_scope(scope: Option<wgpu::ErrorScopeGuard>) -> Option<wgpu::Error> {
    scope.and_then(|scope| pollster::block_on(scope.pop()))
}

#[derive(Clone, Copy, Debug)]
/// Host timing metadata returned by command-buffer submission helpers.
pub(crate) struct SubmitTiming {
    /// Instant used as the anchor for later GPU trace spans.
    pub gpu_anchor: Instant,
}

/// Submits a command buffer and reports validation errors when enabled.
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

/// Reflected compute-pipeline data shared by pass wrappers.
pub struct PassData {
    /// Compiled compute pipeline.
    pub pipeline: Arc<wgpu::ComputePipeline>,
    /// Bind group layouts derived from Slang reflection.
    pub bind_group_layouts: Vec<Arc<wgpu::BindGroupLayout>>,
    /// Stable shader/pass id used for cache keys and diagnostics.
    pub shader_id: String,
    /// Reflected compute thread-group size.
    pub thread_group_size: [u32; 3],
    /// Parsed Slang reflection used for bind groups.
    pub reflection: Arc<SlangReflection>,
}

#[derive(Debug)]
pub(crate) struct GpuPassResourceLimitError {
    pub(crate) pass_label: String,
    pub(crate) required_storage_buffers: usize,
    pub(crate) adapter_storage_buffer_limit: usize,
}

impl std::fmt::Display for GpuPassResourceLimitError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "GPU pass {} requires {} storage buffers in the compute stage, but the selected adapter supports {}; this pass must use packed records or be split before it can run on this adapter",
            self.pass_label, self.required_storage_buffers, self.adapter_storage_buffer_limit
        )
    }
}

impl std::error::Error for GpuPassResourceLimitError {}

#[derive(Copy, Clone, Debug)]
/// Dispatch dimensionality expected by a pass wrapper.
pub enum DispatchDim {
    /// One-dimensional logical input.
    D1,
    /// Two-dimensional logical input.
    D2,
}

#[derive(Copy, Clone, Debug)]
/// Logical input size supplied to dispatch planning.
pub enum InputElements {
    /// One-dimensional element count.
    Elements1D(u32),
    /// Two-dimensional width and height.
    Elements2D(u32, u32),
}

/// Creates bind group layouts from Slang reflection metadata.
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

/// Counts storage-buffer descriptors visible to the reflected compute stage.
///
/// WGPU applies `max_storage_buffers_per_shader_stage` across every bind group,
/// so program-layout descriptor sets must be summed rather than checked one at
/// a time. Flat Slang reflection uses the top-level parameter list instead.
fn reflected_compute_storage_buffer_count(reflection: &SlangReflection) -> Result<usize> {
    let entry = reflection
        .entry_points
        .iter()
        .find(|entry| entry.stage.as_deref() == Some("compute"))
        .ok_or_else(|| anyhow!("no compute entry point found in reflection"))?;
    let parameters = if let Some(layout) = entry.program_layout.as_ref() {
        layout
            .parameters
            .iter()
            .flat_map(|set| set.parameters.iter())
            .collect::<Vec<_>>()
    } else {
        reflection.parameters.iter().collect::<Vec<_>>()
    };
    Ok(parameters
        .into_iter()
        .filter(|parameter| {
            matches!(
                slang_category_and_type_to_wgpu(parameter, &parameter.ty),
                Some(wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Storage { .. },
                    ..
                })
            )
        })
        .count())
}

fn validate_reflected_compute_limits(
    reflection: &SlangReflection,
    label: &str,
    limits: &wgpu::Limits,
) -> Result<()> {
    let storage_buffer_count = reflected_compute_storage_buffer_count(reflection)?;
    let storage_buffer_limit = limits.max_storage_buffers_per_shader_stage as usize;
    if storage_buffer_count > storage_buffer_limit {
        return Err(GpuPassResourceLimitError {
            pass_label: label.to_owned(),
            required_storage_buffers: storage_buffer_count,
            adapter_storage_buffer_limit: storage_buffer_limit,
        }
        .into());
    }
    Ok(())
}

#[cfg(test)]
mod reflected_limit_tests {
    use super::*;

    fn storage_parameter(name: &str, index: u32) -> ParameterReflection {
        ParameterReflection {
            name: name.to_owned(),
            binding: crate::reflection::BindingInfo {
                kind: "descriptorTableSlot".to_owned(),
                index: Some(index),
                offset: None,
                size: None,
            },
            ty: crate::reflection::TypeLayout {
                kind: Some("resource".to_owned()),
                base_shape: Some("structuredBuffer".to_owned()),
                access: Some("Read".to_owned()),
                ..Default::default()
            },
            user_attribs: Vec::new(),
        }
    }

    #[test]
    fn storage_buffer_count_uses_flat_compute_parameters() {
        let reflection = SlangReflection {
            parameters: vec![storage_parameter("left", 0), storage_parameter("right", 1)],
            entry_points: vec![EntryPointReflection {
                stage: Some("compute".to_owned()),
                ..Default::default()
            }],
            ..Default::default()
        };

        assert_eq!(
            reflected_compute_storage_buffer_count(&reflection).unwrap(),
            2
        );
    }

    #[test]
    fn storage_buffer_limit_sums_program_layout_sets_and_names_pass() {
        let reflection = SlangReflection {
            entry_points: vec![EntryPointReflection {
                stage: Some("compute".to_owned()),
                program_layout: Some(crate::reflection::ProgramLayoutReflection {
                    parameters: vec![
                        crate::reflection::ParameterSetReflection {
                            parameters: vec![storage_parameter("left", 0)],
                            space: 0,
                        },
                        crate::reflection::ParameterSetReflection {
                            parameters: vec![storage_parameter("right", 0)],
                            space: 1,
                        },
                    ],
                }),
                ..Default::default()
            }],
            ..Default::default()
        };
        let mut limits = wgpu::Limits::defaults();
        limits.max_storage_buffers_per_shader_stage = 1;

        let error = validate_reflected_compute_limits(&reflection, "type_check.example", &limits)
            .expect_err("two storage buffers must exceed a one-buffer adapter limit");
        let message = error.to_string();
        assert!(message.contains("type_check.example"));
        assert!(message.contains("requires 2 storage buffers"));
        assert!(message.contains("supports 1"));
    }
}

/// Creates a compute pipeline from SPIR-V and reflected bind group layouts.
pub fn pipeline_from_spirv_and_bgls(
    device: &wgpu::Device,
    label: &str,
    entry: &str,
    spirv: &[u8],
    bgls: &[&wgpu::BindGroupLayout],
) -> wgpu::ComputePipeline {
    let total_start = Instant::now();
    let shader_module_start = total_start;
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
    let shader_module_end = Instant::now();
    trace_pipeline(label, "shader_module.done");
    let pipeline_layout_start = shader_module_end;
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
    let pipeline_layout_end = Instant::now();
    trace_pipeline(label, "pipeline_layout.done");
    let compute_pipeline_start = pipeline_layout_end;
    trace_pipeline(label, "compute_pipeline.start");
    let pipeline = device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some(label),
        layout: Some(&pl),
        module: &module,
        entry_point: Some(entry),
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache: crate::gpu::device::pipeline_cache_for(device).as_deref(),
    });
    PIPELINE_CREATION_COUNT.fetch_add(1, Ordering::Relaxed);
    crate::gpu::device::mark_pipeline_cache_dirty(device);
    let compute_pipeline_end = Instant::now();
    trace_pipeline(label, "compute_pipeline.done");
    trace_pipeline_timing(
        label,
        shader_module_end.duration_since(shader_module_start),
        pipeline_layout_end.duration_since(pipeline_layout_start),
        compute_pipeline_end.duration_since(compute_pipeline_start),
        compute_pipeline_end.duration_since(total_start),
    );
    pipeline
}

fn trace_pipeline(label: &str, stage: &str) {
    if crate::gpu::env::env_bool_strict("LANIUS_PIPELINE_TRACE", false) {
        eprintln!("[laniusc][pipeline][{label}] {stage}");
    }
}

fn trace_pipeline_timing(
    label: &str,
    shader_module: Duration,
    pipeline_layout: Duration,
    compute_pipeline: Duration,
    total: Duration,
) {
    if !crate::gpu::env::env_bool_strict("LANIUS_PIPELINE_TIMING", false) {
        return;
    }
    let minimum_ms = env::var("LANIUS_PIPELINE_TIMING_MIN_MS")
        .ok()
        .and_then(|value| value.parse::<f64>().ok())
        .unwrap_or(100.0);
    let total_ms = total.as_secs_f64() * 1000.0;
    if total_ms < minimum_ms {
        return;
    }
    eprintln!(
        "[laniusc][pipeline-timing] label={label} total_ms={total_ms:.3} shader_module_ms={:.3} pipeline_layout_ms={:.3} compute_pipeline_ms={:.3}",
        shader_module.as_secs_f64() * 1000.0,
        pipeline_layout.as_secs_f64() * 1000.0,
        compute_pipeline.as_secs_f64() * 1000.0,
    );
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

/// Emits coarse GPU progress logging when progress tracing is enabled.
pub(crate) fn trace_gpu_progress(label: &str) {
    if gpu_pipeline_progress_enabled() {
        if log::log_enabled!(log::Level::Info) {
            info!("[laniusc][gpu-progress] {label}");
        } else {
            eprintln!("[laniusc][gpu-progress] {label}");
        }
    }
}

/// Submits one command buffer and records host-side submit timing.
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

/// Queues a readback map request and records progress/trace events.
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

/// Polls a device while emitting progress messages for a pending map.
pub(crate) fn wait_for_map_progress(device: &wgpu::Device, label: &str, poll_type: wgpu::PollType) {
    trace_gpu_progress(&format!("poll.start :: {label}"));
    let _ = device.poll(poll_type);
    trace_gpu_progress(&format!("poll.done :: {label}"));
}

/// Blocks until a readback map completes or the configured timeout expires.
pub(crate) fn map_readback_blocking(
    device: &wgpu::Device,
    slice: &wgpu::BufferSlice<'_>,
    label: &str,
) -> Result<()> {
    wait_for_readback_map(device, slice, label, readback_timeout())
}

fn readback_timeout() -> Duration {
    Duration::from_millis(crate::gpu::env::env_u64(
        "LANIUS_READBACK_TIMEOUT_MS",
        120_000,
    ))
}

/// Waits for a readback map callback with explicit timeout and progress output.
pub(crate) fn wait_for_readback_map(
    device: &wgpu::Device,
    slice: &wgpu::BufferSlice<'_>,
    label: &str,
    timeout: Duration,
) -> Result<()> {
    let pending = begin_readback_map(slice, label);
    finish_readback_map(device, pending, timeout)
}

/// Finishes a queued readback using the standard configured timeout.
pub(crate) fn finish_readback_map_blocking(
    device: &wgpu::Device,
    pending: PendingReadbackMap,
) -> Result<()> {
    finish_readback_map(device, pending, readback_timeout())
}

/// Pending asynchronous readback map whose wait may be overlapped with host work.
pub(crate) struct PendingReadbackMap {
    receiver: mpsc::Receiver<std::result::Result<(), wgpu::BufferAsyncError>>,
    label: String,
    started: Instant,
}

/// Queues a readback map callback without polling the device.
pub(crate) fn begin_readback_map(slice: &wgpu::BufferSlice<'_>, label: &str) -> PendingReadbackMap {
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
    PendingReadbackMap {
        receiver: rx,
        label,
        started: Instant::now(),
    }
}

/// Polls until a previously queued readback map completes.
pub(crate) fn finish_readback_map(
    device: &wgpu::Device,
    pending: PendingReadbackMap,
    timeout: Duration,
) -> Result<()> {
    let PendingReadbackMap {
        receiver,
        label,
        started,
    } = pending;
    let mut next_progress = Duration::from_millis(500);
    loop {
        device
            .poll(wgpu::PollType::Poll)
            .map_err(|err| anyhow!("{label} readback poll failed: {err}"))?;
        match receiver.try_recv() {
            Ok(Ok(())) => {
                crate::gpu::trace::record_host_span(
                    "host.readback",
                    &label,
                    started,
                    Instant::now(),
                );
                trace_gpu_progress(&format!(
                    "map.done :: {label} elapsed_ms={}",
                    started.elapsed().as_millis()
                ));
                return Ok(());
            }
            Ok(Err(err)) => return Err(anyhow!("{label} readback map failed: {err}")),
            Err(mpsc::TryRecvError::Empty) => {}
            Err(mpsc::TryRecvError::Disconnected) => {
                return Err(anyhow!("{label} readback callback disconnected"));
            }
        }
        let elapsed = started.elapsed();
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

/// Builds `PassData` from SPIR-V bytes and Slang reflection JSON.
pub fn make_pass_data(
    device: &wgpu::Device,
    label: &str,
    entry: &str,
    spirv: &[u8],
    reflection_json: &[u8],
) -> Result<PassData> {
    let reflection: SlangReflection =
        parse_reflection_from_bytes(reflection_json).map_err(anyhow::Error::msg)?;
    validate_reflected_compute_limits(&reflection, label, &device.limits())?;
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

#[cfg(all(debug_assertions, not(target_arch = "wasm32")))]
/// Builds `PassData` from debug artifact files on disk.
pub fn make_pass_data_from_artifact_files<P, R>(
    device: &wgpu::Device,
    label: &str,
    entry: &str,
    spv_path: P,
    reflection_path: R,
) -> Result<PassData>
where
    P: AsRef<std::path::Path>,
    R: AsRef<std::path::Path>,
{
    let spv_path = spv_path.as_ref();
    let reflection_path = reflection_path.as_ref();
    let spirv = std::fs::read(spv_path)
        .map_err(|err| anyhow!("read debug shader SPIR-V {}: {err}", spv_path.display()))?;
    let reflection_json = std::fs::read(reflection_path).map_err(|err| {
        anyhow!(
            "read debug shader reflection {}: {err}",
            reflection_path.display()
        )
    })?;
    make_pass_data(device, label, entry, &spirv, &reflection_json)
}

/// Builds `PassData` from a shader artifact key without extensions.
pub fn make_pass_data_from_shader_key(
    device: &wgpu::Device,
    label: &str,
    entry: &str,
    shader: &str,
) -> Result<PassData> {
    make_pass_data_from_shader_artifacts(
        device,
        label,
        entry,
        &format!("{shader}.spv"),
        &format!("{shader}.reflect.json"),
    )
}

/// Builds `PassData` from explicit SPIR-V and reflection artifact names.
pub fn make_pass_data_from_shader_artifacts(
    device: &wgpu::Device,
    label: &str,
    entry: &str,
    spv: &str,
    reflection: &str,
) -> Result<PassData> {
    #[cfg(all(debug_assertions, not(target_arch = "wasm32")))]
    {
        return make_pass_data_from_artifact_files(
            device,
            label,
            entry,
            crate::shader_artifacts::artifact_path(spv),
            crate::shader_artifacts::artifact_path(reflection),
        );
    }
    #[cfg(any(not(debug_assertions), target_arch = "wasm32"))]
    {
        let spv_path = crate::shader_artifacts::artifact_path(spv);
        let reflection_path = crate::shader_artifacts::artifact_path(reflection);
        let spv_bytes = std::fs::read(&spv_path)
            .map_err(|err| anyhow!("read shader SPIR-V {}: {err}", spv_path.display()))?;
        let reflection_bytes = std::fs::read(&reflection_path).map_err(|err| {
            anyhow!(
                "read shader reflection {}: {err}",
                reflection_path.display()
            )
        })?;
        make_pass_data(device, label, entry, &spv_bytes, &reflection_bytes)
    }
}

macro_rules! make_shader_pass {
    ($device:expr, $label:expr, entry: $entry:expr, shader: $shader:literal) => {{ $crate::gpu::passes_core::make_pass_data_from_shader_key($device, $label, $entry, $shader) }};
    ($device:expr, $label:expr, entry: $entry:expr, artifacts: ($spv:literal, $reflection:literal)) => {{
        $crate::gpu::passes_core::make_pass_data_from_shader_artifacts(
            $device,
            $label,
            $entry,
            $spv,
            $reflection,
        )
    }};
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
            /// Creates this static shader pass for `device`.
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
            /// Creates this static shader pass for `device`.
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

/// Helpers for creating bind groups from reflected Slang parameter names.
pub mod bind_group {
    use std::collections::{HashMap, HashSet};

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

    /// Creates a bind group by looking up resources by reflected parameter name.
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

    /// Creates a bind group from named resources, preferring reflected order.
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

    /// Proves that a graph-managed pass binds exactly the resources present in
    /// shader reflection. This catches stale shader artifacts and optimizer
    /// changes which would otherwise make a named resource silently disappear.
    pub fn validate_exact_binding_names(
        pass: &PassData,
        set_index: usize,
        bindings: &[(&str, wgpu::BindingResource<'_>)],
    ) -> Result<()> {
        let reflected = reflected_parameters_for_set(&pass.reflection, set_index)
            .iter()
            .filter(|parameter| parameter.binding.index.is_some() && parameter.ty.kind.is_some())
            .map(|parameter| parameter.name.as_str())
            .collect::<HashSet<_>>();
        let provided = bindings
            .iter()
            .map(|(name, _)| *name)
            .collect::<HashSet<_>>();
        if provided.len() != bindings.len() {
            return Err(anyhow!(
                "duplicate named resource in graph-managed bind group for '{}'",
                pass.shader_id
            ));
        }
        if reflected != provided {
            let mut missing = reflected.difference(&provided).copied().collect::<Vec<_>>();
            let mut unexpected = provided.difference(&reflected).copied().collect::<Vec<_>>();
            missing.sort_unstable();
            unexpected.sort_unstable();
            return Err(anyhow!(
                "graph-managed shader '{}' binding contract differs from reflection: missing {:?}, unexpected {:?}",
                pass.shader_id,
                missing,
                unexpected
            ));
        }
        Ok(())
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

/// WebGPU maximum workgroup count per dispatch dimension used by the planner.
pub const MAX_GROUPS_PER_DIM: u32 = 65_535;

/// Compute (gx, gy, gz) for a pass, reusing the same rules everywhere.
/// This is the *only* place that knows about the 65_535 limit and D1-to-D2 tiling.
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
/// Cache of reflected bind groups keyed by shader id.
pub struct BindGroupCache {
    // Keyed by shader id (label) to its vector of bind groups (per set index)
    map: HashMap<String, Vec<Arc<wgpu::BindGroup>>>,
}

impl BindGroupCache {
    /// Creates an empty bind group cache.
    pub fn new() -> Self {
        Self {
            map: HashMap::new(),
        }
    }
    /// Clears all cached bind groups.
    pub fn clear(&mut self) {
        self.map.clear();
    }

    /// Removes cached bind groups for one shader id.
    pub fn remove(&mut self, shader_id: &str) {
        self.map.remove(shader_id);
    }

    /// Returns reflected bind groups for raw `PassData`, reusing them while the
    /// owning phase's resident buffer identities remain stable.
    pub(crate) fn reflected_for_pass_data<'a>(
        &mut self,
        device: &wgpu::Device,
        label: &str,
        pass: &PassData,
        resources: &HashMap<String, wgpu::BindingResource<'a>>,
    ) -> Result<Vec<Arc<wgpu::BindGroup>>, anyhow::Error> {
        let cache_key = format!("{}::raw::{label}", pass.shader_id);
        if let Some(groups) = self.map.get(&cache_key)
            && groups.len() == pass.bind_group_layouts.len()
        {
            return Ok(groups.clone());
        }
        let groups = pass
            .bind_group_layouts
            .iter()
            .enumerate()
            .map(|(set_index, layout)| {
                bind_group::create_bind_group_from_reflection(
                    device,
                    Some(label),
                    layout,
                    &pass.reflection,
                    set_index,
                    resources,
                )
                .map(Arc::new)
            })
            .collect::<Result<Vec<_>, _>>()?;
        self.map.insert(cache_key, groups.clone());
        Ok(groups)
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

/// Records multiple compatible passes into one compute pass.
pub struct ComputePassBatch<'encoder> {
    pass: wgpu::ComputePass<'encoder>,
    retained_bind_groups: Vec<Vec<Arc<wgpu::BindGroup>>>,
}

impl<'encoder> ComputePassBatch<'encoder> {
    /// Begins a batched compute pass.
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

    /// Records one pre-bound direct dispatch into this compute pass.
    pub(crate) fn record_raw(
        &mut self,
        pass: &'encoder PassData,
        bind_group: &'encoder wgpu::BindGroup,
        n_elements: u32,
    ) -> Result<()> {
        let [tgsx, tgsy, _] = pass.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(n_elements),
            [tgsx, tgsy, 1],
        )?;
        self.pass.set_pipeline(&pass.pipeline);
        self.pass.set_bind_group(0, Some(bind_group), &[]);
        self.pass.dispatch_workgroups(gx, gy, gz);
        Ok(())
    }

    /// Records one pre-bound indirect dispatch into this compute pass.
    pub(crate) fn record_raw_indirect(
        &mut self,
        pass: &'encoder PassData,
        bind_group: &'encoder wgpu::BindGroup,
        dispatch_args: &'encoder wgpu::Buffer,
    ) {
        self.pass.set_pipeline(&pass.pipeline);
        self.pass.set_bind_group(0, Some(bind_group), &[]);
        self.pass.dispatch_workgroups_indirect(dispatch_args, 0);
    }

    /// Records one reflected pass using cached bind groups.
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

    /// Records one indirect-dispatch pass using cached bind groups.
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

/// Reflected compute-pass wrapper that can bind phase buffers and record dispatches.
///
/// Generated shader pass structs implement this trait to connect static pass
/// metadata with runtime GPU resources. `Buffers` is the resident buffer bundle
/// owned by the compiler phase, while `DebugOutput` is the optional phase-specific
/// readback sink populated after dispatch.
pub trait Pass<Buffers, DebugOutput> {
    /// Stable pass label used for validation scopes, tracing, and timing output.
    const NAME: &'static str;

    /// Logical input shape used to translate an element count into workgroups.
    const DIM: DispatchDim;

    /// Builds the wrapper from precompiled pipeline and reflection data.
    fn from_data(data: PassData) -> Self
    where
        Self: Sized;

    /// Returns the reflected pipeline data shared by all dispatch paths.
    fn data(&self) -> &PassData;

    /// Maps shader binding names to the resident buffers used by this pass.
    fn create_resource_map<'a>(
        &self,
        buffers: &'a Buffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>>;

    /// Records a direct dispatch for this pass into the shared pass context.
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

        if !defer_compute_direct_bind_groups(pd, &bind_groups, (gx, gy, gz)) {
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
        }

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

    /// Records an indirect dispatch whose workgroup counts are read from a GPU buffer.
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

        if !defer_compute_indirect_bind_groups(pd, &bind_groups, dispatch_args) {
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
        }

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

    /// Records any phase-specific debug readback work after the main dispatch.
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
