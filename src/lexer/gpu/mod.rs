use std::sync::OnceLock;

// src/lexer/gpu/mod.rs
use anyhow::{Result, anyhow};
use encase::ShaderType;

use crate::lexer::tables::{
    dfa::{N_STATES, StreamingDfa},
    tokens::TokenKind,
};

// New-style pass imports (trait + concrete passes)
mod buffers;
use buffers::GpuBuffers;

mod debug;

mod passes;
use passes::Pass;

#[derive(Debug, Clone)]
pub struct Token {
    pub kind: TokenKind,
    pub start: usize,
    pub len: usize,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(super) struct LexParams {
    pub n: u32,
    pub m: u32,           // (= n_states)
    pub identity_id: u32, // (= start_state)
    // Avoid uniform arrays (encase requires 16B array stride). Use 4 scalars.
    pub skip0: u32,
    pub skip1: u32,
    pub skip2: u32,
    pub skip3: u32,
}

fn u32_from_first_4(bytes: &[u8]) -> u32 {
    let mut le = [0u8; 4];
    le.copy_from_slice(&bytes[..4]);
    u32::from_le_bytes(le)
}

fn read_tokens_from_mapped(bytes: &[u8], count: usize) -> Vec<Token> {
    let mut out = Vec::with_capacity(count);
    for chunk in bytes
        .chunks_exact(std::mem::size_of::<GpuToken>())
        .take(count)
    {
        let (k, rest) = chunk.split_at(4);
        let (s, l) = rest.split_at(4);
        let kind_u32 = u32_from_first_4(k);
        let start = u32_from_first_4(s) as usize;
        let len = u32_from_first_4(l) as usize;
        let kind = unsafe { std::mem::transmute::<u32, TokenKind>(kind_u32) };
        out.push(Token { kind, start, len });
    }
    out
}

#[repr(C)]
#[derive(Clone, Copy)]
struct GpuToken {
    kind: u32,
    start: u32,
    len: u32,
}

pub struct GpuLexer {
    device: wgpu::Device,
    queue: wgpu::Queue,

    // Prebuilt passes (pipelines + reflected layouts)
    p_scan_inblock: passes::scan_inblock_inclusive_pass::ScanInblockInclusivePass,
    p_scan_blocks: passes::scan_block_summaries_inclusive::ScanBlockSummariesInclusivePass,
    p_apply_prefix: passes::apply_block_prefix_downsweep::ApplyBlockPrefixDownsweepPass,
    p_finalize: passes::finalize_boundaries_and_seed::FinalizeBoundariesAndSeedPass,

    // REPLACED: hierarchical sum for BOTH streams (ALL & KEPT) over uint2
    p_sum_inblock: passes::sum_inblock_pairs::SumInblockPairsPass,
    p_sum_blocks: passes::sum_scan_block_totals_inclusive::SumScanBlockTotalsInclusivePass,
    p_sum_apply:
        passes::sum_apply_block_prefix_downsweep_pairs::SumApplyBlockPrefixDownsweepPairsPass,

    p_compact_all: passes::compact_boundaries_all::CompactBoundariesAllPass,
    p_compact_kept: passes::compact_boundaries_kept::CompactBoundariesKeptPass,
    p_build: passes::build_tokens::BuildTokensPass,
}

impl GpuLexer {
    pub async fn new() -> Result<Self> {
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

        // Build once, reuse every call
        let p_scan_inblock =
            passes::scan_inblock_inclusive_pass::ScanInblockInclusivePass::new(&device)?;
        let p_scan_blocks =
            passes::scan_block_summaries_inclusive::ScanBlockSummariesInclusivePass::new(&device)?;
        let p_apply_prefix =
            passes::apply_block_prefix_downsweep::ApplyBlockPrefixDownsweepPass::new(&device)?;
        let p_finalize =
            passes::finalize_boundaries_and_seed::FinalizeBoundariesAndSeedPass::new(&device)?;

        // NEW hierarchical sum passes
        let p_sum_inblock = passes::sum_inblock_pairs::SumInblockPairsPass::new(&device)?;
        let p_sum_blocks =
            passes::sum_scan_block_totals_inclusive::SumScanBlockTotalsInclusivePass::new(&device)?;
        let p_sum_apply =
            passes::sum_apply_block_prefix_downsweep_pairs::SumApplyBlockPrefixDownsweepPairsPass::new(
                &device,
            )?;

        let p_compact_all = passes::compact_boundaries_all::CompactBoundariesAllPass::new(&device)?;
        let p_compact_kept =
            passes::compact_boundaries_kept::CompactBoundariesKeptPass::new(&device)?;
        let p_build = passes::build_tokens::BuildTokensPass::new(&device)?;

        Ok(Self {
            device,
            queue,
            p_scan_inblock,
            p_scan_blocks,
            p_apply_prefix,
            p_finalize,
            p_sum_inblock,
            p_sum_blocks,
            p_sum_apply,
            p_compact_all,
            p_compact_kept,
            p_build,
        })
    }

