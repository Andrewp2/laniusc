use super::*;

/// Encodes the accepted sentinel used to initialize the type-check status word.
pub(super) fn status_init_bytes() -> Vec<u8> {
    [1u32, u32::MAX, 0, 0]
        .into_iter()
        .flat_map(u32::to_le_bytes)
        .collect()
}

/// Encodes a `TypeCheckParams` uniform packet with the same layout shaders read.
pub(super) fn type_check_params_bytes(params: &TypeCheckParams) -> Vec<u8> {
    uniform_bytes(params)
}

pub(super) fn uniform_bytes<T>(value: &T) -> Vec<u8>
where
    T: encase::ShaderType + encase::internal::WriteInto,
{
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(value).expect("failed to encode uniform value");
    ub.as_ref().to_vec()
}

/// Allocates a valid zero-value type-check params uniform before real inputs arrive.
pub(super) fn zeroed_type_check_params_buffer(
    device: &wgpu::Device,
    label: &str,
) -> LaniusBuffer<TypeCheckParams> {
    let byte_len = type_check_params_bytes(&TypeCheckParams {
        n_tokens: 0,
        source_len: 0,
        n_hir_nodes: 0,
        n_source_files: 0,
        parser_feature_flags: 0,
        dependency_interfaces_present: 0,
    })
    .len();
    let raw = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_len as u64,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    LaniusBuffer::new_labeled((raw, byte_len as u64), 1, label)
}

/// Decodes the four-word type-check status readback buffer.
pub(super) fn read_status_words(bytes: &[u8]) -> Result<[u32; 4]> {
    crate::gpu::readback::read_u32_words(bytes, "type checker status")
}

/// Hashes buffer identities that affect resident bind-group reuse.
pub(super) fn buffer_fingerprint(buffers: &[&wgpu::Buffer]) -> u64 {
    crate::gpu::passes_core::buffer_fingerprint(buffers)
}

/// Allocates a writable typed `u32` storage buffer with at least one element.
pub(super) fn typed_storage_u32_rw(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    extra_usage: wgpu::BufferUsages,
) -> LaniusBuffer<u32> {
    let byte_size = (count.max(1) * 4) as u64;
    let raw = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_size,
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_SRC
            | wgpu::BufferUsages::COPY_DST
            | extra_usage,
        mapped_at_creation: false,
    });
    let buffer = LaniusBuffer::new_labeled((raw, byte_size), count, label);
    crate::gpu::buffers::register_resettable_buffer(
        &buffer,
        crate::gpu::buffers::JobResetPolicy::ClearBeforeJob,
    );
    buffer
}

/// Allocates a writable typed `u32` storage buffer initialized to one repeated value.
pub(super) fn typed_storage_u32_fill_rw(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    value: u32,
    extra_usage: wgpu::BufferUsages,
) -> LaniusBuffer<u32> {
    let allocated_count = count.max(1);
    let pattern = value.to_le_bytes();
    let mut bytes = vec![pattern[0]; allocated_count * 4];
    if !pattern.iter().all(|&byte| byte == pattern[0]) {
        for word in bytes.chunks_exact_mut(4) {
            word.copy_from_slice(&pattern);
        }
    }
    let raw = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &bytes,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | extra_usage,
    });
    LaniusBuffer::new_labeled((raw, bytes.len() as u64), count, label)
}

/// Allocates a host-readable `u32` readback buffer sized for `count` words.
pub(super) fn readback_u32s(device: &wgpu::Device, label: &str, count: usize) -> LaniusBuffer<u32> {
    let count = count.max(1);
    let byte_size = count * std::mem::size_of::<u32>();
    let raw = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_size as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    LaniusBuffer::new_labeled((raw, byte_size as u64), count, label)
}
