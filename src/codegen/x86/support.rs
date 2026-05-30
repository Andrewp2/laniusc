use std::{
    collections::HashMap,
    ops::Deref,
    sync::{Mutex, OnceLock},
    time::Duration,
};

use anyhow::{Result, bail};
use log::warn;
use wgpu::util::DeviceExt;

use super::{RecordedX86Codegen, X86OutputError, X86Params, X86RegallocParams, X86ScanParams};
use crate::gpu::passes_core::{PassData, bind_group};

const UNIFORM_BINDING_ARRAY_STRIDE: u64 = 256;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
struct PooledStorageBufferKey {
    device: usize,
    size: u64,
    usage_bits: u64,
}

pub(super) struct PooledStorageBuffer {
    buffer: Option<wgpu::Buffer>,
    key: PooledStorageBufferKey,
}

impl PooledStorageBuffer {
    fn new(buffer: wgpu::Buffer, key: PooledStorageBufferKey) -> Self {
        Self {
            buffer: Some(buffer),
            key,
        }
    }

    fn buffer(&self) -> &wgpu::Buffer {
        self.buffer
            .as_ref()
            .expect("pooled x86 storage buffer was already returned")
    }
}

impl Deref for PooledStorageBuffer {
    type Target = wgpu::Buffer;

    fn deref(&self) -> &Self::Target {
        self.buffer()
    }
}

impl Drop for PooledStorageBuffer {
    fn drop(&mut self) {
        let Some(buffer) = self.buffer.take() else {
            return;
        };
        match storage_buffer_pool().lock() {
            Ok(mut pool) => {
                pool.entry(self.key).or_default().push(buffer);
            }
            Err(err) => warn!("failed to return x86 storage buffer to pool: {err}"),
        }
    }
}

pub(super) struct PooledReadbackBuffer {
    buffer: Option<wgpu::Buffer>,
    key: PooledStorageBufferKey,
}

impl PooledReadbackBuffer {
    fn new(buffer: wgpu::Buffer, key: PooledStorageBufferKey) -> Self {
        Self {
            buffer: Some(buffer),
            key,
        }
    }

    fn buffer(&self) -> &wgpu::Buffer {
        self.buffer
            .as_ref()
            .expect("pooled x86 readback buffer was already returned")
    }
}

impl Deref for PooledReadbackBuffer {
    type Target = wgpu::Buffer;

    fn deref(&self) -> &Self::Target {
        self.buffer()
    }
}

impl Drop for PooledReadbackBuffer {
    fn drop(&mut self) {
        let Some(buffer) = self.buffer.take() else {
            return;
        };
        match storage_buffer_pool().lock() {
            Ok(mut pool) => {
                pool.entry(self.key).or_default().push(buffer);
            }
            Err(err) => warn!("failed to return x86 readback buffer to pool: {err}"),
        }
    }
}

#[allow(dead_code)]
pub(super) enum RetainedX86Buffer {
    Plain(wgpu::Buffer),
    Pooled(PooledStorageBuffer),
}

impl From<wgpu::Buffer> for RetainedX86Buffer {
    fn from(buffer: wgpu::Buffer) -> Self {
        Self::Plain(buffer)
    }
}

impl From<PooledStorageBuffer> for RetainedX86Buffer {
    fn from(buffer: PooledStorageBuffer) -> Self {
        Self::Pooled(buffer)
    }
}

pub(super) struct UniformBindingArray {
    buffer: wgpu::Buffer,
    item_size: u64,
    len: usize,
}

impl UniformBindingArray {
    pub(super) fn len(&self) -> usize {
        self.len
    }

