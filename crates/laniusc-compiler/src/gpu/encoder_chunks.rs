//! Chunked command encoding: wgpu validates and encodes every recorded
//! command in `CommandEncoder::finish` (about 4-9 us per dispatch on the
//! laptop), and a long recording otherwise pays all of it at its submit
//! point while the GPU waits. Inside a [`ChunkedEncoding`] scope the
//! registered encoder is cut at compute-batch flushes once enough dispatches
//! have accumulated; each cut-off chunk is finished on a worker thread while
//! recording continues.
//!
//! Chunks never get a submission of their own. Whoever submits the
//! registered encoder takes its finished chunks ([`take`]) and submits them
//! first, in recording order, in the same `Queue::submit` as the rest. A
//! submit applies every pending `Queue::write_buffer` before all of its
//! command buffers, so what each command sees is unchanged, and other
//! encoders' submissions keep their order relative to this one.
//!
//! Batched dispatches reach the encoder only when the deferred compute batch
//! flushes, so a registered encoder's batch is also flushed every
//! `LANIUS_ENCODER_CHUNK_DISPATCHES` commands ([`after_deferred`]); the extra
//! pass boundary costs about 25-35 us of GPU time against 4-9 us of finish
//! per dispatch moved off the submit path.
//!
//! `LANIUS_ENCODER_FINISH_THREADS=0` turns chunking off (default 4 workers);
//! `LANIUS_ENCODER_CHUNK_DISPATCHES` sets the cut size (default 96).
//! Validation scopes disable it: their error scopes belong to the recording
//! thread.
//!
//! The write-order check ([`note_queue_write`]) records which buffer ranges
//! each cut chunk accesses (bound by its dispatches, cleared or copied) and
//! flags a `Queue::write_buffer` that touches one before the chunk's
//! submission. Today that write still reaches the chunk (the chunk is
//! submitted with its encoder); a chunk submitted when it is cut would miss
//! it. Unit tests and debug builds run the check and print what it flags;
//! `LANIUS_ENCODER_CHUNK_WRITE_CHECK=1` runs it in any build and also lists
//! every write of the scope, with a per-scope summary, and `=panic` makes a
//! flagged write panic.

use std::{
    cell::RefCell,
    collections::HashMap,
    sync::{Arc, LazyLock, Mutex, OnceLock, mpsc},
};

struct FinishJob {
    device: wgpu::Device,
    dispatches: u64,
    encoder: wgpu::CommandEncoder,
    done: mpsc::Sender<FinishedChunk>,
}

/// A finished chunk and the errors its `finish` raised. Error scopes are
/// per thread, so the worker captures them and the submitting thread
/// reports them.
struct FinishedChunk {
    commands: wgpu::CommandBuffer,
    errors: Vec<wgpu::Error>,
}

struct FinishPool {
    jobs: Mutex<mpsc::Sender<FinishJob>>,
}

fn finish_threads() -> usize {
    static THREADS: OnceLock<usize> = OnceLock::new();
    // `env_u64` rejects 0, which is the off switch here.
    *THREADS.get_or_init(|| {
        std::env::var("LANIUS_ENCODER_FINISH_THREADS")
            .ok()
            .and_then(|value| value.trim().parse::<usize>().ok())
            .unwrap_or(4)
            .min(16)
    })
}

fn chunk_dispatches() -> u64 {
    static DISPATCHES: OnceLock<u64> = OnceLock::new();
    *DISPATCHES
        .get_or_init(|| crate::gpu::env::env_u64("LANIUS_ENCODER_CHUNK_DISPATCHES", 96).max(1))
}

