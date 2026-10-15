//! GPU gather for sparse batched readbacks.
//!
//! Fact readers pass `PagedReadback::read_regions` thousands of word-sized
//! rows. One buffer copy per row costs about 2 µs of encoding plus GPU time,
//! so ~12k rows took ~22 ms of a warm 1 MB job. Instead, one dispatch per
//! source buffer gathers the small rows into a dense image, and the page loop
//! copies that image with a few coalesced copies.

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
        match passes_core::make_pass_data_from_shader_key(device, GATHER_LABEL, "main", GATHER_SHADER) {
            Ok(pass) => {
                *guard = Some(GatherKernel {
                    device: device.clone(),
                    pass,
                    pairs: None,
                    output: None,
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

/// The source buffers of one dispatch: a bound window and the gathered
/// regions that lie inside it.
struct SourceGroup<'a> {
    source: &'a wgpu::Buffer,
    start: u64,
    end: u64,
    regions: Vec<usize>,
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
        let mut group_by_source = HashMap::<&wgpu::Buffer, usize>::new();
        for (index, region) in regions.iter().enumerate() {
            if region.byte_len == 0
                || region.byte_len > MAX_GATHER_REGION_BYTES
                || !region.source.usage().contains(wgpu::BufferUsages::STORAGE)
            {
                continue;
            }
            let start = region.source_offset;
            let end = start + region.byte_len.next_multiple_of(4) as u64;
            let group = *group_by_source.entry(region.source).or_insert_with(|| {
                groups.push(SourceGroup {
                    source: region.source,
                    start,
                    end,
                    regions: Vec::new(),
                });
                groups.len() - 1
            });
            let group = &mut groups[group];
            group.start = group.start.min(start);
            group.end = group.end.max(end);
            group.regions.push(index);
        }
        // Each window starts at an aligned offset and must fit one binding.
        groups.retain_mut(|group| {
            group.start -= group.start % align;
            group.end <= group.source.size() && group.end - group.start <= max_window
        });
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

        // One pair segment per group, each at an aligned binding offset.
        let align_words = (align / 4) as usize;
        let mut pairs = Vec::<u32>::with_capacity(image_words * 2 + groups.len() * align_words);
        let mut segments = Vec::with_capacity(groups.len());
        for group in &groups {
            pairs.resize(pairs.len().next_multiple_of(align_words), 0);
            let first = pairs.len();
            for &index in &group.regions {
                let region = &regions[index];
                let image = image_word[index].expect("gathered region has an image word");
                let source_word = ((region.source_offset - group.start) / 4) as u32;
                for word in 0..region.byte_len.div_ceil(4) as u32 {
                    pairs.push(image + word);
                    pairs.push(source_word + word);
                }
            }
            segments.push((first, (pairs.len() - first) / 2));
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

        let kernel = self.0.as_ref().expect("leased gather kernel");
        let pairs_buffer = kernel.pairs.as_ref().expect("gather pairs buffer");
        let output = kernel.output.as_ref().expect("gather output buffer");
        // Create every bind group before recording, so an error leaves no
        // stamped dispatch in an encoder that is never submitted.
        let mut dispatches = Vec::with_capacity(groups.len());
        for (group, &(first, pair_count)) in groups.iter().zip(&segments) {
            let source = wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                buffer: group.source,
                offset: group.start,
                size: NonZeroU64::new(group.end - group.start),
            });
            let pairs = wgpu::BindingResource::Buffer(wgpu::BufferBinding {
                buffer: &pairs_buffer.buffer,
                offset: first as u64 * 4,
                size: NonZeroU64::new(pair_count as u64 * 8),
            });
            let bindings = passes_core::bind_group::create_bind_group_from_bindings(
                device,
                Some(GATHER_LABEL),
                &kernel.pass,
                0,
                &[
                    ("gather_source", source),
                    ("gather_pairs", pairs),
                    ("gather_output", output.as_entire_binding()),
                ],
            )?;
            let workgroups = passes_core::plan_workgroups(
                DispatchDim::D1,
                InputElements::Elements1D(pair_count as u32),
                kernel.pass.thread_group_size,
            )?;
            dispatches.push((bindings, workgroups));
        }
        for (bindings, (x, y, z)) in &dispatches {
            {
                let mut pass = passes_core::begin_counted_compute_pass(
                    encoder,
                    &wgpu::ComputePassDescriptor {
                        label: Some(GATHER_LABEL),
                        timestamp_writes: None,
                    },
                );
                pass.set_pipeline(&kernel.pass.pipeline);
                pass.set_bind_group(0, Some(bindings), &[]);
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
