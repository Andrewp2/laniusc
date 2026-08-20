use std::{
    cell::RefCell,
    collections::{HashMap, HashSet},
    ops::Deref,
    sync::{
        Arc,
        LazyLock,
        Mutex,
        atomic::{AtomicBool, AtomicU64, Ordering},
    },
};

thread_local! {
    static RESETTABLE_BUFFER_COLLECTOR: RefCell<Option<Vec<ResettableBuffer>>> = const { RefCell::new(None) };
    static RESETTABLE_ROW_DOMAIN: RefCell<Option<(ResettableRowDomain, usize)>> = const { RefCell::new(None) };
    static UNIFORM_BUFFER_ARENA: RefCell<Option<UniformBufferArena>> = const { RefCell::new(None) };
}

const DEFAULT_UNIFORM_ARENA_BYTES: u64 = 1024 * 1024;

struct UniformBufferArena {
    label: String,
    alignment: u64,
    max_buffer_size: u64,
    logical_bindings: u64,
    arenas: Vec<(LaniusBuffer<u8>, u64)>,
}

impl UniformBufferArena {
    fn allocate(&mut self, device: &wgpu::Device, bytes: &[u8]) -> Option<LaniusBuffer<u8>> {
        let binding_bytes = u64::try_from(bytes.len()).ok()?.max(4).next_multiple_of(4);
        if binding_bytes > u64::from(device.limits().max_uniform_buffer_binding_size) {
            return None;
        }

        let mut placement = self.arenas.last().and_then(|(arena, used)| {
            let offset = used.next_multiple_of(self.alignment);
            (offset.checked_add(binding_bytes)? <= arena.byte_size as u64)
                .then_some((self.arenas.len() - 1, offset))
        });
        if placement.is_none() {
            let arena_bytes = DEFAULT_UNIFORM_ARENA_BYTES
                .max(binding_bytes.next_multiple_of(self.alignment))
                .min(self.max_buffer_size);
            if arena_bytes < binding_bytes {
                return None;
            }
            let index = self.arenas.len();
            let label = format!("{}.{}", self.label, index);
            let raw = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(&label),
                size: arena_bytes,
                usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: true,
            });
            self.arenas.push((
                LaniusBuffer::new_labeled((raw, arena_bytes), arena_bytes as usize, label),
                0,
            ));
            placement = Some((index, 0));
        }

        let (arena_index, offset) = placement?;
        let (arena, used) = &mut self.arenas[arena_index];
        {
            let mut mapped = arena
                .buffer
                .slice(offset..offset + binding_bytes)
                .get_mapped_range_mut();
            mapped.slice(..bytes.len()).copy_from_slice(bytes);
            mapped.slice(bytes.len()..).fill(0);
        }
        *used = offset + binding_bytes;
        self.logical_bindings += 1;
        arena
            .subrange::<u8>(offset, binding_bytes, bytes.len())
            .ok()
    }
}

/// Packs immutable uniform parameters created by `build` into aligned ranges
/// of a small number of physical buffers. Reflected bind groups still bind
/// each parameter's exact logical range; only the WGPU allocation identity is
/// shared. This avoids making every tiny pass parameter permanently enlarge
/// command-encoder resource-tracking tables.
pub(crate) fn with_uniform_buffer_arena<T>(
    device: &wgpu::Device,
    label: &str,
    build: impl FnOnce() -> T,
) -> T {
    let limits = device.limits();
    UNIFORM_BUFFER_ARENA.with(|arena| {
        assert!(arena.borrow().is_none(), "nested uniform-buffer arena");
        *arena.borrow_mut() = Some(UniformBufferArena {
            label: label.to_owned(),
            alignment: u64::from(limits.min_uniform_buffer_offset_alignment.max(1)),
            max_buffer_size: limits.max_buffer_size,
            logical_bindings: 0,
            arenas: Vec::new(),
        });
    });
    let value = build();
    let arena = UNIFORM_BUFFER_ARENA.with(|arena| {
        arena
            .borrow_mut()
            .take()
            .expect("uniform-buffer arena disappeared")
    });
    if crate::gpu::env::env_bool_strict("LANIUS_GPU_BUFFER_BREAKDOWN", false) {
        eprintln!(
            "gpu_uniform_arena label=\"{}\" logical_bindings={} physical_buffers={} reserved_bytes={} used_bytes={}",
            arena.label,
            arena.logical_bindings,
            arena.arenas.len(),
            arena
                .arenas
                .iter()
                .map(|(buffer, _)| buffer.byte_size as u64)
                .sum::<u64>(),
            arena.arenas.iter().map(|(_, used)| *used).sum::<u64>(),
        );
    }
    for (buffer, _) in arena.arenas {
        buffer.buffer.unmap();
    }
    value
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct ResettableRowDomain(u32);

impl ResettableRowDomain {
    pub(crate) const fn new(id: u32) -> Self {
        Self(id)
    }
}

pub(crate) struct ResettableRowDomainGuard {
    previous: Option<(ResettableRowDomain, usize)>,
}

impl ResettableRowDomainGuard {
    pub(crate) fn enter(domain: ResettableRowDomain, allocated_rows: usize) -> Self {
        let previous = RESETTABLE_ROW_DOMAIN.with(|current| {
            current
                .borrow_mut()
                .replace((domain, allocated_rows.max(1)))
        });
        Self { previous }
    }
}

impl Drop for ResettableRowDomainGuard {
    fn drop(&mut self) {
        RESETTABLE_ROW_DOMAIN.with(|current| *current.borrow_mut() = self.previous);
    }
}

#[derive(Clone)]
pub(crate) struct ResettableBuffer {
    pub(crate) buffer: wgpu::Buffer,
    pub(crate) byte_size: u64,
    pub(crate) allocation_id: u64,
    pub(crate) label: Arc<str>,
    pub(crate) row_domain: Option<ResettableRowDomain>,
    pub(crate) allocated_rows: usize,
    pub(crate) reset_policy: JobResetPolicy,
}

impl ResettableBuffer {
    /// Borrows the complete physical allocation while preserving the identity
    /// used by compiler-graph ownership and alias validation.
    pub(crate) fn tracked_view(&self) -> TrackedBufferView<'_> {
        TrackedBufferView::from_parts(&self.buffer, 0, self.byte_size, Some(self.allocation_id))
    }
}

