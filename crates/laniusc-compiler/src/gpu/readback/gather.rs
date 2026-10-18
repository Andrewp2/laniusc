//! GPU gather for sparse batched readbacks.
//!
//! Fact readers pass `PagedReadback::read_regions` thousands of word-sized
//! rows. One buffer copy per row costs about 2 µs of encoding plus GPU time,
//! so ~12k rows took ~22 ms of a warm 1 MB job. Instead, one dispatch per
//! source buffer gathers the small rows into a dense image, and the page loop
//! copies that image with a few coalesced copies. All dispatches of one
//! readback share one compute pass.
//!
//! Word readbacks (`PagedReadback::read_words`) also take sets of rows of
//! fixed-stride tables. Their records are written straight from the row
//! indices, so ~40k rows of a 1.4 MB generic program no longer cost one
//! region each to plan, group, remap and copy.
//!
//! A dispatch's bind group names only whole buffers (a source, or a fixed
//! window of one too large to bind) and the retained region records, output
//! and params buffers; its record range comes through a dynamic uniform
//! offset. A record names a whole region (output word, source word, word
//! count), so a 32-word row uploads 12 bytes instead of 32 word pairs. Readbacks
//! of other regions therefore reuse the cached bind groups, and new ones are
//! created only for a new source buffer or when a retained buffer grows.

use std::{
    collections::HashMap,
    num::NonZeroU64,
    sync::{
        Mutex,
        MutexGuard,
        TryLockError,
        atomic::{AtomicBool, Ordering},
    },
};

use anyhow::Result;
use log::warn;

use super::{ReadbackRegion, ReadbackRows, WordRead};
use crate::gpu::{
    buffers::{LaniusBuffer, with_debug_copy},
    passes_core::{self, DispatchDim, InputElements, PassData},
};

const GATHER_SHADER: &str = "readback/gather_words";
const GATHER_LABEL: &str = "readback.gather";
const GATHER_PARAMS: &str = "gather_params";
/// One `GatherParams` record: first region record, record count, padding.
const PARAMS_BYTES: usize = 16;
/// Words of one region record: output word, source word, word count.
const RECORD_WORDS: usize = 3;
/// Below this many small regions, direct copies cost about as much as the
/// gather's upload and dispatch.
const MIN_GATHER_REGIONS: usize = 64;
/// Larger regions already copy efficiently.
const MAX_GATHER_REGION_BYTES: usize = 256;
/// Groups remembered while grouping regions, before the window map.
const RECENT_GROUPS: usize = 8;
/// Bounds the retained gather buffers (16 MiB of output, at most 48 MiB of
/// records when every region is one word).
const MAX_GATHER_WORDS: usize = 1 << 22;

struct GatherKernel {
    device: wgpu::Device,
    pass: PassData,
    records: Option<LaniusBuffer<u32>>,
    output: Option<LaniusBuffer<u32>>,
    /// One params record per dispatch, at uniform-offset-aligned strides.
    params: Option<LaniusBuffer<u32>>,
}

static GATHER: Mutex<Option<GatherKernel>> = Mutex::new(None);
static GATHER_UNAVAILABLE: AtomicBool = AtomicBool::new(false);

