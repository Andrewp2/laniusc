use std::{
    collections::HashMap,
    ops::Deref,
    sync::{Mutex, OnceLock},
    time::Duration,
};

use anyhow::{Result, bail};
use log::warn;
use wgpu::util::DeviceExt;

use super::{
    GPU_X86_OBJECT_VERSION,
    GpuX86DependencySymbolBuffers,
    GpuX86ObjectSection,
    GpuX86ObjectSymbolRecord,
    GpuX86RelocatableObject,
    GpuX86RelocationKind,
    GpuX86RelocationRecord,
    GpuX86RelocationTargetKind,
    RecordedX86ArtifactMode,
    RecordedX86Codegen,
    X86_ERR_HIR_TREE_SHAPE,
    X86_ERR_INTRINSIC_CALLS,
    X86_ERR_MULTIPLE_MAIN,
    X86_ERR_NESTED_AGGREGATE_MEMBER,
    X86_ERR_NODE_INST_COUNTS,
    X86_ERR_NODE_INST_LOCATIONS,
    X86_ERR_REGALLOC_BOUNDARY,
    X86_ERR_SIGNED_DIV_OVERFLOW,
    X86_ERR_STRUCT_RECORDS,
    X86_ERR_UNSUPPORTED_LITERAL_EXPR,
    X86_ERR_VIRTUAL_LIVENESS,
    X86OutputError,
    X86Params,
    X86RegallocParams,
    X86ScanParams,
};
use crate::gpu::{
    buffers::LaniusBuffer,
    passes_core::{PassData, bind_group},
};

const UNIFORM_BINDING_ARRAY_STRIDE: u64 = 256;

#[derive(Clone, Copy, Debug, Eq, Hash, PartialEq)]
struct PooledStorageBufferKey {
    device: usize,
    size: u64,
    usage_bits: u64,
}

/// Storage buffer returned to the x86 pool when dropped.
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

/// Readback buffer returned to the x86 pool when dropped.
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
/// Buffer retained across x86 recording that may or may not come from the pool.
pub(super) enum RetainedX86Buffer {
    /// Owned WGPU buffer with ordinary drop behavior.
    Plain(wgpu::Buffer),
    /// Storage buffer that returns to the x86 pool when dropped.
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

impl RetainedX86Buffer {
    fn buffer(&self) -> &wgpu::Buffer {
        match self {
            Self::Plain(buffer) => buffer,
            Self::Pooled(buffer) => buffer,
        }
    }
}

impl<T> From<LaniusBuffer<T>> for RetainedX86Buffer {
    fn from(buffer: LaniusBuffer<T>) -> Self {
        Self::Plain(buffer.buffer)
    }
}

/// Uniform buffer containing fixed-stride items addressable by dynamic offsets.
pub(super) struct UniformBindingArray {
    buffer: wgpu::Buffer,
    item_size: u64,
    len: usize,
}

impl UniformBindingArray {
    /// Returns the number of logical uniform items in the array.
    pub(super) fn len(&self) -> usize {
        self.len
    }

    /// Returns a binding resource for one fixed-stride uniform item.
    pub(super) fn binding(&self, index: usize) -> wgpu::BindingResource<'_> {
        let offset = uniform_binding_array_offset(index);
        wgpu::BindingResource::Buffer(wgpu::BufferBinding {
            buffer: &self.buffer,
            offset,
            size: wgpu::BufferSize::new(self.item_size),
        })
    }

    /// Returns the dynamic offset for one fixed-stride uniform item.
    pub(super) fn dynamic_offset(&self, index: usize) -> u32 {
        let offset = uniform_binding_array_offset(index);
        u32::try_from(offset).expect("x86 uniform dynamic offset exceeded u32")
    }

    /// Consumes the wrapper and returns the underlying uniform buffer.
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

/// Emits an x86 backend trace event when `LANIUS_X86_TRACE` is enabled.
pub(super) fn trace_x86_codegen(stage: &str) {
    if x86_trace_enabled() {
        eprintln!("[laniusc][x86-codegen] {stage}");
    }
}

/// Encodes the main x86 parameter uniform using shader layout rules.
pub(super) fn x86_params_bytes(params: &X86Params) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params)
        .expect("failed to encode x86 codegen params");
    ub.as_ref().to_vec()
}