/// Collects writable allocations created while `build` runs. This lets an
/// owning workspace reset each unique physical allocation according to its
/// first-use contract without manually listing every logical alias.
pub(crate) fn collect_resettable_buffers<T>(
    build: impl FnOnce() -> T,
) -> (T, Vec<ResettableBuffer>) {
    RESETTABLE_BUFFER_COLLECTOR.with(|collector| {
        assert!(
            collector.borrow().is_none(),
            "nested resettable-buffer collection"
        );
        *collector.borrow_mut() = Some(Vec::new());
    });
    let value = build();
    let mut buffers = RESETTABLE_BUFFER_COLLECTOR.with(|collector| {
        collector
            .borrow_mut()
            .take()
            .expect("resettable-buffer collection disappeared")
    });
    let mut unique_allocations = HashSet::with_capacity(buffers.len());
    buffers.retain(|buffer| unique_allocations.insert(buffer.allocation_id));
    (value, buffers)
}

pub(crate) fn register_resettable_buffer<T>(
    buffer: &LaniusBuffer<T>,
    reset_policy: JobResetPolicy,
) {
    RESETTABLE_BUFFER_COLLECTOR.with(|collector| {
        let mut collector = collector.borrow_mut();
        let Some(buffers) = collector.as_mut() else {
            return;
        };
        let declared_rows = RESETTABLE_ROW_DOMAIN.with(|current| *current.borrow());
        let row_domain = declared_rows
            .filter(|(_, allocated_rows)| *allocated_rows == buffer.count)
            .map(|(domain, _)| domain);
        buffers.push(ResettableBuffer {
            buffer: buffer.buffer.clone(),
            // Resetting is allocation-wide: one collected entry represents
            // every logical range packed into this physical arena.
            byte_size: buffer.buffer.size(),
            allocation_id: buffer
                .allocation_id()
                .expect("resettable buffers must have tracked allocation identities"),
            label: buffer._allocation.as_ref().map_or_else(
                || Arc::<str>::from("<borrowed>"),
                |value| value.label.clone(),
            ),
            row_domain,
            allocated_rows: buffer.count,
            reset_policy,
        });
    });
}

static LIVE_BUFFER_ALLOCATIONS: AtomicU64 = AtomicU64::new(0);
static LIVE_BUFFER_BYTES: AtomicU64 = AtomicU64::new(0);
static PEAK_BUFFER_ALLOCATIONS: AtomicU64 = AtomicU64::new(0);
static PEAK_BUFFER_BYTES: AtomicU64 = AtomicU64::new(0);
static NEXT_BUFFER_ALLOCATION_ID: AtomicU64 = AtomicU64::new(1);
static BUFFER_CREATION_COUNT: AtomicU64 = AtomicU64::new(0);
static LIVE_BUFFER_BYTES_BY_LABEL: LazyLock<Mutex<HashMap<Arc<str>, (u64, u64)>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static LIVE_BUFFER_IDENTITIES: LazyLock<Mutex<HashMap<wgpu::Buffer, (u64, Arc<str>, u64)>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static BUFFER_CREATIONS_BY_LABEL: LazyLock<Mutex<HashMap<Arc<str>, u64>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static BUFFER_PHASE_SNAPSHOTS: LazyLock<Mutex<Vec<TrackedBufferPhaseSnapshot>>> =
    LazyLock::new(|| Mutex::new(Vec::new()));
static BUFFER_RESIDENCY_TIMELINE: LazyLock<Mutex<Option<TrackedBufferResidencyTimeline>>> =
    LazyLock::new(|| Mutex::new(None));
static BUFFER_RESIDENCY_TIMELINE_ENABLED: AtomicBool = AtomicBool::new(false);