/// Exclusive use of the gather kernel and its retained buffers for one
/// batched readback. Concurrent readbacks copy directly instead of waiting.
pub(super) struct GatherLease(MutexGuard<'static, Option<GatherKernel>>);

/// Leases the gather for a readback of `region_count` regions, or returns
/// `None` when direct copies should be used.
pub(super) fn lease(device: &wgpu::Device, region_count: usize) -> Option<GatherLease> {
    if region_count < MIN_GATHER_REGIONS
        || GATHER_UNAVAILABLE.load(Ordering::Relaxed)
        || passes_core::debug_operation_limited()
        // Retained buffers belong to one device: the compiler's global one.
        || !crate::gpu::device::is_global_device(device)
    {
        return None;
    }
    let mut guard = match GATHER.try_lock() {
        Ok(guard) => guard,
        Err(TryLockError::Poisoned(poisoned)) => poisoned.into_inner(),
        Err(TryLockError::WouldBlock) => return None,
    };
    if guard.as_ref().is_none_or(|kernel| kernel.device != *device) {
        match passes_core::make_pass_data_from_shader_key_with_dynamic_uniforms(
            device,
            GATHER_LABEL,
            "main",
            GATHER_SHADER,
            &[GATHER_PARAMS],
        ) {
            Ok(pass) => {
                *guard = Some(GatherKernel {
                    device: device.clone(),
                    pass,
                    records: None,
                    output: None,
                    params: None,
                });
            }
            Err(err) => {
                warn!("readback gather unavailable, copying regions directly: {err:#}");
                GATHER_UNAVAILABLE.store(true, Ordering::Relaxed);
                return None;
            }
        }
    }
    Some(GatherLease(guard))
}

/// The source buffer of one dispatch: its bound window (offset, size) and
/// the records of the gathered regions that lie inside it.
struct SourceGroup<'a> {
    source: &'a wgpu::Buffer,
    window: (u64, u64),
    records: Vec<u8>,
}

/// The bound window (offset, size) of `source` that holds the bytes
/// `start..end`, or `None` when they cannot be gathered from it. A source that
/// fits one binding is bound whole. A larger one binds `max_window`-byte
/// windows starting every half window, so a small region lies inside the
/// window of its half-window index. Windows depend only on the buffer, never
/// on which regions are read.
fn source_window(
    source: &wgpu::Buffer,
    start: u64,
    end: u64,
    align: u64,
    max_window: u64,
) -> Option<(u64, u64)> {
    let size = source.size() & !3;
    if end > size {
        return None;
    }
    if size <= max_window {
        return Some((0, size));
    }
    let half = max_window / 2 / align * align;
    if half < MAX_GATHER_REGION_BYTES as u64 {
        return None;
    }
    let offset = start / half * half;
    let window_end = (offset + max_window).min(size);
    (end <= window_end).then_some((offset, window_end - offset))
}

/// Regions after a gather was recorded: small regions name their words in
/// the gather image, other regions are unchanged.
pub(super) struct Gathered<'a> {
    pub(super) regions: Vec<ReadbackRegion<'a>>,
    pub(super) gathered_regions: usize,
    pub(super) dispatches: usize,
}

/// A word readback after a gather was recorded: where each gathered read's
/// words start in the image, which holds the gathered reads in order.
pub(super) struct GatheredWords<'a> {
    pub(super) output: &'a wgpu::Buffer,
    pub(super) image_starts: Vec<Option<u32>>,
    pub(super) gathered_regions: usize,
    pub(super) dispatches: usize,
}

