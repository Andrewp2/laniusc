use anyhow::{Result, anyhow};
use wgpu;

use super::buffers::{ActionHeader, ParserBuffers};

/// Staging buffers for parser readbacks.
pub struct ParserReadbacks {
    pub headers: wgpu::Buffer,
    pub sc: wgpu::Buffer,
    pub emit: wgpu::Buffer,
    pub match_idx: wgpu::Buffer,
    pub depths: wgpu::Buffer,
    pub valid: wgpu::Buffer,
    pub node_kind: wgpu::Buffer,
    pub parent: wgpu::Buffer,
}

impl ParserReadbacks {
    pub fn create(device: &wgpu::Device, bufs: &ParserBuffers) -> Self {
        // Helper to make a MAP_READ + COPY_DST buffer of given size.
        let mk = |label: &str, size: u64| {
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            })
        };

        let headers = mk("rb.parser.out_headers", bufs.out_headers.byte_size as u64);
        let sc_bytes = (bufs.total_sc.max(1) * 4) as u64;
        let emit_bytes = (bufs.total_emit.max(1) * 4) as u64;

        let sc = mk("rb.parser.out_sc", sc_bytes);
        let emit = mk("rb.parser.out_emit", emit_bytes);
        let match_idx = mk("rb.parser.match_for_index", sc_bytes);
        let depths = mk("rb.parser.depths_out", bufs.depths_out.byte_size as u64);
        let valid = mk("rb.parser.valid_out", bufs.valid_out.byte_size as u64);
        let node_kind = mk("rb.parser.node_kind", emit_bytes);
        let parent = mk("rb.parser.parent", emit_bytes);

        Self {
            headers,
            sc,
            emit,
            match_idx,
            depths,
            valid,
            node_kind,
            parent,
        }
    }

    /// Record copy commands from device-local outputs into staging buffers.
    pub fn encode_copies(&self, encoder: &mut wgpu::CommandEncoder, bufs: &ParserBuffers) {
        // out_headers
        encoder.copy_buffer_to_buffer(
            &bufs.out_headers,
            0,
            &self.headers,
            0,
            bufs.out_headers.byte_size as u64,
        );

        // out_sc and match_for_index
        let sc_bytes = (bufs.total_sc.max(1) * 4) as u64;
        encoder.copy_buffer_to_buffer(&bufs.out_sc, 0, &self.sc, 0, sc_bytes);
        encoder.copy_buffer_to_buffer(&bufs.match_for_index, 0, &self.match_idx, 0, sc_bytes);

        // out_emit, node_kind, parent
        let emit_bytes = (bufs.total_emit.max(1) * 4) as u64;
        encoder.copy_buffer_to_buffer(&bufs.out_emit, 0, &self.emit, 0, emit_bytes);
        encoder.copy_buffer_to_buffer(&bufs.node_kind, 0, &self.node_kind, 0, emit_bytes);
        encoder.copy_buffer_to_buffer(&bufs.parent, 0, &self.parent, 0, emit_bytes);

        // depths_out, valid_out
        encoder.copy_buffer_to_buffer(
            &bufs.depths_out,
            0,
            &self.depths,
            0,
            bufs.depths_out.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.valid_out,
            0,
            &self.valid,
            0,
            bufs.valid_out.byte_size as u64,
        );
    }
}

/// Decoded results from the staging buffers.
pub struct DecodedParserReadbacks {
    pub headers: Vec<ActionHeader>,
    pub sc_stream: Vec<u32>,
    pub emit_stream: Vec<u32>,
    pub match_for_index: Vec<u32>,
    pub final_depth: i32,
    pub min_depth: i32,
    pub valid: bool,
    pub node_kind: Vec<u32>,
    pub parent: Vec<u32>,
}

impl DecodedParserReadbacks {
    /// Map, wait, decode all staging buffers into host vectors.
    pub fn map_and_decode(
        device: &wgpu::Device,
        bufs: &ParserBuffers,
        rb: ParserReadbacks,
    ) -> Result<Self> {
        // Map all
        let map = |b: &wgpu::Buffer| {
            let sl = b.slice(..);
            sl.map_async(wgpu::MapMode::Read, |_| {});
        };
        map(&rb.headers);
        map(&rb.sc);
        map(&rb.emit);
        map(&rb.match_idx);
        map(&rb.depths);
        map(&rb.valid);
        map(&rb.node_kind);
        map(&rb.parent);

        let _ = device.poll(wgpu::PollType::Wait);

        // headers
        let headers = {
            let data = rb.headers.slice(..).get_mapped_range();
            let count = (bufs.n_tokens.saturating_sub(1)) as usize;
            let out = decode_action_headers(&data, count)?;
            drop(data);
            rb.headers.unmap();
            out
        };

        // sc_stream
        let sc_stream = {
            let data = rb.sc.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(bufs.total_sc as usize);
            for chunk in data.chunks_exact(4) {
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.sc.unmap();
            v.truncate(bufs.total_sc as usize);
            v
        };

        // emit_stream
        let emit_stream = {
            let data = rb.emit.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(bufs.total_emit as usize);
            for chunk in data.chunks_exact(4) {
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.emit.unmap();
            v.truncate(bufs.total_emit as usize);
            v
        };

        // match_for_index
        let match_for_index = {
            let data = rb.match_idx.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(bufs.total_sc as usize);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= bufs.total_sc as usize {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.match_idx.unmap();
            v
        };

        // depths
        let (final_depth, min_depth) = {
            let data = rb.depths.slice(..).get_mapped_range();
            let fd = i32::from_le_bytes(data[0..4].try_into().unwrap());
            let md = i32::from_le_bytes(data[4..8].try_into().unwrap());
            drop(data);
            rb.depths.unmap();
            (fd, md)
        };

        // valid
        let valid = {
            let data = rb.valid.slice(..).get_mapped_range();
            let ok = u32::from_le_bytes(data[0..4].try_into().unwrap()) != 0;
            drop(data);
            rb.valid.unmap();
            ok
        };

        // node_kind
        let node_kind = {
            let data = rb.node_kind.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(bufs.total_emit as usize);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= bufs.total_emit as usize {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.node_kind.unmap();
            v
        };

        // parent
        let parent = {
            let data = rb.parent.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(bufs.total_emit as usize);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= bufs.total_emit as usize {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.parent.unmap();
            v
        };

        Ok(Self {
            headers,
            sc_stream,
            emit_stream,
            match_for_index,
            final_depth,
            min_depth,
            valid,
            node_kind,
            parent,
        })
    }
}

fn decode_action_headers(bytes: &[u8], count: usize) -> Result<Vec<ActionHeader>> {
    let stride = core::mem::size_of::<ActionHeader>();
    if bytes.len() < stride * count {
        return Err(anyhow!("out_headers readback too small"));
    }
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        let off = i * stride;
        let push_len = u32::from_le_bytes(bytes[off + 0..off + 4].try_into().unwrap());
        let emit_len = u32::from_le_bytes(bytes[off + 4..off + 8].try_into().unwrap());
        let pop_tag = u32::from_le_bytes(bytes[off + 8..off + 12].try_into().unwrap());
        let pop_count = u32::from_le_bytes(bytes[off + 12..off + 16].try_into().unwrap());
        out.push(ActionHeader {
            push_len,
            emit_len,
            pop_tag,
            pop_count,
        });
    }
    Ok(out)
}
