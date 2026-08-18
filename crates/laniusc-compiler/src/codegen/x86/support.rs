//! Small shared helpers for the GPU x86 linker.

use std::{ops::Range, sync::OnceLock};

#[cfg(test)]
use anyhow::Result;
#[cfg(test)]
use wgpu::util::DeviceExt;

use super::GpuX86Linker;
use crate::gpu::buffers::LaniusBuffer;
#[cfg(test)]
use crate::gpu::passes_core::{PassData, bind_group};

fn trace_enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| crate::gpu::env::env_bool_strict("LANIUS_X86_TRACE", false))
}

pub(super) fn trace_x86_codegen(stage: &str) {
    if trace_enabled() {
        eprintln!("[laniusc][x86-link] {stage}");
    }
}

#[cfg(test)]
fn trace_event(stage: &str, event: &str) {
    if trace_enabled() {
        eprintln!("[laniusc][x86-link] {stage}.{event}");
    }
}

const INCREMENTAL_UPLOAD_CHUNK_BYTES: usize = 256 * 1024;

pub(super) fn u32_words_bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|word| word.to_le_bytes()).collect()
}

impl GpuX86Linker {
    pub(crate) fn release_job_buffers(&self) {
        self.job_buffers.clear();
        self.executable_page_graph
            .lock()
            .expect("x86 executable-page graph cache poisoned")
            .take();
        self.layout_chunk_graph
            .lock()
            .expect("x86 layout-chunk graph cache poisoned")
            .take();
        self.symbol_partition_graph
            .lock()
            .expect("x86 symbol-partition graph cache poisoned")
            .take();
        self.input_shadows
            .lock()
            .expect("x86 input-shadow cache poisoned")
            .clear();
    }

    pub(super) fn reusable_uniform_u32(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        label: &str,
        words: &[u32],
    ) -> LaniusBuffer<u32> {
        let bytes = u32_words_bytes(words);
        let byte_len = bytes.len().max(4);
        let buffer = self.job_buffers.buffer(
            device,
            label,
            byte_len,
            words.len().max(1),
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        );
        if bytes.is_empty() {
            buffer.write(queue, 0, &[0; 4]);
        } else {
            buffer.write(queue, 0, &bytes);
        }
        buffer
    }

    pub(super) fn reusable_storage_u32(
        &self,
        device: &wgpu::Device,
        label: &str,
        count: usize,
        extra_usage: wgpu::BufferUsages,
    ) -> LaniusBuffer<u32> {
        self.job_buffers
            .storage_u32(device, label, count, extra_usage)
    }

    pub(super) fn reusable_input_u32(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        label: &str,
        words: &[u32],
    ) -> LaniusBuffer<u32> {
        let contents = if words.is_empty() {
            u32_words_bytes(&[0])
        } else {
            u32_words_bytes(words)
        };
        let buffer = self.job_buffers.buffer(
            device,
            label,
            contents.len(),
            words.len().max(1),
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        );
        buffer.write(queue, 0, &contents);
        buffer
    }

    pub(super) fn reusable_input_bytes(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        label: &str,
        bytes: &[u8],
    ) -> LaniusBuffer<u8> {
        let byte_len = bytes.len().max(4).next_multiple_of(4);
        let buffer = self.job_buffers.buffer(
            device,
            label,
            byte_len,
            byte_len,
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        );
        let mut shadows = self
            .input_shadows
            .lock()
            .expect("x86 input-shadow cache poisoned");
        let shadow = shadows
            .entry(label.to_owned())
            .or_insert_with(|| super::X86InputShadow {
                allocation_id: None,
                bytes: Vec::new(),
            });
        let ranges = if shadow.allocation_id == buffer.allocation_id() {
            changed_upload_ranges(&shadow.bytes, bytes, INCREMENTAL_UPLOAD_CHUNK_BYTES)
        } else {
            vec![0..byte_len]
        };
        for range in ranges {
            write_aligned_byte_range(&buffer, queue, bytes, range);
        }
        shadow.allocation_id = buffer.allocation_id();
        shadow.bytes.clear();
        shadow.bytes.extend_from_slice(bytes);
        buffer
    }

    pub(super) fn reusable_readback(
        &self,
        device: &wgpu::Device,
        label: &str,
        byte_len: usize,
    ) -> LaniusBuffer<u8> {
        self.job_buffers.buffer(
            device,
            label,
            byte_len.max(4),
            byte_len.max(4),
            wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        )
    }
}

