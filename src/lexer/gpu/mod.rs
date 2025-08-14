use std::{sync::OnceLock, time::Instant};

// src/lexer/gpu/mod.rs
use anyhow::{Result, anyhow};
use buffers::GpuBuffers;
use encase::ShaderType;
use passes::Pass;

use crate::lexer::{
    gpu::timer::GpuTimer,
    tables::{compact::load_compact_tables_from_bytes, dfa::N_STATES, tokens::TokenKind},
};

// New-style pass imports (trait + concrete passes)
mod buffers;
mod debug;
mod passes;
mod timer;

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
    pub start_state: u32, // (= start_state)
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
    use std::{mem::size_of, ptr::read_unaligned};

    let mut out = Vec::with_capacity(count);
    let mut p = bytes.as_ptr();
    let stride = size_of::<u32>() * 3; // kind,start,len = 12 bytes

    for _ in 0..count {
        // SAFETY: we ensured the mapped slice is at least count*stride bytes long.
        // read_unaligned handles any alignment.
        let kind_u32 = unsafe { read_unaligned(p as *const u32) };
        let start = unsafe { read_unaligned(p.add(4) as *const u32) } as usize;
        let len = unsafe { read_unaligned(p.add(8) as *const u32) } as usize;

        let kind = unsafe { std::mem::transmute::<u32, TokenKind>(kind_u32) };
        out.push(Token { kind, start, len });

        // advance
        p = unsafe { p.add(stride) };
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

    timers_supported: bool,

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
    p_retag: passes::retag_calls_and_arrays::RetagCallsAndArraysPass,
    p_build: passes::build_tokens::BuildTokensPass,
}

