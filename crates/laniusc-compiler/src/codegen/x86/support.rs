//! Small shared helpers for the GPU x86 linker.

use std::sync::OnceLock;

use anyhow::Result;
use wgpu::util::DeviceExt;

use crate::gpu::{
    buffers::LaniusBuffer,
    passes_core::{PassData, bind_group},
};

fn trace_enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| crate::gpu::env::env_bool_strict("LANIUS_X86_TRACE", false))
}

pub(super) fn trace_x86_codegen(stage: &str) {
    if trace_enabled() {
        eprintln!("[laniusc][x86-link] {stage}");
    }
}

fn trace_event(stage: &str, event: &str) {
    if trace_enabled() {
        eprintln!("[laniusc][x86-link] {stage}.{event}");
    }
}

pub(super) fn u32_words_bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|word| word.to_le_bytes()).collect()
}

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

pub(super) fn storage_u32_copy(
    device: &wgpu::Device,
    label: &str,
    count: usize,
) -> LaniusBuffer<u32> {
    storage_u32_rw(device, label, count, wgpu::BufferUsages::COPY_SRC)
}

pub(super) fn workgroup_grid_1d(groups: u32) -> (u32, u32) {
    let groups = groups.max(1);
    let x = groups.min(65_535);
    (x, groups.div_ceil(x))
}

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
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(label),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, bind_group, &[]);
        compute.dispatch_workgroups(groups.0, groups.1, 1);
    }
    trace_event(trace_stage, "record.done");
}

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
