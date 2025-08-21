//! GPU lexer driver (device init, pass orchestration, and readback).

use std::sync::{Arc, OnceLock};

use anyhow::{Result, anyhow};

use super::passes;
use crate::{
    gpu::{
        passes_core::InputElements,
        timer::{GpuTimer, MINIMUM_TIME_TO_NOT_ELIDE_MS},
    },
    lexer::{
        gpu::{
            Pass,
            buffers::GpuBuffers,
            types::{GpuToken, Token},
            util::{read_tokens_from_mapped, readback_enabled, u32_from_first_4},
        },
        tables::{compact::load_compact_tables_from_bytes, tokens::TokenKind},
    },
};

pub struct GpuLexer {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    timers_supported: bool,

    // Precomputed tables loaded once at device init
    next_emit_words: Vec<u32>,
    next_u8_packed: Vec<u32>,
    token_map: Vec<u32>,

    p_dfa_01_scan_inblock: passes::dfa_01_scan_inblock::Dfa01ScanInblockPass,
    p_dfa_02_scan_block_summaries: passes::dfa_02_scan_block_summaries::Dfa02ScanBlockSummariesPass,
    p_dfa_03_apply_block_prefix: passes::dfa_03_apply_block_prefix::Dfa03ApplyBlockPrefixPass,
    p_boundary_finalize_and_seed: passes::boundary_finalize_and_seed::BoundaryFinalizeAndSeedPass,

    p_pair_01_sum_inblock: passes::pair_01_sum_inblock::Pair01SumInblockPass,
    p_pair_02_scan_block_totals: passes::pair_02_scan_block_totals::Pair02ScanBlockTotalsPass,
    p_pair_03_apply_block_prefix: passes::pair_03_apply_block_prefix::Pair03ApplyBlockPrefixPass,

    p_compact_boundaries_all: passes::compact_boundaries_all::CompactBoundariesAllPass,
    p_compact_boundaries_kept: passes::compact_boundaries_kept::CompactBoundariesKeptPass,
    p_retag_calls_and_arrays: passes::retag_calls_and_arrays::RetagCallsAndArraysPass,
    p_tokens_build: passes::tokens_build::TokensBuildPass,
}