fn pool() -> &'static FinishPool {
    static POOL: OnceLock<FinishPool> = OnceLock::new();
    POOL.get_or_init(|| {
        let (jobs, receiver) = mpsc::channel::<FinishJob>();
        let receiver = std::sync::Arc::new(Mutex::new(receiver));
        for worker in 0..finish_threads().max(1) {
            let receiver = receiver.clone();
            std::thread::Builder::new()
                .name(format!("lanius-encoder-finish-{worker}"))
                .spawn(move || {
                    loop {
                        let job = {
                            let receiver =
                                receiver.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
                            receiver.recv()
                        };
                        let Ok(job) = job else {
                            return;
                        };
                        let out_of_memory =
                            job.device.push_error_scope(wgpu::ErrorFilter::OutOfMemory);
                        let validation =
                            job.device.push_error_scope(wgpu::ErrorFilter::Validation);
                        let started = std::time::Instant::now();
                        let commands = job.encoder.finish();
                        let finished = std::time::Instant::now();
                        if crate::gpu::trace::enabled() {
                            crate::gpu::trace::record_host_span(
                                "host.encoder_finish_worker",
                                "encoder_chunks.finish",
                                started,
                                finished,
                            );
                        }
                        if crate::gpu::passes_core::host_timing_enabled() {
                            eprintln!(
                                "[gpu_compile_host_timer] encoder_chunks.finish: dispatches={} finish_ms={:.3}",
                                job.dispatches,
                                finished.duration_since(started).as_secs_f64() * 1000.0,
                            );
                        }
                        let mut errors = Vec::new();
                        errors.extend(pollster::block_on(validation.pop()));
                        errors.extend(pollster::block_on(out_of_memory.pop()));
                        // The receiver only disappears when the recording
                        // thread is unwinding; nothing is left to submit.
                        let _ = job.done.send(FinishedChunk { commands, errors });
                    }
                })
                .expect("spawn encoder finish worker");
        }
        FinishPool {
            jobs: Mutex::new(jobs),
        }
    })
}

struct Chunking {
    device: wgpu::Device,
    /// Address of the registered `wgpu::CommandEncoder` variable. Callers
    /// continue a submitted recording with `std::mem::replace` on the same
    /// variable, so the address names the recording across submissions.
    encoder: usize,
    label: &'static str,
    pending: Vec<mpsc::Receiver<FinishedChunk>>,
    dispatches_at_cut: u64,
    check: Option<WriteCheck>,
}

thread_local! {
    static CHUNKING: RefCell<Option<Chunking>> = const { RefCell::new(None) };
}

fn address(encoder: &wgpu::CommandEncoder) -> usize {
    encoder as *const wgpu::CommandEncoder as usize
}

fn enabled() -> bool {
    finish_threads() > 0 && !crate::gpu::passes_core::validation_scopes_enabled()
}

/// Registers one encoder variable for chunked finishing until the guard
/// drops. Scopes do not nest: an inner scope on the same thread is inert.
/// Every submission of the encoder inside the scope must [`take`] its chunks,
/// and the scope must end with none pending.
pub(crate) struct ChunkedEncoding {
    active: bool,
}

impl ChunkedEncoding {
    pub(crate) fn begin(
        device: &wgpu::Device,
        encoder: &wgpu::CommandEncoder,
        label: &'static str,
    ) -> Self {
        if !enabled() {
            return Self { active: false };
        }
        let active = CHUNKING.with(|state| {
            let mut state = state.borrow_mut();
            if state.is_some() {
                return false;
            }
            *state = Some(Chunking {
                device: device.clone(),
                encoder: address(encoder),
                label,
                pending: Vec::new(),
                dispatches_at_cut: crate::gpu::passes_core::recorded_compute_dispatch_count(),
                check: write_check_mode().map(|_| WriteCheck::default()),
            });
            true
        });
        Self { active }
    }
}

impl Drop for ChunkedEncoding {
    fn drop(&mut self) {
        if !self.active {
            return;
        }
        let state = CHUNKING.with(|state| state.borrow_mut().take());
        if let Some(Chunking { label, check: Some(check), .. }) = &state {
            if write_check_mode() == Some(WriteCheckMode::Report) {
                eprintln!(
                    "[encoder_chunks] write_check: scope={label} writes={} writes_after_cut={} hazards={} chunk_accesses={} submits={}",
                    check.writes, check.writes_after_cut, check.hazards, check.accesses_cut, check.submits,
                );
            }
        }
        let pending = state.map_or(0, |state| state.pending.len());
        // An early error return abandons the recording with its chunks.
        // Otherwise a chunk left here was never submitted with its encoder.
        if pending != 0 && !std::thread::panicking() {
            log::debug!("chunked encoding scope ended with {pending} unsubmitted chunks");
        }
    }
}

