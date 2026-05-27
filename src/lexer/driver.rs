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
    gpu::timer::{GpuTimer, MINIMUM_TIME_TO_NOT_ELIDE_MS},
    lexer::{
        buffers::GpuBuffers,
        passes::{LexerPasses, record_all_passes},
        tables::{compact::load_compact_tables_from_bytes, tokens::TokenKind},
        types::{GpuToken, Token},
        util::{read_tokens_from_mapped, readback_enabled, u32_from_first_4},
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

    passes: LexerPasses,

    // Persistent buffers reused across lex() calls
    buffers: std::sync::Mutex<Option<buffers::GpuBuffers>>,
    // Bind group cache to avoid recreating them every dispatch
    bg_cache: std::sync::Mutex<crate::gpu::passes_core::BindGroupCache>,
}

pub struct ResidentLexerParserInputs {
    pub source_len: u32,
    pub in_bytes: wgpu::Buffer,
    pub tokens_out: wgpu::Buffer,
    pub token_count: wgpu::Buffer,
    pub token_file_id: wgpu::Buffer,
}

impl ResidentLexerParserInputs {
    fn from_buffers(bufs: &buffers::GpuBuffers) -> Self {
        Self {
            source_len: bufs.n,
            in_bytes: bufs.in_bytes.buffer.clone(),
            tokens_out: bufs.tokens_out.buffer.clone(),
            token_count: bufs.token_count.buffer.clone(),
            token_file_id: bufs.token_file_id.buffer.clone(),
        }
    }
}

impl GpuLexer {
    pub async fn new() -> Result<Self> {
        Self::new_with_device(crate::gpu::device::global()).await
    }