/// Process-wide logical allocation totals for live buffers created through
/// Lanius's typed GPU-buffer helpers. Cloning a buffer handle does not count as
/// a new allocation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct TrackedBufferAllocationStats {
    pub allocations: u64,
    pub bytes: u64,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TrackedBufferPhaseSnapshot {
    pub phase: Arc<str>,
    pub stats: TrackedBufferAllocationStats,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TrackedBufferResidencyPoint {
    pub elapsed_ns: u64,
    pub allocations: u64,
    pub bytes: u64,
    pub event: &'static str,
    pub allocation_id: Option<u64>,
    pub label: Option<Arc<str>>,
    pub changed_bytes: u64,
}

#[derive(Debug)]
struct TrackedBufferResidencyTimeline {
    started: std::time::Instant,
    points: Vec<TrackedBufferResidencyPoint>,
}

pub fn tracked_buffer_allocation_stats() -> TrackedBufferAllocationStats {
    TrackedBufferAllocationStats {
        allocations: LIVE_BUFFER_ALLOCATIONS.load(Ordering::Relaxed),
        bytes: LIVE_BUFFER_BYTES.load(Ordering::Relaxed),
    }
}

/// Monotonic number of physical GPU buffers created through Lanius's typed
/// allocation boundary. Aliases and cloned handles do not increment it.
pub(crate) fn buffer_creation_count() -> u64 {
    BUFFER_CREATION_COUNT.load(Ordering::Relaxed)
}

pub(crate) fn buffer_creation_counts_by_label() -> HashMap<Arc<str>, u64> {
    BUFFER_CREATIONS_BY_LABEL
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .clone()
}

/// Resets the peak window to the allocations that are live at the phase/job boundary.
///
/// The compiler daemon executes jobs serially, so one process-wide window captures the
/// actual high-water mark without adding bookkeeping to every compiler subsystem.
pub fn reset_tracked_buffer_allocation_peaks() -> TrackedBufferAllocationStats {
    let current = tracked_buffer_allocation_stats();
    PEAK_BUFFER_ALLOCATIONS.store(current.allocations, Ordering::Relaxed);
    PEAK_BUFFER_BYTES.store(current.bytes, Ordering::Relaxed);
    BUFFER_PHASE_SNAPSHOTS
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .clear();
    current
}

/// Starts an opt-in job-relative record of physical LaniusBuffer residency.
///
/// Profiling owns this boundary. Normal compilation leaves the recorder absent,
/// so allocation and release keep their existing atomic-only fast path.
pub fn begin_tracked_buffer_residency_timeline(enabled: bool) {
    BUFFER_RESIDENCY_TIMELINE_ENABLED.store(false, Ordering::Release);
    let mut timeline = BUFFER_RESIDENCY_TIMELINE
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    if !enabled {
        *timeline = None;
        return;
    }
    let stats = tracked_buffer_allocation_stats();
    *timeline = Some(TrackedBufferResidencyTimeline {
        started: std::time::Instant::now(),
        points: vec![TrackedBufferResidencyPoint {
            elapsed_ns: 0,
            allocations: stats.allocations,
            bytes: stats.bytes,
            event: "baseline",
            allocation_id: None,
            label: None,
            changed_bytes: 0,
        }],
    });
    BUFFER_RESIDENCY_TIMELINE_ENABLED.store(true, Ordering::Release);
}

pub fn tracked_buffer_residency_timeline() -> Vec<TrackedBufferResidencyPoint> {
    BUFFER_RESIDENCY_TIMELINE
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .as_ref()
        .map_or_else(Vec::new, |timeline| timeline.points.clone())
}

fn record_buffer_residency_event(
    event: &'static str,
    allocation_id: u64,
    label: &Arc<str>,
    changed_bytes: u64,
) {
    if !BUFFER_RESIDENCY_TIMELINE_ENABLED.load(Ordering::Acquire) {
        return;
    }
    let mut timeline = BUFFER_RESIDENCY_TIMELINE
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let Some(timeline) = timeline.as_mut() else {
        return;
    };
    let stats = tracked_buffer_allocation_stats();
    timeline.points.push(TrackedBufferResidencyPoint {
        elapsed_ns: timeline
            .started
            .elapsed()
            .as_nanos()
            .min(u128::from(u64::MAX)) as u64,
        allocations: stats.allocations,
        bytes: stats.bytes,
        event,
        allocation_id: Some(allocation_id),
        label: Some(label.clone()),
        changed_bytes,
    });
}

/// Captures live tracked storage at a named job/phase boundary.
pub fn record_tracked_buffer_phase_snapshot(
    phase: impl Into<Arc<str>>,
) -> TrackedBufferAllocationStats {
    let stats = tracked_buffer_allocation_stats();
    BUFFER_PHASE_SNAPSHOTS
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .push(TrackedBufferPhaseSnapshot {
            phase: phase.into(),
            stats,
        });
    stats
}

pub fn tracked_buffer_phase_snapshots() -> Vec<TrackedBufferPhaseSnapshot> {
    BUFFER_PHASE_SNAPSHOTS
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .clone()
}

/// Returns the high-water mark since the last peak-window reset.
pub fn tracked_buffer_allocation_peak_stats() -> TrackedBufferAllocationStats {
    TrackedBufferAllocationStats {
        allocations: PEAK_BUFFER_ALLOCATIONS.load(Ordering::Relaxed),
        bytes: PEAK_BUFFER_BYTES.load(Ordering::Relaxed),
    }
}

fn record_allocation_peak(allocations: u64, bytes: u64) {
    PEAK_BUFFER_ALLOCATIONS.fetch_max(allocations, Ordering::Relaxed);
    PEAK_BUFFER_BYTES.fetch_max(bytes, Ordering::Relaxed);
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct TrackedBufferLabelStats {
    pub label: Arc<str>,
    pub allocations: u64,
    pub bytes: u64,
}

pub fn tracked_buffer_allocation_stats_by_label() -> Vec<TrackedBufferLabelStats> {
    let labels = LIVE_BUFFER_BYTES_BY_LABEL
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    let mut rows = labels
        .iter()
        .map(|(label, &(allocations, bytes))| TrackedBufferLabelStats {
            label: label.clone(),
            allocations,
            bytes,
        })
        .collect::<Vec<_>>();
    rows.sort_unstable_by(|left, right| {
        right
            .bytes
            .cmp(&left.bytes)
            .then_with(|| left.label.cmp(&right.label))
    });
    rows
}

struct BufferAllocationLedger {
    id: u64,
    bytes: u64,
    label: Arc<str>,
    buffer: Option<wgpu::Buffer>,
}

impl BufferAllocationLedger {
    #[cfg(test)]
    fn new(bytes: u64, label: impl Into<Arc<str>>) -> Arc<Self> {
        Self::new_inner(None, bytes, label)
    }

    fn new_for_buffer(buffer: &wgpu::Buffer, bytes: u64, label: impl Into<Arc<str>>) -> Arc<Self> {
        Self::new_inner(Some(buffer.clone()), bytes, label)
    }

    fn new_inner(
        buffer: Option<wgpu::Buffer>,
        bytes: u64,
        label: impl Into<Arc<str>>,
    ) -> Arc<Self> {
        BUFFER_CREATION_COUNT.fetch_add(1, Ordering::Relaxed);
        let label = label.into();
        *BUFFER_CREATIONS_BY_LABEL
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .entry(label.clone())
            .or_default() += 1;
        let allocations = LIVE_BUFFER_ALLOCATIONS.fetch_add(1, Ordering::Relaxed) + 1;
        let live_bytes = LIVE_BUFFER_BYTES.fetch_add(bytes, Ordering::Relaxed) + bytes;
        record_allocation_peak(allocations, live_bytes);
        let mut labels = LIVE_BUFFER_BYTES_BY_LABEL
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let entry = labels.entry(label.clone()).or_default();
        entry.0 += 1;
        entry.1 += bytes;
        drop(labels);
        let id = NEXT_BUFFER_ALLOCATION_ID.fetch_add(1, Ordering::Relaxed);
        if let Some(buffer) = buffer.as_ref() {
            LIVE_BUFFER_IDENTITIES
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .insert(buffer.clone(), (id, label.clone(), bytes));
        }
        record_buffer_residency_event("allocate", id, &label, bytes);
        Arc::new(Self {
            id,
            bytes,
            label,
            buffer,
        })
    }
}

impl Drop for BufferAllocationLedger {
    fn drop(&mut self) {
        if let Some(buffer) = self.buffer.as_ref() {
            LIVE_BUFFER_IDENTITIES
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .remove(buffer);
        }
        LIVE_BUFFER_ALLOCATIONS.fetch_sub(1, Ordering::Relaxed);
        LIVE_BUFFER_BYTES.fetch_sub(self.bytes, Ordering::Relaxed);
        let mut labels = LIVE_BUFFER_BYTES_BY_LABEL
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let mut remove = false;
        if let Some(entry) = labels.get_mut(&self.label) {
            entry.0 = entry.0.saturating_sub(1);
            entry.1 = entry.1.saturating_sub(self.bytes);
            remove = entry.0 == 0;
        }
        if remove {
            labels.remove(&self.label);
        }
        drop(labels);
        record_buffer_residency_event("release", self.id, &self.label, self.bytes);
    }
}

/// Returns the compiler allocation identity attached to a raw WGPU handle.
/// This is used only for ownership validation and opt-in liveness telemetry;
/// semantic code must continue to pass `LaniusBuffer`/`TrackedBufferView`.
pub(crate) fn tracked_buffer_identity(buffer: &wgpu::Buffer) -> Option<(u64, Arc<str>, u64)> {
    LIVE_BUFFER_IDENTITIES
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .get(buffer)
        .cloned()
}

/// A thin wrapper around `wgpu::Buffer` that also tracks element count and byte size.
/// Always create these via the helpers below so we respect WGSL/encase layout rules.
#[derive(Clone)]
pub struct LaniusBuffer<T> {
    pub buffer: wgpu::Buffer,
    /// Byte offset of this logical view inside the physical allocation.
    pub byte_offset: u64,
    /// Size of this logical view in bytes.
    pub byte_size: usize,
    /// number of logical T elements
    pub count: usize,
    _allocation: Option<Arc<BufferAllocationLedger>>,
    _borrowed_allocation_id: Option<u64>,
    _marker: std::marker::PhantomData<T>,
}

/// One uniform-buffer allocation containing fixed-stride records selected by
/// WGPU dynamic offsets. This is the GPU equivalent of an array of small pass
/// parameters without one allocation and bind group per element.
pub struct DynamicUniformBuffer<T> {
    pub buffer: LaniusBuffer<u8>,
    stride: u32,
    binding_size: std::num::NonZeroU64,
    count: usize,
    _marker: std::marker::PhantomData<T>,
}

impl<T> DynamicUniformBuffer<T> {
    pub fn binding(&self) -> wgpu::BindingResource<'_> {
        wgpu::BindingResource::Buffer(wgpu::BufferBinding {
            buffer: &self.buffer,
            offset: self.buffer.byte_offset,
            size: Some(self.binding_size),
        })
    }

    pub fn dynamic_offset(&self, index: usize) -> u32 {
        assert!(index < self.count, "dynamic uniform index out of bounds");
        self.stride
            .checked_mul(index as u32)
            .expect("dynamic uniform offset overflow")
    }
}

/// Borrowed, type-erased view of a tracked GPU allocation.
///
/// Compiler phase boundaries often reuse storage with a different logical
/// element type. Passing only `&wgpu::Buffer` across that boundary loses the
/// allocation identity needed by compiler-graph ownership validation. This
/// view keeps the physical identity and byte extent without pretending that
/// the producer's element type is still meaningful to the consumer.
#[derive(Clone, Copy)]
pub struct TrackedBufferView<'a> {
    pub buffer: &'a wgpu::Buffer,
    pub byte_offset: u64,
    pub byte_size: u64,
    allocation_id: Option<u64>,
}

