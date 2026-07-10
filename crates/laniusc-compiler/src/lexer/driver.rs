//! GPU lexer driver (device init, pass orchestration, and readback).

use std::sync::Arc;

use anyhow::{Result, anyhow};
use log::warn;

mod global;
mod inputs;
mod readback;
mod timing;

pub use global::{get_global_lexer, lex_on_gpu, try_global_lexer};
use readback::read_resident_tokens;
use timing::{HostCompileTimer, print_timer_trace};

use super::buffers;
use crate::{
    gpu::{
        buffers::LaniusBuffer,
        timer::{GpuTimer, MINIMUM_TIME_TO_NOT_ELIDE_MS},
    },
    lexer::{
        passes::{LexerPasses, record_all_passes},
        tables::{compact::load_compact_tables_from_bytes, tokens::TokenKind},
        types::{GpuToken, Token},
        util::{read_tokens_from_mapped, readback_enabled, u32_from_first_4},
    },
};

/// GPU lexer instance with loaded DFA tables, shader passes, and resident buffers.
///
/// One instance can be reused across lexing calls. Resident buffers are resized
/// only when the input capacity, block count, or source-pack file capacity
/// changes.
pub struct GpuLexer {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    timers_supported: bool,

    // Precomputed tables loaded once at device init
    next_emit_words: Vec<u32>,
    next_u8_packed: Vec<u32>,
    token_map: Vec<u32>,

    passes: LexerPasses,

    // Persistent buffers reused across lex() calls
    buffers: std::sync::Mutex<Option<buffers::GpuBuffers>>,
    // Bind group cache to avoid recreating them every dispatch
    bg_cache: std::sync::Mutex<crate::gpu::passes_core::BindGroupCache>,
}

/// Cloned buffer handles needed by parser after the lexer guard is released.
pub struct ResidentLexerParserInputs {
    /// Current source byte length.
    pub source_len: u32,
    /// Resident source byte buffer.
    pub in_bytes: LaniusBuffer<u8>,
    /// Resident token record buffer.
    pub tokens_out: LaniusBuffer<GpuToken>,
    /// Resident token-count buffer.
    pub token_count: LaniusBuffer<u32>,
    /// Resident source-file id for each token.
    pub token_file_id: LaniusBuffer<u32>,
    /// Conservative parser-family flags collected at the lexer count boundary.
    pub parser_feature_flags: u32,
}

impl ResidentLexerParserInputs {
    fn from_buffers(bufs: &buffers::GpuBuffers) -> Self {
        Self {
            source_len: bufs.n,
            in_bytes: bufs.in_bytes.clone(),
            tokens_out: bufs.tokens_out.clone(),
            token_count: bufs.token_count.clone(),
            token_file_id: bufs.token_file_id.clone(),
            parser_feature_flags: bufs.parser_feature_flags_value,
        }
    }
}

impl GpuLexer {
    /// Creates a lexer on the process-global GPU device.
    pub async fn new() -> Result<Self> {
        Self::new_with_device(crate::gpu::device::global()).await
    }

    /// Creates a lexer on an existing GPU device and loads compact DFA tables.
    pub async fn new_with_device(ctx: &crate::gpu::device::GpuDevice) -> Result<Self> {
        let device = Arc::clone(&ctx.device);
        let queue = Arc::clone(&ctx.queue);
        let timers_supported = ctx.timers_supported;

        // Load compact DFA tables and build packed-next table once at init.
        const COMPACT_BIN: &[u8] = include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../tables/lexer_tables.bin"
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

        let passes = LexerPasses::new(&device)?;

        Ok(Self {
            device,
            queue,
            timers_supported,
            next_emit_words,
            next_u8_packed,
            token_map,
            passes,
            buffers: std::sync::Mutex::new(None),
            bg_cache: std::sync::Mutex::new(crate::gpu::passes_core::BindGroupCache::new()),
        })
    }

    /// Lexes one source string and reads kept tokens back to the host.
    ///
    /// If lexer readback is disabled by environment, this still records and
    /// submits the GPU work but returns an empty vector.
    pub async fn lex(&self, input: &str) -> Result<Vec<Token>> {
        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.start_graphics_debugger_capture()
        };

        let start_state = 0u32;

        let n = input.as_bytes().len() as u32;

        let skip_kinds = [
            TokenKind::White as u32,
            TokenKind::LineComment as u32,
            TokenKind::BlockComment as u32,
            u32::MAX,
        ];

        let mut guard = self.prepare_buffers_for_input(input, start_state, skip_kinds)?;
        let bufs = guard
            .as_mut()
            .expect("GpuLexer buffers must exist after preparation");

        let use_scopes = crate::gpu::env::env_bool_truthy("LANIUS_VALIDATION_SCOPES", false);

        let timers_on = self.timers_supported
            && (crate::gpu::env::env_bool_truthy("LANIUS_GPU_TIMING", false)
                || crate::gpu::trace::enabled());

        let mut maybe_timer = if timers_on {
            Some(GpuTimer::new(&self.device, &self.queue, 128))
        } else {
            None
        };

        // Optional debug capture handle that all passes can use
        #[cfg(feature = "gpu-debug")]
        let mut debug_output = crate::lexer::debug::DebugOutput::default();
        #[cfg(feature = "gpu-debug")]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = Some(&mut debug_output);
        #[cfg(not(feature = "gpu-debug"))]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = None;

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
        let mut cache_guard = self
            .bg_cache
            .lock()
            .expect("GpuLexer.bg_cache mutex poisoned");

