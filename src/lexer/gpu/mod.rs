// src/lexer/gpu/mod.rs
use crate::lexer::tables::dfa::{N_STATES, StreamingDfa};
use crate::lexer::tables::tokens::TokenKind;
use anyhow::{Result, anyhow};
use bytemuck::{Pod, Zeroable};
use encase::ShaderType;
use wgpu::util::DeviceExt;

mod buffers;
use buffers::GpuBuffers;

mod passes;
use passes::{
    PassCtx, encode_rounds, encode_simple, make_block_scan_stage, make_build_tokens_stage,
    make_finalize_stage, make_fixup_stage, make_map_stage, make_scan_blocks_stage,
    make_scan_sum_stage, make_scatter_stage,
};

#[derive(Debug, Clone)]
pub struct Token {
    pub kind: TokenKind,
    pub start: usize,
    pub len: usize,
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
struct GpuToken {
    kind: u32,
    start: u32,
    len: u32,
}

#[derive(Clone, Copy, ShaderType)]
pub(super) struct LexParams {
    pub n: u32,           // input length
    pub m: u32,           // N_STATES (fixed 32)
    pub identity_id: u32, // start state index
}

pub async fn lex_on_gpu(input: &str) -> Result<Vec<Token>> {
    // --- WGPU bootstrap ---
    let instance = wgpu::Instance::default();
    let adapter = instance
        .request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: None,
            force_fallback_adapter: false,
        })
        .await
        .or_else(|_| Err(anyhow!("no adapter")))?;

    let mut limits = wgpu::Limits::defaults();
    limits.max_storage_buffers_per_shader_stage = 10;
    limits.max_storage_buffer_binding_size = 2_147_483_644;
    limits.max_buffer_size = 2_147_483_644;

    let (device, queue) = adapter
        .request_device(&wgpu::DeviceDescriptor {
            label: Some("Lanius Lexer Device"),
            required_features: wgpu::Features::empty(),
            required_limits: limits,
            memory_hints: wgpu::MemoryHints::default(),
            trace: wgpu::Trace::default(),
        })
        .await?;

    // --- Tiny DFA tables (no m×m) ---
    let dfa = StreamingDfa::new();

    // next_state[byte * N_STATES + state]
    let mut next_state: Vec<u32> = vec![0; 256 * N_STATES];
    let mut emit_mask: Vec<u32> = vec![0; 256];
    for b in 0u32..256 {
        let mut mask = 0u32;
        for s in 0usize..N_STATES {
            let nx = dfa.next[s][b as usize];
            next_state[(b as usize) * N_STATES + s] = nx.state as u32;
            if nx.emit {
                mask |= 1u32 << s;
            }
        }
        emit_mask[b as usize] = mask;
    }
    let token_map: Vec<u32> = dfa.token_map.into();

    // identity char_to_func so lex_map writes raw bytes to f_ping
    let mut char_to_func = [0u32; 256];
    for b in 0..256 {
        char_to_func[b] = b as u32;
    }

    // Input bytes as u32
    let bytes_u32: Vec<u32> = input.bytes().map(|b| b as u32).collect();
    let n = bytes_u32.len() as u32;

    // --- Buffers ---
    let (bufs, params_buf) = GpuBuffers::new(
        &device,
        n,
        dfa.start as u32,
        &bytes_u32,
        &char_to_func,
        &next_state,
        &emit_mask,
        &token_map,
    );

    // --- Build passes ---
    let ctx = PassCtx {
        device: &device,
        bufs: &bufs,
        params_buf: &params_buf,
    };

    let st_map = make_map_stage(&ctx)?;
    let tgs_x = st_map.thread_group_size[0].max(1);
    let groups = (n + tgs_x - 1) / tgs_x;
    let nblocks = groups;

    let st_block_scan = make_block_scan_stage(&ctx)?;
    let rounds_blocks = {
        let mut r = 0u32;
        let mut s = 1u32;
        while s < nblocks {
            r += 1;
            s <<= 1;
        }
        r
    };
    let st_scan_blocks = make_scan_blocks_stage(&ctx, rounds_blocks)?;

    let st_fixup = make_fixup_stage(&ctx)?;
    let st_finalize = make_finalize_stage(&ctx)?;

    let rounds_sum = {
        let mut r = 0u32;
        let mut s = 1u32;
        while s < n {
            r += 1;
            s <<= 1;
        }
        r
    };
    let st_scan_sum = make_scan_sum_stage(&ctx, rounds_sum)?;

    let st_scatter = make_scatter_stage(&ctx)?;
    let st_build = make_build_tokens_stage(&ctx)?;

    // --- Encode ---
    let mut enc = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("lex-enc"),
    });

    // 1) map (bytes -> f_ping = bytes via identity table)
    encode_simple(&mut enc, "map", &st_map, (groups, 1, 1));

    // 2a) per-block scan (summarize each block as a 32-entry function vector)
    encode_simple(&mut enc, "block_scan", &st_block_scan, (nblocks, 1, 1));

    // Seed block_ping from block_summaries
    enc.copy_buffer_to_buffer(
        &bufs.block_summaries,
        0,
        &bufs.block_ping,
        0,
        (nblocks as u64) * (N_STATES as u64) * 4,
    );

    // 2b) scan block summaries (inclusive)
    encode_rounds(&mut enc, "scan_blocks", &st_scan_blocks, (nblocks, 1, 1));

    // Copy block prefix into dedicated buffer
    if st_scan_blocks.last_write_pong {
        enc.copy_buffer_to_buffer(
            &bufs.block_pong,
            0,
            &bufs.block_prefix,
            0,
            (nblocks as u64) * (N_STATES as u64) * 4,
        );
    } else {
        enc.copy_buffer_to_buffer(
            &bufs.block_ping,
            0,
            &bufs.block_prefix,
            0,
            (nblocks as u64) * (N_STATES as u64) * 4,
        );
    }

    // 2c) fixup: recompute final states per element using block carry
    encode_simple(&mut enc, "fixup", &st_fixup, (groups, 1, 1));

    // 3) finalize: compute end flags/types + seed sum-scan
    encode_simple(&mut enc, "finalize", &st_finalize, (groups, 1, 1));

    // 4a) scan (sum of valid ends)
    encode_rounds(&mut enc, "scan_sum", &st_scan_sum, (groups, 1, 1));

    // Copy sum scan result to s_final
    if st_scan_sum.last_write_pong {
        enc.copy_buffer_to_buffer(&bufs.s_pong, 0, &bufs.s_final, 0, (n as u64) * 4);
    } else {
        enc.copy_buffer_to_buffer(&bufs.s_ping, 0, &bufs.s_final, 0, (n as u64) * 4);
    }

    // 4b) scatter
    encode_simple(&mut enc, "scatter", &st_scatter, (groups, 1, 1));

    // 5) build tokens
    encode_simple(&mut enc, "build_tokens", &st_build, (groups, 1, 1));

    // 6) read back
    let rb_count = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb_count"),
        size: 4,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let rb_tokens = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb_tokens"),
        size: (n as u64) * (std::mem::size_of::<GpuToken>() as u64),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    enc.copy_buffer_to_buffer(&bufs.token_count, 0, &rb_count, 0, 4);
    enc.copy_buffer_to_buffer(
        &bufs.tokens_out,
        0,
        &rb_tokens,
        0,
        (n as u64) * (std::mem::size_of::<GpuToken>() as u64),
    );

    queue.submit(Some(enc.finish()));

    rb_count.slice(..).map_async(wgpu::MapMode::Read, |_| {});
    rb_tokens.slice(..).map_async(wgpu::MapMode::Read, |_| {});
    let _ = device.poll(wgpu::PollType::Wait);

    let token_count_u32 =
        bytemuck::cast_slice::<u8, u32>(&rb_count.slice(..).get_mapped_range())[0] as usize;
    let mapped_range = rb_tokens.slice(..).get_mapped_range();
    let toks_raw: &[GpuToken] = bytemuck::cast_slice(&mapped_range);

    let mut out = Vec::with_capacity(token_count_u32);
    for gt in &toks_raw[..token_count_u32.min(toks_raw.len())] {
        let kind = unsafe { std::mem::transmute::<u32, TokenKind>(gt.kind) };
        out.push(Token {
            kind,
            start: gt.start as usize,
            len: gt.len as usize,
        });
    }
    Ok(out)
}