    pub(super) fn binding(&self, index: usize) -> wgpu::BindingResource<'_> {
        let offset = uniform_binding_array_offset(index);
        wgpu::BindingResource::Buffer(wgpu::BufferBinding {
            buffer: &self.buffer,
            offset,
            size: wgpu::BufferSize::new(self.item_size),
        })
    }

    pub(super) fn dynamic_offset(&self, index: usize) -> u32 {
        let offset = uniform_binding_array_offset(index);
        u32::try_from(offset).expect("x86 uniform dynamic offset exceeded u32")
    }

    pub(super) fn into_buffer(self) -> wgpu::Buffer {
        self.buffer
    }
}

fn uniform_binding_array_offset(index: usize) -> u64 {
    (index as u64).saturating_mul(UNIFORM_BINDING_ARRAY_STRIDE)
}

fn x86_trace_enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| crate::gpu::env::env_bool_strict("LANIUS_X86_TRACE", false))
}

fn trace_x86_codegen_event(stage: &str, event: &str) {
    if x86_trace_enabled() {
        eprintln!("[laniusc][x86-codegen] {stage}.{event}");
    }
}

pub(super) fn trace_x86_codegen(stage: &str) {
    if x86_trace_enabled() {
        eprintln!("[laniusc][x86-codegen] {stage}");
    }
}

pub(super) fn x86_params_bytes(params: &X86Params) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params)
        .expect("failed to encode x86 codegen params");
    ub.as_ref().to_vec()
}

pub(super) fn x86_scan_params_bytes(params: &X86ScanParams) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params).expect("failed to encode x86 scan params");
    ub.as_ref().to_vec()
}

pub(super) fn x86_regalloc_params_bytes(params: &X86RegallocParams) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params)
        .expect("failed to encode x86 register-allocation params");
    ub.as_ref().to_vec()
}

pub(super) fn u32_words_bytes(words: &[u32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(words.len() * 4);
    for word in words {
        out.extend_from_slice(&word.to_le_bytes());
    }
    out
}

pub(super) fn write_u32_words(queue: &wgpu::Queue, buffer: &wgpu::Buffer, words: &[u32]) {
    queue.write_buffer(buffer, 0, &u32_words_bytes(words));
}

pub(super) fn init_repeated_u32_words(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    fill_pass: &PassData,
    label: &str,
    buffer: &wgpu::Buffer,
    pattern: &[u32],
    repeats: usize,
) -> Result<()> {
    if pattern.is_empty() || repeats == 0 {
        return Ok(());
    }

    fill_repeated_u32_words_gpu(
        device, queue, encoder, fill_pass, label, buffer, pattern, repeats,
    )
}

pub(super) fn fill_repeated_u32_words_gpu(
    device: &wgpu::Device,
    _queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    fill_pass: &PassData,
    label: &str,
    buffer: &wgpu::Buffer,
    pattern: &[u32],
    repeats: usize,
) -> Result<()> {
    if pattern.is_empty() || repeats == 0 {
        return Ok(());
    }
    if pattern.len() > 4 {
        bail!("x86 GPU fill supports repeated patterns up to four u32 words");
    }

    let words = pattern.len().saturating_mul(repeats).max(1);
    let mut pattern_words = [0u32; 4];
    for (index, word) in pattern.iter().enumerate() {
        pattern_words[index] = *word;
    }
    let param_words = [
        words as u32,
        pattern.len() as u32,
        pattern_words[0],
        pattern_words[1],
        pattern_words[2],
        pattern_words[3],
        0,
        0,
    ];
    let params = uniform_u32_words(device, "codegen.x86.fill_u32.params", &param_words);
    let bind_group = reflected_bind_group(
        device,
        Some("codegen.x86.fill_u32.bind_group"),
        fill_pass,
        0,
        &[
            ("gFill", params.as_entire_binding()),
            ("target", buffer.as_entire_binding()),
        ],
    )?;
    let groups = workgroup_grid_1d((words as u32).div_ceil(256).max(1));
    let trace_stage = format!("fill_u32.{label}");
    let pass_label = format!("codegen.x86.fill_u32.{label}");
    dispatch_compute_pass(
        encoder,
        &trace_stage,
        &pass_label,
        fill_pass,
        &bind_group,
        groups,
    );
    Ok(())
}

pub(super) fn zero_u32_words(
    _queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    buffer: &wgpu::Buffer,
    words: usize,
) {
    let words = words.max(1);
    let bytes = words * 4;
    encoder.clear_buffer(buffer, 0, Some(bytes as u64));
}

pub(super) fn uniform_u32_struct(device: &wgpu::Device, label: &str, bytes: &[u8]) -> wgpu::Buffer {
    let contents = if bytes.is_empty() { &[0u8][..] } else { bytes };
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
    })
}