        let ctx = crate::gpu::passes_core::PassContext {
            device: &self.device,
            encoder: &mut enc,
            buffers: &*bufs,
            maybe_timer: &mut timer_ref,
            maybe_dbg: &mut dbg_ref,
            bg_cache: Some(&mut *cache_guard),
        };

        let passes = &self.passes;

        record_all_passes(bufs.n, bufs.nb_dfa, bufs.nb_sum, ctx, passes)?;

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

            crate::gpu::passes_core::submit_with_optional_validation(
                &self.device,
                &self.queue,
                "lex.batch-with-count",
                enc.finish(),
                use_scopes,
                "lex batch",
            );

            crate::gpu::passes_core::map_readback_for_progress(
                &readback_tokens_count.slice(..),
                "lex.count",
            );
            crate::gpu::passes_core::wait_for_map_progress(
                &self.device,
                "lex.count",
                wgpu::PollType::wait_indefinitely(),
            );
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
            crate::gpu::passes_core::submit_with_optional_validation(
                &self.device,
                &self.queue,
                "lex.batch-without-count",
                enc.finish(),
                use_scopes,
                "lex batch",
            );
            // We intentionally skip token-count readback when readback is disabled.
            0usize
        };

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
                    eprintln!("[gpu_timer] {label}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
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
        crate::gpu::passes_core::submit_with_progress(
            &self.queue,
            "lex.token-readback",
            encoder_two.finish(),
        );

        crate::gpu::passes_core::map_readback_for_progress(
            &readback_tokens_buffer.slice(0..need_bytes),
            "lex.tokens",
        );
        crate::gpu::passes_core::wait_for_map_progress(
            &self.device,
            "lex.tokens",
            wgpu::PollType::wait_indefinitely(),
        );

        let mapped = readback_tokens_buffer
            .slice(0..need_bytes)
            .get_mapped_range();
        let tokens =
            read_tokens_from_mapped(&mapped, token_count_u32).map_err(anyhow::Error::msg)?;
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
                eprintln!("[gpu_timer] {label}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
                prev = t;
            }
        }

        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.stop_graphics_debugger_capture()
        };

        Ok(tokens)
    }

    /// Lexes one source and reads the one-word conservative parser-family summary.
    #[doc(hidden)]
    pub async fn debug_parser_feature_flags(&self, input: &str) -> Result<u32> {
        self.lex(input).await?;
        let guard = self
            .buffers
            .lock()
            .expect("GpuLexer.buffers mutex poisoned");
        let bufs = guard
            .as_ref()
            .expect("GpuLexer buffers must exist after lexing");
        let readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.lexer.parser_feature_flags.debug"),
            size: 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lexer.parser_feature_flags.debug.encoder"),
            });
        encoder.copy_buffer_to_buffer(&bufs.parser_feature_flags, 0, &readback, 0, 4);
        crate::gpu::passes_core::submit_with_progress(
            &self.queue,
            "lexer.parser-feature-flags.debug",
            encoder.finish(),
        );
        let slice = readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &slice,
            "lexer.parser_feature_flags.debug",
        )?;
        let mapped = slice.get_mapped_range();
        let value = u32_from_first_4(&mapped);
        drop(mapped);
        readback.unmap();
        Ok(value)
    }

    /// Lexes one source string and exposes resident buffers to a continuation.
    ///
    /// The continuation runs after lexer work has been submitted and before the
    /// lexer buffer guard is released.
    pub async fn with_resident_tokens<R>(
        &self,
        input: &str,
        consume: impl FnOnce(&wgpu::Device, &wgpu::Queue, &buffers::GpuBuffers) -> R,
    ) -> Result<R> {
        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.start_graphics_debugger_capture()
        };

        let start_state = 0u32;
        let skip_kinds = [
            TokenKind::White as u32,
            TokenKind::LineComment as u32,
            TokenKind::BlockComment as u32,
            u32::MAX,
        ];
        let mut guard = self.prepare_buffers_for_input(input, start_state, skip_kinds)?;
        let bufs = guard
            .as_mut()
            .expect("GpuLexer buffers must exist after preparation");

        let use_scopes = crate::gpu::env::env_bool_truthy("LANIUS_VALIDATION_SCOPES", false);

        #[cfg(feature = "gpu-debug")]
        let mut debug_output = crate::lexer::debug::DebugOutput::default();
        #[cfg(feature = "gpu-debug")]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = Some(&mut debug_output);
        #[cfg(not(feature = "gpu-debug"))]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = None;

        let mut enc = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-resident-enc"),
            });

        {
            let mut timer_ref: Option<&mut GpuTimer> = None;
            let mut dbg_ref = maybe_dbg;
            let mut cache_guard = self
                .bg_cache
                .lock()
                .expect("GpuLexer.bg_cache mutex poisoned");
            let ctx = crate::gpu::passes_core::PassContext {
                device: &self.device,
                encoder: &mut enc,
                buffers: &*bufs,
                maybe_timer: &mut timer_ref,
                maybe_dbg: &mut dbg_ref,
                bg_cache: Some(&mut *cache_guard),
            };
            record_all_passes(bufs.n, bufs.nb_dfa, bufs.nb_sum, ctx, &self.passes)?;
        }

        crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "lex.resident",
            enc.finish(),
            use_scopes,
            "resident lex batch",
        );

        let result = consume(&self.device, &self.queue, bufs);

        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.stop_graphics_debugger_capture()
        };

        Ok(result)
    }

    /// Lexes a source pack and reads kept tokens back to the host.
    pub async fn lex_source_pack<S: AsRef<str>>(&self, sources: &[S]) -> Result<Vec<Token>> {
        self.with_resident_source_pack_tokens(sources, read_resident_tokens)
            .await?
    }

    /// Lexes a source pack and exposes resident buffers to a continuation.
    ///
    /// Source strings are concatenated for GPU work; source-file metadata
    /// buffers preserve file ownership for each final token.
    pub async fn with_resident_source_pack_tokens<S: AsRef<str>, R>(
        &self,
        sources: &[S],
        consume: impl FnOnce(&wgpu::Device, &wgpu::Queue, &buffers::GpuBuffers) -> R,
    ) -> Result<R> {
        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.start_graphics_debugger_capture()
        };

        let start_state = 0u32;
        let skip_kinds = [
            TokenKind::White as u32,
            TokenKind::LineComment as u32,
            TokenKind::BlockComment as u32,
            u32::MAX,
        ];
        let mut guard = self.prepare_buffers_for_source_pack(sources, start_state, skip_kinds)?;
        let bufs = guard
            .as_mut()
            .expect("GpuLexer buffers must exist after source pack preparation");

        let use_scopes = crate::gpu::env::env_bool_truthy("LANIUS_VALIDATION_SCOPES", false);

        #[cfg(feature = "gpu-debug")]
        let mut debug_output = crate::lexer::debug::DebugOutput::default();
        #[cfg(feature = "gpu-debug")]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = Some(&mut debug_output);
        #[cfg(not(feature = "gpu-debug"))]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = None;

        let mut enc = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-source-pack-resident-enc"),
            });

        {
            let mut timer_ref: Option<&mut GpuTimer> = None;
            let mut dbg_ref = maybe_dbg;
            let mut cache_guard = self
                .bg_cache
                .lock()
                .expect("GpuLexer.bg_cache mutex poisoned");
            let ctx = crate::gpu::passes_core::PassContext {
                device: &self.device,
                encoder: &mut enc,
                buffers: &*bufs,
                maybe_timer: &mut timer_ref,
                maybe_dbg: &mut dbg_ref,
                bg_cache: Some(&mut *cache_guard),
            };
            record_all_passes(bufs.n, bufs.nb_dfa, bufs.nb_sum, ctx, &self.passes)?;
        }

        crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "lex.source-pack.resident",
            enc.finish(),
            use_scopes,
            "source-pack resident lex batch",
        );

        let result = consume(&self.device, &self.queue, bufs);

        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.stop_graphics_debugger_capture()
        };

        Ok(result)
    }

    /// Records source-pack lexing and caller-provided GPU work in one command stream.
    ///
    /// This variant does not read back token count before `record_more`; callers
    /// should use byte-capacity-sized downstream buffers or perform their own
    /// bounded sizing.
    pub async fn with_recorded_resident_source_pack_tokens<S, T, R, E>(
        &self,
        sources: &[S],
        record_more: impl FnOnce(
            &wgpu::Device,
            &wgpu::Queue,
            &buffers::GpuBuffers,
            &mut wgpu::CommandEncoder,
            Option<&mut GpuTimer>,
        ) -> std::result::Result<T, E>,
        consume_after_submit: impl FnOnce(
            &wgpu::Device,
            &wgpu::Queue,
            &buffers::GpuBuffers,
            T,
        ) -> std::result::Result<R, E>,
    ) -> Result<std::result::Result<R, E>>
    where
        S: AsRef<str>,
    {
        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.start_graphics_debugger_capture()
        };

        let start_state = 0u32;
        let skip_kinds = [
            TokenKind::White as u32,
            TokenKind::LineComment as u32,
            TokenKind::BlockComment as u32,
            u32::MAX,
        ];
        let mut guard = self.prepare_buffers_for_source_pack(sources, start_state, skip_kinds)?;
        let bufs = guard
            .as_mut()
            .expect("GpuLexer buffers must exist after source pack preparation");

        let use_scopes = crate::gpu::env::env_bool_truthy("LANIUS_VALIDATION_SCOPES", false);

        #[cfg(feature = "gpu-debug")]
        let mut debug_output = crate::lexer::debug::DebugOutput::default();
        #[cfg(feature = "gpu-debug")]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = Some(&mut debug_output);
        #[cfg(not(feature = "gpu-debug"))]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = None;

        let mut enc = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-source-pack-resident-recorded-enc"),
            });
        let timers_on = self.timers_supported
            && (crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_TIMING", false)
                || crate::gpu::trace::enabled());
        let mut maybe_timer = if timers_on {
            Some(GpuTimer::new(&self.device, &self.queue, 512))
        } else {
            None
        };
        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut enc, "compile.source_pack.start");
        }

        {
            let mut timer_ref = maybe_timer.as_mut();
            let mut dbg_ref = maybe_dbg;
            let mut cache_guard = self
                .bg_cache
                .lock()
                .expect("GpuLexer.bg_cache mutex poisoned");
            let ctx = crate::gpu::passes_core::PassContext {
                device: &self.device,
                encoder: &mut enc,
                buffers: &*bufs,
                maybe_timer: &mut timer_ref,
                maybe_dbg: &mut dbg_ref,
                bg_cache: Some(&mut *cache_guard),
            };
            record_all_passes(bufs.n, bufs.nb_dfa, bufs.nb_sum, ctx, &self.passes)?;
        }
        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut enc, "lexer.source_pack.done");
        }

        let recorded_more = match record_more(
            &self.device,
            &self.queue,
            bufs,
            &mut enc,
            maybe_timer.as_mut(),
        ) {
            Ok(recorded) => recorded,
            Err(err) => return Ok(Err(err)),
        };
        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut enc, "compile.source_pack.recorded");
            timer.resolve(&mut enc);
        }

        let submit_timing = crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "lex.source-pack.recorded-with-code",
            enc.finish(),
            use_scopes,
            "recorded source-pack resident lex batch",
        );

        let result = consume_after_submit(&self.device, &self.queue, bufs, recorded_more);
        if let Some(timer) = maybe_timer
            .as_ref()
            .and_then(|timer| timer.try_read(&self.device))
        {
            print_timer_trace(
                &timer,
                maybe_timer.as_ref().expect("timer exists").period_ns(),
                submit_timing.gpu_anchor,
            );
        }

        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.stop_graphics_debugger_capture()
        };

        Ok(result)
    }

    /// Lexes a source pack, reads token count, then records caller GPU work.
    ///
    /// The count boundary is a deliberate synchronization point for downstream
    /// phases that need exact token counts before recording their dispatches.
    pub async fn with_recorded_resident_source_pack_tokens_after_count<S, T, R, E>(
        &self,
        sources: &[S],
        record_more: impl FnOnce(
            &wgpu::Device,
            &wgpu::Queue,
            &buffers::GpuBuffers,
            u32,
            &mut wgpu::CommandEncoder,
            Option<&mut GpuTimer>,
        ) -> std::result::Result<T, E>,
        consume_after_submit: impl FnOnce(&wgpu::Device, &wgpu::Queue, T) -> std::result::Result<R, E>,
    ) -> Result<std::result::Result<R, E>>
    where
        S: AsRef<str>,
    {
        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.start_graphics_debugger_capture()
        };

        let start_state = 0u32;
        let skip_kinds = [
            TokenKind::White as u32,
            TokenKind::LineComment as u32,
            TokenKind::BlockComment as u32,
            u32::MAX,
        ];
        let mut guard = self.prepare_buffers_for_source_pack(sources, start_state, skip_kinds)?;
        let bufs = guard
            .as_mut()
            .expect("GpuLexer buffers must exist after source pack preparation");

        let use_scopes = crate::gpu::env::env_bool_truthy("LANIUS_VALIDATION_SCOPES", false);
        let mut host_timer = HostCompileTimer::new();

        #[cfg(feature = "gpu-debug")]
        let mut debug_output = crate::lexer::debug::DebugOutput::default();
        #[cfg(feature = "gpu-debug")]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = Some(&mut debug_output);
        #[cfg(not(feature = "gpu-debug"))]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = None;

        let mut lex_encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-source-pack-resident-count-boundary-enc"),
            });

        {
            let mut timer_ref: Option<&mut GpuTimer> = None;
            let mut dbg_ref = maybe_dbg;
            let mut cache_guard = self
                .bg_cache
                .lock()
                .expect("GpuLexer.bg_cache mutex poisoned");
            let ctx = crate::gpu::passes_core::PassContext {
                device: &self.device,
                encoder: &mut lex_encoder,
                buffers: &*bufs,
                maybe_timer: &mut timer_ref,
                maybe_dbg: &mut dbg_ref,
                bg_cache: Some(&mut *cache_guard),
            };
            record_all_passes(bufs.n, bufs.nb_dfa, bufs.nb_sum, ctx, &self.passes)?;
        }

        let token_count_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.lex.source_pack.resident.token_count"),
            size: 8,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        lex_encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &token_count_readback, 0, 4);
        lex_encoder.copy_buffer_to_buffer(
            &bufs.parser_feature_flags,
            0,
            &token_count_readback,
            4,
            4,
        );

        crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "lex.source-pack.resident-count-boundary",
            lex_encoder.finish(),
            use_scopes,
            "source-pack resident lex count boundary",
        );

        let count_slice = token_count_readback.slice(..);
        crate::gpu::passes_core::map_readback_for_progress(
            &count_slice,
            "lex.source-pack.resident.count",
        );
        crate::gpu::passes_core::wait_for_map_progress(
            &self.device,
            "lex.source-pack.resident.count",
            wgpu::PollType::wait_indefinitely(),
        );
        let count_bytes = count_slice.get_mapped_range();
        let token_count = u32_from_first_4(&count_bytes);
        bufs.parser_feature_flags_value = u32_from_first_4(&count_bytes[4..]);
        drop(count_bytes);
        token_count_readback.unmap();
        if token_count > bufs.n {
            anyhow::bail!(
                "source-pack lexer token count unexpectedly exceeds byte capacity: count={}, capacity={}",
                token_count,
                bufs.n
            );
        }
        host_timer.stamp("lex.source-pack.count_boundary");

        let mut code_encoder =
            self.device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("compile-source-pack-after-token-count-enc"),
                });
        let timers_on = self.timers_supported
            && (crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_TIMING", false)
                || crate::gpu::trace::enabled());
        let mut maybe_timer = if timers_on {
            Some(GpuTimer::new(&self.device, &self.queue, 512))
        } else {
            None
        };
        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut code_encoder, "compile.after_count.start");
        }
        let recorded_more = match record_more(
            &self.device,
            &self.queue,
            bufs,
            token_count,
            &mut code_encoder,
            maybe_timer.as_mut(),
        ) {
            Ok(recorded) => recorded,
            Err(err) => return Ok(Err(err)),
        };
        host_timer.stamp("compile.source-pack.record_more");
        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut code_encoder, "compile.after_count.recorded");
            timer.resolve(&mut code_encoder);
        }

        let command_buffer = code_encoder.finish();
        host_timer.stamp("compile.source-pack.encoder_finish");
        let submit_timing = crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "compile.source-pack.after-token-count",
            command_buffer,
            use_scopes,
            "source-pack compile after token count",
        );
        host_timer.stamp("compile.source-pack.submit");

        drop(guard);
        host_timer.stamp("lex.source-pack.resident.retained");

        let result = consume_after_submit(&self.device, &self.queue, recorded_more);
        host_timer.stamp("compile.source-pack.finish");
        if let Some(stamps) = maybe_timer
            .as_ref()
            .and_then(|timer| timer.try_read(&self.device))
        {
            print_timer_trace(
                &stamps,
                maybe_timer.as_ref().expect("timer exists").period_ns(),
                submit_timing.gpu_anchor,
            );
        }
        host_timer.stamp("compile.source-pack.timer_readback");

        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.stop_graphics_debugger_capture()
        };

        Ok(result)
    }

    /// Records single-source lexing and caller-provided GPU work in one command stream.
    pub async fn with_recorded_resident_tokens<S, R, E>(
        &self,
        input: &str,
        record_more: impl FnOnce(
            &wgpu::Device,
            &wgpu::Queue,
            &buffers::GpuBuffers,
            &mut wgpu::CommandEncoder,
            Option<&mut GpuTimer>,
        ) -> std::result::Result<S, E>,
        consume_after_submit: impl FnOnce(
            &wgpu::Device,
            &wgpu::Queue,
            &buffers::GpuBuffers,
            S,
        ) -> std::result::Result<R, E>,
    ) -> Result<std::result::Result<R, E>> {
        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.start_graphics_debugger_capture()
        };

        let start_state = 0u32;
        let skip_kinds = [
            TokenKind::White as u32,
            TokenKind::LineComment as u32,
            TokenKind::BlockComment as u32,
            u32::MAX,
        ];
        let mut guard = self.prepare_buffers_for_input(input, start_state, skip_kinds)?;
        let bufs = guard
            .as_mut()
            .expect("GpuLexer buffers must exist after preparation");

        let use_scopes = crate::gpu::env::env_bool_truthy("LANIUS_VALIDATION_SCOPES", false);

        #[cfg(feature = "gpu-debug")]
        let mut debug_output = crate::lexer::debug::DebugOutput::default();
        #[cfg(feature = "gpu-debug")]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = Some(&mut debug_output);
        #[cfg(not(feature = "gpu-debug"))]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = None;

        let mut enc = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-resident-recorded-enc"),
            });
        let timers_on = self.timers_supported
            && (crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_TIMING", false)
                || crate::gpu::trace::enabled());
        let mut maybe_timer = if timers_on {
            Some(GpuTimer::new(&self.device, &self.queue, 512))
        } else {
            None
        };
        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut enc, "compile.start");
        }

        {
            let mut timer_ref = maybe_timer.as_mut();
            let mut dbg_ref = maybe_dbg;
            let mut cache_guard = self
                .bg_cache
                .lock()
                .expect("GpuLexer.bg_cache mutex poisoned");
            let ctx = crate::gpu::passes_core::PassContext {
                device: &self.device,
                encoder: &mut enc,
                buffers: &*bufs,
                maybe_timer: &mut timer_ref,
                maybe_dbg: &mut dbg_ref,
                bg_cache: Some(&mut *cache_guard),
            };
            record_all_passes(bufs.n, bufs.nb_dfa, bufs.nb_sum, ctx, &self.passes)?;
        }
        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut enc, "lexer.done");
        }

        let recorded_more = match record_more(
            &self.device,
            &self.queue,
            bufs,
            &mut enc,
            maybe_timer.as_mut(),
        ) {
            Ok(recorded) => recorded,
            Err(err) => return Ok(Err(err)),
        };
        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut enc, "compile.recorded");
            timer.resolve(&mut enc);
        }

        let submit_timing = crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "lex.recorded-with-code",
            enc.finish(),
            use_scopes,
            "recorded resident lex batch",
        );

        let result = consume_after_submit(&self.device, &self.queue, bufs, recorded_more);
        if let Some(timer) = maybe_timer
            .as_ref()
            .and_then(|timer| timer.try_read(&self.device))
        {
            print_timer_trace(
                &timer,
                maybe_timer.as_ref().expect("timer exists").period_ns(),
                submit_timing.gpu_anchor,
            );
        }

        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.stop_graphics_debugger_capture()
        };

        Ok(result)
    }

    /// Lexes one source, reads token count, then records caller GPU work.
    pub async fn with_recorded_resident_tokens_after_count<S, R, E>(
        &self,
        input: &str,
        record_more: impl FnOnce(
            &wgpu::Device,
            &wgpu::Queue,
            &buffers::GpuBuffers,
            u32,
            &mut wgpu::CommandEncoder,
            Option<&mut GpuTimer>,
        ) -> std::result::Result<S, E>,
        consume_after_submit: impl FnOnce(
            &wgpu::Device,
            &wgpu::Queue,
            &buffers::GpuBuffers,
            S,
        ) -> std::result::Result<R, E>,
    ) -> Result<std::result::Result<R, E>> {
        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.start_graphics_debugger_capture()
        };

        let start_state = 0u32;
        let skip_kinds = [
            TokenKind::White as u32,
            TokenKind::LineComment as u32,
            TokenKind::BlockComment as u32,
            u32::MAX,
        ];
        let mut guard = self.prepare_buffers_for_input(input, start_state, skip_kinds)?;
        let bufs = guard
            .as_mut()
            .expect("GpuLexer buffers must exist after preparation");

        let use_scopes = crate::gpu::env::env_bool_truthy("LANIUS_VALIDATION_SCOPES", false);
        let mut host_timer = HostCompileTimer::new();

        #[cfg(feature = "gpu-debug")]
        let mut debug_output = crate::lexer::debug::DebugOutput::default();
        #[cfg(feature = "gpu-debug")]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = Some(&mut debug_output);
        #[cfg(not(feature = "gpu-debug"))]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = None;

        let mut lex_encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-resident-count-boundary-enc"),
            });

        {
            let mut timer_ref: Option<&mut GpuTimer> = None;
            let mut dbg_ref = maybe_dbg;
            let mut cache_guard = self
                .bg_cache
                .lock()
                .expect("GpuLexer.bg_cache mutex poisoned");
            let ctx = crate::gpu::passes_core::PassContext {
                device: &self.device,
                encoder: &mut lex_encoder,
                buffers: &*bufs,
                maybe_timer: &mut timer_ref,
                maybe_dbg: &mut dbg_ref,
                bg_cache: Some(&mut *cache_guard),
            };
            record_all_passes(bufs.n, bufs.nb_dfa, bufs.nb_sum, ctx, &self.passes)?;
        }

        let token_count_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.lex.resident.token_count"),
            size: 8,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        lex_encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &token_count_readback, 0, 4);
        lex_encoder.copy_buffer_to_buffer(
            &bufs.parser_feature_flags,
            0,
            &token_count_readback,
            4,
            4,
        );

        crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "lex.resident-count-boundary",
            lex_encoder.finish(),
            use_scopes,
            "resident lex count boundary",
        );

        let count_slice = token_count_readback.slice(..);
        crate::gpu::passes_core::map_readback_for_progress(&count_slice, "lex.resident.count");
        crate::gpu::passes_core::wait_for_map_progress(
            &self.device,
            "lex.resident.count",
            wgpu::PollType::wait_indefinitely(),
        );
        let count_bytes = count_slice.get_mapped_range();
        let token_count = u32_from_first_4(&count_bytes);
        bufs.parser_feature_flags_value = u32_from_first_4(&count_bytes[4..]);
        drop(count_bytes);
        token_count_readback.unmap();
        if token_count > bufs.n {
            anyhow::bail!(
                "lexer token count unexpectedly exceeds byte capacity: count={}, capacity={}",
                token_count,
                bufs.n
            );
        }
        host_timer.stamp("lex.resident.count_boundary");

        let mut code_encoder =
            self.device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("compile-after-token-count-enc"),
                });
        let timers_on = self.timers_supported
            && (crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_TIMING", false)
                || crate::gpu::trace::enabled());
        let mut maybe_timer = if timers_on {
            Some(GpuTimer::new(&self.device, &self.queue, 512))
        } else {
            None
        };
        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut code_encoder, "compile.after_count.start");
        }
        let recorded_more = match record_more(
            &self.device,
            &self.queue,
            bufs,
            token_count,
            &mut code_encoder,
            maybe_timer.as_mut(),
        ) {
            Ok(recorded) => recorded,
            Err(err) => return Ok(Err(err)),
        };
        host_timer.stamp("compile.record_more");
        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut code_encoder, "compile.after_count.recorded");
            timer.resolve(&mut code_encoder);
        }

        let code_command_buffer = code_encoder.finish();
        host_timer.stamp("compile.encoder_finish");
        let submit_timing = crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "compile.after-token-count",
            code_command_buffer,
            use_scopes,
            "compile after token count",
        );
        host_timer.stamp("compile.submit");

        let result = consume_after_submit(&self.device, &self.queue, bufs, recorded_more);
        host_timer.stamp("compile.finish");
        if let Some(stamps) = maybe_timer
            .as_ref()
            .and_then(|timer| timer.try_read(&self.device))
        {
            print_timer_trace(
                &stamps,
                maybe_timer.as_ref().expect("timer exists").period_ns(),
                submit_timing.gpu_anchor,
            );
        }
        host_timer.stamp("compile.timer_readback");

        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.stop_graphics_debugger_capture()
        };

        Ok(result)
    }

    /// Lexes one source, reads token count, releases lexer buffers, then records parser work.
    ///
    /// The parser receives cloned handles in `ResidentLexerParserInputs`. This
    /// reduces resident memory pressure before downstream buffers are allocated.
    pub async fn with_recorded_resident_parser_inputs_after_count_releasing_lexer<S, R, E>(
        &self,
        input: &str,
        record_more: impl FnOnce(
            &wgpu::Device,
            &wgpu::Queue,
            &ResidentLexerParserInputs,
            u32,
            &mut wgpu::CommandEncoder,
            Option<&mut GpuTimer>,
        ) -> std::result::Result<S, E>,
        consume_after_submit: impl FnOnce(
            &wgpu::Device,
            &wgpu::Queue,
            &ResidentLexerParserInputs,
            S,
        ) -> std::result::Result<R, E>,
    ) -> Result<std::result::Result<R, E>> {
        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.start_graphics_debugger_capture()
        };

        let start_state = 0u32;
        let skip_kinds = [
            TokenKind::White as u32,
            TokenKind::LineComment as u32,
            TokenKind::BlockComment as u32,
            u32::MAX,
        ];
        let mut guard = self.prepare_buffers_for_input(input, start_state, skip_kinds)?;
        let bufs = guard
            .as_mut()
            .expect("GpuLexer buffers must exist after preparation");

        let use_scopes = crate::gpu::env::env_bool_truthy("LANIUS_VALIDATION_SCOPES", false);
        let mut host_timer = HostCompileTimer::new();

        #[cfg(feature = "gpu-debug")]
        let mut debug_output = crate::lexer::debug::DebugOutput::default();
        #[cfg(feature = "gpu-debug")]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = Some(&mut debug_output);
        #[cfg(not(feature = "gpu-debug"))]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = None;

        let mut lex_encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-resident-count-boundary-enc"),
            });

        {
            let mut timer_ref: Option<&mut GpuTimer> = None;
            let mut dbg_ref = maybe_dbg;
            let mut cache_guard = self
                .bg_cache
                .lock()
                .expect("GpuLexer.bg_cache mutex poisoned");
            let ctx = crate::gpu::passes_core::PassContext {
                device: &self.device,
                encoder: &mut lex_encoder,
                buffers: &*bufs,
                maybe_timer: &mut timer_ref,
                maybe_dbg: &mut dbg_ref,
                bg_cache: Some(&mut *cache_guard),
            };
            record_all_passes(bufs.n, bufs.nb_dfa, bufs.nb_sum, ctx, &self.passes)?;
        }

        let token_count_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.lex.resident.token_count"),
            size: 8,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        lex_encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &token_count_readback, 0, 4);
        lex_encoder.copy_buffer_to_buffer(
            &bufs.parser_feature_flags,
            0,
            &token_count_readback,
            4,
            4,
        );

        crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "lex.resident-count-boundary",
            lex_encoder.finish(),
            use_scopes,
            "resident lex count boundary",
        );

        let count_slice = token_count_readback.slice(..);
        crate::gpu::passes_core::map_readback_for_progress(&count_slice, "lex.resident.count");
        crate::gpu::passes_core::wait_for_map_progress(
            &self.device,
            "lex.resident.count",
            wgpu::PollType::wait_indefinitely(),
        );
        let count_bytes = count_slice.get_mapped_range();
        let token_count = u32_from_first_4(&count_bytes);
        bufs.parser_feature_flags_value = u32_from_first_4(&count_bytes[4..]);
        drop(count_bytes);
        token_count_readback.unmap();
        if token_count > bufs.n {
            anyhow::bail!(
                "lexer token count unexpectedly exceeds byte capacity: count={}, capacity={}",
                token_count,
                bufs.n
            );
        }
        host_timer.stamp("lex.resident.count_boundary");

        let parser_inputs = ResidentLexerParserInputs::from_buffers(bufs);
        *guard = None;
        drop(guard);
        if let Ok(mut cache) = self.bg_cache.lock() {
            cache.clear();
        } else {
            warn!("failed to clear lexer bind-group cache (poisoned mutex)");
        }
        let _ = self.device.poll(wgpu::PollType::wait_indefinitely());
        host_timer.stamp("lex.resident.released_before_parser");

        let mut code_encoder =
            self.device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("compile-after-token-count-enc"),
                });
        let timers_on = self.timers_supported
            && (crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_TIMING", false)
                || crate::gpu::trace::enabled());
        let mut maybe_timer = if timers_on {
            Some(GpuTimer::new(&self.device, &self.queue, 512))
        } else {
            None
        };
        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut code_encoder, "compile.after_count.start");
        }
        let recorded_more = match record_more(
            &self.device,
            &self.queue,
            &parser_inputs,
            token_count,
            &mut code_encoder,
            maybe_timer.as_mut(),
        ) {
            Ok(recorded) => recorded,
            Err(err) => return Ok(Err(err)),
        };
        host_timer.stamp("compile.record_more");
        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut code_encoder, "compile.after_count.recorded");
            timer.resolve(&mut code_encoder);
        }

        let code_command_buffer = code_encoder.finish();
        host_timer.stamp("compile.encoder_finish");
        let submit_timing = crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "compile.after-token-count",
            code_command_buffer,
            use_scopes,
            "compile after token count",
        );
        host_timer.stamp("compile.submit");

        let result = consume_after_submit(&self.device, &self.queue, &parser_inputs, recorded_more);
        host_timer.stamp("compile.finish");
        if let Some(stamps) = maybe_timer
            .as_ref()
            .and_then(|timer| timer.try_read(&self.device))
        {
            print_timer_trace(
                &stamps,
                maybe_timer.as_ref().expect("timer exists").period_ns(),
                submit_timing.gpu_anchor,
            );
        }
        host_timer.stamp("compile.timer_readback");

        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.stop_graphics_debugger_capture()
        };

        Ok(result)
    }

    /// Lexes one source, reads token count, records work, and releases lexer buffers.
    ///
    /// Unlike the parser-input variant, `record_more` still receives `GpuBuffers`
    /// before the guard is dropped. The buffers must not be used after submit.
    pub async fn with_recorded_resident_tokens_after_count_releasing_lexer<S, R, E>(
        &self,
        input: &str,
        record_more: impl FnOnce(
            &wgpu::Device,
            &wgpu::Queue,
            &buffers::GpuBuffers,
            u32,
            &mut wgpu::CommandEncoder,
            Option<&mut GpuTimer>,
        ) -> std::result::Result<S, E>,
        consume_after_submit: impl FnOnce(&wgpu::Device, &wgpu::Queue, S) -> std::result::Result<R, E>,
    ) -> Result<std::result::Result<R, E>> {
        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.start_graphics_debugger_capture()
        };

        let start_state = 0u32;
        let skip_kinds = [
            TokenKind::White as u32,
            TokenKind::LineComment as u32,
            TokenKind::BlockComment as u32,
            u32::MAX,
        ];
        let mut guard = self.prepare_buffers_for_input(input, start_state, skip_kinds)?;
        let bufs = guard
            .as_mut()
            .expect("GpuLexer buffers must exist after preparation");

        let use_scopes = crate::gpu::env::env_bool_truthy("LANIUS_VALIDATION_SCOPES", false);
        let mut host_timer = HostCompileTimer::new();

        #[cfg(feature = "gpu-debug")]
        let mut debug_output = crate::lexer::debug::DebugOutput::default();
        #[cfg(feature = "gpu-debug")]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = Some(&mut debug_output);
        #[cfg(not(feature = "gpu-debug"))]
        let maybe_dbg: Option<&mut crate::lexer::debug::DebugOutput> = None;

        let mut lex_encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("lex-resident-count-boundary-enc"),
            });

        {
            let mut timer_ref: Option<&mut GpuTimer> = None;
            let mut dbg_ref = maybe_dbg;
            let mut cache_guard = self
                .bg_cache
                .lock()
                .expect("GpuLexer.bg_cache mutex poisoned");
            let ctx = crate::gpu::passes_core::PassContext {
                device: &self.device,
                encoder: &mut lex_encoder,
                buffers: &*bufs,
                maybe_timer: &mut timer_ref,
                maybe_dbg: &mut dbg_ref,
                bg_cache: Some(&mut *cache_guard),
            };
            record_all_passes(bufs.n, bufs.nb_dfa, bufs.nb_sum, ctx, &self.passes)?;
        }

        let token_count_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.lex.resident.token_count"),
            size: 8,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        lex_encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &token_count_readback, 0, 4);
        lex_encoder.copy_buffer_to_buffer(
            &bufs.parser_feature_flags,
            0,
            &token_count_readback,
            4,
            4,
        );

        crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "lex.resident-count-boundary",
            lex_encoder.finish(),
            use_scopes,
            "resident lex count boundary",
        );

        let count_slice = token_count_readback.slice(..);
        crate::gpu::passes_core::map_readback_for_progress(&count_slice, "lex.resident.count");
        crate::gpu::passes_core::wait_for_map_progress(
            &self.device,
            "lex.resident.count",
            wgpu::PollType::wait_indefinitely(),
        );
        let count_bytes = count_slice.get_mapped_range();
        let token_count = u32_from_first_4(&count_bytes);
        bufs.parser_feature_flags_value = u32_from_first_4(&count_bytes[4..]);
        drop(count_bytes);
        token_count_readback.unmap();
        if token_count > bufs.n {
            anyhow::bail!(
                "lexer token count unexpectedly exceeds byte capacity: count={}, capacity={}",
                token_count,
                bufs.n
            );
        }
        host_timer.stamp("lex.resident.count_boundary");

        let mut code_encoder =
            self.device
                .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("compile-after-token-count-enc"),
                });
        let timers_on = self.timers_supported
            && (crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_TIMING", false)
                || crate::gpu::trace::enabled());
        let mut maybe_timer = if timers_on {
            Some(GpuTimer::new(&self.device, &self.queue, 512))
        } else {
            None
        };
        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut code_encoder, "compile.after_count.start");
        }
        let recorded_more = match record_more(
            &self.device,
            &self.queue,
            bufs,
            token_count,
            &mut code_encoder,
            maybe_timer.as_mut(),
        ) {
            Ok(recorded) => recorded,
            Err(err) => return Ok(Err(err)),
        };
        host_timer.stamp("compile.record_more");
        if let Some(timer) = maybe_timer.as_mut() {
            timer.stamp(&mut code_encoder, "compile.after_count.recorded");
            timer.resolve(&mut code_encoder);
        }

        let code_command_buffer = code_encoder.finish();
        host_timer.stamp("compile.encoder_finish");
        let submit_timing = crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "compile.after-token-count",
            code_command_buffer,
            use_scopes,
            "compile after token count",
        );
        host_timer.stamp("compile.submit");

        *guard = None;
        drop(guard);
        if let Ok(mut cache) = self.bg_cache.lock() {
            cache.clear();
        } else {
            warn!("failed to clear lexer bind-group cache (poisoned mutex)");
        }
        host_timer.stamp("lex.resident.released");

        let result = consume_after_submit(&self.device, &self.queue, recorded_more);
        host_timer.stamp("compile.finish");
        if let Some(stamps) = maybe_timer
            .as_ref()
            .and_then(|timer| timer.try_read(&self.device))
        {
            print_timer_trace(
                &stamps,
                maybe_timer.as_ref().expect("timer exists").period_ns(),
                submit_timing.gpu_anchor,
            );
        }
        host_timer.stamp("compile.timer_readback");

        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.stop_graphics_debugger_capture()
        };

        Ok(result)
    }
}
