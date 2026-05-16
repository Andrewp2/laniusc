use super::*;

pub(super) fn status_init_bytes() -> Vec<u8> {
    [1u32, u32::MAX, 0, 0]
        .into_iter()
        .flat_map(u32::to_le_bytes)
        .collect()
}

pub(super) fn type_check_params_bytes(params: &TypeCheckParams) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params)
        .expect("failed to encode type checker params");
    ub.as_ref().to_vec()
}

pub(super) fn read_status_words(bytes: &[u8]) -> Result<[u32; 4]> {
    crate::gpu::readback::read_u32_words(bytes, "type checker status")
}

pub(super) fn buffer_fingerprint(buffers: &[&wgpu::Buffer]) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    for buffer in buffers {
        buffer.hash(&mut hasher);
    }
    hasher.finish()
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
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | extra_usage,
        mapped_at_creation: false,
    })
}

pub(super) fn storage_u32_fill_rw(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    value: u32,
    extra_usage: wgpu::BufferUsages,
) -> wgpu::Buffer {
    let count = count.max(1);
    let mut bytes = Vec::with_capacity(count * 4);
    for _ in 0..count {
        bytes.extend_from_slice(&value.to_le_bytes());
    }
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &bytes,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | extra_usage,
    })
}

pub(super) fn storage_i32_rw(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    extra_usage: wgpu::BufferUsages,
) -> wgpu::Buffer {
    storage_u32_rw(device, label, count, extra_usage)
}

pub(super) fn readback_u32s(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}

pub(super) fn token_bytes(tokens: &[Token]) -> Vec<u8> {
    let mut out = Vec::with_capacity(tokens.len().max(1) * 12);
    for token in tokens {
        out.extend_from_slice(&(token.kind as u32).to_le_bytes());
        out.extend_from_slice(&(token.start as u32).to_le_bytes());
        out.extend_from_slice(&(token.len as u32).to_le_bytes());
    }
    if out.is_empty() {
        out.resize(12, 0);
    }
    out
}

pub(super) fn nonempty_bytes(bytes: &[u8]) -> Vec<u8> {
    let mut out = if bytes.is_empty() {
        vec![0]
    } else {
        bytes.to_vec()
    };
    let aligned_len = out.len().div_ceil(4) * 4;
    if out.len() < aligned_len {
        out.resize(aligned_len, 0);
    }
    out
}