pub(super) fn uniform_u32_words(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    uniform_u32_struct(device, label, &u32_words_bytes(words))
}

pub(super) fn uniform_u32_struct_array(
    device: &wgpu::Device,
    label: &str,
    items: &[Vec<u8>],
) -> UniformBindingArray {
    let len = items.len().max(1);
    let item_size = items
        .first()
        .map(|bytes| bytes.len().max(1) as u64)
        .unwrap_or(4);
    assert!(
        item_size <= UNIFORM_BINDING_ARRAY_STRIDE,
        "x86 uniform binding item is larger than the fixed aligned stride"
    );
    let mut contents = vec![0u8; (UNIFORM_BINDING_ARRAY_STRIDE as usize).saturating_mul(len)];
    for (index, bytes) in items.iter().enumerate() {
        assert_eq!(
            bytes.len() as u64,
            item_size,
            "x86 uniform binding array items must have identical encoded sizes"
        );
        let start = uniform_binding_array_offset(index) as usize;
        contents[start..start + bytes.len()].copy_from_slice(bytes);
    }
    let buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &contents,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
    });
    UniformBindingArray {
        buffer,
        item_size,
        len,
    }
}

pub(super) fn storage_u32_rw(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    extra_usage: wgpu::BufferUsages,
) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | extra_usage,
        mapped_at_creation: false,
    })
}

pub(super) fn storage_u32_copy(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    storage_u32_rw(device, label, count, wgpu::BufferUsages::COPY_SRC)
}

pub(super) fn external_or_storage_u32_copy(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    external: Option<&wgpu::Buffer>,
) -> wgpu::Buffer {
    external
        .cloned()
        .unwrap_or_else(|| storage_u32_copy(device, label, count))
}

pub(super) fn push_allocation_error_scope(device: &wgpu::Device) -> wgpu::ErrorScopeGuard {
    device.push_error_scope(wgpu::ErrorFilter::OutOfMemory)
}

pub(super) fn pop_allocation_error_scope(scope: wgpu::ErrorScopeGuard, stage: &str) -> Result<()> {
    if let Some(err) = pollster::block_on(scope.pop()) {
        bail!("GPU x86 buffer allocation failed during {stage}: {err}");
    }
    Ok(())
}

pub(super) fn pooled_storage_u32_rw(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    extra_usage: wgpu::BufferUsages,
) -> PooledStorageBuffer {
    let size = (count.max(1) * 4) as u64;
    let usage = wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | extra_usage;
    let key = PooledStorageBufferKey {
        device: device as *const wgpu::Device as usize,
        size,
        usage_bits: usage.bits() as u64,
    };
    let reused = match storage_buffer_pool().lock() {
        Ok(mut pool) => pool.get_mut(&key).and_then(Vec::pop),
        Err(err) => {
            warn!("failed to take x86 storage buffer from pool: {err}");
            None
        }
    };
    let buffer = reused.unwrap_or_else(|| {
        device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size,
            usage,
            mapped_at_creation: false,
        })
    });
    PooledStorageBuffer::new(buffer, key)
}

pub(super) fn pooled_storage_u32_copy(
    device: &wgpu::Device,
    label: &str,
    count: usize,
) -> PooledStorageBuffer {
    pooled_storage_u32_rw(device, label, count, wgpu::BufferUsages::COPY_SRC)
}

