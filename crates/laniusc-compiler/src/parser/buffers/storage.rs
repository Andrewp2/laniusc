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
