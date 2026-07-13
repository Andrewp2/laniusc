use crate::gpu::buffers::LaniusBuffer;

/// Reinterprets one typed storage buffer as another typed buffer with a new element count.
pub(super) fn alias_storage_buffer<T, U>(
    source: &LaniusBuffer<T>,
    count: usize,
) -> LaniusBuffer<U> {
    LaniusBuffer::new((source.buffer.clone(), source.byte_size as u64), count)
}

/// Allocates a three-word dispatch-argument buffer usable for compute indirect dispatches.
pub(super) fn dispatch_args_buffer(device: &wgpu::Device, label: &str) -> LaniusBuffer<u32> {
    dispatch_args_schedule_buffer(device, label, 1)
}

/// Allocates consecutive three-word compute dispatch arguments.
pub(super) fn dispatch_args_schedule_buffer(
    device: &wgpu::Device,
    label: &str,
    dispatch_count: usize,
) -> LaniusBuffer<u32> {
    let word_count = dispatch_count.max(1) * 3;
    let byte_size = (word_count * std::mem::size_of::<u32>()) as u64;
    LaniusBuffer::new(
        (
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: byte_size,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::INDIRECT
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            }),
            byte_size,
        ),
        word_count,
    )
}

/// Allocates a dispatch schedule followed by one GPU-written host metadata word.
pub(super) fn dispatch_args_schedule_with_count_buffer(
    device: &wgpu::Device,
    label: &str,
    dispatch_count: usize,
) -> LaniusBuffer<u32> {
    let word_count = dispatch_count.max(1) * 3 + 1;
    let byte_size = (word_count * std::mem::size_of::<u32>()) as u64;
    LaniusBuffer::new(
        (
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: byte_size,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::INDIRECT
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            }),
            byte_size,
        ),
        word_count,
    )
}

pub(crate) fn dispatch_args_schedule_count_offset(dispatch_count: usize) -> u64 {
    (dispatch_count.max(1) * 3 * std::mem::size_of::<u32>()) as u64
}

pub(crate) fn pointer_jump_step_capacity(items: u32) -> u32 {
    u32::BITS - items.saturating_sub(1).leading_zeros()
}

#[cfg(test)]
mod tests {
    use super::pointer_jump_step_capacity;

    #[test]
    fn pointer_jump_capacity_is_ceiling_log_two() {
        assert_eq!(pointer_jump_step_capacity(0), 0);
        assert_eq!(pointer_jump_step_capacity(1), 0);
        assert_eq!(pointer_jump_step_capacity(2), 1);
        assert_eq!(pointer_jump_step_capacity(3), 2);
        assert_eq!(pointer_jump_step_capacity(4), 2);
        assert_eq!(pointer_jump_step_capacity(5), 3);
        assert_eq!(pointer_jump_step_capacity(u32::MAX), 32);
    }
}