pub(super) fn pooled_readback_bytes(
    device: &wgpu::Device,
    label: &str,
    bytes: u64,
) -> PooledReadbackBuffer {
    let size = bytes.max(1);
    let usage = wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ;
    let key = PooledStorageBufferKey {
        device: device as *const wgpu::Device as usize,
        size,
        usage_bits: usage.bits() as u64,
    };
    let reused = match storage_buffer_pool().lock() {
        Ok(mut pool) => pool.get_mut(&key).and_then(Vec::pop),
        Err(err) => {
            warn!("failed to take x86 readback buffer from pool: {err}");
            None
        }
    };
    let buffer = reused.unwrap_or_else(|| {
        device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size,
            usage,
            mapped_at_creation: false,
        })
    });
    PooledReadbackBuffer::new(buffer, key)
}

fn storage_buffer_pool() -> &'static Mutex<HashMap<PooledStorageBufferKey, Vec<wgpu::Buffer>>> {
    static POOL: OnceLock<Mutex<HashMap<PooledStorageBufferKey, Vec<wgpu::Buffer>>>> =
        OnceLock::new();
    POOL.get_or_init(|| Mutex::new(HashMap::new()))
}

pub(super) fn readback_u32s(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}

pub(super) fn workgroup_grid_1d(groups: u32) -> (u32, u32) {
    const MAX_X: u32 = 65_535;
    let groups = groups.max(1);
    if groups <= MAX_X {
        (groups, 1)
    } else {
        (MAX_X, groups.div_ceil(MAX_X))
    }
}

pub(super) fn scan_steps_for_blocks(n_blocks: usize) -> Vec<u32> {
    crate::gpu::scan::scan_step_values(n_blocks as u32)
}

pub(super) fn pointer_jump_steps_for_items(n_items: usize) -> Vec<u32> {
    let mut value = n_items.max(1) as u32;
    let mut steps = Vec::new();
    while value != 0 {
        steps.push(steps.len() as u32);
        value >>= 1;
    }
    steps
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn uniform_binding_array_offsets_are_webgpu_aligned() {
        assert_eq!(uniform_binding_array_offset(0), 0);
        assert_eq!(uniform_binding_array_offset(1), 256);
        assert_eq!(uniform_binding_array_offset(7), 1792);
        assert_eq!(uniform_binding_array_offset(3) % 256, 0);
    }
}

pub(super) fn dispatch_compute_pass(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage: &str,
    label: &str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    groups: (u32, u32),
) {
    trace_x86_codegen_event(trace_stage, "record.start");
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(label),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, bind_group, &[]);
        compute.dispatch_workgroups(groups.0, groups.1, 1);
    }
    trace_x86_codegen_event(trace_stage, "record.done");
}

pub(super) fn dispatch_compute_pass_indirect(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage: &str,
    label: &str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    indirect_buffer: &wgpu::Buffer,
) {
    dispatch_compute_pass_indirect_offset(
        encoder,
        trace_stage,
        label,
        pass,
        bind_group,
        indirect_buffer,
        0,
    );
}

pub(super) fn dispatch_compute_pass_indirect_offset(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage: &str,
    label: &str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    indirect_buffer: &wgpu::Buffer,
    indirect_offset: u64,
) {
    dispatch_compute_pass_indirect_offset_with_dynamic_offsets(
        encoder,
        trace_stage,
        label,
        pass,
        bind_group,
        indirect_buffer,
        indirect_offset,
        &[],
    );
}

pub(super) fn dispatch_compute_pass_indirect_offset_with_dynamic_offsets(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage: &str,
    label: &str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    indirect_buffer: &wgpu::Buffer,
    indirect_offset: u64,
    dynamic_offsets: &[u32],
) {
    trace_x86_codegen_event(trace_stage, "record.start");
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(label),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, bind_group, dynamic_offsets);
        compute.dispatch_workgroups_indirect(indirect_buffer, indirect_offset);
    }
    trace_x86_codegen_event(trace_stage, "record.done");
}

