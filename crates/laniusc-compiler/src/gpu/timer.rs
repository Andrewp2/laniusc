//! Simple per-encode GPU timestamp helper. Not thread-safe; create per "frame"/encode.

use std::sync::{
    Arc,
    Mutex,
    atomic::{AtomicU64, Ordering},
};

use log::warn;
use wgpu;

static OPERATION_CAPTURE_SCOPE_COUNT: AtomicU64 = AtomicU64::new(0);
static OPERATION_TIMESTAMP_COUNT: AtomicU64 = AtomicU64::new(0);

thread_local! {
    static ACTIVE_OPERATION_TIMER: std::cell::RefCell<Vec<Arc<Mutex<GpuTimerRecordingState>>>> =
        const { std::cell::RefCell::new(Vec::new()) };
}

/// Stable compiler phase attached to every measured GPU interval.
///
/// There is deliberately no `Unknown` or `Orchestration` variant: executing
/// GPU work without a compiler phase is an instrumentation contract error.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum GpuCompilerPhase {
    Lexing,
    Parsing,
    HirConstruction,
    TypeChecking,
    SemanticInterface,
    Optimization,
    Lowering,
    X86Emission,
    WasmEmission,
    ArtifactEmission,
}

impl GpuCompilerPhase {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Lexing => "lexing",
            Self::Parsing => "parsing",
            Self::HirConstruction => "hir_construction",
            Self::TypeChecking => "type_checking",
            Self::SemanticInterface => "semantic_interface",
            Self::Optimization => "optimization",
            Self::Lowering => "lowering",
            Self::X86Emission => "x86_emission",
            Self::WasmEmission => "wasm_emission",
            Self::ArtifactEmission => "artifact_emission",
        }
    }
}

#[derive(Clone, Debug)]
pub struct GpuTimestampSample {
    pub label: String,
    pub phase: GpuCompilerPhase,
    pub ticks: u64,
}

/// Default minimum span duration printed by timing helpers.
pub const MINIMUM_TIME_TO_NOT_ELIDE_MS: f64 = 0.2;

/// Query capacity for one fully attributed compiler job. Exhaustion is a hard
/// profiling error so captures can never silently omit kernel events.
pub const COMPILE_QUERY_CAPACITY: u32 = 4_096;

/// Returns whether compile GPU timestamps are needed for console output or tracing.
pub(crate) fn compile_timing_requested() -> bool {
    crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_TIMING", false)
        || crate::gpu::env::env_bool_truthy("LANIUS_GPU_TIMING", false)
        || crate::gpu::trace::enabled()
}

/// A timer for measuring GPU execution time.
pub struct GpuTimer {
    period_in_nanoseconds: f32,
    resolve_buffer: wgpu::Buffer,
    readback_buffer: wgpu::Buffer,
    recording: Arc<Mutex<GpuTimerRecordingState>>,
}

struct GpuTimerRecordingState {
    query_set: wgpu::QuerySet,
    next: u32,
    capacity: u32,
    phase: GpuCompilerPhase,
    timestamps_inside_passes: bool,
    operation_capture_enabled: bool,
    stamp_metadata: Vec<(String, GpuCompilerPhase)>,
}

/// Installs one timer at the generic GPU-operation recording boundary.
///
/// The guard owns a reference-counted recording handle rather than borrowing
/// the timer, so compiler phases may continue to change phase metadata while
/// the scope is active. Nested phase helpers may reuse the same timer, while a
/// second timer is rejected so one command stream has one timing owner.
pub struct GpuOperationCaptureGuard {
    recording: Arc<Mutex<GpuTimerRecordingState>>,
}

impl Drop for GpuOperationCaptureGuard {
    fn drop(&mut self) {
        ACTIVE_OPERATION_TIMER.with(|active| {
            let popped = active
                .borrow_mut()
                .pop()
                .expect("GPU operation timing scope stack underflow");
            assert!(
                Arc::ptr_eq(&popped, &self.recording),
                "GPU operation timing scopes must be dropped in stack order"
            );
        });
    }
}