/// Encodes an x86 scan parameter uniform using shader layout rules.
pub(super) fn x86_scan_params_bytes(params: &X86ScanParams) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params).expect("failed to encode x86 scan params");
    ub.as_ref().to_vec()
}

/// Encodes an x86 register-allocation parameter uniform.
pub(super) fn x86_regalloc_params_bytes(params: &X86RegallocParams) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params)
        .expect("failed to encode x86 register-allocation params");
    ub.as_ref().to_vec()
}

/// Encodes little-endian `u32` words for storage or uniform initialization.
pub(super) fn u32_words_bytes(words: &[u32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(words.len() * 4);
    for word in words {
        out.extend_from_slice(&word.to_le_bytes());
    }
    out
}

/// Writes little-endian `u32` words to the start of a WGPU buffer.
pub(super) fn write_u32_words(queue: &wgpu::Queue, buffer: &wgpu::Buffer, words: &[u32]) {
    queue.write_buffer(buffer, 0, &u32_words_bytes(words));
}

/// Initializes a buffer with a repeated `u32` pattern through the GPU fill pass.
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

/// Records the GPU pass that writes a repeated `u32` pattern.
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
        bail!("x86 fill supports repeated patterns up to four u32 words");
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

/// Clears the first `words` `u32` slots of a buffer.
pub(super) fn zero_u32_words(
    _queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    buffer: &wgpu::Buffer,
    words: usize,
) {
    crate::gpu::passes_core::flush_deferred_compute(encoder);
    let words = words.max(1);
    let bytes = words * 4;
    encoder.clear_buffer(buffer, 0, Some(bytes as u64));
}

pub(super) fn copy_x86_buffer_to_buffer(
    encoder: &mut wgpu::CommandEncoder,
    source: &wgpu::Buffer,
    source_offset: u64,
    destination: &wgpu::Buffer,
    destination_offset: u64,
    size: u64,
) {
    crate::gpu::passes_core::flush_deferred_compute(encoder);
    encoder.copy_buffer_to_buffer(source, source_offset, destination, destination_offset, size);
}

/// Creates a uniform buffer from already-encoded struct bytes.
pub(super) fn uniform_u32_struct(
    device: &wgpu::Device,
    label: &str,
    bytes: &[u8],
) -> LaniusBuffer<u32> {
    let contents = if bytes.is_empty() { &[0u8][..] } else { bytes };
    let buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
    });
    let count = contents.len().div_ceil(4).max(1);
    LaniusBuffer::new_labeled((buffer, contents.len() as u64), count, label)
}

/// Creates a uniform buffer from little-endian `u32` words.
pub(super) fn uniform_u32_words(
    device: &wgpu::Device,
    label: &str,
    words: &[u32],
) -> LaniusBuffer<u32> {
    uniform_u32_struct(device, label, &u32_words_bytes(words))
}

/// Creates a fixed-stride uniform array for dynamic-offset dispatch loops.
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

/// Allocates writable x86 storage for `u32` rows.
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

/// Allocates writable x86 `u32` storage that can also be copied from.
pub(super) fn storage_u32_copy(
    device: &wgpu::Device,
    label: &str,
    count: usize,
) -> LaniusBuffer<u32> {
    storage_u32_rw(device, label, count, wgpu::BufferUsages::COPY_SRC)
}

/// Wraps an external storage buffer or allocates copy-readable `u32` storage.
pub(super) fn external_or_storage_u32_copy(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    external: Option<&wgpu::Buffer>,
) -> LaniusBuffer<u32> {
    let count = count.max(1);
    external
        .cloned()
        .map(|buffer| LaniusBuffer::untracked_alias((buffer, (count * 4) as u64), count))
        .unwrap_or_else(|| storage_u32_copy(device, label, count))
}

/// Opens a WGPU out-of-memory error scope around backend buffer allocation.
pub(super) fn push_allocation_error_scope(device: &wgpu::Device) -> wgpu::ErrorScopeGuard {
    device.push_error_scope(wgpu::ErrorFilter::OutOfMemory)
}