pub(super) fn dispatch_compute_pass_indirect_offsets_with_dynamic_uniform_offsets(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage: &str,
    label: &str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    indirect_buffer: &wgpu::Buffer,
    indirect_offsets: &[u64],
    uniform_dynamic_offsets: &[u32],
) {
    assert_eq!(
        indirect_offsets.len(),
        uniform_dynamic_offsets.len(),
        "x86 indirect dispatch offsets and dynamic uniform offsets must match"
    );
    trace_x86_codegen_event(trace_stage, "record.start");
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(label),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        for (&indirect_offset, &dynamic_offset) in
            indirect_offsets.iter().zip(uniform_dynamic_offsets)
        {
            compute.set_bind_group(0, bind_group, &[dynamic_offset]);
            compute.dispatch_workgroups_indirect(indirect_buffer, indirect_offset);
        }
    }
    trace_x86_codegen_event(trace_stage, "record.done");
}

pub(super) fn dispatch_indirect_dynamic_sequence(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage: &str,
    label: &str,
    pass: &PassData,
    bind_groups: &[&wgpu::BindGroup],
    indirect_buffer: &wgpu::Buffer,
    indirect_offsets: &[u64],
    uniform_dynamic_offsets: &[u32],
) {
    assert_eq!(
        bind_groups.len(),
        indirect_offsets.len(),
        "x86 bind group sequence and indirect dispatch offsets must match"
    );
    assert_eq!(
        indirect_offsets.len(),
        uniform_dynamic_offsets.len(),
        "x86 indirect dispatch offsets and dynamic uniform offsets must match"
    );
    trace_x86_codegen_event(trace_stage, "record.start");
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(label),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        for ((bind_group, &indirect_offset), &dynamic_offset) in bind_groups
            .iter()
            .zip(indirect_offsets)
            .zip(uniform_dynamic_offsets)
        {
            compute.set_bind_group(0, *bind_group, &[dynamic_offset]);
            compute.dispatch_workgroups_indirect(indirect_buffer, indirect_offset);
        }
    }
    trace_x86_codegen_event(trace_stage, "record.done");
}

pub(super) fn dispatch_compute_pass_indirect_ping_pong_scan_steps(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage: &str,
    label: &str,
    pass: &PassData,
    bind_groups: &[wgpu::BindGroup],
    scan_params: &UniformBindingArray,
    indirect_buffer: &wgpu::Buffer,
) {
    assert_eq!(
        bind_groups.len(),
        2,
        "x86 ping-pong scan dispatch requires even and odd bind groups"
    );
    let step_count = scan_params.len();
    let indirect_offsets = vec![0u64; step_count];
    let dynamic_offsets = (0..step_count)
        .map(|step_i| scan_params.dynamic_offset(step_i))
        .collect::<Vec<_>>();
    let bind_group_sequence = (0..step_count)
        .map(|step_i| &bind_groups[step_i & 1])
        .collect::<Vec<_>>();
    dispatch_indirect_dynamic_sequence(
        encoder,
        trace_stage,
        label,
        pass,
        &bind_group_sequence,
        indirect_buffer,
        &indirect_offsets,
        &dynamic_offsets,
    );
}

pub(super) fn dispatch_compute_pass_indirect_bind_group_steps(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage_prefix: &str,
    label: &str,
    pass: &PassData,
    bind_groups: &[wgpu::BindGroup],
    indirect_buffer: &wgpu::Buffer,
) {
    if bind_groups.is_empty() {
        return;
    }
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pass.pipeline);
    for (step_i, bind_group) in bind_groups.iter().enumerate() {
        let trace_stage = format!("{trace_stage_prefix}.{step_i}");
        trace_x86_codegen_event(&trace_stage, "record.start");
        compute.set_bind_group(0, bind_group, &[]);
        compute.dispatch_workgroups_indirect(indirect_buffer, 0);
        trace_x86_codegen_event(&trace_stage, "record.done");
    }
}