impl GpuTimer {
    /// Creates a new GpuTimer with the given maximum number of queries.
    pub fn new(
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        max_queries: u32,
        phase: GpuCompilerPhase,
    ) -> Self {
        let query_set = device.create_query_set(&wgpu::QuerySetDescriptor {
            label: Some("LaniusTimestamps"),
            ty: wgpu::QueryType::Timestamp,
            count: max_queries,
        });

        let resolve_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("TimestampResolve"),
            size: (max_queries as u64) * 8,
            usage: wgpu::BufferUsages::QUERY_RESOLVE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });

        let readback_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("TimestampReadback"),
            size: (max_queries as u64) * 8,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });

        Self {
            period_in_nanoseconds: queue.get_timestamp_period(),
            resolve_buffer,
            readback_buffer,
            recording: Arc::new(Mutex::new(GpuTimerRecordingState {
                query_set,
                next: 0,
                capacity: max_queries,
                phase,
                timestamps_inside_passes: device
                    .features()
                    .contains(wgpu::Features::TIMESTAMP_QUERY_INSIDE_PASSES),
                operation_capture_enabled: false,
                stamp_metadata: vec![],
            })),
        }
    }

    /// Makes every generic compute operation emit its own timestamp until the
    /// returned scope guard is dropped.
    pub fn capture_operations(&self) -> GpuOperationCaptureGuard {
        OPERATION_CAPTURE_SCOPE_COUNT.fetch_add(1, Ordering::Relaxed);
        self.recording
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .operation_capture_enabled = true;
        ACTIVE_OPERATION_TIMER.with(|active| {
            let mut active = active.borrow_mut();
            if let Some(current) = active.last() {
                assert!(
                    Arc::ptr_eq(current, &self.recording),
                    "nested GPU operation timing scopes must use the same timer"
                );
            }
            active.push(self.recording.clone());
        });
        GpuOperationCaptureGuard {
            recording: self.recording.clone(),
        }
    }

    /// Changes the phase inherited by subsequent timestamp stamps.
    pub fn set_phase(&mut self, phase: GpuCompilerPhase) {
        self.recording
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .phase = phase;
    }

    /// Records a timestamp with the given label.
    pub fn stamp(&mut self, enc: &mut wgpu::CommandEncoder, label: impl Into<String>) -> u32 {
        let label = label.into();
        // Once this timer has adopted operation-level capture, hand-written
        // milestones must never become synthetic GPU intervals between
        // kernels. Submission boundaries remain as timeline anchors.
        let captured_automatically = self
            .recording
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .operation_capture_enabled;
        if captured_automatically && !is_submission_boundary(&label) {
            return self
                .recording
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .next
                .saturating_sub(1);
        }
        stamp_recording(&self.recording, enc, label)
    }

    /// Resets the timer.
    pub fn reset(&mut self) {
        let mut recording = self
            .recording
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        recording.stamp_metadata.clear();
        recording.next = 0;
        recording.operation_capture_enabled = false;
    }

    /// Resolves the timestamp queries.
    pub fn resolve(&self, encoder: &mut wgpu::CommandEncoder) {
        let recording = self
            .recording
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let query_count = recording.next;
        if query_count == 0 {
            return;
        }
        encoder.resolve_query_set(
            &recording.query_set,
            0..query_count,
            &self.resolve_buffer,
            0,
        );
        encoder.copy_buffer_to_buffer(
            &self.resolve_buffer,
            0,
            &self.readback_buffer,
            0,
            (query_count as u64) * 8,
        );
    }

    /// Attempts to read the recorded timestamps.
    pub fn try_read(&self, device: &wgpu::Device) -> Option<Vec<GpuTimestampSample>> {
        let recording = self
            .recording
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let query_count = recording.next;
        if query_count == 0 {
            return None;
        }
        let slice = self.readback_buffer.slice(..(query_count as u64) * 8);
        let (sender, receiver) = std::sync::mpsc::channel();
        crate::gpu::passes_core::trace_gpu_progress("gpu.timer.readback.map.start");
        slice.map_async(wgpu::MapMode::Read, move |v| {
            if let Err(err) = sender.send(v) {
                warn!("failed to send timer readback completion signal: {err}");
            }
        });
        crate::gpu::passes_core::trace_gpu_progress("gpu.timer.readback.map.queued");
        crate::gpu::passes_core::wait_for_map_progress(
            device,
            "gpu.timer.readback",
            wgpu::PollType::wait_indefinitely(),
        );

        if let Ok(Ok(())) = receiver.try_recv() {
            let data = slice.get_mapped_range().to_vec();
            let mut vals = Vec::with_capacity(query_count as usize);
            for chunk in data.chunks_exact(8) {
                let mut arr = [0u8; 8];
                arr.copy_from_slice(chunk);
                vals.push(u64::from_le_bytes(arr));
            }
            drop(data);
            self.readback_buffer.unmap();

            let mut out = Vec::with_capacity(query_count as usize);
            for (i, val) in vals.iter().enumerate() {
                let (label, phase) = &recording.stamp_metadata[i];
                out.push(GpuTimestampSample {
                    label: label.clone(),
                    phase: *phase,
                    ticks: *val,
                });
            }
            Some(out)
        } else {
            None
        }
    }

    /// Returns the timestamp period in nanoseconds.
    pub fn period_ns(&self) -> f32 {
        self.period_in_nanoseconds
    }
}

