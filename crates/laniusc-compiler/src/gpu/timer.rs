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
static OPERATION_TIMESTAMPS_DROPPED: AtomicU64 = AtomicU64::new(0);

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

/// Query capacity for one compiler phase timer. Exhaustion is a hard
/// profiling error so captures can never silently omit kernel events.
pub const COMPILE_QUERY_CAPACITY: u32 = 4_096;

/// Most timestamps one job timing session holds. A session spans a whole job,
/// whose dispatch count grows with the program: a generic 1 MB unit with 184
/// monomorphization replays stamps 8,681 operations more than the 4,096 one
/// WGPU query set holds. So the session adds query sets as it fills them, and
/// only past this bound stops stamping and counts the stamps it dropped
/// (`operation_timestamps_dropped`), which fails the profiled job.
pub(crate) const JOB_SESSION_QUERY_CAPACITY: u32 = 256 * wgpu::QUERY_SET_MAX_QUERIES;

/// Returns whether compile GPU timestamps are needed for console output or tracing.
pub(crate) fn compile_timing_requested() -> bool {
    crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_TIMING", false)
        || crate::gpu::env::env_bool_truthy("LANIUS_GPU_TIMING", false)
        || crate::gpu::trace::enabled()
}

/// A timer for measuring GPU execution time.
pub struct GpuTimer {
    period_in_nanoseconds: f32,
    buffers: Mutex<TimestampBuffers>,
    recording: Arc<Mutex<GpuTimerRecordingState>>,
}

/// Where `GpuTimer::resolve` copies the timestamps for `try_read`.
struct TimestampBuffers {
    resolve: wgpu::Buffer,
    readback: wgpu::Buffer,
    /// Timestamps the buffers hold.
    queries: u32,
    /// Timestamps the last `resolve` copied into `readback`.
    resolved: u32,
}

impl TimestampBuffers {
    fn new(device: &wgpu::Device, queries: u32) -> Self {
        let size = u64::from(queries) * u64::from(wgpu::QUERY_SIZE);
        Self {
            resolve: device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("TimestampResolve"),
                size,
                usage: wgpu::BufferUsages::QUERY_RESOLVE | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            }),
            readback: device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("TimestampReadback"),
                size,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            }),
            queries,
            resolved: 0,
        }
    }
}

struct GpuTimerRecordingState {
    /// Timestamp `i` is query `i % queries_per_set` of `query_sets[i /
    /// queries_per_set]`. A timer whose capacity exceeds one WGPU query set
    /// creates the later sets when it first needs them.
    query_sets: Vec<wgpu::QuerySet>,
    queries_per_set: u32,
    device: wgpu::Device,
    next: u32,
    capacity: u32,
    phase: GpuCompilerPhase,
    timestamps_inside_passes: bool,
    operation_capture_enabled: bool,
    /// Set for a `GpuJobTimingSession`: it owns operations recorded outside
    /// every phase timer, and phase timers may nest inside it.
    job_session: bool,
    stamp_metadata: Vec<(String, GpuCompilerPhase)>,
}

