use crate::gpu::buffers::LaniusBuffer;

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
