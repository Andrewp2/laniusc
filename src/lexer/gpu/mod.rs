use std::sync::OnceLock;

use anyhow::{Result, anyhow};
use buffers::GpuBuffers;
use encase::ShaderType;

use crate::{
    gpu::{passes_core::InputElements, timer::GpuTimer},
    lexer::tables::{compact::load_compact_tables_from_bytes, dfa::N_STATES, tokens::TokenKind},
};

mod buffers;
mod debug;
mod passes;

pub use crate::gpu::{debug::DebugBuffer, passes_core::Pass};

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
    pub m: u32,
    pub start_state: u32,
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

fn env_flag_true(var: &str, default: bool) -> bool {
    std::env::var(var)
        .map(|v| !(v == "0" || v.eq_ignore_ascii_case("false")))
        .unwrap_or(default)
}

fn readback_enabled() -> bool {
    env_flag_true("LANIUS_READBACK", true) && env_flag_true("PERF_ONE_READBACK", true)
}

fn read_tokens_from_mapped(bytes: &[u8], count: usize) -> Vec<Token> {
    use std::{mem::size_of, ptr::read_unaligned};

    let instant = std::time::Instant::now();
    let mut out = Vec::with_capacity(count);
    let mut p = bytes.as_ptr();
    let stride = size_of::<u32>() * 3;

    for _ in 0..count {
        let kind_u32 = unsafe { read_unaligned(p as *const u32) };
        let start = unsafe { read_unaligned(p.add(4) as *const u32) } as usize;
        let len = unsafe { read_unaligned(p.add(8) as *const u32) } as usize;

        let kind = unsafe { std::mem::transmute::<u32, TokenKind>(kind_u32) };
        out.push(Token { kind, start, len });

        p = unsafe { p.add(stride) };
    }
    eprintln!(
        "[read_tokens_from_mapped] {} tokens in {:.3} ms",
        count,
        instant.elapsed().as_nanos() as f64 / 1.0e6
    );
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

    p_scan_inblock: passes::scan_inblock_inclusive_pass::ScanInblockInclusivePass,
    p_scan_blocks: passes::scan_block_summaries_inclusive::ScanBlockSummariesInclusivePass,
    p_apply_prefix: passes::apply_block_prefix_downsweep::ApplyBlockPrefixDownsweepPass,
    p_finalize: passes::finalize_boundaries_and_seed::FinalizeBoundariesAndSeedPass,

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
            _ => wgpu::Backends::all(),
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
            .await
            .map_err(|_| anyhow!("no adapter"))?;

        let mut limits = wgpu::Limits::defaults();
        // ... why are my comments missing here...
        // they were explaining why we chose these values from the web3d survey...
        limits.max_storage_buffers_per_shader_stage = 10;
        limits.max_storage_buffer_binding_size = 2_147_483_644;
        limits.max_buffer_size = 2_147_483_644;
        let (device, queue) = adapter
            .request_device(&wgpu::DeviceDescriptor {
                label: Some("laniusc_lexer"),
                required_features: wgpu::Features::TIMESTAMP_QUERY,
                required_limits: limits,
                memory_hints: wgpu::MemoryHints::default(),
                trace: wgpu::Trace::default(),
            })
            .await?;

        let adapter_features = adapter.features();
        let want_timers = std::env::var("LANIUS_GPU_TIMING")
            .map(|v| v != "0" && !v.eq_ignore_ascii_case("false"))
            .unwrap_or(false);

        let timers_supported =
            want_timers && adapter_features.contains(wgpu::Features::TIMESTAMP_QUERY);

        let p_scan_inblock =
            passes::scan_inblock_inclusive_pass::ScanInblockInclusivePass::new(&device)?;
        let p_scan_blocks =
            passes::scan_block_summaries_inclusive::ScanBlockSummariesInclusivePass::new(&device)?;
        let p_apply_prefix =
            passes::apply_block_prefix_downsweep::ApplyBlockPrefixDownsweepPass::new(&device)?;
        let p_finalize =
            passes::finalize_boundaries_and_seed::FinalizeBoundariesAndSeedPass::new(&device)?;

        let p_sum_inblock = passes::sum_inblock_pairs::SumInblockPairsPass::new(&device)?;
        let p_sum_blocks =
            passes::sum_scan_block_totals_inclusive::SumScanBlockTotalsInclusivePass::new(&device)?;
        let p_sum_apply = passes::sum_apply_block_prefix_downsweep_pairs::SumApplyBlockPrefixDownsweepPairsPass::new(&device)?;

        let p_compact_all = passes::compact_boundaries_all::CompactBoundariesAllPass::new(&device)?;
        let p_compact_kept =
            passes::compact_boundaries_kept::CompactBoundariesKeptPass::new(&device)?;
        let p_retag = passes::retag_calls_and_arrays::RetagCallsAndArraysPass::new(&device)?;
        let p_build = passes::build_tokens::BuildTokensPass::new(&device)?;

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
        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.start_graphics_debugger_capture()
        };

        const COMPACT_BIN: &[u8] = include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tables/lexer_tables.bin"
        ));

        let (n_states_from_file, next_emit_words, token_map) =
            load_compact_tables_from_bytes(COMPACT_BIN)
                .map_err(|e| anyhow!("failed to parse compact lexer_tables.bin: {e}"))?;

        if n_states_from_file != N_STATES {
            return Err(anyhow!(
                "compact table has n_states={} but shaders expect N_STATES={}",
                n_states_from_file,
                N_STATES
            ));
        }

        let start_state = 0u32;

        let input_bytes: &[u8] = input.as_bytes();
        let n = input_bytes.len() as u32;

        let skip_kinds = [
            TokenKind::White as u32,
            TokenKind::LineComment as u32,
            TokenKind::BlockComment as u32,
            u32::MAX,
        ];

        let bufs = GpuBuffers::new(
            &self.device,
            n,
            start_state,
            input_bytes,
            &next_emit_words,
            &token_map,
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

        let mut enc = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-enc"),
            });

        if let Some(t) = maybe_timer.as_mut() {
            t.reset();
            t.stamp(&mut enc, "BEGIN");
        }

        self.p_scan_inblock.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            InputElements::Elements1D(bufs.nb_dfa),
            &mut maybe_timer.as_mut(),
        )?;
        self.p_scan_blocks.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            InputElements::Elements1D(bufs.nb_dfa),
            &mut maybe_timer.as_mut(),
        )?;
        self.p_apply_prefix.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            InputElements::Elements1D(bufs.n),
            &mut maybe_timer.as_mut(),
        )?;

        self.p_finalize.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            InputElements::Elements1D(bufs.n),
            &mut maybe_timer.as_mut(),
        )?;

        self.p_sum_inblock.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            InputElements::Elements1D(bufs.n),
            &mut maybe_timer.as_mut(),
        )?;
        self.p_sum_blocks.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            InputElements::Elements1D(bufs.nb_sum),
            &mut maybe_timer.as_mut(),
        )?;
        self.p_sum_apply.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            InputElements::Elements1D(bufs.n),
            &mut maybe_timer.as_mut(),
        )?;

        self.p_compact_all.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            InputElements::Elements1D(bufs.n),
            &mut maybe_timer.as_mut(),
        )?;
        self.p_compact_kept.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            InputElements::Elements1D(bufs.n),
            &mut maybe_timer.as_mut(),
        )?;

        self.p_retag.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            InputElements::Elements1D(bufs.n),
            &mut maybe_timer.as_mut(),
        )?;
        self.p_build.record_pass(
            &self.device,
            &mut enc,
            &bufs,
            InputElements::Elements1D(bufs.n),
            &mut maybe_timer.as_mut(),
        )?;

        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut enc, "before copy count");
        }

        let readback_tokens_count = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb_count"),
            size: 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });

        enc.copy_buffer_to_buffer(&bufs.token_count, 0, &readback_tokens_count, 0, 4);

        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut enc, "after copy count");
            timer.resolve(&mut enc);
        }

        self.device.push_error_scope(wgpu::ErrorFilter::Validation);
        self.queue.submit(Some(enc.finish()));
        if let Some(err) = pollster::block_on(self.device.pop_error_scope()) {
            eprintln!("[wgpu submit] validation while submitting lex batch: {err:#?}");
        }

        readback_tokens_count
            .slice(..)
            .map_async(wgpu::MapMode::Read, |_| {});
        let _ = self.device.poll(wgpu::PollType::Wait);
        let count_bytes = readback_tokens_count.slice(..).get_mapped_range();
        let token_count_u32 = u32_from_first_4(&count_bytes) as usize;
        drop(count_bytes);
        readback_tokens_count.unmap();
        if token_count_u32 == 0 {
            return Ok(Vec::new());
        }

        if !readback_enabled() {
            if let Some(timer) = maybe_timer {
                if let Some(vals) = timer.try_read(&self.device) {
                    if !vals.is_empty() {
                        let period_ns = timer.period_ns() as f64;
                        let t0 = vals[0].1;
                        let mut prev = t0;
                        for (label, t) in vals {
                            let dt_ms = ((t - prev) as f64 * period_ns) / 1.0e6;
                            let total_ms = ((t - t0) as f64 * period_ns) / 1.0e6;
                            if dt_ms < 0.5 {
                                continue;
                            }
                            println!(
                                "[gpu_timer] {label}: {:.3}ms (total {:.3}ms)",
                                dt_ms, total_ms
                            );
                            prev = t;
                        }
                    }
                }
            }

            return Ok(vec![
                Token {
                    kind: TokenKind::White,
                    start: 0,
                    len: 0
                };
                token_count_u32
            ]);
        }

        let need_bytes = (token_count_u32 * std::mem::size_of::<GpuToken>()) as u64;

        let readback_tokens_buffer = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb_tokens_partial"),
            size: need_bytes,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let mut encoder_two = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-enc-readback-tokens"),
            });
        encoder_two.copy_buffer_to_buffer(
            &bufs.tokens_out,
            0,
            &readback_tokens_buffer,
            0,
            need_bytes,
        );
        self.queue.submit(Some(encoder_two.finish()));

        readback_tokens_buffer
            .slice(0..need_bytes)
            .map_async(wgpu::MapMode::Read, |_| {});
        let _ = self.device.poll(wgpu::PollType::Wait);

        let mapped = readback_tokens_buffer
            .slice(0..need_bytes)
            .get_mapped_range();
        let tokens = read_tokens_from_mapped(&mapped, token_count_u32);
        drop(mapped);
        readback_tokens_buffer.unmap();

        if let Some(timer) = maybe_timer {
            if let Some(vals) = timer.try_read(&self.device) {
                if !vals.is_empty() {
                    let period_ns = timer.period_ns() as f64;
                    let t0 = vals[0].1;
                    let mut prev = t0;

                    for (label, t) in vals {
                        let dt_ms = ((t - prev) as f64 * period_ns) / 1.0e6;
                        let total_ms = ((t - t0) as f64 * period_ns) / 1.0e6;
                        if dt_ms < 0.5 {
                            continue;
                        }
                        println!(
                            "[gpu_timer] {label}: {:.3}ms (total {:.3}ms)",
                            dt_ms, total_ms
                        );
                        prev = t;
                    }
                }
            }
        }

        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.stop_graphics_debugger_capture()
        };

        Ok(tokens)
    }
}

static GPU_LEXER: OnceLock<GpuLexer> = OnceLock::new();

pub async fn lex_on_gpu(input: &str) -> Result<Vec<Token>> {
    let lexer = GPU_LEXER.get_or_init(|| pollster::block_on(GpuLexer::new()).expect("GPU init"));
    lexer.lex(input).await
}
