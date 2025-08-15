//! Simple per-encode GPU timestamp helper. Not thread-safe; create per "frame"/encode.

use wgpu;

/// A timer for measuring GPU execution time.
pub struct GpuTimer {
    period_in_nanoseconds: f32,
    query_set: wgpu::QuerySet,
    resolve_buffer: wgpu::Buffer,
    readback_buffer: wgpu::Buffer,
    next: u32,
    capacity: u32,
    pub stamp_labels: Vec<String>,
}

impl GpuTimer {
    /// Creates a new GpuTimer with the given maximum number of queries.
    pub fn new(device: &wgpu::Device, queue: &wgpu::Queue, max_queries: u32) -> Self {
        let query_set = device.create_query_set(&wgpu::QuerySetDescriptor {
            label: Some("LaniusTimestamps"),
            ty: wgpu::QueryType::Timestamp,
            count: max_queries,
        });

        let resolve_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("TimestampResolve"),
            size: (max_queries as u64) * 8,
            usage: wgpu::BufferUsages::QUERY_RESOLVE | wgpu::BufferUsages::COPY_SRC,
            mapped_at_creation: false,
        });

        let readback_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("TimestampReadback"),
            size: (max_queries as u64) * 8,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });

        Self {
            period_in_nanoseconds: queue.get_timestamp_period(),
            query_set,
            resolve_buffer,
            readback_buffer,
            next: 0,
            capacity: max_queries,
            stamp_labels: vec![],
        }
    }

    /// Records a timestamp with the given label.
    pub fn stamp(&mut self, enc: &mut wgpu::CommandEncoder, label: impl Into<String>) -> u32 {
        let index = self.next % self.capacity;
        self.next = (self.next + 1) % self.capacity;
        self.stamp_labels.push(label.into());
        enc.write_timestamp(&self.query_set, index);
        index
    }

    /// Resets the timer.
    pub fn reset(&mut self) {
        self.stamp_labels.clear();
        self.next = 0;
    }

    /// Resolves the timestamp queries.
    pub fn resolve(&self, encoder: &mut wgpu::CommandEncoder) {
        let query_count = if self.next == 0 { self.capacity } else { self.next };
        encoder.resolve_query_set(&self.query_set, 0..query_count, &self.resolve_buffer, 0);
        encoder.copy_buffer_to_buffer(
            &self.resolve_buffer,
            0,
            &self.readback_buffer,
            0,
            (query_count as u64) * 8,
        );
    }

    /// Attempts to read the recorded timestamps.
    pub fn try_read(&self, device: &wgpu::Device) -> Option<Vec<(String, u64)>> {
        let query_count = if self.next == 0 { self.capacity } else { self.next };
        let slice = self.readback_buffer.slice(..(query_count as u64) * 8);
        let (sender, receiver) = std::sync::mpsc::channel();
        slice.map_async(wgpu::MapMode::Read, move |v| { sender.send(v).expect("mpsc send") });
        let _ = device.poll(wgpu::PollType::Wait);

        if let Ok(Ok(())) = receiver.try_recv() {
            let data = slice.get_mapped_range().to_vec();
            let mut vals = Vec::with_capacity(query_count as usize);
            for chunk in data.chunks_exact(8) {
                let mut arr = [0u8; 8];
                arr.copy_from_slice(chunk);
                vals.push(u64::from_le_bytes(arr));
            }
            drop(data);
            self.readback_buffer.unmap();

            let mut out = Vec::with_capacity(query_count as usize);
            for (i, val) in vals.iter().enumerate() {
                out.push((self.stamp_labels[i].clone(), *val));
            }
            Some(out)
        } else {
            None
        }
    }

    /// Returns the timestamp period in nanoseconds.
    pub fn period_ns(&self) -> f32 {
        self.period_in_nanoseconds
    }
}