/// The gather dispatches of one readback: one per source window, each with
/// the records of its regions.
struct GatherPlan<'a> {
    align: u64,
    max_window: u64,
    groups: Vec<SourceGroup<'a>>,
    group_by_window: HashMap<(&'a wgpu::Buffer, u64), usize>,
    /// Readers interleave the rows of a few buffers (a record's columns);
    /// the last few groups let most regions skip the window map.
    recent: [Option<(&'a wgpu::Buffer, u64, usize)>; RECENT_GROUPS],
    next_recent: usize,
    /// Words of the image so far: the next gathered region's first word.
    image_words: usize,
    regions: usize,
}

impl<'a> GatherPlan<'a> {
    fn new(device: &wgpu::Device) -> Self {
        let limits = device.limits();
        Self {
            align: u64::from(limits.min_storage_buffer_offset_alignment).max(8),
            max_window: limits.max_storage_buffer_binding_size.min(u64::from(u32::MAX)) & !3,
            groups: Vec::new(),
            group_by_window: HashMap::new(),
            recent: [None; RECENT_GROUPS],
            next_recent: 0,
            image_words: 0,
            regions: 0,
        }
    }

    fn gatherable_source(source: &wgpu::Buffer) -> bool {
        source.usage().contains(wgpu::BufferUsages::STORAGE)
    }

    /// Whether every row of a `width_bytes`-wide column of `source` can be
    /// gathered. A row that small always lies inside one window.
    fn gatherable_rows(&self, source: &wgpu::Buffer, width_bytes: usize) -> bool {
        width_bytes != 0
            && width_bytes <= MAX_GATHER_REGION_BYTES
            && Self::gatherable_source(source)
            && (source.size() & !3 <= self.max_window
                || self.max_window / 2 / self.align * self.align
                    >= MAX_GATHER_REGION_BYTES as u64)
    }

    fn group(&mut self, source: &'a wgpu::Buffer, window: (u64, u64)) -> usize {
        let known = self
            .recent
            .iter()
            .flatten()
            .find(|&&(known, offset, _)| offset == window.0 && known == source);
        if let Some(&(_, _, group)) = known {
            return group;
        }
        let groups = &mut self.groups;
        let group = *self.group_by_window.entry((source, window.0)).or_insert_with(|| {
            groups.push(SourceGroup {
                source,
                window,
                records: Vec::new(),
            });
            groups.len() - 1
        });
        self.recent[self.next_recent % RECENT_GROUPS] = Some((source, window.0, group));
        self.next_recent += 1;
        group
    }

    /// Queues `words` words from the absolute byte `start`, which lies in
    /// `group`'s window, at the next image word.
    fn push(&mut self, group: usize, start: u64, words: usize) {
        let group = &mut self.groups[group];
        let source_word = ((start - group.window.0) / 4) as u32;
        for word in [self.image_words as u32, source_word, words as u32] {
            group.records.extend_from_slice(&word.to_le_bytes());
        }
        self.image_words += words;
        self.regions += 1;
    }

    /// Queues one region when it is small enough to gather and returns its
    /// first image word.
    fn push_region(&mut self, region: &ReadbackRegion<'a>) -> Option<u32> {
        if region.byte_len == 0
            || region.byte_len > MAX_GATHER_REGION_BYTES
            || !Self::gatherable_source(region.source)
        {
            return None;
        }
        let start = region.source_offset;
        let end = start + region.byte_len.next_multiple_of(4) as u64;
        let window = source_window(region.source, start, end, self.align, self.max_window)?;
        let group = self.group(region.source, window);
        let image = self.image_words as u32;
        self.push(group, start, region.byte_len.div_ceil(4));
        Some(image)
    }

    /// Queues every row of `rows` when all of its columns can be gathered
    /// and returns the rows' first image word.
    fn push_rows(&mut self, rows: &ReadbackRows<'a>) -> Option<u32> {
        if rows.indices.is_empty()
            || !rows
                .columns
                .iter()
                .all(|column| self.gatherable_rows(column.source, column.width_words * 4))
        {
            return None;
        }
        let image = self.image_words as u32;
        // A column whose buffer is bound whole has one group for every row.
        let whole = rows
            .columns
            .iter()
            .map(|column| {
                let size = column.source.size() & !3;
                (size <= self.max_window).then(|| self.group(column.source, (0, size)))
            })
            .collect::<Vec<_>>();
        if let ([column], [Some(group)]) = (&rows.columns[..], &whole[..]) {
            // One column of a buffer bound whole, the common shape: one
            // record per row, written directly.
            let records = &mut self.groups[*group].records;
            records.reserve(rows.indices.len() * RECORD_WORDS * 4);
            let first_word = (column.base / 4) as u32;
            let stride = column.stride_words as u32;
            let width = column.width_words as u32;
            let mut image_word = image;
            for &index in &rows.indices {
                for word in [image_word, first_word + index * stride, width] {
                    records.extend_from_slice(&word.to_le_bytes());
                }
                image_word += width;
            }
            self.image_words = image_word as usize;
            self.regions += rows.indices.len();
            return Some(image);
        }
        for &index in &rows.indices {
            for (column, whole) in rows.columns.iter().zip(&whole) {
                let start = column.row_offset(index);
                let group = match whole {
                    Some(group) => *group,
                    None => {
                        let end = start + column.width_words as u64 * 4;
                        let window =
                            source_window(column.source, start, end, self.align, self.max_window)
                                .expect("a gatherable row lies inside one window");
                        self.group(column.source, window)
                    }
                };
                self.push(group, start, column.width_words);
            }
        }
        Some(image)
    }
}

impl GatherLease {
    /// Records the gather of every small region into `encoder` and returns
    /// the regions to copy instead. Returns `None`, recording nothing, when
    /// too few regions qualify. Callers must submit `encoder` once this
    /// returns `Some`: it holds timestamps of the recorded dispatches.
    pub(super) fn record<'a>(
        &'a mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        regions: &[ReadbackRegion<'a>],
        label: &str,
    ) -> Result<Option<Gathered<'a>>> {
        let mut plan = GatherPlan::new(device);
        // The image keeps region order, so consecutive gathered regions copy
        // to the staging page as one range.
        let image_words = regions
            .iter()
            .map(|region| plan.push_region(region))
            .collect::<Vec<_>>();
        let gathered_regions = plan.regions;
        let Some((output, dispatches)) = self.dispatch(device, queue, encoder, plan, label)? else {
            return Ok(None);
        };
        let regions = regions
            .iter()
            .zip(&image_words)
            .map(|(region, image)| match image {
                Some(word) => ReadbackRegion {
                    source: output,
                    source_offset: u64::from(*word) * 4,
                    byte_len: region.byte_len,
                },
                None => *region,
            })
            .collect();
        Ok(Some(Gathered {
            regions,
            gathered_regions,
            dispatches,
        }))
    }

    /// [`Self::record`] for a word readback: gathers each small region and
    /// each set of rows whose columns can all be gathered.
    pub(super) fn record_words<'a>(
        &'a mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        reads: &[WordRead<'a>],
        label: &str,
    ) -> Result<Option<GatheredWords<'a>>> {
        let mut plan = GatherPlan::new(device);
        let image_starts = reads
            .iter()
            .map(|read| match read {
                WordRead::Region(region) => plan.push_region(region),
                WordRead::Rows(rows) => plan.push_rows(rows),
            })
            .collect::<Vec<_>>();
        let gathered_regions = plan.regions;
        let Some((output, dispatches)) = self.dispatch(device, queue, encoder, plan, label)? else {
            return Ok(None);
        };
        Ok(Some(GatheredWords {
            output,
            image_starts,
            gathered_regions,
            dispatches,
        }))
    }

    /// Uploads the plan's records and records its dispatches, in one compute
    /// pass unless operation timing needs a pass per dispatch. Returns the
    /// image buffer and the dispatch count, or `None`, recording nothing,
    /// when the plan is too small or too large to gather.
    fn dispatch<'a>(
        &'a mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        plan: GatherPlan<'_>,
        label: &str,
    ) -> Result<Option<(&'a wgpu::Buffer, usize)>> {
        if plan.regions < MIN_GATHER_REGIONS || plan.image_words > MAX_GATHER_WORDS {
            return Ok(None);
        }
        let image_words = plan.image_words;
        let groups = plan.groups;
        let limits = device.limits();
        // One run of region records per group, named by the group's params
        // record.
        let params_stride = PARAMS_BYTES
            .next_multiple_of(limits.min_uniform_buffer_offset_alignment.max(1) as usize);
        let record_bytes = groups.iter().map(|group| group.records.len()).sum::<usize>();
        let mut params = vec![0u8; groups.len() * params_stride];
        let mut first = 0u32;
        for (slot, group) in groups.iter().enumerate() {
            let count = (group.records.len() / (RECORD_WORDS * 4)) as u32;
            let slot_params = &mut params[slot * params_stride..][..8];
            slot_params[..4].copy_from_slice(&first.to_le_bytes());
            slot_params[4..].copy_from_slice(&count.to_le_bytes());
            first += count;
        }

        let records = retained_buffer(
            device,
            &mut self.kernel().records,
            "readback.gather.records",
            record_bytes / 4,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        );
        let mut offset = 0u64;
        for group in &groups {
            records.write(queue, offset, &group.records);
            offset += group.records.len() as u64;
        }
        retained_buffer(
            device,
            &mut self.kernel().output,
            "readback.gather.output",
            image_words,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        );
        retained_buffer(
            device,
            &mut self.kernel().params,
            "readback.gather.params",
            params.len() / 4,
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        )
        .write(queue, 0, &params);

        let kernel = self.0.as_ref().expect("leased gather kernel");
        let records_buffer = kernel.records.as_ref().expect("gather records buffer");
        let output = kernel.output.as_ref().expect("gather output buffer");
        let params_buffer = kernel.params.as_ref().expect("gather params buffer");
        // Create every bind group before recording, so an error leaves no
        // stamped dispatch in an encoder that is never submitted.
        let mut dispatches = Vec::with_capacity(groups.len());
        for (slot, group) in groups.iter().enumerate() {
            let record_count = (group.records.len() / (RECORD_WORDS * 4)) as u32;
            let params = wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                buffer: &params_buffer.buffer,
                offset: 0,
                size: NonZeroU64::new(PARAMS_BYTES as u64),
            });
            let source = wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                buffer: group.source,
                offset: group.window.0,
                size: NonZeroU64::new(group.window.1),
            });
            let bindings = passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some(GATHER_LABEL),
                &kernel.pass,
                0,
                &[
                    (GATHER_PARAMS, params),
                    ("gather_source", source),
                    ("gather_regions", records_buffer.as_entire_binding()),
                    ("gather_output", output.as_entire_binding()),
                ],
            )?;
            let workgroups = passes_core::plan_workgroups(
                DispatchDim::D1,
                InputElements::Elements1D(record_count),
                kernel.pass.thread_group_size,
            )?;
            dispatches.push((bindings, (slot * params_stride) as u32, workgroups));
        }
        let descriptor = wgpu::ComputePassDescriptor {
            label: Some(GATHER_LABEL),
            timestamp_writes: None,
        };
        let timing_label = format!("{GATHER_LABEL}.{label}");
        // The dispatches write disjoint image words, so one pass holds them
        // all unless the timer can stamp only between passes.
        if crate::gpu::timer::operation_capture_requires_split_passes() {
            for (bindings, params_offset, (x, y, z)) in &dispatches {
                {
                    let mut pass = passes_core::begin_counted_compute_pass(encoder, &descriptor);
                    pass.set_pipeline(&kernel.pass.pipeline);
                    pass.set_bind_group(0, Some(bindings), &[*params_offset]);
                    passes_core::record_compute_dispatch();
                    pass.dispatch_workgroups(*x, *y, *z);
                }
                crate::gpu::timer::stamp_active_operation(encoder, timing_label.clone());
            }
        } else {
            let timed = crate::gpu::timer::operation_capture_active();
            let mut pass = passes_core::begin_counted_compute_pass(encoder, &descriptor);
            pass.set_pipeline(&kernel.pass.pipeline);
            for (bindings, params_offset, (x, y, z)) in &dispatches {
                pass.set_bind_group(0, Some(bindings), &[*params_offset]);
                passes_core::record_compute_dispatch();
                pass.dispatch_workgroups(*x, *y, *z);
                if timed {
                    crate::gpu::timer::stamp_active_operation_in_pass(
                        &mut pass,
                        timing_label.clone(),
                    );
                }
            }
        }
        Ok(Some((&output.buffer, dispatches.len())))
    }

    fn kernel(&mut self) -> &mut GatherKernel {
        self.0.as_mut().expect("leased gather kernel")
    }
}