pub(super) fn dispatch_x86_stages(
    encoder: &mut wgpu::CommandEncoder,
    stages: &[(&'static str, &PassData, &wgpu::BindGroup)],
    groups: (u32, u32),
) {
    if stages.is_empty() {
        return;
    }
    let label = if stages.len() == 1 {
        format!("codegen.x86.{}", stages[0].0)
    } else {
        format!("codegen.x86.group.{}+{}", stages[0].0, stages.len())
    };
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(&label),
        timestamp_writes: None,
    });
    for (stage, pass, bind_group) in stages {
        trace_x86_codegen_event(stage, "record.start");
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, *bind_group, &[]);
        compute.dispatch_workgroups(groups.0, groups.1, 1);
        trace_x86_codegen_event(stage, "record.done");
    }
}

pub(super) fn dispatch_x86_stage(
    encoder: &mut wgpu::CommandEncoder,
    stage: &'static str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    groups: (u32, u32),
) {
    let label = format!("codegen.x86.{stage}");
    dispatch_compute_pass(encoder, stage, &label, pass, bind_group, groups);
}

pub(super) fn dispatch_x86_stages_indirect(
    encoder: &mut wgpu::CommandEncoder,
    stages: &[(&'static str, &PassData, &wgpu::BindGroup)],
    indirect_buffer: &wgpu::Buffer,
) {
    if stages.is_empty() {
        return;
    }
    let label = if stages.len() == 1 {
        format!("codegen.x86.{}", stages[0].0)
    } else {
        format!("codegen.x86.group.{}+{}", stages[0].0, stages.len())
    };
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(&label),
        timestamp_writes: None,
    });
    for (stage, pass, bind_group) in stages {
        trace_x86_codegen_event(stage, "record.start");
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, *bind_group, &[]);
        compute.dispatch_workgroups_indirect(indirect_buffer, 0);
        trace_x86_codegen_event(stage, "record.done");
    }
}

pub(super) fn dispatch_x86_stage_indirect(
    encoder: &mut wgpu::CommandEncoder,
    stage: &'static str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    indirect_buffer: &wgpu::Buffer,
) {
    let label = format!("codegen.x86.{stage}");
    dispatch_compute_pass_indirect(encoder, stage, &label, pass, bind_group, indirect_buffer);
}