    pub async fn new_with_device(ctx: &crate::gpu::device::GpuDevice) -> Result<Self> {
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

    pub async fn lex(&self, input: &str) -> Result<Vec<Token>> {
        #[cfg(feature = "graphics_debugger")]
        unsafe {
            self.device.start_graphics_debugger_capture()
        };

        let start_state = 0u32;

        let input_bytes: &[u8] = input.as_bytes();
        let n = input_bytes.len() as u32;
        let aligned_len_usize = ((n as usize + 3) / 4) * 4; // for in_bytes writes

        let skip_kinds = [
            TokenKind::White as u32,
            TokenKind::LineComment as u32,
            TokenKind::BlockComment as u32,
            u32::MAX,
        ];

        // Prepare or resize persistent buffers
        const BLOCK_WIDTH_DFA: u32 = 256;
        const BLOCK_WIDTH_SUM: u32 = 256;

        let mut guard = self
            .buffers
            .lock()
            .expect("GpuLexer.buffers mutex poisoned");

        // Helper to (re)create buffers with at-least current n capacity
        let recreate = |cap_n: u32| -> buffers::GpuBuffers {
            GpuBuffers::new(
                &self.device,
                cap_n,
                1,
                start_state,
                &self.next_emit_words,
                &self.next_u8_packed,
                &self.token_map,
                skip_kinds,
            )
        };

        // Ensure buffers exist and have enough capacity; otherwise reuse and just update content
        let bufs = if guard.is_none() {
            // First-time allocation: ensure input buffer can accept aligned writes
            let init_cap = (aligned_len_usize as u32).max(1);
            let b = recreate(init_cap);
            *guard = Some(b);
            guard.as_mut().unwrap()
        } else {
            guard.as_mut().unwrap()
        };

        // Compute dispatch sizes for current input
        let nb_dfa_needed = n.div_ceil(BLOCK_WIDTH_DFA);
        let nb_sum_needed = n.div_ceil(BLOCK_WIDTH_SUM);

        // Current capacities
        let desired_cap = (aligned_len_usize as u32).max(n).max(1);
        let cap_n = bufs.in_bytes.count as u32;
        let cap_bytes = bufs.in_bytes.byte_size as u32;
        let cap_nb_dfa = (bufs.dfa_02_ping.count / crate::lexer::tables::dfa::N_STATES) as u32;

        // Pair scans reuse DFA block buffers; ensuring DFA capacity is sufficient implies pair capacity
        let needs_resize = desired_cap != cap_bytes || nb_dfa_needed != cap_nb_dfa || n > cap_n;
        if needs_resize {
            // Keep resident capacity exact; doubling here can create multi-GiB
            // parser/typechecker over-allocation when benchmarks grow input size.
            let new_cap = desired_cap;
            let mut new_bufs = recreate(new_cap);
            // Adjust dynamic sizes and params to the actual input n
            new_bufs.n = n;
            new_bufs.nb_dfa = nb_dfa_needed;
            new_bufs.nb_sum = nb_sum_needed;
            let params_val = super::types::LexParams {
                n,
                m: self.token_map.len() as u32,
                start_state,
                skip0: skip_kinds[0],
                skip1: skip_kinds[1],
                skip2: skip_kinds[2],
                skip3: skip_kinds[3],
            };
            let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
            ub.write(&params_val).expect("failed to encode LexParams");
            let bytes = ub.as_ref();
            self.queue.write_buffer(&new_bufs.params, 0, bytes);
            self.write_current_source_file_metadata(&new_bufs, n);
            // Upload input bytes (padded to 4-byte alignment)
            if n > 0 {
                let aligned_len = ((n as usize + 3) / 4) * 4;
                if aligned_len == input_bytes.len() {
                    self.queue.write_buffer(&new_bufs.in_bytes, 0, input_bytes);
                } else {
                    let mut tmp = Vec::with_capacity(aligned_len);
                    tmp.extend_from_slice(input_bytes);
                    tmp.resize(aligned_len, 0u8);
                    self.queue.write_buffer(&new_bufs.in_bytes, 0, &tmp);
                }
            }
            *bufs = new_bufs;
            // Buffers replaced: clear bind group cache so we recreate with new resources
            if let Ok(mut cache) = self.bg_cache.lock() {
                cache.clear();
            } else {
                warn!("failed to clear lexer bind-group cache (poisoned mutex)");
            }
        } else {
            // Reuse: update input bytes and params for current n/start/skip
            if n > 0 {
                // wgpu requires COPY_BUFFER-aligned sizes; pad to 4 bytes
                let aligned_len = ((n as usize + 3) / 4) * 4;
                if aligned_len == input_bytes.len() {
                    self.queue.write_buffer(&bufs.in_bytes, 0, input_bytes);
                } else {
                    let mut tmp = Vec::with_capacity(aligned_len);
                    tmp.extend_from_slice(input_bytes);
                    tmp.resize(aligned_len, 0u8);
                    self.queue.write_buffer(&bufs.in_bytes, 0, &tmp);
                }
            }
            // Update params uniform with new values
            let params_val = super::types::LexParams {
                n,
                m: self.token_map.len() as u32,
                start_state,
                skip0: skip_kinds[0],
                skip1: skip_kinds[1],
                skip2: skip_kinds[2],
                skip3: skip_kinds[3],
            };
            let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
            ub.write(&params_val).expect("failed to encode LexParams");
            let bytes = ub.as_ref();
            self.queue.write_buffer(&bufs.params, 0, bytes);
            self.write_current_source_file_metadata(bufs, n);

            // Keep the dynamic sizes in the struct up to date for dispatch
            bufs.n = n;
            bufs.nb_dfa = nb_dfa_needed;
            bufs.nb_sum = nb_sum_needed;
        }

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

    pub async fn lex_source_pack<S: AsRef<str>>(&self, sources: &[S]) -> Result<Vec<Token>> {
        self.with_resident_source_pack_tokens(sources, read_resident_tokens)
            .await?
    }

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
            size: 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        lex_encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &token_count_readback, 0, 4);

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
        drop(count_bytes);
        token_count_readback.unmap();
        if token_count > bufs.n {
            anyhow::bail!(
                "GPU source-pack lexer token_count unexpectedly exceeds byte capacity: count={}, capacity={}",
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

        let submit_timing = crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "compile.source-pack.after-token-count",
            code_encoder.finish(),
            use_scopes,
            "source-pack compile after token count",
        );
        host_timer.stamp("compile.source-pack.submit");

        *guard = None;
        drop(guard);
        if let Ok(mut cache) = self.bg_cache.lock() {
            cache.clear();
        } else {
            warn!("failed to clear source-pack lexer bind-group cache (poisoned mutex)");
        }
        host_timer.stamp("lex.source-pack.resident.released");

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
            size: 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        lex_encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &token_count_readback, 0, 4);

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
        drop(count_bytes);
        token_count_readback.unmap();
        if token_count > bufs.n {
            anyhow::bail!(
                "GPU lexer token_count unexpectedly exceeds byte capacity: count={}, capacity={}",
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
            size: 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        lex_encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &token_count_readback, 0, 4);

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
        drop(count_bytes);
        token_count_readback.unmap();
        if token_count > bufs.n {
            anyhow::bail!(
                "GPU lexer token_count unexpectedly exceeds byte capacity: count={}, capacity={}",
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
            size: 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        lex_encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &token_count_readback, 0, 4);

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
        drop(count_bytes);
        token_count_readback.unmap();
        if token_count > bufs.n {
            anyhow::bail!(
                "GPU lexer token_count unexpectedly exceeds byte capacity: count={}, capacity={}",
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