impl<'a> TrackedBufferView<'a> {
    pub(crate) fn from_parts(
        buffer: &'a wgpu::Buffer,
        byte_offset: u64,
        byte_size: u64,
        allocation_id: Option<u64>,
    ) -> Self {
        Self {
            buffer,
            byte_offset,
            byte_size,
            allocation_id,
        }
    }

    pub fn allocation_id(self) -> Option<u64> {
        self.allocation_id
    }

    pub fn as_entire_binding(self) -> wgpu::BindingResource<'a> {
        let binding_size = self.byte_size.saturating_add(3) & !3;
        wgpu::BindingResource::Buffer(wgpu::BufferBinding {
            buffer: self.buffer,
            offset: self.byte_offset,
            size: (self.byte_offset != 0 || binding_size != self.buffer.size())
                .then(|| std::num::NonZeroU64::new(binding_size))
                .flatten(),
        })
    }

    /// Narrows this view to a relative byte range while retaining the physical
    /// allocation identity used by compiler-graph ownership checks.
    pub fn subrange(self, byte_offset: u64, byte_size: u64) -> Result<Self, String> {
        let relative_end = byte_offset
            .checked_add(byte_size)
            .ok_or_else(|| "tracked GPU buffer subrange overflows".to_owned())?;
        if byte_size == 0 || relative_end > self.byte_size {
            return Err(format!(
                "tracked GPU buffer subrange {byte_offset}..{relative_end} exceeds view size {}",
                self.byte_size,
            ));
        }
        Ok(Self {
            buffer: self.buffer,
            byte_offset: self
                .byte_offset
                .checked_add(byte_offset)
                .ok_or_else(|| "tracked GPU buffer absolute offset overflows".to_owned())?,
            byte_size,
            allocation_id: self.allocation_id,
        })
    }

    /// Reinterprets this borrowed allocation without losing the producer's
    /// compiler allocation identity. The producer remains responsible for
    /// ledger accounting and physical lifetime.
    pub fn alias<T>(self, count: usize) -> LaniusBuffer<T> {
        LaniusBuffer {
            buffer: self.buffer.clone(),
            byte_offset: self.byte_offset,
            byte_size: self.byte_size as usize,
            count,
            _allocation: None,
            _borrowed_allocation_id: self.allocation_id,
            _marker: std::marker::PhantomData,
        }
    }
}

impl std::ops::Deref for TrackedBufferView<'_> {
    type Target = wgpu::Buffer;

    fn deref(&self) -> &Self::Target {
        self.buffer
    }
}

impl<'a, T> From<&'a LaniusBuffer<T>> for TrackedBufferView<'a> {
    fn from(buffer: &'a LaniusBuffer<T>) -> Self {
        Self {
            buffer: &buffer.buffer,
            byte_offset: buffer.byte_offset,
            byte_size: buffer.byte_size as u64,
            allocation_id: buffer.allocation_id(),
        }
    }
}

impl<'a> From<&'a wgpu::Buffer> for TrackedBufferView<'a> {
    fn from(buffer: &'a wgpu::Buffer) -> Self {
        Self {
            buffer,
            byte_offset: 0,
            byte_size: buffer.size(),
            allocation_id: None,
        }
    }
}

