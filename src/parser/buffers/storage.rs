use crate::gpu::buffers::LaniusBuffer;

pub(super) fn alias_storage_buffer<T, U>(
    source: &LaniusBuffer<T>,
    count: usize,
) -> LaniusBuffer<U> {
    LaniusBuffer::new((source.buffer.clone(), source.byte_size as u64), count)
}

pub(super) fn dispatch_args_buffer(device: &wgpu::Device, label: &str) -> LaniusBuffer<u32> {
    LaniusBuffer::new(
        (
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: 12,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::INDIRECT
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            }),
            12,
        ),
        3,
    )
}