pub(super) fn reflected_bind_group(
    device: &wgpu::Device,
    label: Option<&'static str>,
    pass: &PassData,
    group_index: usize,
    bindings: &[(&str, wgpu::BindingResource<'_>)],
) -> Result<wgpu::BindGroup> {
    bind_group::create_bind_group_from_bindings(device, label, pass, group_index, bindings).map_err(
        |err| {
            anyhow::anyhow!(
                "create reflected bind group {}: {err:#}",
                label.unwrap_or("<unnamed>")
            )
        },
    )
}

pub(super) fn read_x86_output(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    recorded: &RecordedX86Codegen,
) -> Result<Vec<u8>> {
    let status_start = recorded.output_status_offset;
    let status_end = status_start.saturating_add(16);
    let total_readback_bytes = status_end;
    let readback_slice = recorded.output_readback.slice(0..total_readback_bytes);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &readback_slice,
        "codegen.x86.output_readback",
        x86_readback_timeout(),
    )?;

    let (status, bytes) = {
        let data = readback_slice.get_mapped_range();
        let status_start = status_start as usize;
        let status_end = status_end as usize;
        let status_words = crate::gpu::readback::read_u32_words(
            &data[status_start..status_end],
            "x86 codegen status",
        );
        let [len, mode, error_code, error_detail] = match status_words {
            Ok(status_words) => status_words,
            Err(err) => {
                drop(data);
                recorded.output_readback.unmap();
                return Err(err);
            }
        };
        let len = len as usize;
        let bytes = if error_code == 0
            && mode == 1
            && len <= recorded.output_capacity
            && len <= status_start
        {
            Some(data[..len].to_vec())
        } else {
            None
        };
        drop(data);
        recorded.output_readback.unmap();
        (
            [
                len,
                mode as usize,
                error_code as usize,
                error_detail as usize,
            ],
            bytes,
        )
    };
    let [len, mode, error_code, error_detail] = status;
    if crate::gpu::trace::enabled() {
        let now = std::time::Instant::now();
        for (name, value) in [
            ("x86.output_len_bytes", len),
            ("x86.output_status_mode", mode),
            ("x86.output_error_code", error_code),
            (
                "x86.output_initial_readback_hit",
                usize::from(bytes.is_some()),
            ),
        ] {
            crate::gpu::trace::record_counter("host.x86.output", name, now, value as f64);
        }
    }

    if error_code != 0 {
        if let Some(status_trace_readback) = &recorded.status_trace_readback {
            if let Err(err) = dump_x86_status_trace(device, status_trace_readback) {
                warn!("failed to read x86 status trace: {err:#}");
            }
        }
        let error_name = match error_code {
            2 => "missing main entrypoint",
            3 => "unsupported return expression",
            4 => "output capacity too small",
            5 => "register allocation failure",
            6 => "instruction sizing failure",
            7 => "ELF layout failure",
            8 => "x86 relocation failure",
            9 => "unsupported x86 call ABI",
            11 => "unsupported x86 virtual instruction",
            15 => "virtual register allocation failure",
            17 if error_detail == u32::MAX as usize => "unsupported x86 entrypoint body",
            17 => "instruction selection failure",
            24 => "unsupported x86 method call",
            25 => "unsupported x86 recursive call",
            26 => "unsupported x86 aggregate copy width",
            29 => "unsupported x86 loop-contained call",
            30 => "unsupported x86 postfix expression",
            31 => "unsupported x86 indexed assignment",
            32 => "unsupported x86 zero divisor",
            33 => "unsupported x86 for iterable",
            34 => "unsupported x86 nested loop",
            35 => "unsupported x86 short-circuit call operand",
            37 => "unsupported x86 parameter aggregate assignment",
            38 => "unsupported x86 parameter aggregate indexed assignment",
            39 => "unsupported x86 unary expression",
            40 => "unsupported x86 array index bounds",
            41 => "unsupported x86 dynamic divisor",
            42 => "unsupported x86 short-circuit trapping operand",
            43 => "unsupported x86 entrypoint body",
            44 => "unsupported x86 match expression",
            45 => "unsupported x86 aggregate temporary index",
            46 => "unsupported x86 aggregate temporary member",
            47 => "unsupported x86 dynamic array index",
            _ => "unsupported source shape",
        };
        return Err(X86OutputError::new(error_name, error_code as u32, error_detail as u32).into());
    }
    if mode != 1 || len > recorded.output_capacity {
        return Err(anyhow::anyhow!(
            "GPU x86 emitter produced {} bytes for capacity {}",
            len,
            recorded.output_capacity
        ));
    }
    if let Some(status_trace_readback) = &recorded.status_trace_readback {
        if let Err(err) = dump_x86_status_trace(device, status_trace_readback) {
            warn!("failed to read x86 status trace: {err:#}");
        }
    }
    if let Some(bytes) = bytes {
        return Ok(bytes);
    }
    if len > recorded.output_status_offset as usize && len <= recorded.output_capacity {
        if crate::gpu::trace::enabled() {
            crate::gpu::trace::record_counter(
                "host.x86.output",
                "x86.output_exact_readback_bytes",
                std::time::Instant::now(),
                len as f64,
            );
        }
        return read_exact_x86_output_bytes(device, queue, recorded, len);
    }
    Err(anyhow::anyhow!(
        "GPU x86 emitter output bytes were unavailable"
    ))
}

fn read_exact_x86_output_bytes(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    recorded: &RecordedX86Codegen,
    len: usize,
) -> Result<Vec<u8>> {
    let copy_bytes = len.div_ceil(4).saturating_mul(4) as u64;
    let exact_readback =
        pooled_readback_bytes(device, "rb.codegen.x86.out_words.exact", copy_bytes);
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("codegen.x86.output_readback.exact.encoder"),
    });
    encoder.copy_buffer_to_buffer(&recorded.out_buf, 0, &exact_readback, 0, copy_bytes);
    crate::gpu::passes_core::submit_with_progress(
        queue,
        "codegen.x86.output-readback-exact",
        encoder.finish(),
    );

    let readback_slice = exact_readback.slice(0..copy_bytes);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &readback_slice,
        "codegen.x86.output_readback.exact",
        x86_readback_timeout(),
    )?;
    let bytes = {
        let data = readback_slice.get_mapped_range();
        let bytes = data[..len].to_vec();
        drop(data);
        exact_readback.unmap();
        bytes
    };
    Ok(bytes)
}

