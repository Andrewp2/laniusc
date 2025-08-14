// src/lexer/gpu/buffers.rs
use std::ops::Deref;

use encase::UniformBuffer;
use wgpu::util::DeviceExt;

use super::LexParams;
use crate::lexer::tables::dfa::N_STATES;

pub struct LaniusBuffer<T> {
    pub buffer: wgpu::Buffer,
    pub byte_size: usize,
    #[allow(dead_code)]
    pub count: usize,
    _marker: std::marker::PhantomData<T>,
}

impl<T> LaniusBuffer<T> {
    pub fn new((buffer, byte_size): (wgpu::Buffer, u64), count: usize) -> Self {
        Self {
            buffer,
            byte_size: byte_size as usize,
            count,
            _marker: std::marker::PhantomData,
        }
    }
}

impl<T> Deref for LaniusBuffer<T> {
    type Target = wgpu::Buffer;
    fn deref(&self) -> &Self::Target {
        &self.buffer
    }
}

pub struct GpuBuffers {
    pub n: u32,
    pub nb: u32,

    /// Uniform params buffer (LexParams)
    pub params: LaniusBuffer<super::LexParams>,

    // inputs/tables
    pub in_bytes: LaniusBuffer<u8>,
    pub next_emit: LaniusBuffer<u32>, // 256 * N_STATES, low15=next, high1=emit
    pub token_map: LaniusBuffer<u32>, // N_STATES

    // function-id mapping + two-pass prefix for DFA states
    pub block_summaries: LaniusBuffer<u32>, // per-block function vector (N_STATES each)
    pub block_ping: LaniusBuffer<u32>,
    pub block_pong: LaniusBuffer<u32>,
    pub block_prefix: LaniusBuffer<u32>,
    pub f_final: LaniusBuffer<u32>,

    pub tok_types: LaniusBuffer<u32>, // type at boundary after i (packed)
    pub flags_packed: LaniusBuffer<u32>, // NEW: packed flags per i
    pub end_excl_by_i: LaniusBuffer<u32>, // exact exclusive end index per boundary i

    // seeds → hierarchical sum scratch/finals for BOTH streams
    pub s_pair_inblock: LaniusBuffer<u32>, // byte_size = n * 8 (uint2)
    pub block_totals_pair: LaniusBuffer<u32>,
    pub block_pair_ping: LaniusBuffer<u32>,
    pub block_pair_pong: LaniusBuffer<u32>,
    pub block_prefix_pair: LaniusBuffer<u32>,
    pub s_all_final: LaniusBuffer<u32>,
    pub s_keep_final: LaniusBuffer<u32>,

    // compaction outputs (ALL and KEPT)
    pub end_positions: LaniusBuffer<u32>,     // kept
    pub end_positions_all: LaniusBuffer<u32>, // all
    pub types_compact: LaniusBuffer<u32>,     // kept
    pub all_index_compact: LaniusBuffer<u32>, // kept
    pub token_count: LaniusBuffer<u32>,       // kept
    pub token_count_all: LaniusBuffer<u32>,   // all (debug/optional)

    // final tokens (kept)
    pub tokens_out: LaniusBuffer<super::GpuToken>,
}

