use anyhow::{Result, anyhow};

mod gather;
mod plan;

pub(crate) use plan::{PlanBuffers, ReadPlan, ReplayStats};

use super::{
    buffers::{LaniusBuffer, readback_bytes},
    passes_core::map_readback_blocking,
};

/// Reusable bounded staging for host output whose live length is known only
/// after GPU execution. Large logical outputs are copied and mapped in pages;
/// daemon residency therefore depends on the page size, not worst-case output.
pub(crate) struct PagedReadback {
    staging: LaniusBuffer<u8>,
    /// The read plan replay of one decoder run, if one is running.
    replay: std::sync::Mutex<Option<plan::PlanReplay>>,
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
    /// The source's allocation identity, which a read plan keys on.
    allocation: Option<u64>,
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
            allocation: source.allocation_id(),
        })
    }

    pub(crate) fn byte_len(&self) -> usize {
        self.byte_len
    }
}

/// One column of [`ReadbackRows`]: the first `width_words` words of each row
/// of a table of `stride_words`-word rows whose row 0 starts at the absolute
/// byte `base`.
#[derive(Clone, Copy)]
pub(crate) struct ReadbackRowsColumn<'a> {
    source: &'a wgpu::Buffer,
    base: u64,
    stride_words: usize,
    width_words: usize,
    allocation: Option<u64>,
}

impl ReadbackRowsColumn<'_> {
    /// The absolute byte offset of row `index`.
    fn row_offset(&self, index: u32) -> u64 {
        self.base + u64::from(index) * self.stride_words as u64 * 4
    }
}

/// The same rows of one or more tables: for each index in order, each
/// column's words in column order. A word readback gathers them with one
/// record per row and column instead of one region each.
#[derive(Clone)]
pub(crate) struct ReadbackRows<'a> {
    indices: Vec<u32>,
    max_index: Option<u32>,
    columns: Vec<ReadbackRowsColumn<'a>>,
}

impl<'a> ReadbackRows<'a> {
    pub(crate) fn new(indices: &[u32]) -> Self {
        Self {
            indices: indices.to_vec(),
            max_index: indices.iter().copied().max(),
            columns: Vec::new(),
        }
    }

    /// Adds a column: the first `width_words` words of each row of a table
    /// of `stride_words`-word rows that starts at word `first_word` of
    /// `source`'s view. Every row must lie inside the view.
    pub(crate) fn column<T>(
        mut self,
        source: &'a LaniusBuffer<T>,
        first_word: u64,
        stride_words: usize,
        width_words: usize,
        label: &str,
    ) -> Result<Self> {
        if let Some(max) = self.max_index {
            let end = (u64::from(max) * stride_words as u64)
                .checked_add(first_word + width_words as u64)
                .and_then(|words| words.checked_mul(4));
            if end.is_none_or(|end| end > source.byte_size as u64) {
                return Err(anyhow!("{label} exceeds its logical GPU buffer view"));
            }
        }
        let base = source.absolute_offset(first_word * 4);
        if base % 4 != 0 {
            return Err(anyhow!("{label} rows are not four-byte aligned"));
        }
        self.columns.push(ReadbackRowsColumn {
            source: &source.buffer,
            base,
            stride_words,
            width_words,
            allocation: source.allocation_id(),
        });
        Ok(self)
    }

    /// The words these rows read.
    pub(crate) fn words(&self) -> usize {
        self.indices.len() * self.columns.iter().map(|column| column.width_words).sum::<usize>()
    }