/// Closes an x86 allocation error scope and turns allocation failure into `Result`.
pub(super) fn pop_allocation_error_scope(scope: wgpu::ErrorScopeGuard, stage: &str) -> Result<()> {
    if let Some(err) = pollster::block_on(scope.pop()) {
        bail!("x86 code generation could not allocate buffers during {stage}: {err}");
    }
    Ok(())
}

/// Takes or allocates pooled writable x86 storage for `u32` rows.
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

/// Takes or allocates pooled copy-readable x86 storage for `u32` rows.
pub(super) fn pooled_storage_u32_copy(
    device: &wgpu::Device,
    label: &str,
    count: usize,
) -> PooledStorageBuffer {
    pooled_storage_u32_rw(device, label, count, wgpu::BufferUsages::COPY_SRC)
}

/// Takes or allocates a pooled readback buffer for `bytes` bytes.
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

/// Drops every currently idle pooled x86 buffer for one device.
///
/// Checked-out buffers are unaffected and return to the pool normally when
/// their recording handle is dropped. The compiler calls this only while its
/// resident pipeline lock excludes active compilation.
pub(super) fn release_pooled_buffers_for_device(device: &wgpu::Device) -> (usize, u64) {
    let device_key = device as *const wgpu::Device as usize;
    let mut released = Vec::new();
    let mut released_bytes = 0u64;
    {
        let mut pool = storage_buffer_pool()
            .lock()
            .expect("x86 storage buffer pool poisoned");
        let keys = pool
            .keys()
            .copied()
            .filter(|key| key.device == device_key)
            .collect::<Vec<_>>();
        for key in keys {
            if let Some(mut buffers) = pool.remove(&key) {
                released_bytes =
                    released_bytes.saturating_add(key.size.saturating_mul(buffers.len() as u64));
                released.append(&mut buffers);
            }
        }
    }
    let released_count = released.len();
    drop(released);
    (released_count, released_bytes)
}

/// Allocates a host-readable readback buffer for `count` `u32` words.
pub(super) fn readback_u32s(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}

/// Splits a one-dimensional workgroup count across x/y WebGPU dispatch limits.
pub(super) fn workgroup_grid_1d(groups: u32) -> (u32, u32) {
    const MAX_X: u32 = 65_535;
    let groups = groups.max(1);
    if groups <= MAX_X {
        (groups, 1)
    } else {
        (MAX_X, groups.div_ceil(MAX_X))
    }
}

/// Returns scan-step values for an x86 block-prefix scan.
pub(super) fn scan_steps_for_blocks(n_blocks: usize) -> Vec<u32> {
    crate::gpu::scan::scan_step_values(n_blocks as u32)
}

/// Returns pointer-jump step numbers needed to cover `n_items` linked rows.
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

    #[test]
    fn x86_hir_tree_shape_error_is_source_addressable() {
        let err = X86OutputError::new(
            x86_error_name(X86_ERR_HIR_TREE_SHAPE as usize, 12),
            X86_ERR_HIR_TREE_SHAPE,
            12,
        );

        assert_eq!(err.error_name(), "unsupported x86 HIR tree shape");
        assert!(err.detail_is_hir_node());
        assert!(!err.detail_is_token());
    }

    #[test]
    fn x86_stage_record_errors_are_source_addressable() {
        for (error_code, expected_name) in [
            (
                X86_ERR_NODE_INST_COUNTS,
                "unsupported x86 node instruction count",
            ),
            (X86_ERR_VIRTUAL_LIVENESS, "unsupported x86 virtual liveness"),
            (
                X86_ERR_NODE_INST_LOCATIONS,
                "unsupported x86 instruction location",
            ),
            (X86_ERR_INTRINSIC_CALLS, "unsupported x86 intrinsic call"),
            (X86_ERR_STRUCT_RECORDS, "unsupported x86 struct record"),
            (
                X86_ERR_REGALLOC_BOUNDARY,
                "unsupported x86 register allocation",
            ),
            (
                X86_ERR_UNSUPPORTED_LITERAL_EXPR,
                "unsupported x86 literal expression",
            ),
        ] {
            let err = X86OutputError::new(x86_error_name(error_code as usize, 12), error_code, 12);

            assert_eq!(err.error_name(), expected_name, "code {error_code}");
            assert!(err.detail_is_hir_node(), "code {error_code}");
            assert!(!err.detail_is_token(), "code {error_code}");
        }
    }
}

