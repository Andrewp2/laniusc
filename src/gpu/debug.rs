//! GPU debugging utilities

#![allow(dead_code)]

use wgpu;

/// CPU-side holder for a staged GPU buffer.
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
    /// Returns true if the buffer is present
    pub fn is_some(&self) -> bool {
        self.buffer.is_some()
    }

    /// Reads the buffer contents as raw bytes
    pub fn read_bytes(&self) -> Option<Vec<u8>> {
        let buf = self.buffer.as_ref()?;
        let view = buf.slice(..).get_mapped_range();
        Some(view.to_vec())
    }

    /// Reads the buffer contents as a vector of u32 values
    pub fn read_u32s(&self) -> Option<Vec<u32>> {
        self.read_bytes().map(|v| {
            let mut out = Vec::with_capacity(v.len() / 4);
            for chunk in v.chunks_exact(4) {
                out.push(u32::from_le_bytes(
                    chunk.try_into().expect("chunk size mismatch"),
                ));
            }
            out
        })
    }

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