impl<T> LaniusBuffer<T> {
    /// Stable identity of the physical GPU allocation shared by all aliases.
    /// Buffers wrapped through `untracked_alias` have no compiler-owned id.
    pub fn allocation_id(&self) -> Option<u64> {
        self._allocation
            .as_ref()
            .map(|allocation| allocation.id)
            .or(self._borrowed_allocation_id)
    }

    /// Creates a WGPU binding for exactly this logical byte range.
    pub fn as_entire_binding(&self) -> wgpu::BindingResource<'_> {
        let binding_size = (self.byte_size as u64).saturating_add(3) & !3;
        wgpu::BindingResource::Buffer(wgpu::BufferBinding {
            buffer: &self.buffer,
            offset: self.byte_offset,
            size: (self.byte_offset != 0 || binding_size != self.buffer.size())
                .then(|| std::num::NonZeroU64::new(binding_size))
                .flatten(),
        })
    }

    /// Absolute physical offset corresponding to a relative offset in this
    /// logical view.
    pub fn absolute_offset(&self, relative_offset: u64) -> u64 {
        assert!(
            relative_offset <= self.byte_size as u64,
            "GPU buffer relative offset exceeds its logical view"
        );
        self.byte_offset
            .checked_add(relative_offset)
            .expect("GPU buffer absolute offset overflow")
    }

    /// Uploads bytes at an offset relative to this logical view.
    pub fn write(&self, queue: &wgpu::Queue, relative_offset: u64, data: &[u8]) {
        let end = relative_offset
            .checked_add(data.len() as u64)
            .expect("GPU buffer upload range overflow");
        assert!(
            end <= self.byte_size as u64,
            "GPU buffer upload exceeds its logical view"
        );
        queue.write_buffer(&self.buffer, self.absolute_offset(relative_offset), data);
    }

    /// Clears bytes relative to this logical view. `None` clears only the rest
    /// of the view, never adjacent arena occupants.
    pub fn clear(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        relative_offset: u64,
        size: Option<u64>,
    ) {
        let size = size.unwrap_or_else(|| self.byte_size as u64 - relative_offset);
        let end = relative_offset
            .checked_add(size)
            .expect("GPU buffer clear range overflow");
        assert!(
            end <= self.byte_size as u64,
            "GPU buffer clear exceeds its logical view"
        );
        encoder.clear_buffer(
            &self.buffer,
            self.absolute_offset(relative_offset),
            Some(size),
        );
    }

    /// Copies between logical views while translating both relative offsets to
    /// their physical arena offsets.
    pub fn copy_to<U>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        source_offset: u64,
        destination: &LaniusBuffer<U>,
        destination_offset: u64,
        size: u64,
    ) {
        assert!(
            source_offset.saturating_add(size) <= self.byte_size as u64,
            "GPU buffer copy exceeds its source view"
        );
        assert!(
            destination_offset.saturating_add(size) <= destination.byte_size as u64,
            "GPU buffer copy exceeds its destination view"
        );
        encoder.copy_buffer_to_buffer(
            &self.buffer,
            self.absolute_offset(source_offset),
            &destination.buffer,
            destination.absolute_offset(destination_offset),
            size,
        );
    }

    /// Creates an owned typed view of a subrange of this allocation.
    pub fn subrange<U>(
        &self,
        relative_offset: u64,
        byte_size: u64,
        count: usize,
    ) -> Result<LaniusBuffer<U>, String> {
        let relative_end = relative_offset
            .checked_add(byte_size)
            .ok_or_else(|| "GPU buffer subrange overflows".to_owned())?;
        if byte_size == 0 || relative_end > self.byte_size as u64 {
            return Err(format!(
                "GPU buffer subrange {relative_offset}..{relative_end} exceeds view size {}",
                self.byte_size,
            ));
        }
        Ok(LaniusBuffer {
            buffer: self.buffer.clone(),
            byte_offset: self
                .byte_offset
                .checked_add(relative_offset)
                .ok_or_else(|| "GPU buffer absolute offset overflows".to_owned())?,
            byte_size: byte_size as usize,
            count,
            _allocation: self._allocation.clone(),
            _borrowed_allocation_id: self._borrowed_allocation_id,
            _marker: std::marker::PhantomData,
        })
    }

    /// Wraps a raw `wgpu::Buffer` plus byte size and logical element count.
    pub fn new((buffer, byte_size): (wgpu::Buffer, u64), count: usize) -> Self {
        Self::new_labeled((buffer, byte_size), count, "<unlabeled>")
    }

    /// Wraps a raw buffer and associates its allocation identity with a
    /// diagnostic label. Aliases retain this one label and allocation entry.
    pub fn new_labeled(
        (buffer, byte_size): (wgpu::Buffer, u64),
        count: usize,
        label: impl Into<Arc<str>>,
    ) -> Self {
        let allocation = BufferAllocationLedger::new_for_buffer(&buffer, byte_size, label);
        Self {
            buffer,
            byte_offset: 0,
            byte_size: byte_size as usize,
            count,
            _allocation: Some(allocation),
            _borrowed_allocation_id: None,
            _marker: std::marker::PhantomData,
        }
    }

    /// Reinterprets this allocation as another element type without changing
    /// its allocation identity.
    pub fn reinterpret<U>(self, count: usize) -> LaniusBuffer<U> {
        LaniusBuffer {
            buffer: self.buffer,
            byte_offset: self.byte_offset,
            byte_size: self.byte_size,
            count,
            _allocation: self._allocation,
            _borrowed_allocation_id: self._borrowed_allocation_id,
            _marker: std::marker::PhantomData,
        }
    }

    /// Creates another typed view of the same allocation. The live-allocation
    /// ledger remains shared, so aliases do not inflate byte or buffer totals.
    pub fn alias<U>(&self, count: usize) -> LaniusBuffer<U> {
        LaniusBuffer {
            buffer: self.buffer.clone(),
            byte_offset: self.byte_offset,
            byte_size: self.byte_size,
            count,
            _allocation: self._allocation.clone(),
            _borrowed_allocation_id: self._borrowed_allocation_id,
            _marker: std::marker::PhantomData,
        }
    }

    /// Wraps a raw buffer whose allocation is owned and accounted elsewhere.
    /// Wgpu registry metrics expose these handles as untracked live buffers.
    pub fn untracked_alias((buffer, byte_size): (wgpu::Buffer, u64), count: usize) -> Self {
        Self {
            buffer,
            byte_offset: 0,
            byte_size: byte_size as usize,
            count,
            _allocation: None,
            _borrowed_allocation_id: None,
            _marker: std::marker::PhantomData,
        }
    }
}

