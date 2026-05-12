use anyhow::{Result, anyhow};
use wgpu;

use super::buffers::{ActionHeader, ParserBuffers};

/// Staging buffers for parser readbacks.
pub struct ParserReadbacks {
    pub ll1_status: wgpu::Buffer,
    pub ll1_emit: wgpu::Buffer,
    pub ll1_emit_pos: wgpu::Buffer,
    pub ll1_block_seed_len: wgpu::Buffer,
    pub ll1_seed_plan_status: wgpu::Buffer,
    pub ll1_seeded_status: wgpu::Buffer,
    pub ll1_seeded_emit: wgpu::Buffer,
    pub headers: wgpu::Buffer,
    pub sc: wgpu::Buffer,
    pub emit: wgpu::Buffer,
    pub match_idx: wgpu::Buffer,
    pub depths: wgpu::Buffer,
    pub valid: wgpu::Buffer,
    pub node_kind: wgpu::Buffer,
    pub parent: wgpu::Buffer,
    pub first_child: wgpu::Buffer,
    pub next_sibling: wgpu::Buffer,
    pub subtree_end: wgpu::Buffer,
    pub hir_kind: wgpu::Buffer,
    pub hir_token_pos: wgpu::Buffer,
    pub hir_token_end: wgpu::Buffer,
    pub hir_item_kind: wgpu::Buffer,
    pub hir_item_name_token: wgpu::Buffer,
    pub hir_item_namespace: wgpu::Buffer,
    pub hir_item_visibility: wgpu::Buffer,
    pub hir_item_path_start: wgpu::Buffer,
    pub hir_item_path_end: wgpu::Buffer,
    pub hir_item_file_id: wgpu::Buffer,
    pub hir_item_import_target_kind: wgpu::Buffer,
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

        let ll1_status = mk("rb.parser.ll1_status", bufs.ll1_status.byte_size as u64);
        let ll1_emit = mk("rb.parser.ll1_emit", bufs.ll1_emit.byte_size as u64);
        let ll1_emit_pos = mk("rb.parser.ll1_emit_pos", bufs.ll1_emit_pos.byte_size as u64);
        let ll1_block_seed_len = mk(
            "rb.parser.ll1_block_seed_len",
            bufs.ll1_block_seed_len.byte_size as u64,
        );
        let ll1_seed_plan_status = mk(
            "rb.parser.ll1_seed_plan_status",
            bufs.ll1_seed_plan_status.byte_size as u64,
        );
        let ll1_seeded_status = mk(
            "rb.parser.ll1_seeded_status",
            bufs.ll1_seeded_status.byte_size as u64,
        );
        let ll1_seeded_emit = mk(
            "rb.parser.ll1_seeded_emit",
            bufs.ll1_seeded_emit.byte_size as u64,
        );
        let headers = mk("rb.parser.out_headers", bufs.out_headers.byte_size as u64);
        let sc_bytes = (bufs.total_sc.max(1) * 4) as u64;
        let emit_bytes = (bufs.total_emit.max(1) * 4) as u64;

        let sc = mk("rb.parser.out_sc", sc_bytes);
        let emit = mk("rb.parser.out_emit", emit_bytes);
        let match_idx = mk("rb.parser.match_for_index", sc_bytes);
        let depths = mk("rb.parser.depths_out", bufs.depths_out.byte_size as u64);
        let valid = mk("rb.parser.valid_out", bufs.valid_out.byte_size as u64);
        let node_kind = mk("rb.parser.node_kind", bufs.node_kind.byte_size as u64);
        let parent = mk("rb.parser.parent", bufs.parent.byte_size as u64);
        let first_child = mk("rb.parser.first_child", bufs.first_child.byte_size as u64);
        let next_sibling = mk("rb.parser.next_sibling", bufs.next_sibling.byte_size as u64);
        let subtree_end = mk("rb.parser.subtree_end", bufs.subtree_end.byte_size as u64);
        let hir_kind = mk("rb.parser.hir_kind", bufs.hir_kind.byte_size as u64);
        let hir_token_pos = mk(
            "rb.parser.hir_token_pos",
            bufs.hir_token_pos.byte_size as u64,
        );
        let hir_token_end = mk(
            "rb.parser.hir_token_end",
            bufs.hir_token_end.byte_size as u64,
        );
        let hir_item_kind = mk(
            "rb.parser.hir_item_kind",
            bufs.hir_item_kind.byte_size as u64,
        );
        let hir_item_name_token = mk(
            "rb.parser.hir_item_name_token",
            bufs.hir_item_name_token.byte_size as u64,
        );
        let hir_item_namespace = mk(
            "rb.parser.hir_item_namespace",
            bufs.hir_item_namespace.byte_size as u64,
        );
        let hir_item_visibility = mk(
            "rb.parser.hir_item_visibility",
            bufs.hir_item_visibility.byte_size as u64,
        );
        let hir_item_path_start = mk(
            "rb.parser.hir_item_path_start",
            bufs.hir_item_path_start.byte_size as u64,
        );
        let hir_item_path_end = mk(
            "rb.parser.hir_item_path_end",
            bufs.hir_item_path_end.byte_size as u64,
        );
        let hir_item_file_id = mk(
            "rb.parser.hir_item_file_id",
            bufs.hir_item_file_id.byte_size as u64,
        );
        let hir_item_import_target_kind = mk(
            "rb.parser.hir_item_import_target_kind",
            bufs.hir_item_import_target_kind.byte_size as u64,
        );

