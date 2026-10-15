//! GPU gather for sparse batched readbacks.
//!
//! Fact readers pass `PagedReadback::read_regions` thousands of word-sized
//! rows. One buffer copy per row costs about 2 µs of encoding plus GPU time,
//! so ~12k rows took ~22 ms of a warm 1 MB job. Instead, one dispatch per
//! source buffer gathers the small rows into a dense image, and the page loop
//! copies that image with a few coalesced copies.
//!
//! A dispatch's bind group names only whole buffers (a source, or a fixed
//! window of one too large to bind) and the retained pairs, output and params
//! buffers; its pair range comes through a dynamic uniform offset. Readbacks
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

use super::ReadbackRegion;
use crate::gpu::{
    buffers::{LaniusBuffer, with_debug_copy},
    passes_core::{self, DispatchDim, InputElements, PassData},
};

const GATHER_SHADER: &str = "readback/gather_words";
const GATHER_LABEL: &str = "readback.gather";
const GATHER_PARAMS: &str = "gather_params";
/// One `GatherParams` record: first pair, pair count, padding.
const PARAMS_BYTES: usize = 16;
/// Below this many small regions, direct copies cost about as much as the
/// gather's upload and dispatch.
const MIN_GATHER_REGIONS: usize = 64;
/// Larger regions already copy efficiently.
const MAX_GATHER_REGION_BYTES: usize = 256;
/// Bounds the retained gather buffers (16 MiB of output, 32 MiB of pairs).
const MAX_GATHER_WORDS: usize = 1 << 22;

struct GatherKernel {
    device: wgpu::Device,
    pass: PassData,
    pairs: Option<LaniusBuffer<u32>>,
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
                    pairs: None,
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
/// the gathered regions that lie inside it.
struct SourceGroup<'a> {
    source: &'a wgpu::Buffer,
    window: (u64, u64),
    regions: Vec<usize>,
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
        let limits = device.limits();
        let align = u64::from(limits.min_storage_buffer_offset_alignment).max(8);
        let max_window = limits.max_storage_buffer_binding_size.min(u64::from(u32::MAX)) & !3;

        let mut groups = Vec::<SourceGroup<'a>>::new();
        let mut group_by_window = HashMap::<(&wgpu::Buffer, u64), usize>::new();
        for (index, region) in regions.iter().enumerate() {
            if region.byte_len == 0
                || region.byte_len > MAX_GATHER_REGION_BYTES
                || !region.source.usage().contains(wgpu::BufferUsages::STORAGE)
            {
                continue;
            }
            let start = region.source_offset;
            let end = start + region.byte_len.next_multiple_of(4) as u64;
            let Some(window) = source_window(region.source, start, end, align, max_window) else {
                continue;
            };
            let group = *group_by_window
                .entry((region.source, window.0))
                .or_insert_with(|| {
                    groups.push(SourceGroup {
                        source: region.source,
                        window,
                        regions: Vec::new(),
                    });
                    groups.len() - 1
                });
            groups[group].regions.push(index);
        }
        let gathered_regions = groups.iter().map(|group| group.regions.len()).sum::<usize>();
        if gathered_regions < MIN_GATHER_REGIONS {
            return Ok(None);
        }

        // The image keeps region order, so consecutive gathered regions copy
        // to the staging page as one range.
        let mut image_word = vec![None::<u32>; regions.len()];
        for group in &groups {
            for &index in &group.regions {
                image_word[index] = Some(0);
            }
        }
        let mut image_words = 0usize;
        for (index, word) in image_word.iter_mut().enumerate() {
            if word.is_some() {
                *word = Some(image_words as u32);
                image_words += regions[index].byte_len.div_ceil(4);
            }
        }
        if image_words > MAX_GATHER_WORDS {
            return Ok(None);
        }

        // One run of pairs per group, named by the group's params record.
        let params_stride = PARAMS_BYTES
            .next_multiple_of(limits.min_uniform_buffer_offset_alignment.max(1) as usize);
        let mut pairs = Vec::<u32>::with_capacity(image_words * 2);
        let mut params = vec![0u8; groups.len() * params_stride];
        let mut pair_counts = Vec::with_capacity(groups.len());
        for (slot, group) in groups.iter().enumerate() {
            let first = pairs.len() / 2;
            for &index in &group.regions {
                let region = &regions[index];
                let image = image_word[index].expect("gathered region has an image word");
                let source_word = ((region.source_offset - group.window.0) / 4) as u32;
                for word in 0..region.byte_len.div_ceil(4) as u32 {
                    pairs.push(image + word);
                    pairs.push(source_word + word);
                }
            }
            let pair_count = (pairs.len() / 2 - first) as u32;
            let record = &mut params[slot * params_stride..][..8];
            record[..4].copy_from_slice(&(first as u32).to_le_bytes());
            record[4..].copy_from_slice(&pair_count.to_le_bytes());
            pair_counts.push(pair_count);
        }

        let pairs_buffer = retained_buffer(
            device,
            &mut self.kernel().pairs,
            "readback.gather.pairs",
            pairs.len(),
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        );
        let mut bytes = Vec::with_capacity(pairs.len() * 4);
        for word in &pairs {
            bytes.extend_from_slice(&word.to_le_bytes());
        }
        pairs_buffer.write(queue, 0, &bytes);
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
        let pairs_buffer = kernel.pairs.as_ref().expect("gather pairs buffer");
        let output = kernel.output.as_ref().expect("gather output buffer");
        let params_buffer = kernel.params.as_ref().expect("gather params buffer");
        // Create every bind group before recording, so an error leaves no
        // stamped dispatch in an encoder that is never submitted.
        let mut dispatches = Vec::with_capacity(groups.len());
        for (slot, (group, &pair_count)) in groups.iter().zip(&pair_counts).enumerate() {
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
                    ("gather_pairs", pairs_buffer.as_entire_binding()),
                    ("gather_output", output.as_entire_binding()),
                ],
            )?;
            let workgroups = passes_core::plan_workgroups(
                DispatchDim::D1,
                InputElements::Elements1D(pair_count),
                kernel.pass.thread_group_size,
            )?;
            dispatches.push((bindings, (slot * params_stride) as u32, workgroups));
        }
        for (bindings, params_offset, (x, y, z)) in &dispatches {
            {
                let mut pass = passes_core::begin_counted_compute_pass(
                    encoder,
                    &wgpu::ComputePassDescriptor {
                        label: Some(GATHER_LABEL),
                        timestamp_writes: None,
                    },
                );
                pass.set_pipeline(&kernel.pass.pipeline);
                pass.set_bind_group(0, Some(bindings), &[*params_offset]);
                passes_core::record_compute_dispatch();
                pass.dispatch_workgroups(*x, *y, *z);
            }
            crate::gpu::timer::stamp_active_operation(encoder, format!("{GATHER_LABEL}.{label}"));
        }

        let regions = regions
            .iter()
            .zip(&image_word)
            .map(|(region, image)| match image {
                Some(word) => ReadbackRegion {
                    source: &output.buffer,
                    source_offset: u64::from(*word) * 4,
                    byte_len: region.byte_len,
                },
                None => *region,
            })
            .collect();
        Ok(Some(Gathered {
            regions,
            gathered_regions,
            dispatches: dispatches.len(),
        }))
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