impl<T> Deref for LaniusBuffer<T> {
    type Target = wgpu::Buffer;
    fn deref(&self) -> &Self::Target {
        &self.buffer
    }
}

/// Create a UNIFORM buffer from a single ShaderType value (std140 layout in WGSL).
pub fn uniform_from_val<T>(device: &wgpu::Device, label: &str, value: &T) -> LaniusBuffer<T>
where
    T: encase::ShaderType + encase::internal::WriteInto,
{
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(value)
        .expect("failed to write value into UniformBuffer");
    let bytes = ub.as_ref();
    if let Some(buffer) = UNIFORM_BUFFER_ARENA.with(|arena| {
        arena
            .borrow_mut()
            .as_mut()
            .and_then(|arena| arena.allocate(device, bytes))
    }) {
        return buffer.reinterpret(1);
    }
    let raw = create_buffer_init_checked(
        device,
        label,
        bytes,
        wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
    );
    LaniusBuffer::new_labeled((raw, bytes.len() as u64), 1, label)
}

/// Creates a uniform buffer and uploads the encoded value through `queue.write_buffer`.
pub fn uniform_from_val_with_queue<T>(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    label: &str,
    value: &T,
) -> LaniusBuffer<T>
where
    T: encase::ShaderType + encase::internal::WriteInto,
{
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(value)
        .expect("failed to write value into UniformBuffer");
    let bytes = ub.as_ref();
    let raw = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: bytes.len() as u64,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    queue.write_buffer(&raw, 0, bytes);
    LaniusBuffer::new_labeled((raw, bytes.len() as u64), 1, label)
}

struct CachedCapacityBuffer {
    buffer: LaniusBuffer<u8>,
    usage: wgpu::BufferUsages,
}

/// Name-keyed GPU allocations that grow to cover a requested byte range and
/// then retain their physical identity. Sequential compiler jobs can update
/// and rebind logical subranges without reconstructing the underlying buffer.
#[derive(Default)]
pub(crate) struct CapacityBufferCache {
    buffers: Mutex<HashMap<String, CachedCapacityBuffer>>,
}

impl CapacityBufferCache {
    fn ensure_buffer<'a>(
        device: &wgpu::Device,
        label: &str,
        byte_size: usize,
        usage: wgpu::BufferUsages,
        buffers: &'a mut HashMap<String, CachedCapacityBuffer>,
    ) -> &'a CachedCapacityBuffer {
        let replace = buffers
            .get(label)
            .map(|cached| cached.buffer.byte_size < byte_size || !cached.usage.contains(usage))
            .unwrap_or(true);
        if replace {
            let raw = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: byte_size as u64,
                usage,
                mapped_at_creation: false,
            });
            buffers.insert(
                label.to_owned(),
                CachedCapacityBuffer {
                    buffer: LaniusBuffer::new_labeled((raw, byte_size as u64), byte_size, label),
                    usage,
                },
            );
        }
        &buffers[label]
    }

    pub(crate) fn buffer<T>(
        &self,
        device: &wgpu::Device,
        label: &str,
        byte_size: usize,
        count: usize,
        usage: wgpu::BufferUsages,
    ) -> LaniusBuffer<T> {
        let byte_size = byte_size.max(4).next_multiple_of(4);
        let mut buffers = self.buffers.lock().expect("capacity buffer cache poisoned");
        Self::ensure_buffer(device, label, byte_size, usage, &mut buffers)
            .buffer
            .subrange(0, byte_size as u64, count)
            .expect("cached buffer covers its requested logical range")
    }

    /// Returns the complete retained allocation after growing it to cover the
    /// requested range. Bind groups should use this view when active counts
    /// are supplied separately, keeping binding identity stable as jobs vary
    /// within the retained capacity.
    pub(crate) fn binding_capacity<T>(
        &self,
        device: &wgpu::Device,
        label: &str,
        required_byte_size: usize,
        usage: wgpu::BufferUsages,
    ) -> LaniusBuffer<T> {
        let required_byte_size = required_byte_size.max(4).next_multiple_of(4);
        let mut buffers = self.buffers.lock().expect("capacity buffer cache poisoned");
        let cached = Self::ensure_buffer(device, label, required_byte_size, usage, &mut buffers);
        let element_size = std::mem::size_of::<T>().max(1);
        cached
            .buffer
            .subrange(
                0,
                cached.buffer.byte_size as u64,
                cached.buffer.byte_size / element_size,
            )
            .expect("complete capacity buffer view is in bounds")
    }

    pub(crate) fn initialized_u32(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        label: &str,
        words: &[u32],
        extra_usage: wgpu::BufferUsages,
    ) -> LaniusBuffer<u32> {
        let mut bytes = Vec::with_capacity(words.len() * 4);
        for word in words {
            bytes.extend_from_slice(&word.to_le_bytes());
        }
        let buffer = self.buffer(
            device,
            label,
            bytes.len(),
            words.len(),
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST
                | extra_usage,
        );
        buffer.write(queue, 0, &bytes);
        buffer
    }

    pub(crate) fn storage_u32(
        &self,
        device: &wgpu::Device,
        label: &str,
        count: usize,
        extra_usage: wgpu::BufferUsages,
    ) -> LaniusBuffer<u32> {
        self.buffer(
            device,
            label,
            count.max(1) * std::mem::size_of::<u32>(),
            count.max(1),
            wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST
                | extra_usage,
        )
    }

    pub(crate) fn uniform<T>(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        label: &str,
        value: &T,
    ) -> LaniusBuffer<T>
    where
        T: encase::ShaderType + encase::internal::WriteInto,
    {
        let mut encoded = encase::UniformBuffer::new(Vec::<u8>::new());
        encoded
            .write(value)
            .expect("failed to write value into UniformBuffer");
        let bytes = encoded.as_ref();
        let buffer = self.buffer(
            device,
            label,
            bytes.len(),
            1,
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        );
        buffer.write(queue, 0, bytes);
        buffer
    }

    pub(crate) fn clear(&self) {
        self.buffers
            .lock()
            .expect("capacity buffer cache poisoned")
            .clear();
    }
}