    /// The rows and their columns, as (buffer, absolute byte offset, bytes)
    /// in read order.
    pub(crate) fn pieces(&self) -> impl Iterator<Item = (&'a wgpu::Buffer, u64, usize)> + '_ {
        self.indices.iter().flat_map(|&index| {
            self.columns.iter().map(move |column| {
                (column.source, column.row_offset(index), column.width_words * 4)
            })
        })
    }
}

/// One part of a word readback ([`PagedReadback::read_words`]).
#[derive(Clone)]
pub(crate) enum WordRead<'a> {
    Region(ReadbackRegion<'a>),
    Rows(ReadbackRows<'a>),
}

impl WordRead<'_> {
    /// The words this part reads; a region must be whole words.
    pub(crate) fn words(&self) -> usize {
        match self {
            WordRead::Region(region) => region.byte_len / 4,
            WordRead::Rows(rows) => rows.words(),
        }
    }

    /// Regions or rows: what a gather counts.
    fn regions(&self) -> usize {
        match self {
            WordRead::Region(_) => 1,
            WordRead::Rows(rows) => rows.indices.len() * rows.columns.len(),
        }
    }
}

impl PagedReadback {
    pub(crate) fn new(device: &wgpu::Device, label: &str, page_bytes: usize) -> Self {
        let page_bytes = page_bytes.max(4).next_multiple_of(4);
        Self {
            staging: readback_bytes(device, label, page_bytes, page_bytes),
            replay: std::sync::Mutex::new(None),
            #[cfg(test)]
            map_wait_override: None,
        }
    }

    pub(crate) fn from_staging(staging: LaniusBuffer<u8>) -> Self {
        Self {
            staging,
            replay: std::sync::Mutex::new(None),
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
        let mut outputs = regions
            .iter()
            .map(|region| Vec::with_capacity(region.byte_len))
            .collect::<Vec<_>>();
        self.read_regions_with(device, queue, regions, label, |index, _, bytes| {
            outputs[index].extend_from_slice(bytes)
        })?;
        Ok(outputs)
    }

    /// [`Self::read_regions`] for regions of whole words, returned as one
    /// vector in which each region's words follow the previous region's.
    /// Readers of thousands of rows slice it instead of decoding a vector per
    /// region; [`Self::read_words`] also takes rows.
    pub(crate) fn read_regions_words(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        regions: &[ReadbackRegion<'_>],
        label: &str,
    ) -> Result<Vec<u32>> {
        let reads = regions.iter().copied().map(WordRead::Region).collect::<Vec<_>>();
        self.read_words(device, queue, &reads, label)
    }

    /// Reads `reads` in one round trip as one vector in which each read's
    /// words follow the previous read's. Small regions and rows are first
    /// gathered on the GPU into one dense image (see [`gather`]), so a set of
    /// thousands of rows costs one record per row, and the copies that
    /// continue each other in their source (the whole image, usually) are
    /// one copy.
    ///
    /// While a read plan replay runs ([`Self::begin_read_plan`]), a read the
    /// plan's fetch holds is answered from it without a round trip.
    pub(crate) fn read_words(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        reads: &[WordRead<'_>],
        label: &str,
    ) -> Result<Vec<u32>> {
        let mut replay = self.replay.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
        match replay.as_mut() {
            Some(replay) => {
                replay.read(reads, |reads| self.read_words_now(device, queue, reads, label))
            }
            None => self.read_words_now(device, queue, reads, label),
        }
    }

    /// Starts a read plan replay ([`plan`]): the next word read that is not
    /// answered also fetches every read of `plan` whose buffers are in
    /// `buffers`, and later reads are answered from that fetch. Only a
    /// decoder whose planned buffers no GPU work writes until
    /// [`Self::finish_read_plan`] may replay a plan.
    pub(crate) fn begin_read_plan(&self, buffers: PlanBuffers, plan: Option<ReadPlan>) {
        *self.replay.lock().unwrap_or_else(std::sync::PoisonError::into_inner) =
            Some(plan::PlanReplay::new(buffers, plan));
    }

    /// Ends the replay; returns the word reads made since it began, which are
    /// the next run's plan, and what the replay did.
    pub(crate) fn finish_read_plan(&self) -> Option<(ReadPlan, ReplayStats)> {
        self.replay
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take()
            .map(plan::PlanReplay::finish)
    }

    fn read_words_now(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        reads: &[WordRead<'_>],
        label: &str,
    ) -> Result<Vec<u32>> {
        let mut total = 0usize;
        for read in reads {
            if let WordRead::Region(region) = read
                && region.byte_len % 4 != 0
            {
                return Err(anyhow!(
                    "{label} region of {} bytes is not a whole number of words",
                    region.byte_len
                ));
            }
            total += read.words();
        }
        if total == 0 {
            return Ok(Vec::new());
        }
        let regions = reads.iter().map(WordRead::regions).sum::<usize>();
        let timing = regions >= 32
            && crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false);
        let started = std::time::Instant::now();
        let mut first_encoder =
            device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) });
        let mut lease = gather::lease(device, regions);
        let gathered = match lease.as_mut() {
            Some(lease) => lease.record_words(device, queue, &mut first_encoder, reads, label)?,
            None => None,
        };

        // The copies in output order, each with its first output word. A
        // copy that continues the previous one in its source extends it.
        let mut pieces = Pieces::default();
        let mut word = 0usize;
        for (index, read) in reads.iter().enumerate() {
            let image = gathered.as_ref().and_then(|gathered| {
                gathered.image_starts[index].map(|image| (gathered.output, image))
            });
            match (image, read) {
                (Some((output, image)), _) => {
                    pieces.push(output, u64::from(image) * 4, read.words() * 4, word)
                }
                (None, WordRead::Region(region)) => {
                    pieces.push(region.source, region.source_offset, region.byte_len, word)
                }
                (None, WordRead::Rows(rows)) => {
                    let mut row_word = word;
                    for (source, offset, byte_len) in rows.pieces() {
                        pieces.push(source, offset, byte_len, row_word);
                        row_word += byte_len / 4;
                    }
                }
            }
            word += read.words();
        }
        let Pieces {
            regions: pieces,
            words: piece_words,
        } = pieces;
        let encode = started.elapsed();

        let mut words = vec![0u32; total];
        let stats = self.copy_regions(device, queue, first_encoder, &pieces, label, |index, offset, bytes| {
            let start = piece_words[index] + offset / 4;
            for (word, bytes) in words[start..start + bytes.len() / 4]
                .iter_mut()
                .zip(bytes.chunks_exact(4))
            {
                *word = u32::from_le_bytes(bytes.try_into().expect("four-byte chunk"));
            }
        })?;
        if timing {
            let (gathered_regions, dispatches) = gathered
                .as_ref()
                .map_or((0, 0), |gathered| (gathered.gathered_regions, gathered.dispatches));
            eprintln!(
                "[gpu_compile_host_timer] readback.words: label={label} reads={} regions={} gathered={gathered_regions} gather_dispatches={dispatches} pieces={} copies={} bytes={} pages={} encode_ms={:.3} total_ms={:.3}",
                reads.len(),
                regions,
                pieces.len(),
                stats.copies,
                total * 4,
                stats.pages,
                (encode + stats.encode).as_secs_f64() * 1000.0,
                started.elapsed().as_secs_f64() * 1000.0,
            );
        }
        Ok(words)
    }