/// Returns whether generic compute recording is currently being timed.
pub(crate) fn operation_capture_active() -> bool {
    ACTIVE_OPERATION_TIMER.with(|active| !active.borrow().is_empty())
}

/// Returns whether the active timer can write timestamps between dispatches
/// without ending the surrounding WGPU compute pass.
pub(crate) fn operation_capture_supports_in_pass_timestamps() -> bool {
    ACTIVE_OPERATION_TIMER.with(|active| {
        active.borrow().last().is_some_and(|recording| {
            recording
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .timestamps_inside_passes
        })
    })
}

/// Returns whether profiling must retain the split-pass fallback because the
/// adapter cannot timestamp inside a compute pass.
pub(crate) fn operation_capture_requires_split_passes() -> bool {
    operation_capture_active() && !operation_capture_supports_in_pass_timestamps()
}

/// Process-wide count used to enforce complete profiled-job coverage.
pub(crate) fn operation_capture_scope_count() -> u64 {
    OPERATION_CAPTURE_SCOPE_COUNT.load(Ordering::Relaxed)
}

/// Process-wide count of dispatch-boundary timestamps.
pub(crate) fn operation_timestamp_count() -> u64 {
    OPERATION_TIMESTAMP_COUNT.load(Ordering::Relaxed)
}

/// Records the completion timestamp for one generic GPU operation.
pub(crate) fn stamp_active_operation(encoder: &mut wgpu::CommandEncoder, label: impl Into<String>) {
    ACTIVE_OPERATION_TIMER.with(|active| {
        let recording = active.borrow().last().cloned();
        if let Some(recording) = recording {
            stamp_recording(&recording, encoder, label.into());
            OPERATION_TIMESTAMP_COUNT.fetch_add(1, Ordering::Relaxed);
        }
    });
}

/// Records one kernel completion while its batched compute pass remains open.
pub(crate) fn stamp_active_operation_in_pass(
    pass: &mut wgpu::ComputePass<'_>,
    label: impl Into<String>,
) {
    ACTIVE_OPERATION_TIMER.with(|active| {
        let recording = active.borrow().last().cloned();
        if let Some(recording) = recording {
            assert!(
                recording
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .timestamps_inside_passes,
                "batched GPU operation timing requires TIMESTAMP_QUERY_INSIDE_PASSES"
            );
            let (query_set, index) = reserve_timestamp(&recording, label.into());
            pass.write_timestamp(&query_set, index);
            OPERATION_TIMESTAMP_COUNT.fetch_add(1, Ordering::Relaxed);
        }
    });
}

fn stamp_recording(
    recording: &Arc<Mutex<GpuTimerRecordingState>>,
    encoder: &mut wgpu::CommandEncoder,
    label: String,
) -> u32 {
    let (query_set, index) = reserve_timestamp(recording, label);
    encoder.write_timestamp(&query_set, index);
    index
}

fn reserve_timestamp(
    recording: &Arc<Mutex<GpuTimerRecordingState>>,
    label: String,
) -> (wgpu::QuerySet, u32) {
    let mut recording = recording
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    assert!(
        recording.next < recording.capacity,
        "GPU operation timing query capacity {} exhausted while recording `{label}`; increase the timer capacity instead of silently dropping GPU events",
        recording.capacity,
    );
    let index = recording.next;
    recording.next += 1;
    let phase = recording.phase;
    recording.stamp_metadata.push((label, phase));
    (recording.query_set.clone(), index)
}

fn is_submission_boundary(label: &str) -> bool {
    label.ends_with(".submission.begin")
}