/// Installs one timer at the generic GPU-operation recording boundary.
///
/// The guard owns a reference-counted recording handle rather than borrowing
/// the timer, so compiler phases may continue to change phase metadata while
/// the scope is active. Nested phase helpers may reuse the same timer, while a
/// second timer is rejected so one command stream has one timing owner. The
/// one exception is a job timing session, which only owns work that no phase
/// timer records; a phase timer nested inside it takes over until it ends.
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
    /// Creates a new GpuTimer with the given maximum number of queries. Up to
    /// `wgpu::QUERY_SET_MAX_QUERIES` are allocated now, the rest as needed.
    pub fn new(
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        max_queries: u32,
        phase: GpuCompilerPhase,
    ) -> Self {
        let queries_per_set = max_queries.clamp(1, wgpu::QUERY_SET_MAX_QUERIES);
        Self {
            period_in_nanoseconds: queue.get_timestamp_period(),
            buffers: Mutex::new(TimestampBuffers::new(device, queries_per_set)),
            recording: Arc::new(Mutex::new(GpuTimerRecordingState {
                query_sets: vec![create_query_set(device, queries_per_set)],
                queries_per_set,
                device: device.clone(),
                next: 0,
                capacity: max_queries,
                phase,
                timestamps_inside_passes: device
                    .features()
                    .contains(wgpu::Features::TIMESTAMP_QUERY_INSIDE_PASSES),
                operation_capture_enabled: false,
                job_session: false,
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
                let nested_in_job_session = current
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner)
                    .job_session;
                assert!(
                    Arc::ptr_eq(current, &self.recording) || nested_in_job_session,
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
        self.buffers
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .resolved = 0;
    }

    /// Resolves the timestamp queries recorded so far for `try_read`.
    pub fn resolve(&self, encoder: &mut wgpu::CommandEncoder) {
        let recording = self
            .recording
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let query_count = recording.next;
        if query_count == 0 {
            return;
        }
        let mut buffers = self
            .buffers
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if buffers.queries < query_count {
            *buffers = TimestampBuffers::new(
                &recording.device,
                query_count.next_multiple_of(recording.queries_per_set),
            );
        }
        // A timer with more than one set has full sets of
        // QUERY_SET_MAX_QUERIES, so every set's destination offset is a
        // multiple of QUERY_RESOLVE_BUFFER_ALIGNMENT.
        for (set, query_set) in recording.query_sets.iter().enumerate() {
            let first = set as u32 * recording.queries_per_set;
            if first >= query_count {
                break;
            }
            let queries = (query_count - first).min(recording.queries_per_set);
            encoder.resolve_query_set(
                query_set,
                0..queries,
                &buffers.resolve,
                u64::from(first) * u64::from(wgpu::QUERY_SIZE),
            );
        }
        encoder.copy_buffer_to_buffer(
            &buffers.resolve,
            0,
            &buffers.readback,
            0,
            u64::from(query_count) * u64::from(wgpu::QUERY_SIZE),
        );
        buffers.resolved = query_count;
    }

    /// Attempts to read the timestamps the last `resolve` copied out.
    pub fn try_read(&self, device: &wgpu::Device) -> Option<Vec<GpuTimestampSample>> {
        let recording = self
            .recording
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let buffers = self
            .buffers
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let query_count = buffers.resolved.min(recording.next);
        if query_count == 0 {
            return None;
        }
        let slice = buffers
            .readback
            .slice(..u64::from(query_count) * u64::from(wgpu::QUERY_SIZE));
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
            buffers.readback.unmap();

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

/// Process-wide count of operation timestamps a job timing session dropped
/// because it held `JOB_SESSION_QUERY_CAPACITY` timestamps already.
pub(crate) fn operation_timestamps_dropped() -> u64 {
    OPERATION_TIMESTAMPS_DROPPED.load(Ordering::Relaxed)
}

/// Records the completion timestamp for one generic GPU operation.
pub(crate) fn stamp_active_operation(encoder: &mut wgpu::CommandEncoder, label: impl Into<String>) {
    ACTIVE_OPERATION_TIMER.with(|active| {
        let recording = active.borrow().last().cloned();
        if let Some(recording) = recording {
            if job_session_full(&recording, 0) {
                // The job then fails the timestamp coverage check instead of
                // panicking the daemon.
                OPERATION_TIMESTAMPS_DROPPED.fetch_add(1, Ordering::Relaxed);
                return;
            }
            stamp_recording(&recording, encoder, label.into());
            OPERATION_TIMESTAMP_COUNT.fetch_add(1, Ordering::Relaxed);
        }
    });
}

/// Whether `recording` is a job timing session with at most `reserve` free
/// queries. Sessions span whole jobs, whose dispatch counts grow with the
/// program, so past `JOB_SESSION_QUERY_CAPACITY` they stop stamping instead of
/// panicking the daemon.
fn job_session_full(recording: &Arc<Mutex<GpuTimerRecordingState>>, reserve: u32) -> bool {
    let recording = recording
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    recording.job_session && recording.next + reserve >= recording.capacity
}

/// Records one kernel completion while its batched compute pass remains open.
pub(crate) fn stamp_active_operation_in_pass(
    pass: &mut wgpu::ComputePass<'_>,
    label: impl Into<String>,
) {
    ACTIVE_OPERATION_TIMER.with(|active| {
        let recording = active.borrow().last().cloned();
        if let Some(recording) = recording {
            if job_session_full(&recording, 0) {
                OPERATION_TIMESTAMPS_DROPPED.fetch_add(1, Ordering::Relaxed);
                return;
            }
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

/// Marks the start of a compute pass that the job timing session owns. Its
/// operations are spread over many submissions, so without this boundary the
/// first kernel of each pass would absorb the host time since the previous
/// session stamp. The boundary is a submission gap, not an operation stamp.
pub(crate) fn stamp_job_session_pass_begin(encoder: &mut wgpu::CommandEncoder, label: &str) {
    ACTIVE_OPERATION_TIMER.with(|active| {
        let recording = active.borrow().last().cloned();
        if let Some(recording) = recording {
            let job_session = recording
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .job_session;
            // Pass boundaries only refine attribution: keep the last quarter
            // of the session's capacity for operation stamps.
            let reserve = JOB_SESSION_QUERY_CAPACITY / 4;
            if job_session && !job_session_full(&recording, reserve) {
                stamp_recording(&recording, encoder, format!("{label}.submission.begin"));
            }
        }
    });
}

/// Marks the start of an encoder that continues a recording split by a partial
/// submit (a readback, an inference round, a dependency page, or a prefix
/// submitted early). The commands before the split ran in an earlier
/// submission, so without this boundary the next operation's span would also
/// cover the GPU idle time between the two submissions. The boundary is a
/// submission gap, not an operation stamp.
pub(crate) fn stamp_active_submission_begin(encoder: &mut wgpu::CommandEncoder, label: &str) {
    ACTIVE_OPERATION_TIMER.with(|active| {
        let recording = active.borrow().last().cloned();
        if let Some(recording) = recording {
            let room = {
                let recording = recording
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                // Boundaries only refine attribution: keep the last quarter
                // of the query set for operation stamps.
                recording.next + recording.capacity / 4 < recording.capacity
            };
            if room {
                stamp_recording(&recording, encoder, format!("{label}.submission.begin"));
            }
        }
    });
}

/// One GPU timestamp observed at a known host instant: the trace places every
/// timer's spans of the current job through it.
#[derive(Clone, Copy, Debug)]
pub(crate) struct GpuClockCalibration {
    pub(crate) host: std::time::Instant,
    pub(crate) ticks: u64,
}

static GPU_CLOCK_CALIBRATION: Mutex<Option<GpuClockCalibration>> = Mutex::new(None);

/// The active job's GPU clock calibration, when a traced job session set one.
pub(crate) fn gpu_clock_calibration() -> Option<GpuClockCalibration> {
    *GPU_CLOCK_CALIBRATION
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}

fn set_gpu_clock_calibration(calibration: Option<GpuClockCalibration>) {
    *GPU_CLOCK_CALIBRATION
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner) = calibration;
}

/// Times the GPU operations of one compiler job that no phase timer records,
/// such as program evidence and the x86 link, so a profiled job stamps every
/// dispatch it records. Phase timers nest inside it.
pub struct GpuJobTimingSession {
    timer: GpuTimer,
    gpu_anchor: std::time::Instant,
    capture: Option<GpuOperationCaptureGuard>,
}

impl GpuJobTimingSession {
    /// Starts a session when compile timing or tracing is requested.
    pub fn begin(device: &wgpu::Device, queue: &wgpu::Queue) -> Option<Self> {
        if !compile_timing_requested() {
            return None;
        }
        let mut timer = GpuTimer::new(
            device,
            queue,
            JOB_SESSION_QUERY_CAPACITY,
            GpuCompilerPhase::ArtifactEmission,
        );
        timer
            .recording
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .job_session = true;
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("gpu.job_timing.begin"),
        });
        timer.stamp(&mut encoder, "gpu.job_timing.begin");
        // A traced job reads its first stamp back right away: the GPU is idle
        // between jobs, so the stamp ran just after this submit returned, and
        // that pairing places every later timestamp of the job. Phase timers'
        // own anchors are wrong whenever their first stamp ran in an earlier
        // partial submit than the one they anchor to.
        let calibrate = crate::gpu::trace::enabled();
        if calibrate {
            timer.resolve(&mut encoder);
        }
        let gpu_anchor = crate::gpu::passes_core::submit_with_progress(
            queue,
            "gpu.job_timing.begin",
            encoder.finish(),
        )
        .gpu_anchor;
        set_gpu_clock_calibration(None);
        if calibrate && let Some(stamps) = timer.try_read(device) {
            set_gpu_clock_calibration(Some(GpuClockCalibration {
                host: gpu_anchor,
                ticks: stamps[0].ticks,
            }));
        }
        let capture = Some(timer.capture_operations());
        Some(Self {
            timer,
            gpu_anchor,
            capture,
        })
    }

    /// Ends the session. When `record` is set, reads its timestamps and adds
    /// their GPU spans to the trace. Only pass `record` for a job that
    /// completed: every stamped encoder must have been submitted, because
    /// resolving a timestamp that was never written waits forever.
    pub fn finish(mut self, device: &wgpu::Device, queue: &wgpu::Queue, record: bool) {
        self.capture = None;
        if !record {
            set_gpu_clock_calibration(None);
            return;
        }
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("gpu.job_timing.resolve"),
        });
        self.timer.resolve(&mut encoder);
        queue.submit(Some(encoder.finish()));
        if let Some(stamps) = self.timer.try_read(device) {
            crate::lexer::driver::timing::print_timer_trace(
                &stamps,
                self.timer.period_ns(),
                self.gpu_anchor,
            );
        }
        set_gpu_clock_calibration(None);
    }
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
    let set = (index / recording.queries_per_set) as usize;
    if set == recording.query_sets.len() {
        let query_set = create_query_set(&recording.device, recording.queries_per_set);
        recording.query_sets.push(query_set);
    }
    recording.next += 1;
    let phase = recording.phase;
    recording.stamp_metadata.push((label, phase));
    (
        recording.query_sets[set].clone(),
        index % recording.queries_per_set,
    )
}

fn create_query_set(device: &wgpu::Device, queries: u32) -> wgpu::QuerySet {
    device.create_query_set(&wgpu::QuerySetDescriptor {
        label: Some("LaniusTimestamps"),
        ty: wgpu::QueryType::Timestamp,
        count: queries,
    })
}

fn is_submission_boundary(label: &str) -> bool {
    label.ends_with(".submission.begin")
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A job-session timer on the physical GPU, or None when the adapter
    /// cannot write timestamps between commands.
    fn job_session_timer(
        capacity: u32,
    ) -> Option<(&'static crate::gpu::device::GpuDevice, GpuTimer)> {
        let gpu = crate::gpu::device::global();
        let needed =
            wgpu::Features::TIMESTAMP_QUERY | wgpu::Features::TIMESTAMP_QUERY_INSIDE_ENCODERS;
        if !gpu.device.features().contains(needed) {
            return None;
        }
        let timer = GpuTimer::new(
            &gpu.device,
            &gpu.queue,
            capacity,
            GpuCompilerPhase::ArtifactEmission,
        );
        timer.recording.lock().unwrap().job_session = true;
        Some((gpu, timer))
    }

    fn encoder(gpu: &crate::gpu::device::GpuDevice) -> wgpu::CommandEncoder {
        gpu.device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.job_session_timestamps"),
            })
    }

    #[test]
    fn physical_gpu_job_session_stamps_past_one_query_set() {
        let Some((gpu, timer)) = job_session_timer(JOB_SESSION_QUERY_CAPACITY) else {
            return;
        };
        let operations = 2 * wgpu::QUERY_SET_MAX_QUERIES + 100;
        let mut encoder = encoder(gpu);
        {
            let _capture = timer.capture_operations();
            for operation in 0..operations {
                stamp_active_operation(&mut encoder, format!("op{operation}"));
            }
        }
        timer.resolve(&mut encoder);
        gpu.queue.submit(Some(encoder.finish()));
        let stamps = timer
            .try_read(&gpu.device)
            .expect("read the job session's timestamps");

        assert_eq!(timer.recording.lock().unwrap().query_sets.len(), 3);
        assert_eq!(stamps.len(), operations as usize);
        for (operation, stamp) in stamps.iter().enumerate() {
            assert_eq!(stamp.label, format!("op{operation}"));
        }
        // Unwritten queries resolve to zero, so ordered nonzero ticks show
        // every set was written and resolved to its own offset.
        assert!(stamps[0].ticks > 0);
        assert!(
            stamps.windows(2).all(|pair| pair[0].ticks <= pair[1].ticks),
            "timestamps out of order across query sets"
        );
    }

    #[test]
    fn physical_gpu_full_job_session_counts_the_stamps_it_drops() {
        let Some((gpu, timer)) = job_session_timer(3) else {
            return;
        };
        let dropped_before = operation_timestamps_dropped();
        let mut encoder = encoder(gpu);
        {
            let _capture = timer.capture_operations();
            for operation in 0..5 {
                stamp_active_operation(&mut encoder, format!("op{operation}"));
            }
        }
        assert_eq!(operation_timestamps_dropped() - dropped_before, 2);
        timer.resolve(&mut encoder);
        gpu.queue.submit(Some(encoder.finish()));
        let stamps = timer.try_read(&gpu.device).expect("read the stamps kept");
        assert_eq!(stamps.len(), 3);
    }
}