    /// The batched copy behind [`Self::read_regions`]: hands `sink` each
    /// mapped piece of a region as (region index, byte offset in the region,
    /// bytes), in order within a region. A piece of a whole-word region is
    /// whole words.
    fn read_regions_with(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        regions: &[ReadbackRegion<'_>],
        label: &str,
        sink: impl FnMut(usize, usize, &[u8]),
    ) -> Result<()> {
        // Sparse fact readers pass thousands of regions; report where their
        // time goes (copy encoding vs. the GPU round trip).
        let timing = regions.len() >= 32
            && crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false);
        let started = std::time::Instant::now();

        let mut first_encoder =
            device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) });
        let mut lease = gather::lease(device, regions.len());
        let gathered = match lease.as_mut() {
            Some(lease) => lease.record(device, queue, &mut first_encoder, regions, label)?,
            None => None,
        };
        let (gathered_regions, gather_dispatches) = gathered
            .as_ref()
            .map_or((0, 0), |gathered| (gathered.gathered_regions, gathered.dispatches));
        let regions = gathered.as_ref().map_or(regions, |gathered| &gathered.regions[..]);
        let encode = started.elapsed();
        let stats = self.copy_regions(device, queue, first_encoder, regions, label, sink)?;
        if timing {
            let total = started.elapsed();
            eprintln!(
                "[gpu_compile_host_timer] readback.regions: label={label} regions={} gathered={gathered_regions} gather_dispatches={gather_dispatches} copies={} bytes={} pages={} encode_ms={:.3} total_ms={:.3}",
                regions.len(),
                stats.copies,
                regions.iter().map(|region| region.byte_len).sum::<usize>(),
                stats.pages,
                (encode + stats.encode).as_secs_f64() * 1000.0,
                total.as_secs_f64() * 1000.0,
            );
        }
        Ok(())
    }

    /// Copies `regions` through the staging page, one round trip per page,
    /// recording the first page's copies into `first_encoder`. Ranges that
    /// are contiguous in both source and page share one copy.
    fn copy_regions(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        first_encoder: wgpu::CommandEncoder,
        regions: &[ReadbackRegion<'_>],
        label: &str,
        mut sink: impl FnMut(usize, usize, &[u8]),
    ) -> Result<CopyStats> {
        let mut stats = CopyStats::default();
        let mut first_encoder = Some(first_encoder);
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
                                stats.copies += 1;
                            }
                            pending =
                                Some((region.source, source_offset, page_cursor as u64, copy_len as u64));
                        }
                    }
                    page_copies.push((index, consumed[index], page_cursor, logical_len));
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
                stats.copies += 1;
            }
            if page_copies.is_empty() {
                return Err(anyhow!(
                    "{label} could not fit an aligned copy in its {}-byte staging page",
                    self.staging.byte_size
                ));
            }
            let command_buffer = encoder.finish();
            stats.encode += page_started.elapsed();
            stats.pages += 1;
            queue.submit(Some(command_buffer));

            let slice = self.staging.buffer.slice(..page_cursor as u64);
            let mapping = self.map_staging(device, &slice, label)?;
            let mapped = slice.get_mapped_range();
            for (index, region_offset, offset, logical_len) in page_copies {
                sink(index, region_offset, &mapped[offset..offset + logical_len]);
            }
            drop(mapped);
            drop(mapping);
        }
        Ok(stats)
    }
}