/// Records one direct x86 compute pass and emits optional trace events.
pub(super) fn dispatch_compute_pass(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage: &str,
    label: &str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    groups: (u32, u32),
) {
    trace_x86_codegen_event(trace_stage, "record.start");
    if crate::gpu::passes_core::defer_compute_direct(pass, bind_group, (groups.0, groups.1, 1)) {
        trace_x86_codegen_event(trace_stage, "record.done");
        return;
    }
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

/// Records one indirect x86 compute pass from offset zero.
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

/// Records one indirect x86 compute pass from a specific dispatch-args offset.
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

/// Records one indirect x86 compute pass with bind-group dynamic offsets.
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
    if crate::gpu::passes_core::defer_compute_indirect(
        pass,
        bind_group,
        indirect_buffer,
        indirect_offset,
        dynamic_offsets,
    ) {
        trace_x86_codegen_event(trace_stage, "record.done");
        return;
    }
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

/// Records repeated indirect dispatches sharing one bind group and uniform array.
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
    for (&indirect_offset, &dynamic_offset) in indirect_offsets.iter().zip(uniform_dynamic_offsets)
    {
        dispatch_compute_pass_indirect_offset_with_dynamic_offsets(
            encoder,
            trace_stage,
            label,
            pass,
            bind_group,
            indirect_buffer,
            indirect_offset,
            &[dynamic_offset],
        );
    }
}

/// Records a sequence of indirect dispatches with per-step bind groups and uniforms.
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
    for ((bind_group, &indirect_offset), &dynamic_offset) in bind_groups
        .iter()
        .zip(indirect_offsets)
        .zip(uniform_dynamic_offsets)
    {
        dispatch_compute_pass_indirect_offset_with_dynamic_offsets(
            encoder,
            trace_stage,
            label,
            pass,
            bind_group,
            indirect_buffer,
            indirect_offset,
            &[dynamic_offset],
        );
    }
}

/// Records ping-pong scan steps with alternating bind groups and dynamic uniforms.
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

/// Records an indirect dispatch for each bind group in a step sequence.
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
    for (step_i, bind_group) in bind_groups.iter().enumerate() {
        let trace_stage = format!("{trace_stage_prefix}.{step_i}");
        dispatch_compute_pass_indirect(
            encoder,
            &trace_stage,
            label,
            pass,
            bind_group,
            indirect_buffer,
        );
    }
}

/// Records a capacity-stable step sequence from per-round indirect commands.
pub(super) fn dispatch_compute_pass_indirect_bind_group_scheduled_steps(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage_prefix: &str,
    label: &str,
    pass: &PassData,
    bind_groups: &[wgpu::BindGroup],
    schedule_buffer: &wgpu::Buffer,
) {
    for (step_i, bind_group) in bind_groups.iter().enumerate() {
        let trace_stage = format!("{trace_stage_prefix}.{step_i}");
        dispatch_compute_pass_indirect_offset(
            encoder,
            &trace_stage,
            label,
            pass,
            bind_group,
            schedule_buffer,
            (step_i * 3 * std::mem::size_of::<u32>()) as u64,
        );
    }
}

