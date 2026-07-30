use anyhow::{Result, anyhow};

use super::{
    buffers::{LaniusBuffer, readback_bytes},
    passes_core::map_readback_blocking,
};

/// Reusable bounded staging for host output whose live length is known only
/// after GPU execution. Large logical outputs are copied and mapped in pages;
/// daemon residency therefore depends on the page size, not worst-case output.
pub(crate) struct PagedReadback {
    staging: LaniusBuffer<u8>,
}

impl PagedReadback {
    pub(crate) fn new(device: &wgpu::Device, label: &str, page_bytes: usize) -> Self {
        let page_bytes = page_bytes.max(4).next_multiple_of(4);
        Self {
            staging: readback_bytes(device, label, page_bytes, page_bytes),
        }
    }

    pub(crate) fn read(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        source: &wgpu::Buffer,
        source_offset: u64,
        byte_len: usize,
        label: &str,
    ) -> Result<Vec<u8>> {
        if source_offset % 4 != 0 {
            return Err(anyhow!(
                "{label} source offset {source_offset} is not four-byte aligned"
            ));
        }
        let mut output = Vec::with_capacity(byte_len);
        while output.len() < byte_len {
            let logical_len = (byte_len - output.len()).min(self.staging.byte_size);
            let copy_len = logical_len.next_multiple_of(4);
            let offset = source_offset + output.len() as u64;
            let mut encoder = device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) });
            encoder.copy_buffer_to_buffer(source, offset, &self.staging.buffer, 0, copy_len as u64);
            queue.submit(Some(encoder.finish()));

            let slice = self.staging.buffer.slice(..copy_len as u64);
            map_readback_blocking(device, &slice, label)?;
            let mapped = slice.get_mapped_range();
            output.extend_from_slice(&mapped[..logical_len]);
            drop(mapped);
            self.staging.unmap();
        }
        Ok(output)
    }
}

/// Decodes exactly `N` little-endian `u32` words from readback bytes.
pub fn read_u32_words<const N: usize>(bytes: &[u8], context: &str) -> Result<[u32; N]> {
    let expected = N * 4;
    if bytes.len() < expected {
        return Err(anyhow!(
            "{context} readback was truncated: expected at least {expected} bytes, got {}",
            bytes.len()
        ));
    }

    let mut out = [0u32; N];
    for (i, word) in out.iter_mut().enumerate() {
        let start = i * 4;
        *word = u32::from_le_bytes(bytes[start..start + 4].try_into()?);
    }
    Ok(out)
}

/// Decodes exactly `N` little-endian `i32` words from readback bytes.
pub fn read_i32_words<const N: usize>(bytes: &[u8], context: &str) -> Result<[i32; N]> {
    let expected = N * 4;
    if bytes.len() < expected {
        return Err(anyhow!(
            "{context} readback was truncated: expected at least {expected} bytes, got {}",
            bytes.len()
        ));
    }

    let mut out = [0i32; N];
    for (i, word) in out.iter_mut().enumerate() {
        let start = i * 4;
        *word = i32::from_le_bytes(bytes[start..start + 4].try_into()?);
    }
    Ok(out)
}
