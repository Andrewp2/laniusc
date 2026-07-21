use std::{
    collections::HashMap,
    ops::Deref,
    sync::{
        Arc,
        LazyLock,
        Mutex,
        atomic::{AtomicU64, Ordering},
    },
};

static LIVE_BUFFER_ALLOCATIONS: AtomicU64 = AtomicU64::new(0);
static LIVE_BUFFER_BYTES: AtomicU64 = AtomicU64::new(0);
static PEAK_BUFFER_ALLOCATIONS: AtomicU64 = AtomicU64::new(0);
static PEAK_BUFFER_BYTES: AtomicU64 = AtomicU64::new(0);
static NEXT_BUFFER_ALLOCATION_ID: AtomicU64 = AtomicU64::new(1);
static LIVE_BUFFER_BYTES_BY_LABEL: LazyLock<Mutex<HashMap<Arc<str>, (u64, u64)>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
static BUFFER_PHASE_SNAPSHOTS: LazyLock<Mutex<Vec<TrackedBufferPhaseSnapshot>>> =
    LazyLock::new(|| Mutex::new(Vec::new()));

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

pub fn tracked_buffer_allocation_stats() -> TrackedBufferAllocationStats {
    TrackedBufferAllocationStats {
        allocations: LIVE_BUFFER_ALLOCATIONS.load(Ordering::Relaxed),
        bytes: LIVE_BUFFER_BYTES.load(Ordering::Relaxed),
    }
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
}

impl BufferAllocationLedger {
    fn new(bytes: u64, label: impl Into<Arc<str>>) -> Arc<Self> {
        let label = label.into();
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
        Arc::new(Self {
            id: NEXT_BUFFER_ALLOCATION_ID.fetch_add(1, Ordering::Relaxed),
            bytes,
            label,
        })
    }
}

impl Drop for BufferAllocationLedger {
    fn drop(&mut self) {
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
    }
}

/// A thin wrapper around `wgpu::Buffer` that also tracks element count and byte size.
/// Always create these via the helpers below so we respect WGSL/encase layout rules.
#[derive(Clone)]
pub struct LaniusBuffer<T> {
    pub buffer: wgpu::Buffer,
    /// total allocated size in bytes
    pub byte_size: usize,
    /// number of logical T elements
    pub count: usize,
    _allocation: Option<Arc<BufferAllocationLedger>>,
    _marker: std::marker::PhantomData<T>,
}

impl<T> LaniusBuffer<T> {
    /// Stable identity of the physical GPU allocation shared by all aliases.
    /// Buffers wrapped through `untracked_alias` have no compiler-owned id.
    pub fn allocation_id(&self) -> Option<u64> {
        self._allocation.as_ref().map(|allocation| allocation.id)
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
        Self {
            buffer,
            byte_size: byte_size as usize,
            count,
            _allocation: Some(BufferAllocationLedger::new(byte_size, label)),
            _marker: std::marker::PhantomData,
        }
    }

    /// Reinterprets this allocation as another element type without changing
    /// its allocation identity.
    pub fn reinterpret<U>(self, count: usize) -> LaniusBuffer<U> {
        LaniusBuffer {
            buffer: self.buffer,
            byte_size: self.byte_size,
            count,
            _allocation: self._allocation,
            _marker: std::marker::PhantomData,
        }
    }

    /// Creates another typed view of the same allocation. The live-allocation
    /// ledger remains shared, so aliases do not inflate byte or buffer totals.
    pub fn alias<U>(&self, count: usize) -> LaniusBuffer<U> {
        LaniusBuffer {
            buffer: self.buffer.clone(),
            byte_size: self.byte_size,
            count,
            _allocation: self._allocation.clone(),
            _marker: std::marker::PhantomData,
        }
    }

    /// Wraps a raw buffer whose allocation is owned and accounted elsewhere.
    /// Wgpu registry metrics expose these handles as untracked live buffers.
    pub fn untracked_alias((buffer, byte_size): (wgpu::Buffer, u64), count: usize) -> Self {
        Self {
            buffer,
            byte_size: byte_size as usize,
            count,
            _allocation: None,
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

/// Create a STORAGE buffer (read/write) sized for an array of `T` using WGSL/std430 size/stride.
/// We compute the **padded element size** by encoding one `T::default()` with `encase::StorageBuffer`.
/// Requires `T: Default` so we can synthesize one element just to measure its layout.
pub fn storage_rw_for_array<T>(device: &wgpu::Device, label: &str, count: usize) -> LaniusBuffer<T>
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
    LaniusBuffer::new_labeled((raw, total as u64), count, label)
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
    LaniusBuffer::new_labeled((raw, byte_size as u64), count, label)
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
}
