//! GPU lexer driver (device init, pass orchestration, and readback).

use std::sync::{Arc, OnceLock};

use anyhow::{Result, anyhow};

use super::buffers;
use crate::{
    gpu::timer::{GpuTimer, MINIMUM_TIME_TO_NOT_ELIDE_MS},
    lexer::{
        gpu::{
            buffers::GpuBuffers,
            passes::{LexerPasses, record_all_passes},
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

    passes: LexerPasses,

    // Persistent buffers reused across lex() calls
    buffers: std::sync::Mutex<Option<buffers::GpuBuffers>>,
    // Bind group cache to avoid recreating them every dispatch
    bg_cache: std::sync::Mutex<crate::gpu::passes_core::BindGroupCache>,
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
        let cap_n = bufs.in_bytes.count as u32;
        let cap_nb_dfa = (bufs.dfa_02_ping.count / crate::lexer::tables::dfa::N_STATES) as u32;

        // Pair scans reuse DFA block buffers; ensuring DFA capacity is sufficient implies pair capacity
        let needs_grow = (aligned_len_usize as u32) > (bufs.in_bytes.byte_size as u32)
            || nb_dfa_needed > cap_nb_dfa
            || n > cap_n;
        if needs_grow {
            println!("growing");
            // Recreate with a grown capacity; choose ≥ n
            let new_cap = (aligned_len_usize as u32)
                .max(cap_n.max(1).saturating_mul(2))
                .max(1);
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

            // Keep the dynamic sizes in the struct up to date for dispatch
            bufs.n = n;
            bufs.nb_dfa = nb_dfa_needed;
            bufs.nb_sum = nb_sum_needed;
        }

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