impl GpuLexer {
    pub async fn new() -> Result<Self> {
        let backends = match std::env::var("LANIUS_BACKEND")
            .unwrap_or_else(|_| "auto".into())
            .to_ascii_lowercase()
            .as_str()
        {
            "vulkan" | "vk" => wgpu::Backends::VULKAN,
            "dx12" => wgpu::Backends::DX12,
            "metal" | "mtl" => wgpu::Backends::METAL,
            "gl" => wgpu::Backends::GL,
            _ => wgpu::Backends::all(), // auto (default)
        };
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            backends,
            ..Default::default()
        });
        let adapter = instance
            .request_adapter(&wgpu::RequestAdapterOptions {
                power_preference: wgpu::PowerPreference::HighPerformance,
                compatible_surface: None,
                force_fallback_adapter: false,
            })
            .await.map_err(|_| anyhow!("no adapter"))?;

        let mut limits = wgpu::Limits::defaults();
        // ... why are my comments missing here...
        // they were explaining why we chose these values from the web3d survey...
        limits.max_storage_buffers_per_shader_stage = 10;
        limits.max_storage_buffer_binding_size = 2_147_483_644;
        limits.max_buffer_size = 2_147_483_644;

        let adapter_features = adapter.features();
        let want_timers = std::env::var("LANIUS_GPU_TIMING")
            .map(|v| v != "0" && !v.eq_ignore_ascii_case("false"))
            .unwrap_or(false);

        let timers_supported =
            want_timers && adapter_features.contains(wgpu::Features::TIMESTAMP_QUERY);

        let mut required_features =
            wgpu::Features::empty() | wgpu::Features::SPIRV_SHADER_PASSTHROUGH;
        if timers_supported {
            required_features |= wgpu::Features::TIMESTAMP_QUERY
                | wgpu::Features::TIMESTAMP_QUERY_INSIDE_ENCODERS
                | wgpu::Features::TIMESTAMP_QUERY_INSIDE_PASSES;
        }

        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor {
                label: Some("Lanius Lexer Device"),
                required_features,
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
        let p_retag = passes::retag_calls_and_arrays::RetagCallsAndArraysPass::new(&device)?;

        Ok(Self {
            device,
            queue,
            timers_supported,
            p_scan_inblock,
            p_scan_blocks,
            p_apply_prefix,
            p_finalize,
            p_sum_inblock,
            p_sum_blocks,
            p_sum_apply,
            p_compact_all,
            p_compact_kept,
            p_retag,
            p_build,
        })
    }

    pub async fn lex(&self, input: &str) -> Result<Vec<Token>> {
        let wall_all = Instant::now();
        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.start_graphics_debugger_capture()
        };
        // ---- load compact DFA tables that were committed in the repo
        const COMPACT_BIN: &[u8] = include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tables/lexer_tables.bin"
        ));

        let (n_states_from_file, next_emit_words, token_map) =
            load_compact_tables_from_bytes(COMPACT_BIN)
                .map_err(|e| anyhow!("failed to parse compact lexer_tables.bin: {e}"))?;

        // sanity: shader kernels are compiled with a fixed N_STATES
        if n_states_from_file != N_STATES {
            return Err(anyhow!(
                "compact table has n_states={} but shaders expect N_STATES={}",
                n_states_from_file,
                N_STATES
            ));
        }

        // start state is 0 in our enum layout
        let start_state = 0u32;

        // -------- prepare per-input buffers
        // let bytes_u32: Vec<u32> = input.bytes().map(|b| b as u32).collect();
        // let n = bytes_u32.len() as u32;
        let input_bytes: &[u8] = input.as_bytes();
        let n = input_bytes.len() as u32;

        let skip_kinds = [
            TokenKind::White as u32,
            TokenKind::LineComment as u32,
            TokenKind::BlockComment as u32,
            u32::MAX,
        ];

        let wall_setup = Instant::now();
        let bufs = GpuBuffers::new(
            &self.device,
            n,
            start_state,
            input_bytes,
            &next_emit_words, // <— from the compact file
            &token_map,       // <— from the compact file
            skip_kinds,
        );

        let timers_on = self.timers_supported
            && std::env::var("LANIUS_GPU_TIMING")
                .map(|v| v != "0" && !v.eq_ignore_ascii_case("false"))
                .unwrap_or(false);

        let mut maybe_timer = if timers_on {
            Some(GpuTimer::new(&self.device, &self.queue, 128))
        } else {
            None
        };

        let wall_encode = Instant::now();
        let mut enc = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-enc"),
            });

        if let Some(t) = maybe_timer.as_mut() {
            t.reset();
            t.stamp(&mut enc, "BEGIN");
        }

        // DFA state prefix (unchanged)
        self.p_scan_inblock.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.nb),
            maybe_timer.as_mut(),
        );
        self.p_scan_blocks.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.nb),
            maybe_timer.as_mut(),
        );
        self.p_apply_prefix.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.n),
            maybe_timer.as_mut(),
        );

        // Boundary classification + seeds (unchanged)
        self.p_finalize.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.n),
            maybe_timer.as_mut(),
        );

        // ---------- NEW: hierarchical sums for BOTH streams ----------
        self.p_sum_inblock.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.nb),
            maybe_timer.as_mut(),
        );
        self.p_sum_blocks.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.nb),
            maybe_timer.as_mut(),
        );
        self.p_sum_apply.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.n),
            maybe_timer.as_mut(),
        );

        // Compaction + token build (unchanged)
        self.p_compact_all.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.n),
            maybe_timer.as_mut(),
        );
        self.p_compact_kept.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.n),
            maybe_timer.as_mut(),
        );
        // Compaction + token build (unchanged)
        self.p_retag.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.n),
            maybe_timer.as_mut(),
        );
        self.p_build.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            &mut debug::DebugOutput::default(),
            passes::InputElements::Elements1D(bufs.n),
            maybe_timer.as_mut(),
        );

        // ----- READBACK (always partial) -----
        let rb_count = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb_count"),
            size: 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });

        // 1) Copy just the count and submit
        if let Some(t) = maybe_timer.as_mut() {
            t.stamp(&mut enc, "BEFORE_COPY_COUNT");
        }
        enc.copy_buffer_to_buffer(&bufs.token_count, 0, &rb_count, 0, 4);
        if let Some(t) = maybe_timer.as_mut() {
            t.stamp(&mut enc, "AFTER_COPY_COUNT");
            t.resolve(&mut enc);
        }
        self.queue.submit(Some(enc.finish()));

        // 2) Map count on CPU, compute needed bytes
        rb_count.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        let _ = self.device.poll(wgpu::PollType::Wait);
        let count_bytes = rb_count.slice(..).get_mapped_range();
        let token_count_u32 = u32_from_first_4(&count_bytes) as usize;
        drop(count_bytes);
        rb_count.unmap();

        let need_bytes = (token_count_u32 * std::mem::size_of::<GpuToken>()) as u64;

        // 3) Copy exactly the used range of tokens, submit, map, decode
        let rb_tokens = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb_tokens_partial"),
            size: need_bytes,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let mut enc2 = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-enc-readback-tokens"),
            });
        enc2.copy_buffer_to_buffer(&bufs.tokens_out, 0, &rb_tokens, 0, need_bytes);
        self.queue.submit(Some(enc2.finish()));

        rb_tokens
            .slice(0..need_bytes)
            .map_async(wgpu::MapMode::Read, |_| {});
        let _ = self.device.poll(wgpu::PollType::Wait);

        let mapped = rb_tokens.slice(0..need_bytes).get_mapped_range();
        let tokens = read_tokens_from_mapped(&mapped, token_count_u32);
        drop(mapped);
        rb_tokens.unmap();

        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.stop_graphics_debugger_capture()
        };

        Ok(tokens)
    }
}

// Optional convenience wrapper that reuses a global context:
static GPU_LEXER: OnceLock<GpuLexer> = OnceLock::new();

pub async fn lex_on_gpu(input: &str) -> Result<Vec<Token>> {
    let lexer = GPU_LEXER.get_or_init(|| pollster::block_on(GpuLexer::new()).expect("GPU init"));
    lexer.lex(input).await
}