        Self {
            ll1_status,
            ll1_emit,
            ll1_emit_pos,
            ll1_block_seed_len,
            ll1_seed_plan_status,
            ll1_seeded_status,
            ll1_seeded_emit,
            headers,
            sc,
            emit,
            match_idx,
            depths,
            valid,
            node_kind,
            parent,
            first_child,
            next_sibling,
            subtree_end,
            hir_kind,
            hir_token_pos,
            hir_token_end,
            hir_item_kind,
            hir_item_name_token,
            hir_item_namespace,
            hir_item_visibility,
            hir_item_path_start,
            hir_item_path_end,
            hir_item_file_id,
            hir_item_import_target_kind,
        }
    }

    /// Record copy commands from device-local outputs into staging buffers.
    pub fn encode_copies(&self, encoder: &mut wgpu::CommandEncoder, bufs: &ParserBuffers) {
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_status,
            0,
            &self.ll1_status,
            0,
            bufs.ll1_status.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_emit,
            0,
            &self.ll1_emit,
            0,
            bufs.ll1_emit.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_emit_pos,
            0,
            &self.ll1_emit_pos,
            0,
            bufs.ll1_emit_pos.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_block_seed_len,
            0,
            &self.ll1_block_seed_len,
            0,
            bufs.ll1_block_seed_len.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_seed_plan_status,
            0,
            &self.ll1_seed_plan_status,
            0,
            bufs.ll1_seed_plan_status.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_seeded_status,
            0,
            &self.ll1_seeded_status,
            0,
            bufs.ll1_seeded_status.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_seeded_emit,
            0,
            &self.ll1_seeded_emit,
            0,
            bufs.ll1_seeded_emit.byte_size as u64,
        );

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
        encoder.copy_buffer_to_buffer(
            &bufs.node_kind,
            0,
            &self.node_kind,
            0,
            bufs.node_kind.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.parent,
            0,
            &self.parent,
            0,
            bufs.parent.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.first_child,
            0,
            &self.first_child,
            0,
            bufs.first_child.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.next_sibling,
            0,
            &self.next_sibling,
            0,
            bufs.next_sibling.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.subtree_end,
            0,
            &self.subtree_end,
            0,
            bufs.subtree_end.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_kind,
            0,
            &self.hir_kind,
            0,
            bufs.hir_kind.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_token_pos,
            0,
            &self.hir_token_pos,
            0,
            bufs.hir_token_pos.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_token_end,
            0,
            &self.hir_token_end,
            0,
            bufs.hir_token_end.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_kind,
            0,
            &self.hir_item_kind,
            0,
            bufs.hir_item_kind.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_name_token,
            0,
            &self.hir_item_name_token,
            0,
            bufs.hir_item_name_token.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_namespace,
            0,
            &self.hir_item_namespace,
            0,
            bufs.hir_item_namespace.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_visibility,
            0,
            &self.hir_item_visibility,
            0,
            bufs.hir_item_visibility.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_path_start,
            0,
            &self.hir_item_path_start,
            0,
            bufs.hir_item_path_start.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_path_end,
            0,
            &self.hir_item_path_end,
            0,
            bufs.hir_item_path_end.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_file_id,
            0,
            &self.hir_item_file_id,
            0,
            bufs.hir_item_file_id.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_import_target_kind,
            0,
            &self.hir_item_import_target_kind,
            0,
            bufs.hir_item_import_target_kind.byte_size as u64,
        );

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
    pub ll1_status: [u32; 6],
    pub ll1_emit_stream: Vec<u32>,
    pub ll1_emit_token_pos: Vec<u32>,
    pub ll1_block_seed_len: Vec<u32>,
    pub ll1_seed_plan_status: [u32; 8],
    pub ll1_seeded_status: Vec<u32>,
    pub ll1_seeded_emit: Vec<u32>,
    pub headers: Vec<ActionHeader>,
    pub sc_stream: Vec<u32>,
    pub emit_stream: Vec<u32>,
    pub match_for_index: Vec<u32>,
    pub final_depth: i32,
    pub min_depth: i32,
    pub valid: bool,
    pub node_kind: Vec<u32>,
    pub parent: Vec<u32>,
    pub first_child: Vec<u32>,
    pub next_sibling: Vec<u32>,
    pub subtree_end: Vec<u32>,
    pub hir_kind: Vec<u32>,
    pub hir_token_pos: Vec<u32>,
    pub hir_token_end: Vec<u32>,
    pub hir_item_kind: Vec<u32>,
    pub hir_item_name_token: Vec<u32>,
    pub hir_item_namespace: Vec<u32>,
    pub hir_item_visibility: Vec<u32>,
    pub hir_item_path_start: Vec<u32>,
    pub hir_item_path_end: Vec<u32>,
    pub hir_item_file_id: Vec<u32>,
    pub hir_item_import_target_kind: Vec<u32>,
}

