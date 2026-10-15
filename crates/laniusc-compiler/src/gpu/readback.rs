use anyhow::{Result, anyhow};

mod gather;

use super::{
    buffers::{LaniusBuffer, readback_bytes},
    passes_core::map_readback_blocking,
};

/// Reusable bounded staging for host output whose live length is known only
/// after GPU execution. Large logical outputs are copied and mapped in pages;
/// daemon residency therefore depends on the page size, not worst-case output.
pub(crate) struct PagedReadback {
    staging: LaniusBuffer<u8>,
    #[cfg(test)]
    map_wait_override: Option<ReadbackMapWait>,
}

#[cfg(test)]
type ReadbackMapWait = fn(&wgpu::Device, &wgpu::BufferSlice<'_>, &str) -> Result<()>;

/// Owns the map attempt, including the period before its callback completes.
/// Declare mapped views after this guard so they drop before unmapping on unwind.
struct ReadbackMapping<'a> {
    device: &'a wgpu::Device,
    buffer: &'a wgpu::Buffer,
    completed: bool,
}

impl Drop for ReadbackMapping<'_> {
    fn drop(&mut self) {
        if self.completed {
            self.buffer.unmap();
        } else {
            // unmap cancels a pending map and resets wgpu's host map context.
            // A failed callback may already have reset the backend to Idle;
            // wgpu then reports NotMapped. Suppress only cleanup validation so
            // it cannot replace the original map error or panic during unwind.
            let _cleanup_scope = self.device.push_error_scope(wgpu::ErrorFilter::Validation);
            self.buffer.unmap();
        }
    }
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
            #[cfg(test)]
            map_wait_override: None,
        }
    }

    pub(crate) fn from_staging(staging: LaniusBuffer<u8>) -> Self {
        Self {
            staging,
            #[cfg(test)]
            map_wait_override: None,
        }
    }

    fn map_staging<'a>(
        &'a self,
        device: &'a wgpu::Device,
        slice: &wgpu::BufferSlice<'_>,
        label: &str,
    ) -> Result<ReadbackMapping<'a>> {
        let mut mapping = ReadbackMapping {
            device,
            buffer: &self.staging.buffer,
            completed: false,
        };
        #[cfg(test)]
        let wait = self.map_wait_override.unwrap_or(map_readback_blocking);
        #[cfg(not(test))]
        let wait = map_readback_blocking;
        wait(device, slice, label)?;
        mapping.completed = true;
        Ok(mapping)
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
            let mapping = self.map_staging(device, &slice, label)?;
            let mapped = slice.get_mapped_range();
            output.extend_from_slice(&mapped[..logical_len]);
            drop(mapped);
            drop(mapping);
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
    /// column. Many small regions are first gathered on the GPU into one
    /// dense image (see [`gather`]), and ranges that are contiguous in both
    /// source and page share one copy.
    pub(crate) fn read_regions(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        regions: &[ReadbackRegion<'_>],
        label: &str,
    ) -> Result<Vec<Vec<u8>>> {
        // Sparse fact readers pass thousands of regions; report where their
        // time goes (copy encoding vs. the GPU round trip).
        let timing = regions.len() >= 32
            && crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false);
        let started = std::time::Instant::now();
        let mut pages = 0usize;
        let mut copies = 0usize;
        let mut encode = std::time::Duration::ZERO;

        let mut first_encoder = Some(
            device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) }),
        );
        let mut lease = gather::lease(device, regions.len());
        let gathered = match lease.as_mut() {
            Some(lease) => lease.record(
                device,
                queue,
                first_encoder.as_mut().expect("first readback encoder"),
                regions,
                label,
            )?,
            None => None,
        };
        let (gathered_regions, gather_dispatches) = gathered
            .as_ref()
            .map_or((0, 0), |gathered| (gathered.gathered_regions, gathered.dispatches));
        let regions = gathered.as_ref().map_or(regions, |gathered| &gathered.regions[..]);
        encode += started.elapsed();

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
            let page_started = std::time::Instant::now();
            let mut encoder = first_encoder.take().unwrap_or_else(|| {
                device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) })
            });
            let mut page_cursor = 0usize;
            let mut page_copies = Vec::new();
            // The copy being extended: source, source offset, page offset, length.
            let mut pending: Option<(&wgpu::Buffer, u64, u64, u64)> = None;

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
                    match &mut pending {
                        Some((source, source_start, page_start, len))
                            if *source == region.source
                                && *source_start + *len == source_offset
                                && *page_start + *len == page_cursor as u64 =>
                        {
                            *len += copy_len as u64;
                        }
                        _ => {
                            if let Some((source, source_start, page_start, len)) = pending.take() {
                                encoder.copy_buffer_to_buffer(
                                    source,
                                    source_start,
                                    &self.staging.buffer,
                                    page_start,
                                    len,
                                );
                                copies += 1;
                            }
                            pending =
                                Some((region.source, source_offset, page_cursor as u64, copy_len as u64));
                        }
                    }
                    page_copies.push((index, page_cursor, logical_len));
                    consumed[index] += logical_len;
                    page_cursor += copy_len;
                }
                if page_cursor == self.staging.byte_size {
                    break;
                }
            }

            if let Some((source, source_start, page_start, len)) = pending.take() {
                encoder.copy_buffer_to_buffer(
                    source,
                    source_start,
                    &self.staging.buffer,
                    page_start,
                    len,
                );
                copies += 1;
            }
            if page_copies.is_empty() {
                return Err(anyhow!(
                    "{label} could not fit an aligned copy in its {}-byte staging page",
                    self.staging.byte_size
                ));
            }
            let command_buffer = encoder.finish();
            encode += page_started.elapsed();
            pages += 1;
            queue.submit(Some(command_buffer));

            let slice = self.staging.buffer.slice(..page_cursor as u64);
            let mapping = self.map_staging(device, &slice, label)?;
            let mapped = slice.get_mapped_range();
            for (index, offset, logical_len) in page_copies {
                outputs[index].extend_from_slice(&mapped[offset..offset + logical_len]);
            }
            drop(mapped);
            drop(mapping);
        }
        if timing {
            let total = started.elapsed();
            eprintln!(
                "[gpu_compile_host_timer] readback.regions: label={label} regions={} gathered={gathered_regions} gather_dispatches={gather_dispatches} copies={copies} bytes={} pages={pages} encode_ms={:.3} total_ms={:.3}",
                regions.len(),
                regions.iter().map(|region| region.byte_len).sum::<usize>(),
                encode.as_secs_f64() * 1000.0,
                total.as_secs_f64() * 1000.0,
            );
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

#[cfg(test)]
mod lifecycle_tests {
    use super::*;
    use crate::gpu::device;

    fn source(device: &wgpu::Device) -> LaniusBuffer<u8> {
        let buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("readback lifecycle source"),
            size: 16,
            usage: wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        LaniusBuffer::new_labeled((buffer, 16), 16, "readback lifecycle source")
    }

    fn fail_pending_map(
        _device: &wgpu::Device,
        slice: &wgpu::BufferSlice<'_>,
        _label: &str,
    ) -> Result<()> {
        // Start a real map, then simulate a poll/timeout error without polling.
        slice.map_async(wgpu::MapMode::Read, |_| {});
        Err(anyhow!("injected pending-map failure"))
    }

    fn fail_already_cancelled_map(
        device: &wgpu::Device,
        slice: &wgpu::BufferSlice<'_>,
        label: &str,
    ) -> Result<()> {
        // Model a failed callback that has already restored backend Idle.
        let _ = fail_pending_map(device, slice, label);
        slice.buffer().unmap();
        Err(anyhow!("injected completed-map failure"))
    }

    #[test]
    fn gpu_paged_readback_cancels_failed_maps_before_staging_reuse() {
        let gpu = device::global();
        let source = source(&gpu.device);
        let mut readback = PagedReadback::new(&gpu.device, "readback lifecycle page", 8);
        let staging_id = readback.staging.allocation_id();
        let validation = gpu.device.push_error_scope(wgpu::ErrorFilter::Validation);
        let waiters: [ReadbackMapWait; 2] = [fail_pending_map, fail_already_cancelled_map];
        for (iteration, wait) in waiters.into_iter().enumerate() {
            let old_bytes = [iteration as u8; 16];
            let new_bytes = [iteration as u8 + 17; 16];
            source.write(&gpu.queue, 0, &old_bytes);
            readback.map_wait_override = Some(wait);
            let error = readback
                .read(
                    &gpu.device,
                    &gpu.queue,
                    &source.buffer,
                    0,
                    16,
                    "injected read",
                )
                .expect_err("map fault must fail the read");
            assert!(error.to_string().starts_with("injected "));

            readback.map_wait_override = None;
            source.write(&gpu.queue, 0, &new_bytes);
            assert_eq!(
                readback
                    .read_buffer(&gpu.device, &gpu.queue, &source, 0, 16, "read retry")
                    .unwrap(),
                new_bytes,
                "both pages must be copied again after the failed map"
            );

            let regions = [
                ReadbackRegion::from_buffer(&source, 0, 4, "first region").unwrap(),
                ReadbackRegion::from_buffer(&source, 4, 12, "second region").unwrap(),
            ];
            readback.map_wait_override = Some(wait);
            let error = readback
                .read_regions(&gpu.device, &gpu.queue, &regions, "injected regions")
                .expect_err("map fault must fail the batched read");
            assert!(error.to_string().starts_with("injected "));
            readback.map_wait_override = None;
            source.write(&gpu.queue, 0, &old_bytes);
            assert_eq!(
                readback
                    .read_regions(&gpu.device, &gpu.queue, &regions, "regions retry")
                    .unwrap(),
                vec![old_bytes[..4].to_vec(), old_bytes[4..].to_vec()]
            );
            assert_eq!(readback.staging.allocation_id(), staging_id);
        }
        assert!(pollster::block_on(validation.pop()).is_none());
    }

    #[test]
    fn gpu_paged_readback_unmaps_after_host_copy_unwinds() {
        let gpu = device::global();
        let source = source(&gpu.device);
        let readback = PagedReadback::new(&gpu.device, "readback unwind page", 8);
        let validation = gpu.device.push_error_scope(wgpu::ErrorFilter::Validation);
        let unwind = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            let slice = readback.staging.buffer.slice(..8);
            let _mapping = readback
                .map_staging(&gpu.device, &slice, "unwind map")
                .unwrap();
            let _mapped = slice.get_mapped_range();
            panic!("injected host-copy panic");
        }));
        assert!(unwind.is_err());
        let expected = [31u8; 16];
        source.write(&gpu.queue, 0, &expected);
        assert_eq!(
            readback
                .read_buffer(&gpu.device, &gpu.queue, &source, 0, 16, "unwind retry")
                .unwrap(),
            expected
        );
        assert!(pollster::block_on(validation.pop()).is_none());
    }

    fn storage_source(device: &wgpu::Device, queue: &wgpu::Queue, seed: u8) -> LaniusBuffer<u8> {
        let size = 8192usize;
        let buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("readback gather source"),
            size: size as u64,
            usage: wgpu::BufferUsages::STORAGE
                | wgpu::BufferUsages::COPY_SRC
                | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let source = LaniusBuffer::new_labeled((buffer, size as u64), size, "readback gather source");
        let bytes = (0..size)
            .map(|i| (i as u8).wrapping_mul(31).wrapping_add(seed))
            .collect::<Vec<_>>();
        source.write(queue, 0, &bytes);
        source
    }

    #[test]
    fn gpu_paged_readback_gathers_many_small_regions() {
        let gpu = device::global();
        let first = storage_source(&gpu.device, &gpu.queue, 7);
        let second = storage_source(&gpu.device, &gpu.queue, 101);
        // A copy-only source (no STORAGE usage) must still read correctly.
        let copy_only = source(&gpu.device);
        copy_only.write(&gpu.queue, 0, &[9u8; 16]);
        // A small page forces the gathered image across several pages.
        let readback = PagedReadback::new(&gpu.device, "readback gather page", 512);
        let validation = gpu.device.push_error_scope(wgpu::ErrorFilter::Validation);

        let mut regions = Vec::new();
        let mut expected = Vec::new();
        for i in 0..300u64 {
            let (buffer, seed) = if i % 3 == 0 { (&second, 101u8) } else { (&first, 7u8) };
            let offset = (i * 52) % 7936 / 4 * 4;
            let len = [4usize, 3, 8, 12, 1, 40][i as usize % 6];
            regions.push(ReadbackRegion::from_buffer(buffer, offset, len, "gather region").unwrap());
            expected.push(
                (offset as usize..offset as usize + len)
                    .map(|b| (b as u8).wrapping_mul(31).wrapping_add(seed))
                    .collect::<Vec<_>>(),
            );
            if i == 150 {
                // A large region and a copy-only region in the middle.
                regions.push(ReadbackRegion::from_buffer(&first, 1024, 1500, "large region").unwrap());
                expected.push(
                    (1024..2524usize)
                        .map(|b| (b as u8).wrapping_mul(31).wrapping_add(7))
                        .collect(),
                );
                regions.push(ReadbackRegion::from_buffer(&copy_only, 4, 8, "copy region").unwrap());
                expected.push(vec![9u8; 8]);
            }
        }
        let read = readback
            .read_regions(&gpu.device, &gpu.queue, &regions, "gather test")
            .unwrap();
        assert_eq!(read, expected);
        assert!(pollster::block_on(validation.pop()).is_none());
    }
}