/// Creates an alignment-padded uniform table for one dynamically offset
/// binding. Records are encoded independently so each offset has the same
/// layout as a standalone `ConstantBuffer<T>`.
pub fn dynamic_uniforms_from_vals_with_queue<T>(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    label: &str,
    values: &[T],
) -> DynamicUniformBuffer<T>
where
    T: encase::ShaderType + encase::internal::WriteInto,
{
    dynamic_uniforms_from_vals_impl(device, label, values, |bytes| {
        let raw = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: bytes.len() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        queue.write_buffer(&raw, 0, bytes);
        raw
    })
}

/// Creates a dynamic-uniform table through the checked mapped-at-creation
/// path when construction does not own a queue.
pub fn dynamic_uniforms_from_vals<T>(
    device: &wgpu::Device,
    label: &str,
    values: &[T],
) -> DynamicUniformBuffer<T>
where
    T: encase::ShaderType + encase::internal::WriteInto,
{
    dynamic_uniforms_from_vals_impl(device, label, values, |bytes| {
        create_buffer_init_checked(
            device,
            label,
            bytes,
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        )
    })
}

fn dynamic_uniforms_from_vals_impl<T>(
    device: &wgpu::Device,
    label: &str,
    values: &[T],
    create: impl FnOnce(&[u8]) -> wgpu::Buffer,
) -> DynamicUniformBuffer<T>
where
    T: encase::ShaderType + encase::internal::WriteInto,
{
    assert!(
        !values.is_empty(),
        "dynamic uniform table must not be empty"
    );
    let encoded = values
        .iter()
        .map(|value| {
            let mut uniform = encase::UniformBuffer::new(Vec::<u8>::new());
            uniform
                .write(value)
                .expect("failed to encode dynamic uniform value");
            uniform.into_inner()
        })
        .collect::<Vec<_>>();
    let binding_len = encoded[0].len();
    assert!(
        encoded.iter().all(|bytes| bytes.len() == binding_len),
        "dynamic uniform records have inconsistent encoded sizes"
    );
    let alignment = device.limits().min_uniform_buffer_offset_alignment.max(1) as usize;
    let stride = binding_len.div_ceil(alignment) * alignment;
    let mut bytes = vec![0u8; stride * values.len()];
    for (index, value) in encoded.iter().enumerate() {
        bytes[index * stride..index * stride + binding_len].copy_from_slice(value);
    }
    let raw = create(&bytes);
    DynamicUniformBuffer {
        buffer: LaniusBuffer::new_labeled((raw, bytes.len() as u64), bytes.len(), label),
        stride: stride
            .try_into()
            .expect("dynamic uniform stride exceeds u32"),
        binding_size: std::num::NonZeroU64::new(binding_len as u64)
            .expect("uniform encoding must not be empty"),
        count: values.len(),
        _marker: std::marker::PhantomData,
    }
}

/// Create a STORAGE (read-only) buffer from a raw byte slice.
pub fn storage_ro_from_bytes<T>(
    device: &wgpu::Device,
    label: &str,
    bytes: &[u8],
    count: usize,
) -> LaniusBuffer<T> {
    let raw = create_buffer_init_checked(
        device,
        label,
        bytes,
        wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
    );
    LaniusBuffer::new_labeled((raw, bytes.len() as u64), count, label)
}

fn create_buffer_init_checked(
    device: &wgpu::Device,
    label: &str,
    contents: &[u8],
    usage: wgpu::BufferUsages,
) -> wgpu::Buffer {
    if contents.is_empty() {
        return device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: 0,
            usage,
            mapped_at_creation: false,
        });
    }

    let unpadded_size = contents.len() as wgpu::BufferAddress;
    let align_mask = wgpu::COPY_BUFFER_ALIGNMENT - 1;
    let padded_size = ((unpadded_size + align_mask) & !align_mask).max(wgpu::COPY_BUFFER_ALIGNMENT);
    let oom_scope = device.push_error_scope(wgpu::ErrorFilter::OutOfMemory);
    let internal_scope = device.push_error_scope(wgpu::ErrorFilter::Internal);
    let validation_scope = device.push_error_scope(wgpu::ErrorFilter::Validation);
    let buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: padded_size,
        usage,
        mapped_at_creation: true,
    });
    let _ = device.poll(wgpu::PollType::Poll);
    let validation_error = pollster::block_on(validation_scope.pop());
    let internal_error = pollster::block_on(internal_scope.pop());
    let oom_error = pollster::block_on(oom_scope.pop());
    if let Some(err) = validation_error.or(internal_error).or(oom_error) {
        panic!("failed to create initialized GPU buffer {label}: {err:?}");
    }

    buffer
        .get_mapped_range_mut(..)
        .slice(..contents.len())
        .copy_from_slice(contents);
    buffer.unmap();
    buffer
}

/// Create a STORAGE (read-only) buffer from `&[u32]`.
pub fn storage_ro_from_u32s(
    device: &wgpu::Device,
    label: &str,
    values: &[u32],
) -> LaniusBuffer<u32> {
    let mut bytes = Vec::with_capacity(values.len() * 4);

    for &v in values {
        bytes.extend_from_slice(&v.to_le_bytes());
    }
    debug_assert_eq!(
        bytes.len(),
        values.len() * 4,
        "storage_ro_from_u32s({label}): packing mismatch"
    );
    storage_ro_from_bytes::<u32>(device, label, &bytes, values.len())
}

/// Creates read-only `u32` storage and uploads through `queue.write_buffer`.
pub fn storage_ro_from_u32s_with_queue(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    label: &str,
    values: &[u32],
) -> LaniusBuffer<u32> {
    let mut bytes = Vec::with_capacity(values.len() * 4);

    for &v in values {
        bytes.extend_from_slice(&v.to_le_bytes());
    }
    debug_assert_eq!(
        bytes.len(),
        values.len() * 4,
        "storage_ro_from_u32s_with_queue({label}): packing mismatch"
    );
    let byte_size = bytes.len();
    let raw = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_size as u64,
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_DST
            | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });
    if !bytes.is_empty() {
        queue.write_buffer(&raw, 0, &bytes);
    }
    LaniusBuffer::new_labeled((raw, byte_size as u64), values.len(), label)
}

