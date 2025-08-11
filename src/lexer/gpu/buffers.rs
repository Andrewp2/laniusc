// src/lexer/gpu/buffers.rs
use super::LexParams;
use crate::lexer::tables::dfa::N_STATES;
use encase::UniformBuffer;
use wgpu::util::DeviceExt;

pub struct GpuBuffers {
    // inputs/tables
    pub in_bytes: wgpu::Buffer,
    pub char_to_func: wgpu::Buffer, // identity map: b -> b
    pub next_state: wgpu::Buffer,   // 256 * N_STATES
    pub emit_mask: wgpu::Buffer,    // 256
    pub token_map: wgpu::Buffer,    // N_STATES

    // function-id mapping (now: bytes) + two-pass prefix
    pub f_ping: wgpu::Buffer,          // map output (bytes)
    pub f_inblock: wgpu::Buffer, // optional scratch (states per element) — kept for compatibility
    pub block_summaries: wgpu::Buffer, // per-block function vector (N_STATES each)
    pub block_ping: wgpu::Buffer, // scan ping (N_STATES per block)
    pub block_pong: wgpu::Buffer, // scan pong (N_STATES per block)
    pub block_prefix: wgpu::Buffer, // inclusive per-block prefix (N_STATES each)
    pub f_final: wgpu::Buffer,   // global DFA state per element (u32)

    // boundary/type streams
    pub end_flags: wgpu::Buffer,
    pub tok_types: wgpu::Buffer,
    pub filtered_flags: wgpu::Buffer,

    // sum-scan scratch
    pub s_ping: wgpu::Buffer,
    pub s_pong: wgpu::Buffer,
    pub s_final: wgpu::Buffer,

    // compaction outputs
    pub end_positions: wgpu::Buffer,
    pub types_compact: wgpu::Buffer,
    pub token_count: wgpu::Buffer,

    // final tokens
    pub tokens_out: wgpu::Buffer,
}