/// Grows a retained gather buffer to hold `words` words, keeping power-of-two
/// capacities so varying jobs reuse one allocation.
fn retained_buffer<'b>(
    device: &wgpu::Device,
    slot: &'b mut Option<LaniusBuffer<u32>>,
    label: &str,
    words: usize,
    usage: wgpu::BufferUsages,
) -> &'b LaniusBuffer<u32> {
    let bytes = words.max(64).next_power_of_two() * 4;
    if slot.as_ref().is_none_or(|buffer| buffer.byte_size < words * 4) {
        let raw = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: bytes as u64,
            usage: with_debug_copy(usage),
            mapped_at_creation: false,
        });
        *slot = Some(LaniusBuffer::new_labeled((raw, bytes as u64), bytes / 4, label));
    }
    slot.as_ref().expect("retained gather buffer")
}

#[cfg(test)]
mod tests {
    use std::time::{Duration, Instant};

    use super::*;
    use crate::gpu::device;

    fn gather_bind_groups_created() -> u64 {
        passes_core::bind_group_creation_counts_by_label()
            .get(GATHER_LABEL)
            .copied()
            .unwrap_or(0)
    }

    fn storage(device: &wgpu::Device, label: &str) -> LaniusBuffer<u8> {
        let buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: 4096,
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        LaniusBuffer::new_labeled((buffer, 4096), 4096, label)
    }

