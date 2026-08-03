//! GPU debugging utilities

use wgpu;

/// Host-side holder for a staged GPU buffer.
#[derive(Clone, Default)]
pub struct DebugBuffer {
    /// Label for the buffer
    pub label: &'static str,
    /// The underlying GPU buffer
    pub buffer: Option<wgpu::Buffer>,
    /// Size of the buffer in bytes
    pub byte_len: usize,
}

impl DebugBuffer {
    /// Allocates a staging buffer and records a copy from `src` into it.
    pub fn set_from_copy(
        &mut self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        src: &wgpu::Buffer,
        label: &'static str,
        size: usize,
    ) {
        let b = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(src, 0, &b, 0, size as u64);
        *self = DebugBuffer {
            label,
            buffer: Some(b),
            byte_len: size,
        };
    }
}