/// Creates a map-readable byte readback buffer.
pub fn readback_bytes(
    device: &wgpu::Device,
    label: &str,
    byte_size: usize,
    count: usize,
) -> LaniusBuffer<u8> {
    let raw = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_size as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    LaniusBuffer::new_labeled((raw, byte_size as u64), count, label)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum JobResetPolicy {
    /// Clear the allocation before each job because some first read requires a baseline value.
    ClearBeforeJob,
}

/// Create a STORAGE buffer (read/write) sized for an array of `T` using WGSL/std430 size/stride.
/// We compute the **padded element size** by encoding one `T::default()` with `encase::StorageBuffer`.
/// Requires `T: Default` so we can synthesize one element just to measure its layout.
pub fn storage_rw_for_array<T>(device: &wgpu::Device, label: &str, count: usize) -> LaniusBuffer<T>
where
    T: Default + encase::ShaderType + encase::internal::WriteInto,
{
    storage_rw_for_array_with_reset_policy(device, label, count, JobResetPolicy::ClearBeforeJob)
}

pub(crate) fn storage_rw_for_array_with_reset_policy<T>(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    reset_policy: JobResetPolicy,
) -> LaniusBuffer<T>
where
    T: Default + encase::ShaderType + encase::internal::WriteInto,
{
    let mut sb = encase::StorageBuffer::new(Vec::<u8>::new());
    sb.write(&T::default())
        .expect("failed to write default element into StorageBuffer");
    let elem_padded_bytes = sb.as_ref().len(); // encase gives us the correct std430-padded size
    debug_assert!(
        elem_padded_bytes > 0,
        "encase reported zero-sized element for {label}"
    );
    let total = elem_padded_bytes
        .checked_mul(count)
        .expect("overflow sizing storage buffer");
    let raw = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: total as u64,
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_SRC
            | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let buffer = LaniusBuffer::new_labeled((raw, total as u64), count, label);
    register_resettable_buffer(&buffer, reset_policy);
    buffer
}

/// Create a STORAGE buffer (read/write) with an explicit byte size. Element type is `u8`.
/// Handy for generic scratch space when the shader side uses `array<u32>`/`array<u8>`.
pub fn storage_rw_uninit_bytes(
    device: &wgpu::Device,
    label: &str,
    byte_size: usize,
    count: usize,
) -> LaniusBuffer<u8> {
    let raw = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_size as u64,
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_SRC
            | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    let buffer = LaniusBuffer::new_labeled((raw, byte_size as u64), count, label);
    register_resettable_buffer(&buffer, JobResetPolicy::ClearBeforeJob);
    buffer
}

#[cfg(test)]
mod tests {
    use super::*;

    static ALLOCATION_LEDGER_TEST_LOCK: Mutex<()> = Mutex::new(());

    #[test]
    fn allocation_peak_window_starts_at_live_baseline_and_tracks_high_water_mark() {
        let _guard = ALLOCATION_LEDGER_TEST_LOCK.lock().unwrap();
        let baseline = tracked_buffer_allocation_stats();
        assert_eq!(reset_tracked_buffer_allocation_peaks(), baseline);
        assert_eq!(tracked_buffer_allocation_peak_stats(), baseline);

        let first = BufferAllocationLedger::new(41, "test.buffer-peak.first");
        let second = BufferAllocationLedger::new(59, "test.buffer-peak.second");
        let peak = tracked_buffer_allocation_peak_stats();
        assert_eq!(peak.allocations, baseline.allocations + 2);
        assert_eq!(peak.bytes, baseline.bytes + 100);

        drop(second);
        assert_eq!(tracked_buffer_allocation_peak_stats(), peak);
        drop(first);
    }

    #[test]
    fn allocation_label_breakdown_tracks_shared_ledger_lifetime() {
        let _guard = ALLOCATION_LEDGER_TEST_LOCK.lock().unwrap();
        const LABEL: &str = "test.buffer-ledger.unique-label";
        assert!(
            tracked_buffer_allocation_stats_by_label()
                .iter()
                .all(|row| row.label.as_ref() != LABEL)
        );

        let ledger = BufferAllocationLedger::new(123, LABEL);
        let alias = ledger.clone();
        let row = tracked_buffer_allocation_stats_by_label()
            .into_iter()
            .find(|row| row.label.as_ref() == LABEL)
            .expect("labeled allocation should appear in the breakdown");
        assert_eq!((row.allocations, row.bytes), (1, 123));

        drop(ledger);
        assert!(
            tracked_buffer_allocation_stats_by_label()
                .iter()
                .any(|row| row.label.as_ref() == LABEL),
            "an alias must keep the allocation ledger live"
        );
        drop(alias);
        assert!(
            tracked_buffer_allocation_stats_by_label()
                .iter()
                .all(|row| row.label.as_ref() != LABEL)
        );
    }

    #[test]
    fn phase_snapshots_are_named_and_reset_with_the_peak_window() {
        let baseline = reset_tracked_buffer_allocation_peaks();
        assert!(tracked_buffer_phase_snapshots().is_empty());
        assert_eq!(record_tracked_buffer_phase_snapshot("parse"), baseline);
        assert_eq!(
            tracked_buffer_phase_snapshots(),
            vec![TrackedBufferPhaseSnapshot {
                phase: Arc::from("parse"),
                stats: baseline,
            }]
        );
        reset_tracked_buffer_allocation_peaks();
        assert!(tracked_buffer_phase_snapshots().is_empty());
    }

    #[test]
    fn residency_timeline_records_physical_allocation_lifetime() {
        let _guard = ALLOCATION_LEDGER_TEST_LOCK.lock().unwrap();
        begin_tracked_buffer_residency_timeline(true);
        let baseline = tracked_buffer_allocation_stats();
        let ledger = BufferAllocationLedger::new(77, "test.buffer-timeline");
        drop(ledger);

        let points = tracked_buffer_residency_timeline();
        assert_eq!(points.len(), 3);
        assert_eq!(points[0].event, "baseline");
        assert_eq!(
            (points[0].allocations, points[0].bytes),
            (baseline.allocations, baseline.bytes)
        );
        assert_eq!(points[1].event, "allocate");
        assert_eq!(points[1].changed_bytes, 77);
        assert_eq!(points[2].event, "release");
        assert_eq!(points[2].changed_bytes, 77);
        assert_eq!(
            (points[2].allocations, points[2].bytes),
            (baseline.allocations, baseline.bytes)
        );
        begin_tracked_buffer_residency_timeline(false);
    }
}