impl GpuLexer {
    pub async fn new() -> Result<Self> {
        let ctx = crate::gpu::device::global();
        let device = Arc::clone(&ctx.device);
        let queue = Arc::clone(&ctx.queue);
        let timers_supported = ctx.timers_supported;

        // Load compact DFA tables and build packed-next table once at init.
        const COMPACT_BIN: &[u8] = include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tables/lexer_tables.bin"
        ));

        let (n_states_from_file, next_emit_words, token_map) =
            load_compact_tables_from_bytes(COMPACT_BIN)
                .map_err(|e| anyhow!("failed to parse compact lexer_tables.bin: {e}"))?;

        // Ensure shader-compiled N_STATES matches table N_STATES.
        debug_assert_eq!(
            n_states_from_file,
            crate::lexer::tables::dfa::N_STATES,
            "shader N_STATES ({}) != tables n_states ({})",
            crate::lexer::tables::dfa::N_STATES,
            n_states_from_file
        );

        // Use dynamic n_states from compact tables for data buffers.
        debug_assert_eq!(
            token_map.len(),
            n_states_from_file,
            "token_map len != n_states"
        );
        let expected_words = ((256 * n_states_from_file) + 1) / 2;
        debug_assert_eq!(
            next_emit_words.len(),
            expected_words,
            "next_emit_words len mismatch (got {}, expect {})",
            next_emit_words.len(),
            expected_words
        );

        // Build packed-next (u8) table for DFA passes: layout [pack4][byte]
        let n_states = n_states_from_file;
        let n_pack4 = (n_states + 3) / 4;
        let mut next_u8_packed: Vec<u32> = vec![0; 256 * n_pack4];
        let read_u16 = |i: usize| -> u16 {
            let w = next_emit_words[i >> 1];
            if (i & 1) == 0 {
                (w & 0xFFFF) as u16
            } else {
                (w >> 16) as u16
            }
        };
        for b in 0..256usize {
            for p in 0..n_pack4 {
                let s0 = p * 4 + 0;
                let s1 = p * 4 + 1;
                let s2 = p * 4 + 2;
                let s3 = p * 4 + 3;
                let v0 = if s0 < n_states {
                    (read_u16(b * n_states + s0) & 0x7FFF) as u32
                } else {
                    s0 as u32
                };
                let v1 = if s1 < n_states {
                    (read_u16(b * n_states + s1) & 0x7FFF) as u32
                } else {
                    s1 as u32
                };
                let v2 = if s2 < n_states {
                    (read_u16(b * n_states + s2) & 0x7FFF) as u32
                } else {
                    s2 as u32
                };
                let v3 = if s3 < n_states {
                    (read_u16(b * n_states + s3) & 0x7FFF) as u32
                } else {
                    s3 as u32
                };
                next_u8_packed[p * 256 + b] =
                    (v0 & 0xFF) | ((v1 & 0xFF) << 8) | ((v2 & 0xFF) << 16) | ((v3 & 0xFF) << 24);
            }
        }

        let p_dfa_01_scan_inblock =
            passes::dfa_01_scan_inblock::Dfa01ScanInblockPass::new(&device)?;
        let p_dfa_02_scan_block_summaries =
            passes::dfa_02_scan_block_summaries::Dfa02ScanBlockSummariesPass::new(&device)?;
        let p_dfa_03_apply_block_prefix =
            passes::dfa_03_apply_block_prefix::Dfa03ApplyBlockPrefixPass::new(&device)?;
        let p_boundary_finalize_and_seed =
            passes::boundary_finalize_and_seed::BoundaryFinalizeAndSeedPass::new(&device)?;

        let p_pair_01_sum_inblock =
            passes::pair_01_sum_inblock::Pair01SumInblockPass::new(&device)?;
        let p_pair_02_scan_block_totals =
            passes::pair_02_scan_block_totals::Pair02ScanBlockTotalsPass::new(&device)?;
        let p_pair_03_apply_block_prefix =
            passes::pair_03_apply_block_prefix::Pair03ApplyBlockPrefixPass::new(&device)?;

        let p_compact_boundaries_all =
            passes::compact_boundaries_all::CompactBoundariesAllPass::new(&device)?;
        let p_compact_boundaries_kept =
            passes::compact_boundaries_kept::CompactBoundariesKeptPass::new(&device)?;
        let p_retag_calls_and_arrays =
            passes::retag_calls_and_arrays::RetagCallsAndArraysPass::new(&device)?;
        let p_tokens_build = passes::tokens_build::TokensBuildPass::new(&device)?;

        Ok(Self {
            device,
            queue,
            timers_supported,
            next_emit_words,
            next_u8_packed,
            token_map,
            p_dfa_01_scan_inblock,
            p_dfa_02_scan_block_summaries,
            p_dfa_03_apply_block_prefix,
            p_boundary_finalize_and_seed,
            p_pair_01_sum_inblock,
            p_pair_02_scan_block_totals,
            p_pair_03_apply_block_prefix,
            p_compact_boundaries_all,
            p_compact_boundaries_kept,
            p_retag_calls_and_arrays,
            p_tokens_build,
        })
    }

    pub async fn lex(&self, input: &str) -> Result<Vec<Token>> {
        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.start_graphics_debugger_capture()
        };

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
            &self.next_emit_words,
            &self.next_u8_packed,
            &self.token_map,
            skip_kinds,
        );

        let use_scopes = std::env::var("LANIUS_VALIDATION_SCOPES")
            .map(|v| v != "0" && !v.eq_ignore_ascii_case("false"))
            .unwrap_or(false); // 🤖

        let timers_on = self.timers_supported
            && std::env::var("LANIUS_GPU_TIMING")
                .map(|v| v != "0" && !v.eq_ignore_ascii_case("false"))
                .unwrap_or(false);

        let mut maybe_timer = if timers_on {
            Some(GpuTimer::new(&self.device, &self.queue, 128))
        } else {
            None
        };

        // Optional debug capture handle that all passes can use
        #[cfg(feature = "gpu-debug")]
        let mut debug_output = crate::lexer::gpu::debug::DebugOutput::default();
        #[cfg(feature = "gpu-debug")]
        let maybe_dbg: Option<&mut crate::lexer::gpu::debug::DebugOutput> = Some(&mut debug_output);
        #[cfg(not(feature = "gpu-debug"))]
        let maybe_dbg: Option<&mut crate::lexer::gpu::debug::DebugOutput> = None;

        let mut enc = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-enc"),
            });

        if let Some(t) = maybe_timer.as_mut() {
            t.reset();
            t.stamp(&mut enc, "BEGIN");
        }

        // Build a single shared PassContext and run all passes with it.
        let mut timer_ref = maybe_timer.as_mut();
        let mut dbg_ref = maybe_dbg;
        let mut ctx = crate::gpu::passes_core::PassContext {
            device: &self.device,
            encoder: &mut enc,
            buffers: &bufs,
            maybe_timer: &mut timer_ref,
            maybe_dbg: &mut dbg_ref,
        };

        self.p_dfa_01_scan_inblock
            .record_pass(&mut ctx, InputElements::Elements1D(bufs.n))?;
        self.p_dfa_02_scan_block_summaries
            .record_pass(&mut ctx, InputElements::Elements1D(bufs.nb_dfa))?;
        self.p_dfa_03_apply_block_prefix
            .record_pass(&mut ctx, InputElements::Elements1D(bufs.n))?;
        self.p_boundary_finalize_and_seed
            .record_pass(&mut ctx, InputElements::Elements1D(bufs.n))?;
        self.p_pair_01_sum_inblock
            .record_pass(&mut ctx, InputElements::Elements1D(bufs.n))?;
        self.p_pair_02_scan_block_totals
            .record_pass(&mut ctx, InputElements::Elements1D(bufs.nb_sum))?;
        self.p_pair_03_apply_block_prefix
            .record_pass(&mut ctx, InputElements::Elements1D(bufs.n))?;

        self.p_compact_boundaries_all
            .record_pass(&mut ctx, InputElements::Elements1D(bufs.n))?;
        self.p_compact_boundaries_kept
            .record_pass(&mut ctx, InputElements::Elements1D(bufs.n))?;

        self.p_retag_calls_and_arrays
            .record_pass(&mut ctx, InputElements::Elements1D(bufs.n))?;
        self.p_tokens_build
            .record_pass(&mut ctx, InputElements::Elements1D(bufs.n))?;

        let rb_enabled = readback_enabled();

        // Submit work, optionally also copy back token count when readback is enabled.
        let token_count_u32 = if rb_enabled {
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

            if use_scopes {
                self.device.push_error_scope(wgpu::ErrorFilter::Validation);
            } // 🤖
            self.queue.submit(Some(enc.finish()));
            if use_scopes {
                if let Some(err) = pollster::block_on(self.device.pop_error_scope()) {
                    eprintln!("[wgpu submit] validation while submitting lex batch: {err:#?}"); // 🤖
                }
            }

            readback_tokens_count
                .slice(..)
                .map_async(wgpu::MapMode::Read, |_| {});
            let _ = self.device.poll(wgpu::PollType::Wait);
            let count_bytes = readback_tokens_count.slice(..).get_mapped_range();
            let token_count_u32 = u32_from_first_4(&count_bytes) as usize;
            drop(count_bytes);
            readback_tokens_count.unmap();
            debug_assert!(
                n == 0 || token_count_u32 <= (n as usize),
                "token_count unexpectedly exceeds n (count={}, n={})",
                token_count_u32,
                n
            );
            if token_count_u32 == 0 {
                return Ok(Vec::new());
            }
            token_count_u32
        } else {
            if let Some(timer) = maybe_timer.as_mut() {
                // No count copy; still resolve timer queries for printing later.
                timer.resolve(&mut enc);
            }
            if use_scopes {
                self.device.push_error_scope(wgpu::ErrorFilter::Validation);
            } // 🤖
            self.queue.submit(Some(enc.finish()));
            if use_scopes {
                if let Some(err) = pollster::block_on(self.device.pop_error_scope()) {
                    eprintln!("[wgpu submit] validation while submitting lex batch: {err:#?}"); // 🤖
                }
            }
            // We intentionally skip token-count readback when readback is disabled.
            0usize
        };

        // Optional debug sanity checks
        #[cfg(feature = "gpu-debug")]
        {
            super::debug_checks::run_debug_sanity_checks(&self.device, input, &debug_output, n);
        }

        if !rb_enabled {
            if let Some(timer) = maybe_timer
                && let Some(vals) = timer.try_read(&self.device)
                && !vals.is_empty()
            {
                let period_ns = timer.period_ns() as f64;
                let t0 = vals[0].1;
                let mut prev = t0;
                for (label, t) in vals {
                    let dt_ms = ((t - prev) as f64 * period_ns) / 1.0e6;
                    let total_ms = ((t - t0) as f64 * period_ns) / 1.0e6;
                    if dt_ms < MINIMUM_TIME_TO_NOT_ELIDE_MS {
                        continue;
                    }
                    println!("[gpu_timer] {label}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
                    prev = t;
                }
            }

            // No token count; return empty vector to avoid any token readback.
            return Ok(Vec::new());
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

        if let Some(timer) = maybe_timer
            && let Some(vals) = timer.try_read(&self.device)
            && !vals.is_empty()
        {
            let period_ns = timer.period_ns() as f64;
            let t0 = vals[0].1;
            let mut prev = t0;
            for (label, t) in vals {
                let dt_ms = ((t - prev) as f64 * period_ns) / 1.0e6;
                let total_ms = ((t - t0) as f64 * period_ns) / 1.0e6;
                if dt_ms < MINIMUM_TIME_TO_NOT_ELIDE_MS {
                    continue;
                }
                println!("[gpu_timer] {label}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
                prev = t;
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
