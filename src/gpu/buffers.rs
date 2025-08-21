use std::ops::Deref;

use wgpu::util::DeviceExt;

/// A thin wrapper around `wgpu::Buffer` that also tracks element count and byte size.
/// Always create these via the helpers below so we respect WGSL/encase layout rules.
pub struct LaniusBuffer<T> {
    pub buffer: wgpu::Buffer,
    /// total allocated size in bytes
    pub byte_size: usize,
    /// number of logical T elements
    pub count: usize,
    _marker: std::marker::PhantomData<T>,
}

impl<T> LaniusBuffer<T> {
    pub fn new((buffer, byte_size): (wgpu::Buffer, u64), count: usize) -> Self {
        Self {
            buffer,
            byte_size: byte_size as usize,
            count,
            _marker: std::marker::PhantomData,
        }
    }
}

impl<T> Deref for LaniusBuffer<T> {
    type Target = wgpu::Buffer;
    fn deref(&self) -> &Self::Target {
        &self.buffer
    }
}

/// Create a UNIFORM buffer from a single ShaderType value (std140 layout in WGSL).
pub fn uniform_from_val<T>(device: &wgpu::Device, label: &str, value: &T) -> LaniusBuffer<T>
where
    T: encase::ShaderType + encase::internal::WriteInto,
{
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(value)
        .expect("failed to write value into UniformBuffer");
    let bytes = ub.as_ref();
    let raw = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: bytes,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
    });
    LaniusBuffer::new((raw, bytes.len() as u64), 1)
}

/// Create a STORAGE (read-only) buffer from a raw byte slice.
pub fn storage_ro_from_bytes<T>(
    device: &wgpu::Device,
    label: &str,
    bytes: &[u8],
    count: usize,
) -> LaniusBuffer<T> {
    let raw = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: bytes,
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_DST
            | wgpu::BufferUsages::COPY_SRC,
    });
    LaniusBuffer::new((raw, bytes.len() as u64), count)
}

/// Create a STORAGE (read-only) buffer from `&[u32]`.
pub fn storage_ro_from_u32s(
    device: &wgpu::Device,
    label: &str,
    values: &[u32],
) -> LaniusBuffer<u32> {
    let mut bytes = Vec::with_capacity(values.len() * 4);

    for &v in values {
        bytes.extend_from_slice(&v.to_le_bytes());
    }
    debug_assert_eq!(
        bytes.len(),
        values.len() * 4,
        "storage_ro_from_u32s({label}): packing mismatch"
    );
    storage_ro_from_bytes::<u32>(device, label, &bytes, values.len())
}

pub fn readback_bytes(
    device: &wgpu::Device,
    label: &str,
    byte_size: usize,
    count: usize,
) -> LaniusBuffer<u8> {
    let raw = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_size as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    LaniusBuffer::new((raw, byte_size as u64), count)
}

/// Create a STORAGE buffer (read/write) sized for an array of `T` using WGSL/std430 size/stride.
/// We compute the **padded element size** by encoding one `T::default()` with `encase::StorageBuffer`.
/// Requires `T: Default` so we can synthesize one element just to measure its layout.
pub fn storage_rw_for_array<T>(device: &wgpu::Device, label: &str, count: usize) -> LaniusBuffer<T>
where
    T: Default + encase::ShaderType + encase::internal::WriteInto,
{
    let mut sb = encase::StorageBuffer::new(Vec::<u8>::new());
    sb.write(&T::default())
        .expect("failed to write default element into StorageBuffer");
    let elem_padded_bytes = sb.as_ref().len(); // encase gives us the correct std430-padded size
    debug_assert!(
        elem_padded_bytes > 0,
        "encase reported zero-sized element for {label}"
    );
    let total = elem_padded_bytes
        .checked_mul(count)
        .expect("overflow sizing storage buffer");
    let raw = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: total as u64,
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_SRC
            | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    LaniusBuffer::new((raw, total as u64), count)
}

/// Create a STORAGE buffer (read/write) with an explicit byte size. Element type is `u8`.
/// Handy for generic scratch space when the shader side uses `array<u32>`/`array<u8>`.
pub fn storage_rw_uninit_bytes(
    device: &wgpu::Device,
    label: &str,
    byte_size: usize,
    count: usize,
) -> LaniusBuffer<u8> {
    let raw = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_size as u64,
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_SRC
            | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    });
    LaniusBuffer::new((raw, byte_size as u64), count)
}