/// The copies of a word readback in output order, each with its first
/// output word.
#[derive(Default)]
struct Pieces<'a> {
    regions: Vec<ReadbackRegion<'a>>,
    words: Vec<usize>,
}

impl<'a> Pieces<'a> {
    /// Adds a copy of whole words; one that continues the previous copy in
    /// its source extends it.
    fn push(&mut self, source: &'a wgpu::Buffer, offset: u64, byte_len: usize, word: usize) {
        if byte_len == 0 {
            return;
        }
        if let Some(last) = self.regions.last_mut()
            && last.source == source
            && last.source_offset + last.byte_len as u64 == offset
        {
            last.byte_len += byte_len;
            return;
        }
        self.regions.push(ReadbackRegion {
            source,
            source_offset: offset,
            byte_len,
            allocation: None,
        });
        self.words.push(word);
    }
}

/// What [`PagedReadback::copy_regions`] recorded.
#[derive(Default)]
struct CopyStats {
    pages: usize,
    copies: usize,
    encode: std::time::Duration,
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

        // Other regions of the same sources reuse the gather's bind groups;
        // their pair ranges must still come out right.
        let mut regions = Vec::new();
        let mut expected = Vec::new();
        for i in 0..150u64 {
            let (buffer, seed) = if i % 2 == 0 { (&first, 7u8) } else { (&second, 101u8) };
            let offset = (i * 76 + 8) % 8000 / 4 * 4;
            let len = [8usize, 4, 2, 16][i as usize % 4];
            regions.push(ReadbackRegion::from_buffer(buffer, offset, len, "gather region").unwrap());
            expected.push(
                (offset as usize..offset as usize + len)
                    .map(|b| (b as u8).wrapping_mul(31).wrapping_add(seed))
                    .collect::<Vec<_>>(),
            );
        }
        let read = readback
            .read_regions(&gpu.device, &gpu.queue, &regions, "gather test again")
            .unwrap();
        assert_eq!(read, expected);
        assert!(pollster::block_on(validation.pop()).is_none());
    }

    #[test]
    fn gpu_paged_readback_reads_word_regions_as_one_vector() {
        let gpu = device::global();
        let first = storage_source(&gpu.device, &gpu.queue, 3);
        let second = storage_source(&gpu.device, &gpu.queue, 59);
        // A small page splits gathered and large regions across pages.
        let readback = PagedReadback::new(&gpu.device, "readback words page", 256);
        let validation = gpu.device.push_error_scope(wgpu::ErrorFilter::Validation);
        let mut regions = Vec::new();
        for i in 0..200u64 {
            let buffer = if i % 3 == 0 { &second } else { &first };
            // The 8192-byte source holds the largest region at any offset.
            let offset = (i * 44) % 7500 / 4 * 4;
            let len = [4usize, 8, 32, 0, 12, 600][i as usize % 6];
            regions.push(ReadbackRegion::from_buffer(buffer, offset, len, "word region").unwrap());
        }
        let expected = readback
            .read_regions(&gpu.device, &gpu.queue, &regions, "word regions as bytes")
            .unwrap()
            .concat()
            .chunks_exact(4)
            .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
            .collect::<Vec<_>>();
        let words = readback
            .read_regions_words(&gpu.device, &gpu.queue, &regions, "word regions")
            .unwrap();
        assert_eq!(words, expected);
        regions.push(ReadbackRegion::from_buffer(&first, 0, 6, "partial word").unwrap());
        assert!(
            readback
                .read_regions_words(&gpu.device, &gpu.queue, &regions, "partial word")
                .is_err()
        );
        assert!(pollster::block_on(validation.pop()).is_none());
    }

    /// Rows read through `read_words` match the same rows read as one region
    /// each: gathered single- and multi-column rows, rows of a copy-only
    /// buffer (copied row by row), and regions between them.
    #[test]
    fn gpu_paged_readback_reads_rows_like_their_regions() {
        let gpu = device::global();
        let first = storage_source(&gpu.device, &gpu.queue, 11);
        let second = storage_source(&gpu.device, &gpu.queue, 77);
        let copy_only = source(&gpu.device);
        copy_only.write(&gpu.queue, 0, &(0..16u8).collect::<Vec<_>>());
        // A small page splits the image and the direct copies across pages.
        let readback = PagedReadback::new(&gpu.device, "readback rows page", 512);
        let validation = gpu.device.push_error_scope(wgpu::ErrorFilter::Validation);

        let indices = (0..150u32).map(|i| (i * 37) % 160).collect::<Vec<_>>();
        let few = [3u32, 0, 2, 2, 1];
        let reads = vec![
            WordRead::Rows(
                ReadbackRows::new(&indices).column(&first, 2, 12, 3, "one column").unwrap(),
            ),
            WordRead::Region(ReadbackRegion::from_buffer(&second, 40, 24, "region").unwrap()),
            WordRead::Rows(
                ReadbackRows::new(&indices)
                    .column(&second, 0, 4, 4, "two columns")
                    .unwrap()
                    .column(&first, 1, 1, 1, "two columns")
                    .unwrap(),
            ),
            WordRead::Rows(
                ReadbackRows::new(&few).column(&copy_only, 0, 1, 1, "copy-only rows").unwrap(),
            ),
            WordRead::Rows(ReadbackRows::new(&[]).column(&first, 0, 1, 1, "no rows").unwrap()),
        ];
        let mut regions = Vec::new();
        for &index in &indices {
            let offset = u64::from(index * 12 + 2) * 4;
            regions.push(ReadbackRegion::from_buffer(&first, offset, 12, "row").unwrap());
        }
        regions.push(ReadbackRegion::from_buffer(&second, 40, 24, "region").unwrap());
        for &index in &indices {
            let (wide, narrow) = (u64::from(index * 4) * 4, u64::from(index + 1) * 4);
            regions.push(ReadbackRegion::from_buffer(&second, wide, 16, "row").unwrap());
            regions.push(ReadbackRegion::from_buffer(&first, narrow, 4, "row").unwrap());
        }
        for &index in &few {
            let offset = u64::from(index) * 4;
            regions.push(ReadbackRegion::from_buffer(&copy_only, offset, 4, "row").unwrap());
        }
        let expected = readback
            .read_regions(&gpu.device, &gpu.queue, &regions, "rows as regions")
            .unwrap()
            .concat()
            .chunks_exact(4)
            .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
            .collect::<Vec<_>>();
        assert_eq!(expected.len(), reads.iter().map(WordRead::words).sum::<usize>());
        let words = readback.read_words(&gpu.device, &gpu.queue, &reads, "rows").unwrap();
        assert_eq!(words, expected);
        assert!(
            ReadbackRows::new(&[171]).column(&first, 0, 12, 1, "past the view").is_err(),
            "a row past the view is rejected"
        );
        assert!(pollster::block_on(validation.pop()).is_none());
    }

    /// A replayed plan fetches its reads with the first read it does not
    /// answer, answers the rest from that fetch with the current contents,
    /// and still reads anything outside the plan.
    #[test]
    fn gpu_read_plan_replay_answers_planned_reads_from_one_fetch() {
        let gpu = device::global();
        let first = storage_source(&gpu.device, &gpu.queue, 5);
        let second = storage_source(&gpu.device, &gpu.queue, 91);
        let readback = PagedReadback::new(&gpu.device, "readback plan page", 4096);
        let validation = gpu.device.push_error_scope(wgpu::ErrorFilter::Validation);
        let buffers = || PlanBuffers::new([(&first).into(), (&second).into()]);
        let indices = (0..90u32).map(|i| (i * 13) % 120).collect::<Vec<_>>();
        let counts = || WordRead::Region(ReadbackRegion::from_buffer(&first, 64, 8, "counts").unwrap());
        let rows = || {
            WordRead::Rows(
                ReadbackRows::new(&indices)
                    .column(&second, 1, 6, 2, "rows")
                    .unwrap()
                    .column(&first, 0, 2, 1, "rows")
                    .unwrap(),
            )
        };
        let tail = || WordRead::Region(ReadbackRegion::from_buffer(&second, 4000, 400, "tail").unwrap());
        let read = |reads: &[WordRead<'_>], label| {
            readback.read_words(&gpu.device, &gpu.queue, reads, label).unwrap()
        };

        readback.begin_read_plan(buffers(), None);
        let expected = [read(&[counts()], "counts"), read(&[rows(), tail()], "rows")];
        let (plan, stats) = readback.finish_read_plan().unwrap();
        assert_eq!((plan.len(), stats.read, stats.answered), (3, 2, 0));

        // The next run sees new contents in the planned ranges.
        let changed = (0..8192u32).map(|i| (i as u8).wrapping_mul(7)).collect::<Vec<_>>();
        second.write(&gpu.queue, 0, &changed);
        readback.begin_read_plan(buffers(), Some(plan));
        let fresh_counts = read(&[counts()], "counts");
        let fresh_rows = read(&[rows(), tail()], "rows");
        let outside = read(
            &[WordRead::Region(ReadbackRegion::from_buffer(&first, 128, 16, "outside").unwrap())],
            "outside",
        );
        let (plan, stats) = readback.finish_read_plan().unwrap();
        assert_eq!(fresh_counts, expected[0]);
        assert_ne!(fresh_rows, expected[1]);
        assert_eq!(plan.len(), 4);
        assert_eq!((stats.read, stats.answered, stats.fetched), (2, 2, 2));
        assert!(readback.finish_read_plan().is_none());

        // Without a replay the same reads come straight from the GPU.
        assert_eq!(read(&[rows(), tail()], "rows"), fresh_rows);
        assert_eq!(
            outside,
            read(
                &[WordRead::Region(
                    ReadbackRegion::from_buffer(&first, 128, 16, "outside").unwrap()
                )],
                "outside",
            )
        );
        assert!(pollster::block_on(validation.pop()).is_none());
    }
}
