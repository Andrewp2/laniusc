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

/// One logical GPU-buffer range in a batched readback. The range retains the
/// arena-relative offset check performed by [`LaniusBuffer`] while erasing the
/// source element type so unrelated object columns can share one transfer.
#[derive(Clone, Copy)]
pub(crate) struct ReadbackRegion<'a> {
    source: &'a wgpu::Buffer,
    source_offset: u64,
    byte_len: usize,
}

impl<'a> ReadbackRegion<'a> {
    pub(crate) fn from_buffer<T>(
        source: &'a LaniusBuffer<T>,
        source_offset: u64,
        byte_len: usize,
        label: &str,
    ) -> Result<Self> {
        if source_offset % 4 != 0 {
            return Err(anyhow!(
                "{label} source offset {source_offset} is not four-byte aligned"
            ));
        }
        if source_offset.saturating_add(byte_len as u64) > source.byte_size as u64 {
            return Err(anyhow!("{label} exceeds its logical GPU buffer view"));
        }
        Ok(Self {
            source: &source.buffer,
            source_offset: source.absolute_offset(source_offset),
            byte_len,
        })
    }
}

impl PagedReadback {
    pub(crate) fn new(device: &wgpu::Device, label: &str, page_bytes: usize) -> Self {
        let page_bytes = page_bytes.max(4).next_multiple_of(4);
        Self {
            staging: readback_bytes(device, label, page_bytes, page_bytes),
        }
    }

    pub(crate) fn from_staging(staging: LaniusBuffer<u8>) -> Self {
        Self { staging }
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

    /// Reads bytes relative to a logical buffer view, preserving its arena
    /// offset and preventing a read from crossing into an adjacent occupant.
    pub(crate) fn read_buffer<T>(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        source: &LaniusBuffer<T>,
        source_offset: u64,
        byte_len: usize,
        label: &str,
    ) -> Result<Vec<u8>> {
        if source_offset.saturating_add(byte_len as u64) > source.byte_size as u64 {
            return Err(anyhow!("{label} exceeds its logical GPU buffer view"));
        }
        self.read(
            device,
            queue,
            &source.buffer,
            source.absolute_offset(source_offset),
            byte_len,
            label,
        )
    }

    /// Copies unrelated logical buffer ranges into the same reusable staging
    /// page and maps that page once. Large aggregate outputs still paginate,
    /// but small object columns no longer pay one queue synchronization per
    /// column.
    pub(crate) fn read_regions(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        regions: &[ReadbackRegion<'_>],
        label: &str,
    ) -> Result<Vec<Vec<u8>>> {
        let mut outputs = regions
            .iter()
            .map(|region| Vec::with_capacity(region.byte_len))
            .collect::<Vec<_>>();
        let mut consumed = vec![0usize; regions.len()];

        while regions
            .iter()
            .zip(&consumed)
            .any(|(region, consumed)| *consumed < region.byte_len)
        {
            let mut encoder = device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) });
            let mut page_cursor = 0usize;
            let mut page_copies = Vec::new();

            for (index, region) in regions.iter().enumerate() {
                while consumed[index] < region.byte_len && page_cursor < self.staging.byte_size {
                    let remaining = region.byte_len - consumed[index];
                    let page_remaining = self.staging.byte_size - page_cursor;
                    if page_remaining < 4 {
                        break;
                    }
                    let logical_len = remaining.min(page_remaining);
                    let copy_len = logical_len.next_multiple_of(4);
                    if copy_len > page_remaining {
                        break;
                    }
                    let source_offset = region.source_offset + consumed[index] as u64;
                    encoder.copy_buffer_to_buffer(
                        region.source,
                        source_offset,
                        &self.staging.buffer,
                        page_cursor as u64,
                        copy_len as u64,
                    );
                    page_copies.push((index, page_cursor, logical_len));
                    consumed[index] += logical_len;
                    page_cursor += copy_len;
                }
                if page_cursor == self.staging.byte_size {
                    break;
                }
            }

            if page_copies.is_empty() {
                return Err(anyhow!(
                    "{label} could not fit an aligned copy in its {}-byte staging page",
                    self.staging.byte_size
                ));
            }
            queue.submit(Some(encoder.finish()));

            let slice = self.staging.buffer.slice(..page_cursor as u64);
            map_readback_blocking(device, &slice, label)?;
            let mapped = slice.get_mapped_range();
            for (index, offset, logical_len) in page_copies {
                outputs[index].extend_from_slice(&mapped[offset..offset + logical_len]);
            }
            drop(mapped);
            self.staging.unmap();
        }

        Ok(outputs)
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
