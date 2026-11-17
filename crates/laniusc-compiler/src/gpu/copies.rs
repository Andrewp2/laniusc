//! Buffer copies, clears and zero-fill queue writes, counted per call site.
//!
//! These commands run outside compute passes, so the per-dispatch timing does
//! not cover them. With the host-timing report (`LANIUS_REPORT=host-timing`)
//! every call through these helpers adds its bytes to its call site's count,
//! and, while a job timing session records, gets its own timestamp pair: the
//! trace then shows it as a `copy@file:line` or `clear@file:line` span. The
//! daemon prints and resets the counts after each job (`report_job`).

use std::{collections::HashMap, panic::Location, sync::Mutex};

#[derive(Clone, Copy, Default)]
struct SiteCount {
    calls: u64,
    bytes: u64,
}

type Sites = HashMap<(&'static str, &'static Location<'static>), SiteCount>;

static SITES: Mutex<Option<Sites>> = Mutex::new(None);

fn enabled() -> bool {
    crate::options::get().report.host_timing
}

fn count(kind: &'static str, site: &'static Location<'static>, bytes: u64) {
    let mut sites = SITES.lock().unwrap_or_else(std::sync::PoisonError::into_inner);
    let entry = sites.get_or_insert_with(HashMap::new).entry((kind, site)).or_default();
    entry.calls += 1;
    entry.bytes += bytes;
}

fn site_name(site: &Location<'_>) -> String {
    let file = site.file();
    let file = file.rsplit_once("/src/").map_or(file, |(_, rest)| rest);
    format!("{file}:{}", site.line())
}

/// Prints this job's counts, largest first, and clears them.
pub(crate) fn report_job() {
    if !enabled() {
        return;
    }
    let sites = SITES
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .take()
        .unwrap_or_default();
    let mut rows: Vec<_> = sites.into_iter().collect();
    rows.sort_by(|a, b| b.1.bytes.cmp(&a.1.bytes));
    let mut totals: HashMap<&str, SiteCount> = HashMap::new();
    for ((kind, site), count) in &rows {
        let total = totals.entry(kind).or_default();
        total.calls += count.calls;
        total.bytes += count.bytes;
        eprintln!(
            "[gpu_copy_census] kind={kind} site={} calls={} bytes={}",
            site_name(site),
            count.calls,
            count.bytes
        );
    }
    for (kind, total) in totals {
        eprintln!(
            "[gpu_copy_census] kind={kind} total calls={} bytes={}",
            total.calls, total.bytes
        );
    }
}

/// Counted forms of the encoder's buffer copy and clear.
pub(crate) trait CountedCommands {
    fn copy_buffer_counted(
        &mut self,
        source: &wgpu::Buffer,
        source_offset: wgpu::BufferAddress,
        destination: &wgpu::Buffer,
        destination_offset: wgpu::BufferAddress,
        size: impl Into<Option<wgpu::BufferAddress>>,
    );
    fn clear_buffer_counted(
        &mut self,
        buffer: &wgpu::Buffer,
        offset: wgpu::BufferAddress,
        size: Option<wgpu::BufferAddress>,
    );
}

impl CountedCommands for wgpu::CommandEncoder {
    #[track_caller]
    fn copy_buffer_counted(
        &mut self,
        source: &wgpu::Buffer,
        source_offset: wgpu::BufferAddress,
        destination: &wgpu::Buffer,
        destination_offset: wgpu::BufferAddress,
        size: impl Into<Option<wgpu::BufferAddress>>,
    ) {
        let size = size.into();
        if !enabled() {
            self.copy_buffer_to_buffer(source, source_offset, destination, destination_offset, size);
            return;
        }
        let site = Location::caller();
        let label = format!("copy@{}", site_name(site));
        crate::gpu::timer::stamp_active_command(self, &label, false);
        self.copy_buffer_to_buffer(source, source_offset, destination, destination_offset, size);
        crate::gpu::timer::stamp_active_command(self, &label, true);
        count(
            "copy",
            site,
            size.unwrap_or_else(|| source.size().saturating_sub(source_offset)),
        );
    }

    #[track_caller]
    fn clear_buffer_counted(
        &mut self,
        buffer: &wgpu::Buffer,
        offset: wgpu::BufferAddress,
        size: Option<wgpu::BufferAddress>,
    ) {
        if !enabled() {
            self.clear_buffer(buffer, offset, size);
            return;
        }
        let site = Location::caller();
        let label = format!("clear@{}", site_name(site));
        crate::gpu::timer::stamp_active_command(self, &label, false);
        self.clear_buffer(buffer, offset, size);
        crate::gpu::timer::stamp_active_command(self, &label, true);
        count(
            "clear",
            site,
            size.unwrap_or_else(|| buffer.size().saturating_sub(offset)),
        );
    }
}

/// Counted form of the queue's buffer write: a write of only zero bytes is
/// counted as a zero fill. Queue writes are staged into the next submission,
/// so they have no timestamps of their own.
pub(crate) trait CountedWrites {
    fn write_buffer_counted(&self, buffer: &wgpu::Buffer, offset: wgpu::BufferAddress, data: &[u8]);
}

impl CountedWrites for wgpu::Queue {
    #[track_caller]
    fn write_buffer_counted(&self, buffer: &wgpu::Buffer, offset: wgpu::BufferAddress, data: &[u8]) {
        if enabled() && data.iter().all(|&b| b == 0) {
            count("zero_write", Location::caller(), data.len() as u64);
        }
        self.write_buffer(buffer, offset, data);
    }
}