    fn regions<'a>(
        sources: [&'a LaniusBuffer<u8>; 2],
        count: u64,
        stride: u64,
    ) -> Vec<ReadbackRegion<'a>> {
        (0..count)
            .map(|i| {
                let offset = (i * stride) % 4000 / 4 * 4;
                let len = 4 + (i % 3) as usize * 4;
                ReadbackRegion::from_buffer(sources[(i % 2) as usize], offset, len, "region")
                    .unwrap()
            })
            .collect()
    }

    /// Readbacks of other regions from the same sources reuse the gather's
    /// bind groups, so warm jobs create none. Only the lease holder creates
    /// gather bind groups, so holding the lease makes the count exact.
    #[test]
    fn gpu_gather_bind_groups_do_not_depend_on_regions() {
        let gpu = device::global();
        let first = storage(&gpu.device, "gather reuse first");
        let second = storage(&gpu.device, "gather reuse second");
        let deadline = Instant::now() + Duration::from_secs(60);
        let mut lease = loop {
            if let Some(lease) = lease(&gpu.device, MIN_GATHER_REGIONS) {
                break lease;
            }
            assert!(Instant::now() < deadline, "gather lease unavailable");
            std::thread::yield_now();
        };
        let validation = gpu.device.push_error_scope(wgpu::ErrorFilter::Validation);
        let mut created = Vec::new();
        // Decreasing sizes: no retained buffer grows after the first gather.
        for (count, stride) in [(300, 52), (200, 36), (120, 100)] {
            let before = gather_bind_groups_created();
            let regions = regions([&first, &second], count, stride);
            let mut encoder = gpu
                .device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("gather reuse test"),
                });
            let dispatches = lease
                .record(&gpu.device, &gpu.queue, &mut encoder, &regions, "reuse test")
                .unwrap()
                .expect("enough regions to gather")
                .dispatches;
            gpu.queue.submit([encoder.finish()]);
            assert_eq!(dispatches, 2, "one dispatch per source buffer");
            created.push(gather_bind_groups_created() - before);
        }
        assert!(pollster::block_on(validation.pop()).is_none());
        assert!(created[0] <= 2, "the first gather creates one bind group per source");
        assert_eq!(created[1..], [0, 0], "gathers of other regions create none");
    }
}