fn dump_x86_status_trace(device: &wgpu::Device, readback: &wgpu::Buffer) -> Result<()> {
    let slice = readback.slice(..);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &slice,
        "codegen.x86.status_trace",
        x86_readback_timeout(),
    )?;
    let data = readback.slice(..).get_mapped_range();
    let words: [u32; 114] = crate::gpu::readback::read_u32_words(&data, "x86 status trace")?;
    drop(data);
    readback.unmap();

    if crate::gpu::trace::enabled() {
        let now = std::time::Instant::now();
        let func_meta_offset = 14usize;
        for (name, value) in [
            ("x86.func_count", words[func_meta_offset]),
            ("x86.main_count", words[func_meta_offset + 1]),
            ("x86.main_node", words[func_meta_offset + 4]),
            ("x86.max_virtual_func_rows", words[func_meta_offset + 5]),
            ("x86.regalloc_active_chunks", words[func_meta_offset + 6]),
            ("x86.regalloc_recorded_chunks", words[func_meta_offset + 7]),
        ] {
            crate::gpu::trace::record_counter("host.x86.gpu_meta", name, now, value as f64);
        }
    }

    let mut offset = 0usize;
    for (name, len) in [
        ("hir_status", 6usize),
        ("active_hir_dispatch", 4usize),
        ("active_hir_plus_one_dispatch", 4usize),
        ("func_meta", 8usize),
        ("node_tree", 4usize),
        ("enum_records", 4usize),
        ("struct_records", 4),
        ("decl_layout", 4),
        ("node_inst_count", 4),
        ("node_inst_order", 4),
        ("node_inst_range", 4),
        ("node_inst_subtree_bounds", 4),
        ("node_inst_locations", 4),
        ("node_inst_gen_input", 4),
        ("virtual_inst", 4),
        ("virtual_func_first_row", 4),
        ("virtual_next_call", 4),
        ("func_param_reg_mask", 4),
        ("virtual_liveness", 4),
        ("virtual_regalloc", 4),
        ("select", 4),
        ("size", 4),
        ("text", 4),
        ("reloc", 4),
        ("encode", 4),
        ("elf_layout", 4),
        ("final", 4),
    ] {
        let end = offset + len;
        if end <= words.len() {
            eprintln!("[laniusc][x86-status] {name}: {:?}", &words[offset..end]);
        }
        offset = end;
    }
    Ok(())
}

fn x86_readback_timeout() -> Duration {
    let ms = crate::gpu::env::env_u64("LANIUS_X86_READBACK_TIMEOUT_MS", 3_000);
    Duration::from_millis(ms)
}