/// After a dispatch joined the deferred compute batch: flushes the batch (and
/// so cuts a chunk) once it holds a chunk's worth of commands for the
/// registered encoder.
pub(crate) fn after_deferred(encoder: &mut wgpu::CommandEncoder) {
    let registered = CHUNKING.with(|state| {
        state
            .borrow()
            .as_ref()
            .is_some_and(|chunking| chunking.encoder == address(encoder))
    });
    if registered
        && crate::gpu::passes_core::deferred_compute_len() as u64 >= chunk_dispatches()
    {
        crate::gpu::passes_core::flush_deferred_compute(encoder);
    }
}

/// Cuts the registered encoder here when enough dispatches were recorded
/// since the last cut, and finishes the cut-off part on a worker. Call only
/// where no pass is open and the commands so far may end a command buffer.
pub(crate) fn maybe_cut(encoder: &mut wgpu::CommandEncoder) {
    cut_after(encoder, chunk_dispatches());
}

fn cut_after(encoder: &mut wgpu::CommandEncoder, min_dispatches: u64) {
    CHUNKING.with(|state| {
        let mut state = state.borrow_mut();
        let Some(chunking) = state.as_mut() else {
            return;
        };
        if chunking.encoder != address(encoder) {
            return;
        }
        let dispatches = crate::gpu::passes_core::recorded_compute_dispatch_count();
        if dispatches.saturating_sub(chunking.dispatches_at_cut) < min_dispatches {
            return;
        }
        let chunk_dispatches = dispatches.saturating_sub(chunking.dispatches_at_cut);
        chunking.dispatches_at_cut = dispatches;
        if let Some(check) = chunking.check.as_mut() {
            check.cut();
        }
        let next = chunking
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some(chunking.label),
            });
        let recorded = std::mem::replace(encoder, next);
        let (done, finished) = mpsc::channel();
        pool()
            .jobs
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .send(FinishJob {
                device: chunking.device.clone(),
                dispatches: chunk_dispatches,
                encoder: recorded,
                done,
            })
            .expect("encoder finish workers are running");
        chunking.pending.push(finished);
    });
}