impl GpuBuffers {
    #[allow(clippy::too_many_arguments)]
    pub fn new(
        device: &wgpu::Device,
        n: u32,
        start_state: u32,
        input_bytes: &[u8],
        next_emit_packed: &[u32],
        token_map: &[u32],
        skip_kinds: [u32; 4],
    ) -> Self {
        fn u32s_to_le_bytes(slice: &[u32]) -> Vec<u8> {
            let mut out = Vec::with_capacity(slice.len() * 4);
            for &v in slice {
                out.extend_from_slice(&v.to_le_bytes());
            }
            out
        }
        fn make_ro<T>(
            device: &wgpu::Device,
            label: &str,
            bytes: &[u8],
            count: usize,
        ) -> LaniusBuffer<T> {
            let raw_buffer = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
                label: Some(label),
                contents: bytes,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
            });
            LaniusBuffer::new((raw_buffer, bytes.len() as u64), count)
        }

        fn make_rw<T>(
            device: &wgpu::Device,
            label: &str,
            size: usize,
            count: usize,
        ) -> LaniusBuffer<T> {
            let raw_buffer = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: size as u64,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_SRC
                    | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
            LaniusBuffer::new((raw_buffer, size as u64), count)
        }

        let nb = n.div_ceil(256);

        // ---- inputs/tables
        let in_bytes: LaniusBuffer<u8> = make_ro::<u8>(device, "in_bytes", input_bytes, n as usize);

        let token_map_buf: LaniusBuffer<u32> = make_ro::<u32>(
            device,
            "token_map",
            &u32s_to_le_bytes(token_map),
            N_STATES,
        );

        let per_block_vec_bytes = N_STATES * 4;
        let block_summaries: LaniusBuffer<u32> = make_rw::<u32>(
            device,
            "block_summaries",
            (nb as usize) * per_block_vec_bytes,
            nb as usize,
        );
        let block_ping: LaniusBuffer<u32> = make_rw::<u32>(
            device,
            "block_ping",
            (nb as usize) * per_block_vec_bytes,
            nb as usize,
        );
        let block_pong: LaniusBuffer<u32> = make_rw::<u32>(
            device,
            "block_pong",
            (nb as usize) * per_block_vec_bytes,
            nb as usize,
        );
        let block_prefix: LaniusBuffer<u32> = make_rw::<u32>(
            device,
            "block_prefix",
            (nb as usize) * per_block_vec_bytes,
            nb as usize,
        );

        let f_final: LaniusBuffer<u32> =
            make_rw::<u32>(device, "f_final", (n as usize) * 4, n as usize);

        let tok_types: LaniusBuffer<u32> =
            make_rw::<u32>(device, "tok_types", (n as usize) * 4, n as usize);

        // -------- NEW: single packed flags buffer --------
        let flags_packed: LaniusBuffer<u32> =
            make_rw::<u32>(device, "flags_packed", (n as usize) * 4, n as usize);

        let end_excl_by_i: LaniusBuffer<u32> =
            make_rw::<u32>(device, "end_excl_by_i", (n as usize) * 4, n as usize);

        // ---- hierarchical sum scratch (uint2)
        let s_pair_inblock: LaniusBuffer<u32> =
            make_rw::<u32>(device, "s_pair_inblock", (n as usize) * 8, n as usize);

        let block_totals_pair: LaniusBuffer<u32> =
            make_rw::<u32>(device, "block_totals_pair", (nb as usize) * 8, nb as usize);
        let block_pair_ping: LaniusBuffer<u32> =
            make_rw::<u32>(device, "block_pair_ping", (nb as usize) * 8, nb as usize);
        let block_pair_pong: LaniusBuffer<u32> =
            make_rw::<u32>(device, "block_pair_pong", (nb as usize) * 8, nb as usize);
        let block_prefix_pair: LaniusBuffer<u32> =
            make_rw::<u32>(device, "block_prefix_pair", (nb as usize) * 8, nb as usize);

        // ---- final sums
        let s_all_final: LaniusBuffer<u32> =
            make_rw::<u32>(device, "s_all_final", (n as usize) * 4, n as usize);
        let s_keep_final: LaniusBuffer<u32> =
            make_rw::<u32>(device, "s_keep_final", (n as usize) * 4, n as usize);

        // ---- compaction + outputs
        let end_positions: LaniusBuffer<u32> =
            make_rw::<u32>(device, "end_positions", (n as usize) * 4, n as usize);
        let end_positions_all: LaniusBuffer<u32> =
            make_rw::<u32>(device, "end_positions_all", (n as usize) * 4, n as usize);
        let types_compact: LaniusBuffer<u32> =
            make_rw::<u32>(device, "types_compact", (n as usize) * 4, n as usize);
        let all_index_compact: LaniusBuffer<u32> =
            make_rw::<u32>(device, "all_index_compact", (n as usize) * 4, n as usize);
        let token_count: LaniusBuffer<u32> = make_rw::<u32>(device, "token_count", 4, 1);
        let token_count_all: LaniusBuffer<u32> = make_rw::<u32>(device, "token_count_all", 4, 1);

        let tokens_out: LaniusBuffer<super::GpuToken> = make_rw::<super::GpuToken>(
            device,
            "tokens_out",
            (n as usize) * std::mem::size_of::<super::GpuToken>(),
            n as usize,
        );

        let params_val = LexParams {
            n,
            m: N_STATES as u32,
            start_state,
            skip0: skip_kinds[0],
            skip1: skip_kinds[1],
            skip2: skip_kinds[2],
            skip3: skip_kinds[3],
        };
        let mut ub = UniformBuffer::new(Vec::new());
        ub.write(&params_val).unwrap();
        let raw = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("LexParams"),
            contents: ub.as_ref(),
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        });
        let params = LaniusBuffer::<LexParams>::new((raw, ub.as_ref().len() as u64), 1);

        let next_emit_buf: LaniusBuffer<u32> = make_ro::<u32>(
            device,
            "next_emit",
            &u32s_to_le_bytes(next_emit_packed),
            N_STATES,
        );

        Self {
            n,
            nb,
            params,

            in_bytes,
            next_emit: next_emit_buf,
            token_map: token_map_buf,

            block_summaries,
            block_ping,
            block_pong,
            block_prefix,
            f_final,

            tok_types,
            flags_packed,
            end_excl_by_i,

            s_pair_inblock,
            block_totals_pair,
            block_pair_ping,
            block_pair_pong,
            block_prefix_pair,

            s_all_final,
            s_keep_final,

            end_positions,
            end_positions_all,
            types_compact,
            all_index_compact,
            token_count,
            token_count_all,

            tokens_out,
        }
    }
}