    pub async fn lex(&self, input: &str) -> Result<Vec<Token>> {
        let dfa = StreamingDfa::new();

        // PACKED next/emit
        // Old (u32 per entry) -> New: pack two u16 entries per u32 word.
        let total = 256 * N_STATES;
        let mut next_emit_u16: Vec<u16> = vec![0; total];
        for b in 0u32..=255 {
            for s in 0usize..N_STATES {
                let nx = dfa.next[s][b as usize];
                let next = nx.state as u16 & 0x7FFF;
                let emit = if nx.emit { 1u16 } else { 0u16 };
                let packed16 = (emit << 15) | next;
                next_emit_u16[(b as usize) * N_STATES + s] = packed16;
            }
        }
        // Pack two u16s per u32 word
        let mut next_emit_words: Vec<u32> = vec![0; (total + 1) / 2];
        for i in 0..total {
            let w = i >> 1;
            if (i & 1) == 0 {
                next_emit_words[w] |= next_emit_u16[i] as u32;
            } else {
                next_emit_words[w] |= (next_emit_u16[i] as u32) << 16;
            }
        }

        let token_map: Vec<u32> = dfa.token_map.into();

        let skip_kinds = [
            TokenKind::White as u32,
            TokenKind::LineComment as u32,
            TokenKind::BlockComment as u32,
            u32::MAX,
        ];

        let bytes_u32: Vec<u32> = input.bytes().map(|b| b as u32).collect();
        let n = bytes_u32.len() as u32;

        let bufs = GpuBuffers::new(
            &self.device,
            n,
            dfa.start as u32,
            &bytes_u32,
            &next_emit_words, // <— pass packed u32 words
            &token_map,
            skip_kinds,
        );

        // Encode passes (no Map pass)
        let mut enc = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-enc"),
            });

        // DFA state prefix (unchanged)
        self.p_scan_inblock.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.nb),
        );
        self.p_scan_blocks.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.nb),
        );
        self.p_apply_prefix.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.n),
        );

        // Boundary classification + seeds (unchanged)
        self.p_finalize.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.n),
        );

        // ---------- NEW: hierarchical sums for BOTH streams ----------
        self.p_sum_inblock.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.nb),
        );
        self.p_sum_blocks.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.nb),
        );
        self.p_sum_apply.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.n),
        );

        // Compaction + token build (unchanged)
        self.p_compact_all.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.n),
        );
        self.p_compact_kept.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.n),
        );
        self.p_build.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.n),
        );

        // --- step 1: read token_count only
        let rb_count = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb_count"),
            size: 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        enc.copy_buffer_to_buffer(&bufs.token_count, 0, &rb_count, 0, 4);
        self.queue.submit(Some(enc.finish()));

        rb_count.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        let _ = self.device.poll(wgpu::PollType::Wait);
        let count_bytes = rb_count.slice(..).get_mapped_range();
        let token_count_u32 = u32_from_first_4(&count_bytes) as usize;
        drop(count_bytes);

        // --- step 2: copy only the produced tokens
        let needed_bytes = (token_count_u32 as u64) * (std::mem::size_of::<GpuToken>() as u64);
        let rb_tokens = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb_tokens"),
            size: needed_bytes.max(1), // zero-sized buffers are invalid
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });

        let mut enc2 = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-enc-rb"),
            });
        enc2.copy_buffer_to_buffer(&bufs.tokens_out, 0, &rb_tokens, 0, needed_bytes);
        self.queue.submit(Some(enc2.finish()));

        rb_tokens.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        let _ = self.device.poll(wgpu::PollType::Wait);
        let mapped = rb_tokens.slice(..).get_mapped_range();
        Ok(read_tokens_from_mapped(&mapped, token_count_u32))
    }
}

// Optional convenience wrapper that reuses a global context:
static GPU_LEXER: OnceLock<GpuLexer> = OnceLock::new();

pub async fn lex_on_gpu(input: &str) -> Result<Vec<Token>> {
    let lexer = GPU_LEXER.get_or_init(|| pollster::block_on(GpuLexer::new()).expect("GPU init"));
    lexer.lex(input).await
}