fn changed_upload_ranges(previous: &[u8], current: &[u8], chunk_bytes: usize) -> Vec<Range<usize>> {
    let padded_len = current.len().max(4).next_multiple_of(4);
    if previous.len() != current.len() {
        return vec![0..padded_len];
    }
    let chunk_bytes = chunk_bytes.max(4).next_multiple_of(4);
    let mut ranges: Vec<Range<usize>> = Vec::new();
    for start in (0..padded_len).step_by(chunk_bytes) {
        let end = (start + chunk_bytes).min(padded_len);
        let logical_end = end.min(current.len());
        if previous[start.min(previous.len())..logical_end]
            != current[start.min(current.len())..logical_end]
        {
            if let Some(last) = ranges.last_mut()
                && last.end == start
            {
                last.end = end;
            } else {
                ranges.push(start..end);
            }
        }
    }
    ranges
}

fn write_aligned_byte_range(
    buffer: &LaniusBuffer<u8>,
    queue: &wgpu::Queue,
    bytes: &[u8],
    range: Range<usize>,
) {
    let logical_end = range.end.min(bytes.len());
    let aligned_end = logical_end & !3;
    if range.start < aligned_end {
        buffer.write(queue, range.start as u64, &bytes[range.start..aligned_end]);
    }
    if aligned_end < range.end {
        let mut tail = [0u8; 4];
        tail[..logical_end - aligned_end].copy_from_slice(&bytes[aligned_end..logical_end]);
        buffer.write(queue, aligned_end as u64, &tail);
    }
}

#[cfg(test)]
mod incremental_upload_tests {
    use super::*;

    #[test]
    fn changed_upload_ranges_merge_adjacent_chunks_and_preserve_alignment() {
        let previous = vec![0u8; 18];
        let mut current = previous.clone();
        current[5] = 1;
        current[12] = 2;
        assert_eq!(changed_upload_ranges(&previous, &current, 8), vec![0..16]);
        assert!(changed_upload_ranges(&current, &current, 8).is_empty());
        assert_eq!(
            changed_upload_ranges(&current[..17], &current, 8),
            vec![0..20]
        );
    }
}

#[cfg(test)]
pub(super) fn uniform_u32_words(
    device: &wgpu::Device,
    label: &str,
    words: &[u32],
) -> LaniusBuffer<u32> {
    let bytes = u32_words_bytes(words);
    let contents = if bytes.is_empty() { &[0u8][..] } else { &bytes };
    let buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
    });
    LaniusBuffer::new_labeled((buffer, contents.len() as u64), words.len().max(1), label)
}

#[cfg(test)]
pub(super) fn storage_u32_rw(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    extra_usage: wgpu::BufferUsages,
) -> LaniusBuffer<u32> {
    let count = count.max(1);
    let buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count * 4) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | extra_usage,
        mapped_at_creation: false,
    });
    LaniusBuffer::new_labeled((buffer, (count * 4) as u64), count, label)
}

#[cfg(test)]
pub(super) fn storage_u32_copy(
    device: &wgpu::Device,
    label: &str,
    count: usize,
) -> LaniusBuffer<u32> {
    storage_u32_rw(device, label, count, wgpu::BufferUsages::COPY_SRC)
}

#[cfg(test)]
pub(super) fn workgroup_grid_1d(groups: u32) -> (u32, u32) {
    let groups = groups.max(1);
    let x = groups.min(65_535);
    (x, groups.div_ceil(x))
}

#[cfg(test)]
pub(super) fn dispatch_compute_pass(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage: &str,
    label: &str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    groups: (u32, u32),
) {
    trace_event(trace_stage, "record.start");
    if !crate::gpu::passes_core::defer_compute_direct(pass, bind_group, (groups.0, groups.1, 1)) {
        let mut compute = crate::gpu::passes_core::begin_counted_compute_pass(
            encoder,
            &wgpu::ComputePassDescriptor {
                label: Some(label),
                timestamp_writes: None,
            },
        );
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, bind_group, &[]);
        compute.dispatch_workgroups(groups.0, groups.1, 1);
    }
    trace_event(trace_stage, "record.done");
}

#[cfg(test)]
pub(super) fn reflected_bind_group(
    device: &wgpu::Device,
    label: Option<&'static str>,
    pass: &PassData,
    group_index: usize,
    bindings: &[(&str, wgpu::BindingResource<'_>)],
) -> Result<wgpu::BindGroup> {
    bind_group::create_bind_group_from_bindings(device, label, pass, group_index, bindings).map_err(
        |error| {
            anyhow::anyhow!(
                "create reflected bind group {}: {error:#}",
                label.unwrap_or("<unnamed>")
            )
        },
    )
}
