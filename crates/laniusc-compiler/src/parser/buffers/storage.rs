use crate::gpu::buffers::{LaniusBuffer, storage_rw_for_array, storage_rw_uninit_bytes};

fn align_up(value: u64, alignment: u64) -> u64 {
    value.div_ceil(alignment) * alignment
}

/// Returns the physical byte size required for independently bindable rows in
/// one phase-local arena. Every row begins at the device's storage-buffer
/// offset alignment; row sizes themselves remain exact.
pub(super) fn phase_arena_bytes(
    device: &wgpu::Device,
    rows: impl IntoIterator<Item = (usize, usize)>,
) -> u64 {
    let alignment = u64::from(device.limits().min_storage_buffer_offset_alignment.max(1));
    rows.into_iter().fold(0u64, |offset, (count, stride)| {
        let row_bytes = count
            .max(1)
            .checked_mul(stride.max(1))
            .expect("phase arena row byte size overflow") as u64;
        align_up(offset, alignment)
            .checked_add(row_bytes)
            .expect("phase arena byte size overflow")
    })
}

/// Assigns typed, aligned, non-overlapping views within one physical arena.
///
/// This cursor only packs rows that coexist in one phase. Reusing the arena
/// across phases is a separate lifetime decision made by the caller.
pub(super) struct PhaseArenaCursor<'a> {
    device: &'a wgpu::Device,
    source: &'a LaniusBuffer<u32>,
    next_offset: u64,
}

impl<'a> PhaseArenaCursor<'a> {
    pub(super) fn new(device: &'a wgpu::Device, source: &'a LaniusBuffer<u32>) -> Self {
        Self {
            device,
            source,
            next_offset: 0,
        }
    }

    pub(super) fn row<T>(&mut self, logical_label: &str, count: usize) -> LaniusBuffer<T> {
        let count = count.max(1);
        let byte_size = count
            .checked_mul(core::mem::size_of::<T>().max(1))
            .expect("phase arena row byte size overflow") as u64;
        let alignment = u64::from(
            self.device
                .limits()
                .min_storage_buffer_offset_alignment
                .max(1),
        );
        let offset = align_up(self.next_offset, alignment);
        self.next_offset = offset
            .checked_add(byte_size)
            .expect("phase arena cursor overflow");
        self.source
            .subrange(offset, byte_size, count)
            .unwrap_or_else(|error| panic!("phase arena row {logical_label} does not fit: {error}"))
    }
}

/// Allocator for parser rows that are all dead once compact HIR has been
/// materialized.
///
/// Rows remain independently bindable. Physical arena packing belongs in the
/// compiler graph because WebGPU tracks access per physical buffer and correct
/// write-to-read transitions depend on the complete reflected pass schedule.
pub(super) struct PostHirWorkspaceArenas<'a> {
    device: &'a wgpu::Device,
}

impl<'a> PostHirWorkspaceArenas<'a> {
    pub(super) fn new(device: &'a wgpu::Device, _label: &'static str, _arena_bytes: u64) -> Self {
        Self { device }
    }

    /// Allocates one independently bindable four-byte-element row. Parser tree
    /// and scan rows use `u32` or `i32`, which have identical storage layout.
    pub(super) fn row<T>(&mut self, logical_label: &str, count: usize) -> LaniusBuffer<T> {
        assert_eq!(
            core::mem::size_of::<T>(),
            4,
            "post-HIR workspace row {logical_label} must have four-byte elements",
        );
        let count = count.max(1);
        let byte_size = count
            .checked_mul(4)
            .expect("post-HIR workspace row byte size overflow");
        storage_rw_uninit_bytes(self.device, logical_label, byte_size, byte_size)
            .subrange(0, byte_size as u64, count)
            .expect("post-HIR workspace row must fit its allocation")
    }
}

/// Reinterprets one typed storage buffer as another typed buffer with a new element count.
pub(super) fn alias_storage_buffer<T, U>(
    source: &LaniusBuffer<T>,
    count: usize,
) -> LaniusBuffer<U> {
    let target_stride = core::mem::size_of::<U>().max(1);
    let required_bytes = count
        .checked_mul(target_stride)
        .expect("storage alias byte size overflow");
    assert!(
        required_bytes <= source.byte_size,
        "storage alias requires {required_bytes} bytes but source only has {} bytes",
        source.byte_size,
    );
    source.alias(count)
}

/// Reuses a dead u32 storage allocation for a later parser phase when it is
/// large enough, otherwise allocates the requested workspace normally.
pub(super) fn reuse_or_allocate_u32_workspace(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    reusable: Option<&LaniusBuffer<u32>>,
) -> LaniusBuffer<u32> {
    let required_bytes = count.saturating_mul(core::mem::size_of::<u32>());
    if let Some(buffer) = reusable.filter(|buffer| buffer.byte_size >= required_bytes) {
        buffer.alias(count)
    } else {
        storage_rw_for_array::<u32>(device, label, count)
    }
}

/// Borrows one aligned, non-overlapping u32 workspace slot from a larger dead
/// allocation. Returns `None` when the requested slot does not fit.
pub(super) fn u32_workspace_subrange<T>(
    device: &wgpu::Device,
    source: &LaniusBuffer<T>,
    slot: usize,
    count: usize,
) -> Option<LaniusBuffer<u32>> {
    workspace_subrange(device, source, slot, count)
}

/// Borrows one aligned typed slot from a larger dead phase allocation.
pub(super) fn workspace_subrange<T, U>(
    device: &wgpu::Device,
    source: &LaniusBuffer<T>,
    slot: usize,
    count: usize,
) -> Option<LaniusBuffer<U>> {
    let byte_size = count.checked_mul(core::mem::size_of::<U>().max(1))? as u64;
    let alignment = u64::from(device.limits().min_storage_buffer_offset_alignment.max(1));
    let stride = byte_size.checked_add(alignment - 1)? / alignment * alignment;
    let offset = stride.checked_mul(slot as u64)?;
    source.subrange(offset, byte_size, count).ok()
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
    LaniusBuffer::new_labeled(
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
        label,
    )
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