/// Records several direct x86 stages in one compute pass.
pub(super) fn dispatch_x86_stages(
    encoder: &mut wgpu::CommandEncoder,
    stages: &[(&'static str, &PassData, &wgpu::BindGroup)],
    groups: (u32, u32),
) {
    if stages.is_empty() {
        return;
    }
    for (stage, pass, bind_group) in stages {
        dispatch_x86_stage(encoder, stage, pass, bind_group, groups);
    }
}

/// Records one named direct x86 stage.
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

/// Records several indirect x86 stages in one compute pass.
pub(super) fn dispatch_x86_stages_indirect(
    encoder: &mut wgpu::CommandEncoder,
    stages: &[(&'static str, &PassData, &wgpu::BindGroup)],
    indirect_buffer: &wgpu::Buffer,
) {
    if stages.is_empty() {
        return;
    }
    for (stage, pass, bind_group) in stages {
        dispatch_x86_stage_indirect(encoder, stage, pass, bind_group, indirect_buffer);
    }
}

/// Records one named indirect x86 stage.
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

/// Builds a bind group and wraps reflection errors with the backend label.
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

/// Reads x86 backend status and output bytes from the recorded readback buffer.
pub(super) fn read_x86_output(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    recorded: &RecordedX86Codegen,
) -> Result<Vec<u8>> {
    if recorded.artifact_mode != RecordedX86ArtifactMode::Executable {
        bail!("recorded x86 artifact is relocatable object work, not an executable");
    }
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
        let error_name = x86_error_name(error_code, error_detail);
        return Err(X86OutputError::new(error_name, error_code as u32, error_detail as u32).into());
    }
    if mode != 1 || len > recorded.output_capacity {
        return Err(anyhow::anyhow!(
            "x86 emitter produced {} bytes for capacity {}",
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
    Err(anyhow::anyhow!("x86 emitter output bytes were unavailable"))
}

/// Reads normalized section-relative rows emitted by the GPU relocation pass.
pub(super) fn read_x86_object(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    recorded: &RecordedX86Codegen,
    library_id: u32,
    unit_id: u32,
    dependency_symbols: Option<GpuX86DependencySymbolBuffers<'_>>,
) -> Result<GpuX86RelocatableObject> {
    if recorded.artifact_mode != RecordedX86ArtifactMode::RelocatableObject {
        bail!("recorded x86 artifact is executable work, not a relocatable object");
    }
    let metadata_slice = recorded.object_metadata_readback.slice(..68);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &metadata_slice,
        "codegen.x86.object_metadata",
        x86_readback_timeout(),
    )?;
    let metadata: [u32; 17] = {
        let data = metadata_slice.get_mapped_range();
        let words = crate::gpu::readback::read_u32_words(&data, "x86 object metadata");
        drop(data);
        recorded.object_metadata_readback.unmap();
        words?
    };
    let text_len = metadata[0] as usize;
    let rodata_len = metadata[1] as usize;
    let relocation_count = metadata[2] as usize;
    let encode_status = &metadata[3..7];
    let reloc_status = &metadata[7..11];
    let layout_status = &metadata[11..15];
    let local_symbol_count = metadata[15] as usize;
    let entry_offset = match metadata[16] {
        0 => None,
        1 => Some(0),
        count => bail!("x86 object records {count} entrypoints"),
    };
    let section_len = text_len
        .checked_add(rodata_len)
        .ok_or_else(|| anyhow::anyhow!("x86 object section length overflows"))?;
    let file_len = 0x78usize
        .checked_add(section_len)
        .ok_or_else(|| anyhow::anyhow!("x86 object file span overflows"))?;
    let metadata_ok = encode_status == [1, 0, u32::MAX, text_len as u32]
        && reloc_status == [1, 0, u32::MAX, relocation_count as u32]
        && layout_status == [1, 0, u32::MAX, file_len as u32]
        && file_len <= recorded.output_capacity;
    if !metadata_ok {
        if let Some(status_trace_readback) = &recorded.status_trace_readback {
            if let Err(err) = dump_x86_status_trace(device, status_trace_readback) {
                warn!("failed to read x86 object status trace: {err:#}");
            }
        }
        bail!(
            "x86 object GPU status is invalid: text={text_len} rodata={rodata_len} relocations={relocation_count} encode={encode_status:?} reloc={reloc_status:?} layout={layout_status:?}"
        );
    }

    let section_copy_bytes = section_len.div_ceil(4).saturating_mul(4) as u64;
    let section_readback = pooled_readback_bytes(
        device,
        "rb.codegen.x86.object_sections.exact",
        section_copy_bytes.max(1),
    );
    let relocation_bytes = relocation_count
        .checked_mul(3)
        .and_then(|words| words.checked_mul(4))
        .ok_or_else(|| anyhow::anyhow!("x86 object relocation readback length overflows"))?;
    let dependency_symbol_count = dependency_symbols
        .as_ref()
        .map_or(0usize, |symbols| symbols.declaration_count as usize);
    let dependency_symbol_bytes = dependency_symbol_count
        .checked_mul(3)
        .and_then(|words| words.checked_mul(4))
        .ok_or_else(|| anyhow::anyhow!("x86 dependency symbol readback length overflows"))?;
    let local_symbol_bytes = local_symbol_count
        .checked_mul(4)
        .and_then(|words| words.checked_mul(4))
        .ok_or_else(|| anyhow::anyhow!("x86 local symbol readback length overflows"))?;
    let relocation_and_symbol_bytes = relocation_bytes
        .checked_add(dependency_symbol_bytes)
        .and_then(|bytes| bytes.checked_add(local_symbol_bytes))
        .ok_or_else(|| anyhow::anyhow!("x86 object metadata readback length overflows"))?;
    let relocation_readback = pooled_readback_bytes(
        device,
        "rb.codegen.x86.object_relocations.exact",
        (relocation_and_symbol_bytes as u64).max(1),
    );
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("codegen.x86.object_readback.exact.encoder"),
    });
    if section_copy_bytes != 0 {
        encoder.copy_buffer_to_buffer(
            &recorded.out_buf,
            0x78,
            &section_readback,
            0,
            section_copy_bytes,
        );
    }
    if relocation_count != 0 {
        let one_array_bytes = (relocation_count * 4) as u64;
        for (source, offset) in [
            (&recorded.object_reloc_kind, 0u64),
            (&recorded.object_reloc_site_offset, one_array_bytes),
            (&recorded.object_reloc_target_offset, one_array_bytes * 2),
        ] {
            encoder.copy_buffer_to_buffer(
                source.buffer(),
                0,
                &relocation_readback,
                offset,
                one_array_bytes,
            );
        }
    }
    if let Some(symbols) = &dependency_symbols {
        if dependency_symbol_count != 0 {
            let one_array_bytes = (dependency_symbol_count * 4) as u64;
            let base = relocation_bytes as u64;
            for (source, offset) in [
                (symbols.declaration_library_id, base),
                (symbols.declaration_unit_id, base + one_array_bytes),
                (symbols.declaration_local_index, base + one_array_bytes * 2),
            ] {
                encoder.copy_buffer_to_buffer(
                    source,
                    0,
                    &relocation_readback,
                    offset,
                    one_array_bytes,
                );
            }
        }
    }
    if local_symbol_count != 0 {
        encoder.copy_buffer_to_buffer(
            recorded.object_symbol_record.buffer(),
            0,
            &relocation_readback,
            (relocation_bytes + dependency_symbol_bytes) as u64,
            local_symbol_bytes as u64,
        );
    }
    crate::gpu::passes_core::submit_with_progress(
        queue,
        "codegen.x86.object-readback-exact",
        encoder.finish(),
    );

    let section_bytes = if section_len == 0 {
        Vec::new()
    } else {
        let slice = section_readback.slice(0..section_copy_bytes);
        crate::gpu::passes_core::wait_for_readback_map(
            device,
            &slice,
            "codegen.x86.object_sections.exact",
            x86_readback_timeout(),
        )?;
        let data = slice.get_mapped_range();
        let bytes = data[..section_len].to_vec();
        drop(data);
        section_readback.unmap();
        bytes
    };
    let relocation_and_symbol_words = if relocation_and_symbol_bytes == 0 {
        Vec::new()
    } else {
        let slice = relocation_readback.slice(0..relocation_and_symbol_bytes as u64);
        crate::gpu::passes_core::wait_for_readback_map(
            device,
            &slice,
            "codegen.x86.object_relocations.exact",
            x86_readback_timeout(),
        )?;
        let data = slice.get_mapped_range();
        let words = data
            .chunks_exact(4)
            .map(|word| u32::from_le_bytes(word.try_into().expect("four bytes")))
            .collect::<Vec<_>>();
        drop(data);
        relocation_readback.unmap();
        words
    };
    let (relocation_words, all_symbol_words) =
        relocation_and_symbol_words.split_at(relocation_count * 3);
    let (dependency_symbol_words, local_symbol_words) =
        all_symbol_words.split_at(dependency_symbol_count * 3);

    let (text, rodata) = section_bytes.split_at(text_len);
    let (kinds, remaining) = relocation_words.split_at(relocation_count);
    let (sites, targets) = remaining.split_at(relocation_count);
    let mut relocations = Vec::with_capacity(relocation_count);
    for index in 0..relocation_count {
        let kind = kinds[index] & 0xff;
        let (kind, target_section, target_kind, addend) = match kind {
            1 => (
                GpuX86RelocationKind::Rel32,
                GpuX86ObjectSection::Text,
                GpuX86RelocationTargetKind::SectionOffset,
                -4,
            ),
            2 => (
                GpuX86RelocationKind::CallRel32,
                GpuX86ObjectSection::Text,
                GpuX86RelocationTargetKind::SectionOffset,
                -4,
            ),
            3 => (
                GpuX86RelocationKind::Abs32,
                GpuX86ObjectSection::Text,
                GpuX86RelocationTargetKind::SectionOffset,
                0,
            ),
            4 => (
                GpuX86RelocationKind::Abs32,
                GpuX86ObjectSection::Rodata,
                GpuX86RelocationTargetKind::SectionOffset,
                0,
            ),
            5 => (
                GpuX86RelocationKind::CallRel32,
                GpuX86ObjectSection::Undefined,
                GpuX86RelocationTargetKind::Symbol,
                -4,
            ),
            other => bail!("x86 object relocation {index} has GPU kind {other}"),
        };
        let symbol_target = target_kind == GpuX86RelocationTargetKind::Symbol;
        relocations.push(GpuX86RelocationRecord {
            kind,
            site_section: GpuX86ObjectSection::Text,
            site_offset: sites[index],
            target_kind,
            target_index: if symbol_target {
                targets[index]
            } else {
                target_section as u32
            },
            target_offset: if symbol_target { 0 } else { targets[index] },
            addend,
        });
    }
    let (dependency_library_ids, dependency_symbol_words) =
        dependency_symbol_words.split_at(dependency_symbol_count);
    let (dependency_unit_ids, dependency_local_indices) =
        dependency_symbol_words.split_at(dependency_symbol_count);
    let mut identity_bytes = Vec::with_capacity(dependency_symbol_count.saturating_mul(12));
    let mut symbols = Vec::with_capacity(dependency_symbol_count);
    for index in 0..dependency_symbol_count {
        let identity_byte_start = identity_bytes.len() as u32;
        for word in [
            dependency_library_ids[index],
            dependency_unit_ids[index],
            dependency_local_indices[index],
        ] {
            identity_bytes.extend_from_slice(&word.to_le_bytes());
        }
        let identity = &identity_bytes[identity_byte_start as usize..];
        let (identity_hash_lo, identity_hash_hi) = crate::compiler::stable_name_hash(identity);
        symbols.push(GpuX86ObjectSymbolRecord {
            identity_hash_lo,
            identity_hash_hi,
            identity_byte_start,
            identity_byte_len: 12,
            section: GpuX86ObjectSection::Undefined,
            offset: 0,
            size: 0,
            flags: 0,
        });
    }
    for persisted_decl in 0..local_symbol_count {
        let base = persisted_decl * 4;
        let section = match local_symbol_words[base] {
            0 => GpuX86ObjectSection::Undefined,
            1 => GpuX86ObjectSection::Text,
            2 => GpuX86ObjectSection::Rodata,
            other => bail!("x86 local object symbol {persisted_decl} has GPU section tag {other}"),
        };
        let identity_byte_start = identity_bytes.len() as u32;
        for word in [library_id, unit_id, persisted_decl as u32] {
            identity_bytes.extend_from_slice(&word.to_le_bytes());
        }
        let identity = &identity_bytes[identity_byte_start as usize..];
        let (identity_hash_lo, identity_hash_hi) = crate::compiler::stable_name_hash(identity);
        symbols.push(GpuX86ObjectSymbolRecord {
            identity_hash_lo,
            identity_hash_hi,
            identity_byte_start,
            identity_byte_len: 12,
            section,
            offset: local_symbol_words[base + 1],
            size: local_symbol_words[base + 2],
            flags: local_symbol_words[base + 3],
        });
    }
    let object = GpuX86RelocatableObject {
        version: GPU_X86_OBJECT_VERSION,
        library_id,
        unit_id,
        entry_offset,
        text: text.to_vec(),
        rodata: rodata.to_vec(),
        relocations,
        symbols,
        identity_bytes,
    };
    object.validate().map_err(anyhow::Error::msg)?;
    Ok(object)
}

fn x86_error_name(error_code: usize, error_detail: usize) -> &'static str {
    match error_code {
        2 => "missing main entrypoint",
        3 => "unsupported return expression",
        4 => "output capacity too small",
        5 => "register allocation failure",
        6 => "instruction sizing failure",
        7 => "ELF layout failure",
        8 => "x86 relocation failure",
        9 => "unsupported x86 call ABI",
        error if error == X86_ERR_NODE_INST_COUNTS as usize => {
            "unsupported x86 node instruction count"
        }
        11 => "unsupported x86 virtual instruction",
        error if error == X86_ERR_VIRTUAL_LIVENESS as usize => "unsupported x86 virtual liveness",
        15 => "virtual register allocation failure",
        error if error == X86_ERR_NODE_INST_LOCATIONS as usize => {
            "unsupported x86 instruction location"
        }
        17 if error_detail == u32::MAX as usize => "unsupported x86 entrypoint body",
        17 => "instruction selection failure",
        error if error == X86_ERR_INTRINSIC_CALLS as usize => "unsupported x86 intrinsic call",
        24 => "unsupported x86 method call",
        26 => "unsupported x86 aggregate copy width",
        27 => "unsupported x86 declaration layout",
        error if error == X86_ERR_STRUCT_RECORDS as usize => "unsupported x86 struct record",
        29 => "unsupported x86 loop-contained call",
        30 => "unsupported x86 postfix expression",
        31 => "unsupported x86 indexed assignment",
        32 => "unsupported x86 zero divisor",
        33 => "unsupported x86 for iterable",
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
        error if error == X86_ERR_REGALLOC_BOUNDARY as usize => {
            "unsupported x86 register allocation"
        }
        49 => "unsupported x86 entrypoint parameters",
        51 => "unsupported x86 parameter register count",
        52 => "unsupported x86 aggregate return call",
        53 => "unsupported x86 multi-payload enum constructor",
        54 => "unsupported x86 entrypoint aggregate return",
        55 => "unsupported x86 loop control outside loop",
        56 => "unsupported x86 call argument count",
        error if error == X86_ERR_HIR_TREE_SHAPE as usize => "unsupported x86 HIR tree shape",
        error if error == X86_ERR_MULTIPLE_MAIN as usize => "multiple main entrypoints",
        error if error == X86_ERR_SIGNED_DIV_OVERFLOW as usize => {
            "unsupported x86 signed division overflow"
        }
        error if error == X86_ERR_UNSUPPORTED_LITERAL_EXPR as usize => {
            "unsupported x86 literal expression"
        }
        62 => "invalid compact x86 call record",
        error if error == X86_ERR_NESTED_AGGREGATE_MEMBER as usize => {
            "unsupported x86 nested aggregate member"
        }
        error if error == super::X86_ERR_RODATA_SIZE as usize => {
            "unsupported x86 rodata size planning"
        }
        error if error == super::X86_ERR_RODATA_OFFSET as usize => {
            "unsupported x86 rodata offset planning"
        }
        error if error == super::X86_ERR_RODATA_WRITE as usize => {
            "unsupported x86 rodata byte emission"
        }
        _ => "unsupported source shape",
    }
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
    let words: [u32; 132] = crate::gpu::readback::read_u32_words(&data, "x86 status trace")?;
    drop(data);
    readback.unmap();

    if crate::gpu::trace::enabled() {
        let now = std::time::Instant::now();
        let func_meta_offset = 14usize;
        for (name, value) in [
            ("x86.func_count", words[func_meta_offset]),
            ("x86.main_count", words[func_meta_offset + 1]),
            ("x86.main_max_node", words[func_meta_offset + 3]),
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
        ("call_records", 4),
        ("param_regs", 4),
        ("intrinsic_calls", 4),
        ("call_abi", 4),
        ("node_inst_count", 5),
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
        ("rodata", 4),
        ("rodata_len", 1),
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