/// The finished chunks cut from `encoder` since its last submission, in
/// recording order. Waits for workers still finishing them. Submit them
/// before the rest of the encoder, in the same `Queue::submit`.
pub(crate) fn take(encoder: &wgpu::CommandEncoder) -> Vec<wgpu::CommandBuffer> {
    let (label, pending) = CHUNKING.with(|state| {
        let mut state = state.borrow_mut();
        match state.as_mut() {
            Some(chunking) if chunking.encoder == address(encoder) => {
                chunking.dispatches_at_cut =
                    crate::gpu::passes_core::recorded_compute_dispatch_count();
                // Everything recorded so far goes in this submit.
                if let Some(check) = chunking.check.as_mut() {
                    check.submitted();
                }
                (chunking.label, std::mem::take(&mut chunking.pending))
            }
            _ => ("", Vec::new()),
        }
    });
    if pending.is_empty() {
        return Vec::new();
    }
    let started = std::time::Instant::now();
    let chunks: Vec<_> = pending
        .into_iter()
        .map(|finished| {
            let finished = finished
                .recv()
                .expect("encoder finish worker returned the chunk");
            // Reported here, on the submitting thread, as the device's
            // uncaptured-error handler would have reported them.
            for error in &finished.errors {
                eprintln!("[wgpu uncaptured] encoder chunk of {label}: {error:?}");
            }
            finished.commands
        })
        .collect();
    let waited = std::time::Instant::now();
    if crate::gpu::trace::enabled() {
        crate::gpu::trace::record_host_span("host.submit", "encoder_chunks.wait", started, waited);
    }
    if crate::gpu::passes_core::host_timing_enabled() {
        eprintln!(
            "[gpu_compile_host_timer] encoder_chunks.take: chunks={} wait_ms={:.3}",
            chunks.len(),
            waited.duration_since(started).as_secs_f64() * 1000.0,
        );
    }
    chunks
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum WriteCheckMode {
    /// Flagged writes panic.
    Panic,
    /// Flagged writes, every write of the scope and a summary are printed.
    Report,
    /// Flagged writes are printed (unit tests and debug builds).
    Flag,
}

fn write_check_mode() -> Option<WriteCheckMode> {
    static MODE: OnceLock<Option<WriteCheckMode>> = OnceLock::new();
    *MODE.get_or_init(|| {
        match std::env::var("LANIUS_ENCODER_CHUNK_WRITE_CHECK").ok().as_deref().map(str::trim) {
            Some("1" | "report" | "true") => Some(WriteCheckMode::Report),
            Some("panic") => Some(WriteCheckMode::Panic),
            Some("0" | "false") => None,
            _ if cfg!(any(debug_assertions, test)) => Some(WriteCheckMode::Flag),
            _ => None,
        }
    })
}

/// A buffer range one recorded command accesses.
#[derive(Clone)]
struct Access {
    start: u64,
    end: u64,
    what: Arc<str>,
}

/// Buffer ranges accessed since the last cut, and by chunks cut since the
/// encoder's last submission, keyed by [`buffer_key`].
#[derive(Default)]
struct WriteCheck {
    since_cut: Vec<(u64, Access)>,
    cut: HashMap<u64, Vec<Access>>,
    accesses_cut: u64,
    writes: u64,
    writes_after_cut: u64,
    hazards: u64,
    submits: u64,
}

impl WriteCheck {
    fn cut(&mut self) {
        self.accesses_cut += self.since_cut.len() as u64;
        for (buffer, access) in self.since_cut.drain(..) {
            self.cut.entry(buffer).or_default().push(access);
        }
    }

    fn submitted(&mut self) {
        self.since_cut.clear();
        self.cut.clear();
        self.submits += 1;
    }
}

/// Bind group handle hash -> the (buffer, start, end) ranges it binds,
/// recorded at creation while the check runs. Keyed by hash, not by handle,
/// so the check keeps no bind group (or its buffers) alive; a handle reused
/// after a drop is re-recorded when it is created.
static BIND_GROUP_RANGES: LazyLock<Mutex<HashMap<u64, Arc<[(u64, u64, u64)]>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn handle_hash<T: std::hash::Hash>(handle: &T) -> u64 {
    use std::hash::Hasher;
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    handle.hash(&mut hasher);
    hasher.finish()
}

/// A tracked allocation's id, or else the buffer handle's hash with the top
/// bit set.
fn buffer_key(buffer: &wgpu::Buffer) -> u64 {
    if let Some((id, _, _)) = crate::gpu::buffers::tracked_buffer_identity(buffer) {
        return id & !(1 << 63);
    }
    handle_hash(buffer) | (1 << 63)
}

fn buffer_name(buffer: &wgpu::Buffer) -> String {
    crate::gpu::buffers::tracked_buffer_identity(buffer)
        .map_or_else(|| "<untracked>".to_owned(), |(_, label, _)| label.to_string())
}

/// Records the buffer ranges a new bind group binds (only while the check
/// runs).
pub(crate) fn note_bind_group(bind_group: &wgpu::BindGroup, entries: &[wgpu::BindGroupEntry<'_>]) {
    if write_check_mode().is_none() {
        return;
    }
    let mut ranges = Vec::new();
    let mut push = |binding: &wgpu::BufferBinding<'_>| {
        let end = binding.size.map_or_else(
            || binding.buffer.size(),
            |size| binding.offset.saturating_add(size.get()),
        );
        ranges.push((buffer_key(binding.buffer), binding.offset, end));
    };
    for entry in entries {
        match &entry.resource {
            wgpu::BindingResource::Buffer(binding) => push(binding),
            wgpu::BindingResource::BufferArray(bindings) => bindings.iter().for_each(&mut push),
            _ => {}
        }
    }
    BIND_GROUP_RANGES
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .insert(handle_hash(bind_group), ranges.into());
}

fn with_check(f: impl FnOnce(&mut WriteCheck, &'static str)) {
    if write_check_mode().is_none() {
        return;
    }
    CHUNKING.with(|state| {
        if let Some(chunking) = state.borrow_mut().as_mut() {
            let label = chunking.label;
            if let Some(check) = chunking.check.as_mut() {
                f(check, label);
            }
        }
    });
}

/// A dispatch recorded on this thread inside a chunked scope: the ranges its
/// bind groups bind (whole buffers under dynamic offsets) and its indirect
/// arguments.
pub(crate) fn note_dispatch<'a>(
    bind_groups: impl IntoIterator<Item = &'a wgpu::BindGroup>,
    dynamic_offsets: bool,
    indirect: Option<(&wgpu::Buffer, u64)>,
    label: &str,
) {
    if write_check_mode().is_none()
        || !CHUNKING.with(|state| state.borrow().as_ref().is_some_and(|c| c.check.is_some()))
    {
        return;
    }
    let what: Arc<str> = Arc::from(format!("dispatch {label}"));
    let mut accesses = Vec::new();
    {
        let ranges = BIND_GROUP_RANGES
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for bind_group in bind_groups {
            let Some(bound) = ranges.get(&handle_hash(bind_group)) else {
                // Created before the check ran: treat as unknown.
                accesses.push((u64::MAX, Access { start: 0, end: u64::MAX, what: what.clone() }));
                continue;
            };
            for &(buffer, start, end) in bound.iter() {
                let (start, end) = if dynamic_offsets { (0, u64::MAX) } else { (start, end) };
                accesses.push((buffer, Access { start, end, what: what.clone() }));
            }
        }
    }
    if let Some((buffer, offset)) = indirect {
        accesses.push((buffer_key(buffer), Access { start: offset, end: offset + 12, what }));
    }
    with_check(|check, _| check.since_cut.extend(accesses));
}

/// A clear or copy recorded into `encoder`, when it is the registered one.
pub(crate) fn note_access(
    encoder: &wgpu::CommandEncoder,
    buffer: &wgpu::Buffer,
    start: u64,
    len: u64,
    what: &'static str,
) {
    if write_check_mode().is_none() {
        return;
    }
    let registered = CHUNKING.with(|state| {
        state
            .borrow()
            .as_ref()
            .is_some_and(|chunking| chunking.encoder == address(encoder) && chunking.check.is_some())
    });
    if registered {
        let key = buffer_key(buffer);
        with_check(|check, _| {
            check.since_cut.push((key, Access { start, end: start.saturating_add(len), what: Arc::from(what) }))
        });
    }
}

/// A `Queue::write_buffer` on this thread: flags it when a chunk cut since
/// the encoder's last submission accesses the written range.
pub(crate) fn note_queue_write(buffer: &wgpu::Buffer, start: u64, len: u64) {
    let Some(mode) = write_check_mode() else {
        return;
    };
    let Some((message, count)) = queue_write_hazard(buffer, start, len) else {
        return;
    };
    match mode {
        WriteCheckMode::Panic => panic!("{message}"),
        _ if count <= 40 => eprintln!("{message}"),
        _ => {}
    }
}

/// Counts a write inside a chunked scope and describes it, with the scope's
/// hazard count, when it touches a range a cut, unsubmitted chunk accesses.
fn queue_write_hazard(buffer: &wgpu::Buffer, start: u64, len: u64) -> Option<(String, u64)> {
    let end = start.saturating_add(len);
    let key = buffer_key(buffer);
    let mut found = None;
    let mut listed = None;
    with_check(|check, label| {
        check.writes += 1;
        let after_cut = !check.cut.is_empty();
        if write_check_mode() == Some(WriteCheckMode::Report) {
            listed = Some((label, check.submits, after_cut));
        }
        if !after_cut {
            return;
        }
        check.writes_after_cut += 1;
        let overlapping = [key, u64::MAX]
            .iter()
            .filter_map(|key| check.cut.get(key))
            .flatten()
            .find(|access| access.start < end && start < access.end);
        if let Some(access) = overlapping {
            check.hazards += 1;
            found = Some((label, access.what.clone(), check.hazards, check.submits));
        }
    });
    if let Some((label, submits, after_cut)) = listed {
        eprintln!(
            "[encoder_chunks] write: scope={label} buffer={} range={start}..{end} submits_before={submits} after_cut={after_cut}",
            buffer_name(buffer),
        );
    }
    let (label, what, count, submits) = found?;
    Some((
        format!(
            "[encoder_chunks] write after cut: scope={label} buffer={} range={start}..{end} submits_before={submits} is accessed by an unsubmitted earlier chunk ({what})",
            buffer_name(buffer),
        ),
        count,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn read_word(gpu: &crate::gpu::device::GpuDevice, buffer: &wgpu::Buffer) -> u32 {
        let slice = buffer.slice(..);
        crate::gpu::passes_core::map_readback_blocking(&gpu.device, &slice, "encoder_chunks.test")
            .expect("map test readback");
        let word = u32::from_le_bytes(slice.get_mapped_range()[..4].try_into().unwrap());
        buffer.unmap();
        word
    }

    /// A chunk cut before a `write_buffer` still sees the written value: the
    /// chunks go in the same submit as the rest, after every pending write.
    #[test]
    fn chunks_submit_with_their_encoder() {
        if !enabled() {
            return;
        }
        let gpu = crate::gpu::device::global();
        let (device, queue) = (&*gpu.device, &*gpu.queue);
        let storage = |label| {
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: 4,
                usage: wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            })
        };
        let readback = |label| {
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: 4,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            })
        };
        let source = storage("encoder_chunks.test.source");
        let (first, second) = (readback("encoder_chunks.test.first"), readback("encoder_chunks.test.second"));
        queue.write_buffer(&source, 0, &1u32.to_le_bytes());
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let scope = ChunkedEncoding::begin(device, &encoder, "encoder_chunks.test");
        encoder.copy_buffer_to_buffer(&source, 0, &first, 0, 4);
        cut_after(&mut encoder, 0);
        queue.write_buffer(&source, 0, &2u32.to_le_bytes());
        encoder.copy_buffer_to_buffer(&source, 0, &second, 0, 4);
        let mut commands = take(&encoder);
        assert_eq!(commands.len(), 1, "one chunk was cut");
        commands.push(encoder.finish());
        drop(scope);
        crate::gpu::passes_core::submit_all_with_progress(queue, "encoder_chunks.test", commands);
        assert_eq!(read_word(gpu, &first), 2);
        assert_eq!(read_word(gpu, &second), 2);
    }

    /// The write-order check flags a write to a range that a cut, unsubmitted
    /// chunk accesses, and nothing else.
    #[test]
    fn a_write_into_an_unsubmitted_chunk_is_flagged() {
        if !enabled() || write_check_mode().is_none() {
            return;
        }
        let gpu = crate::gpu::device::global();
        let device = &*gpu.device;
        let buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("encoder_chunks.test.checked"),
            size: 16,
            usage: wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let _scope = ChunkedEncoding::begin(device, &encoder, "encoder_chunks.test");
        note_access(&encoder, &buffer, 0, 8, "copy source");
        assert!(queue_write_hazard(&buffer, 0, 8).is_none(), "the access is not cut yet");
        cut_after(&mut encoder, 0);
        assert!(queue_write_hazard(&buffer, 8, 8).is_none(), "disjoint from the chunk's access");
        drop(take(&encoder));
        assert!(queue_write_hazard(&buffer, 0, 8).is_none(), "the chunk was submitted");
        note_access(&encoder, &buffer, 4, 4, "clear");
        cut_after(&mut encoder, 0);
        let (message, _) = queue_write_hazard(&buffer, 0, 8).expect("the cut chunk clears 4..8");
        assert!(message.contains("write after cut") && message.contains("(clear)"), "{message}");
        drop(take(&encoder));
        drop(encoder.finish());
    }

    /// Only the registered encoder is cut, and scopes do not nest.
    #[test]
    fn only_the_registered_encoder_is_cut() {
        if !enabled() {
            return;
        }
        let gpu = crate::gpu::device::global();
        let device = &*gpu.device;
        let mut registered = device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let mut other = device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        let scope = ChunkedEncoding::begin(device, &registered, "encoder_chunks.test");
        let inner = ChunkedEncoding::begin(device, &other, "encoder_chunks.test.inner");
        assert!(!inner.active);
        cut_after(&mut other, 0);
        assert!(take(&other).is_empty());
        cut_after(&mut registered, 0);
        cut_after(&mut registered, 0);
        assert_eq!(take(&registered).len(), 2);
        assert!(take(&registered).is_empty());
        drop(inner);
        drop(scope);
        drop((registered.finish(), other.finish()));
    }
}