impl GpuBuffers {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        device: &wgpu::Device,
        n: u32,
        start_state: u32,
        bytes_u32: &[u32],
        char_to_func: &[u32; 256],
        next_state: &[u32],
        emit_mask: &[u32],
        token_map: &[u32],
    ) -> (Self, wgpu::Buffer) {
        let nb = n.div_ceil(128); // workgroup/block size is 128
        let make_ro = |label: &str, bytes: &[u8]| {
            device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some(label),
                contents: bytes,
                usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            })
        };
        let make_rw = |label: &str, size: usize| {
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: size as u64,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_SRC
                    | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            })
        };

        let in_bytes = make_ro("in_bytes", bytemuck::cast_slice(bytes_u32));
        let char_to_func_buf = make_ro("char_to_func", bytemuck::cast_slice(char_to_func));
        let next_state_buf = make_ro("next_state", bytemuck::cast_slice(next_state));
        let emit_mask_buf = make_ro("emit_mask", bytemuck::cast_slice(emit_mask));
        let token_map_buf = make_ro("token_map", bytemuck::cast_slice(token_map));

        let f_ping = make_rw("f_ping", (n as usize) * 4);
        let f_inblock = make_rw("f_inblock", (n as usize) * 4);

        let per_block_vec_bytes = (N_STATES * 4) as usize;
        let block_summaries = make_rw("block_summaries", (nb as usize) * per_block_vec_bytes);
        let block_ping = make_rw("block_ping", (nb as usize) * per_block_vec_bytes);
        let block_pong = make_rw("block_pong", (nb as usize) * per_block_vec_bytes);
        let block_prefix = make_rw("block_prefix", (nb as usize) * per_block_vec_bytes);

        let f_final = make_rw("f_final", (n as usize) * 4);

        let end_flags = make_rw("end_flags", (n as usize) * 4);
        let tok_types = make_rw("tok_types", (n as usize) * 4);
        let filtered_flags = make_rw("filtered_flags", (n as usize) * 4);

        let s_ping = make_rw("s_ping", (n as usize) * 4);
        let s_pong = make_rw("s_pong", (n as usize) * 4);
        let s_final = make_rw("s_final", (n as usize) * 4);

        let end_positions = make_rw("end_positions", (n as usize) * 4);
        let types_compact = make_rw("types_compact", (n as usize) * 4);
        let token_count = make_rw("token_count", 4);

        let tokens_out = make_rw(
            "tokens_out",
            (n as usize) * std::mem::size_of::<super::GpuToken>(),
        );

        // LexParams UBO
        let mut ub = UniformBuffer::new(Vec::new());
        ub.write(&LexParams {
            n,
            m: N_STATES as u32,
            identity_id: start_state,
        })
        .unwrap();
        let params_buf = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("LexParams"),
            contents: ub.as_ref(),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });

        (
            Self {
                in_bytes,
                char_to_func: char_to_func_buf,
                next_state: next_state_buf,
                emit_mask: emit_mask_buf,
                token_map: token_map_buf,
                f_ping,
                f_inblock,
                block_summaries,
                block_ping,
                block_pong,
                block_prefix,
                f_final,
                end_flags,
                tok_types,
                filtered_flags,
                s_ping,
                s_pong,
                s_final,
                end_positions,
                types_compact,
                token_count,
                tokens_out,
            },
            params_buf,
        )
    }

    pub fn resolve<'a>(
        &'a self,
        name: &str,
        params_buf: &'a wgpu::Buffer,
    ) -> Option<wgpu::BindingResource<'a>> {
        Some(match name {
            "gParams" => wgpu::BindingResource::Buffer(params_buf.as_entire_buffer_binding()),
            "in_bytes" => self.in_bytes.as_entire_binding(),
            "char_to_func" => self.char_to_func.as_entire_binding(),

            "next_state" => self.next_state.as_entire_binding(),
            "emit_mask" => self.emit_mask.as_entire_binding(),
            "token_map" => self.token_map.as_entire_binding(),

            "f_ping" => self.f_ping.as_entire_binding(),
            "f_src" => self.f_ping.as_entire_binding(),
            "f_inblock" => self.f_inblock.as_entire_binding(),

            "block_summaries" => self.block_summaries.as_entire_binding(),
            "block_prefix" => self.block_prefix.as_entire_binding(),

            "f_final" => self.f_final.as_entire_binding(),

            "end_flags" => self.end_flags.as_entire_binding(),
            "tok_types" => self.tok_types.as_entire_binding(),
            "filtered_flags" => self.filtered_flags.as_entire_binding(),

            "s_ping" => self.s_ping.as_entire_binding(),
            "s_pong" => self.s_pong.as_entire_binding(),
            "s_final" => self.s_final.as_entire_binding(),

            "end_positions" => self.end_positions.as_entire_binding(),
            "types_compact" => self.types_compact.as_entire_binding(),
            "token_count" => self.token_count.as_entire_binding(),
            "tokens_out" => self.tokens_out.as_entire_binding(),

            _ => return None,
        })
    }

    pub fn resolve_scan<'a>(
        &'a self,
        name: &str,
        params_buf: &'a wgpu::Buffer,
        scan_params_buf: &'a wgpu::Buffer,
    ) -> Option<wgpu::BindingResource<'a>> {
        Some(match name {
            "gParams" => wgpu::BindingResource::Buffer(params_buf.as_entire_buffer_binding()),
            "gScan" => wgpu::BindingResource::Buffer(scan_params_buf.as_entire_buffer_binding()),

            // sum-scan
            "s_ping" => self.s_ping.as_entire_binding(),
            "s_pong" => self.s_pong.as_entire_binding(),

            // block scan
            "block_ping" => self.block_ping.as_entire_binding(),
            "block_pong" => self.block_pong.as_entire_binding(),

            // fall back to regular resolver
            _ => return self.resolve(name, params_buf),
        })
    }
}