impl DecodedParserReadbacks {
    /// Map, wait, decode all staging buffers into host vectors.
    pub fn map_and_decode(
        device: &wgpu::Device,
        bufs: &ParserBuffers,
        rb: ParserReadbacks,
    ) -> Result<Self> {
        // Map all
        let map = |name: &str, b: &wgpu::Buffer| {
            crate::gpu::passes_core::map_readback_for_progress(
                &b.slice(..),
                &format!("parser.readback.{name}"),
            );
        };
        map("headers", &rb.headers);
        map("ll1_status", &rb.ll1_status);
        map("ll1_emit", &rb.ll1_emit);
        map("ll1_emit_pos", &rb.ll1_emit_pos);
        map("ll1_block_seed_len", &rb.ll1_block_seed_len);
        map("ll1_seed_plan_status", &rb.ll1_seed_plan_status);
        map("ll1_seeded_status", &rb.ll1_seeded_status);
        map("ll1_seeded_emit", &rb.ll1_seeded_emit);
        map("sc", &rb.sc);
        map("emit", &rb.emit);
        map("match_idx", &rb.match_idx);
        map("depths", &rb.depths);
        map("valid", &rb.valid);
        map("node_kind", &rb.node_kind);
        map("parent", &rb.parent);
        map("first_child", &rb.first_child);
        map("next_sibling", &rb.next_sibling);
        map("subtree_end", &rb.subtree_end);
        map("hir_kind", &rb.hir_kind);
        map("hir_token_pos", &rb.hir_token_pos);
        map("hir_token_end", &rb.hir_token_end);
        map("hir_item_kind", &rb.hir_item_kind);
        map("hir_item_name_token", &rb.hir_item_name_token);
        map("hir_item_namespace", &rb.hir_item_namespace);
        map("hir_item_visibility", &rb.hir_item_visibility);
        map("hir_item_path_start", &rb.hir_item_path_start);
        map("hir_item_path_end", &rb.hir_item_path_end);
        map("hir_item_file_id", &rb.hir_item_file_id);
        map(
            "hir_item_import_target_kind",
            &rb.hir_item_import_target_kind,
        );

        crate::gpu::passes_core::wait_for_map_progress(
            device,
            "parser.readback",
            wgpu::PollType::Wait,
        );

        let ll1_status = {
            let data = rb.ll1_status.slice(..).get_mapped_range();
            let mut out = [0u32; 6];
            for (i, chunk) in data.chunks_exact(4).take(6).enumerate() {
                out[i] = u32::from_le_bytes(chunk.try_into().unwrap());
            }
            drop(data);
            rb.ll1_status.unmap();
            out
        };
        let ll1_emit_stream = {
            let data = rb.ll1_emit.slice(..).get_mapped_range();
            let len = (ll1_status[5] as usize).min(bufs.ll1_emit.count);
            let mut v = Vec::with_capacity(len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.ll1_emit.unmap();
            v
        };
        let ll1_emit_token_pos = {
            let data = rb.ll1_emit_pos.slice(..).get_mapped_range();
            let len = (ll1_status[5] as usize).min(bufs.ll1_emit_pos.count);
            let mut v = Vec::with_capacity(len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.ll1_emit_pos.unmap();
            v
        };
        let ll1_block_seed_len = {
            let data = rb.ll1_block_seed_len.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(bufs.ll1_block_seed_len.count);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= bufs.ll1_block_seed_len.count {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.ll1_block_seed_len.unmap();
            v
        };
        let ll1_seed_plan_status = {
            let data = rb.ll1_seed_plan_status.slice(..).get_mapped_range();
            let mut out = [0u32; 8];
            for (i, chunk) in data.chunks_exact(4).take(8).enumerate() {
                out[i] = u32::from_le_bytes(chunk.try_into().unwrap());
            }
            drop(data);
            rb.ll1_seed_plan_status.unmap();
            out
        };
        let ll1_seeded_status = {
            let data = rb.ll1_seeded_status.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(bufs.ll1_seeded_status.count);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= bufs.ll1_seeded_status.count {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.ll1_seeded_status.unmap();
            v
        };
        let ll1_seeded_emit = {
            let data = rb.ll1_seeded_emit.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(bufs.ll1_seeded_emit.count);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= bufs.ll1_seeded_emit.count {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.ll1_seeded_emit.unmap();
            v
        };
        let tree_len = if bufs.tree_count_uses_status {
            (ll1_status[5] as usize).min(bufs.node_kind.count)
        } else {
            (bufs.total_emit as usize).min(bufs.node_kind.count)
        };

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
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
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
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.parent.unmap();
            v
        };

        let first_child = {
            let data = rb.first_child.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.first_child.unmap();
            v
        };

        let next_sibling = {
            let data = rb.next_sibling.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.next_sibling.unmap();
            v
        };

        let subtree_end = {
            let data = rb.subtree_end.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.subtree_end.unmap();
            v
        };

        let hir_kind = {
            let data = rb.hir_kind.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.hir_kind.unmap();
            v
        };

        let hir_token_pos = {
            let data = rb.hir_token_pos.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.hir_token_pos.unmap();
            v
        };

        let hir_token_end = {
            let data = rb.hir_token_end.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.hir_token_end.unmap();
            v
        };
        let hir_item_kind = {
            let data = rb.hir_item_kind.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.hir_item_kind.unmap();
            v
        };
        let hir_item_name_token = {
            let data = rb.hir_item_name_token.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.hir_item_name_token.unmap();
            v
        };
        let hir_item_namespace = {
            let data = rb.hir_item_namespace.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.hir_item_namespace.unmap();
            v
        };
        let hir_item_visibility = {
            let data = rb.hir_item_visibility.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.hir_item_visibility.unmap();
            v
        };
        let hir_item_path_start = {
            let data = rb.hir_item_path_start.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.hir_item_path_start.unmap();
            v
        };
        let hir_item_path_end = {
            let data = rb.hir_item_path_end.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.hir_item_path_end.unmap();
            v
        };
        let hir_item_file_id = {
            let data = rb.hir_item_file_id.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.hir_item_file_id.unmap();
            v
        };
        let hir_item_import_target_kind = {
            let data = rb.hir_item_import_target_kind.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(tree_len);
            for (i, chunk) in data.chunks_exact(4).enumerate() {
                if i >= tree_len {
                    break;
                }
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            drop(data);
            rb.hir_item_import_target_kind.unmap();
            v
        };

        Ok(Self {
            ll1_status,
            ll1_emit_stream,
            ll1_emit_token_pos,
            ll1_block_seed_len,
            ll1_seed_plan_status,
            ll1_seeded_status,
            ll1_seeded_emit,
            headers,
            sc_stream,
            emit_stream,
            match_for_index,
            final_depth,
            min_depth,
            valid,
            node_kind,
            parent,
            first_child,
            next_sibling,
            subtree_end,
            hir_kind,
            hir_token_pos,
            hir_token_end,
            hir_item_kind,
            hir_item_name_token,
            hir_item_namespace,
            hir_item_visibility,
            hir_item_path_start,
            hir_item_path_end,
            hir_item_file_id,
            hir_item_import_target_kind,
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
