// src/parser/gpu/driver.rs
//! GPU parser driver, reshaped to mirror the style used by the lexer driver:
//! - Pass bundle + `record_all_passes`
//! - Bind-group cache reuse across passes
//! - Env-gated timers and validation scopes
//! - Optional readback (LANIUS_READBACK), returning empty streams when off

use std::sync::{Arc, OnceLock};

use anyhow::Result;
use wgpu;

use crate::{
    gpu::{
        device,
        passes_core::{BindGroupCache, PassContext},
        timer::{GpuTimer, MINIMUM_TIME_TO_NOT_ELIDE_MS},
    },
    parser::{
        gpu::{
            buffers::{ActionHeader, ParserBuffers},
            debug::DebugOutput,
            passes::{self, ParserPasses},
            readback,
        },
        tables::PrecomputedParseTables,
    },
};

// ------------ little helpers (match lexer ergonomics) ----------------

fn bool_from_env(name: &str, default_true: bool) -> bool {
    std::env::var(name)
        .map(|v| {
            if default_true {
                v != "0" && !v.eq_ignore_ascii_case("false")
            } else {
                v == "1" || v.eq_ignore_ascii_case("true")
            }
        })
        .unwrap_or(default_true)
}

/// Mirrors the lexer: allow disabling readback with `LANIUS_READBACK=0`.
fn readback_enabled() -> bool {
    bool_from_env("LANIUS_READBACK", true)
}

// ---------------------------------------------------------------------

pub struct GpuParser {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    timers_supported: bool,

    passes: ParserPasses,

    // Bind group cache so passes don’t recreate BGs every dispatch.
    bg_cache: std::sync::Mutex<BindGroupCache>,
}

pub struct BracketsMatchResult {
    pub valid: bool,
    pub final_depth: i32,
    pub min_depth: i32,
    pub match_for_index: Vec<u32>,
}

pub struct ParseResult {
    pub headers: Vec<ActionHeader>,
    pub sc_stream: Vec<u32>,
    pub emit_stream: Vec<u32>,
    pub brackets: BracketsMatchResult,

    /// Tree outputs (inverted tree arrays), read back from GPU.
    pub node_kind: Vec<u32>,
    pub parent: Vec<u32>,

    /// Populated by each pass via record_debug(); consumers can copy out snapshots.
    pub debug: DebugOutput,
}

impl GpuParser {
    pub async fn new() -> Result<Self> {
        let ctx = device::global();
        let device = Arc::clone(&ctx.device);
        let queue = Arc::clone(&ctx.queue);

        Ok(Self {
            device,
            queue,
            timers_supported: ctx.timers_supported,
            passes: ParserPasses::new(&ctx.device)?,
            bg_cache: std::sync::Mutex::new(BindGroupCache::new()),
        })
    }

    /// One-shot GPU parse pipeline. Tables are provided per-call (unlike the lexer),
    /// so we allocate `ParserBuffers` per invocation.
    pub async fn parse(
        &self,
        token_kinds_u32: &[u32],
        tables: &PrecomputedParseTables,
    ) -> Result<ParseResult> {
        // Build the headers grid bytes from the 7-array tables.
        let action_table_bytes = tables.to_action_header_grid_bytes();
        let n_kinds = tables.n_kinds;

        // Allocate per-call buffers (they depend on the specific token pair sequence).
        let bufs = ParserBuffers::new(
            &self.device,
            token_kinds_u32,
            n_kinds,
            &action_table_bytes,
            tables,
        );

        // Timing is gated the same way as the lexer (and only if supported).
        let timers_on = self.timers_supported && bool_from_env("LANIUS_GPU_TIMING", false);
        let mut maybe_timer = if timers_on {
            Some(GpuTimer::new(&self.device, &self.queue, 128))
        } else {
            None
        };

        // Create an owned debug sink; we’ll hand out a temporary &mut to the passes.
        #[cfg(feature = "gpu-debug")]
        let mut debug_output = DebugOutput::default();

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.pipeline.encoder"),
            });

        if let Some(t) = maybe_timer.as_mut() {
            t.reset();
            t.stamp(&mut encoder, "BEGIN");
        }

        // ---- Record passes inside a short scope so borrows end before readbacks/timer use ----
        {
            let mut timer_ref = maybe_timer.as_mut();

            // Build the Option<&mut DebugOutput> locally without moving any outer state.
            #[allow(unused_mut)]
            let mut dbg_ref_opt: Option<&mut DebugOutput> = {
                #[cfg(feature = "gpu-debug")]
                {
                    Some(&mut debug_output)
                }
                #[cfg(not(feature = "gpu-debug"))]
                {
                    None
                }
            };

            let mut cache_guard = self.bg_cache.lock().expect("parser.bg_cache poisoned");

            let ctx = PassContext {
                device: &self.device,
                encoder: &mut encoder,
                buffers: &bufs,
                maybe_timer: &mut timer_ref,
                maybe_dbg: &mut dbg_ref_opt,
                bg_cache: Some(&mut *cache_guard),
            };

            // Record all passes in one place (like the lexer).
            passes::record_all_passes(ctx, &self.passes)?;
        } // <- drop ctx, timer_ref, dbg_ref_opt, cache_guard

        // -------- Submit & (optionally) read back --------
        let rb_enabled = readback_enabled();

        // Build readback buffers only when needed (keeps resource count and bandwidth low).
        let rb_handles = if rb_enabled {
            let rb = readback::ParserReadbacks::create(&self.device, &bufs);
            rb.encode_copies(&mut encoder, &bufs);
            Some(rb)
        } else {
            None
        };

        if let Some(t) = maybe_timer.as_mut() {
            t.stamp(&mut encoder, "resolve timers");
            t.resolve(&mut encoder);
        }

        let use_scopes = bool_from_env("LANIUS_VALIDATION_SCOPES", false);
        if use_scopes {
            self.device.push_error_scope(wgpu::ErrorFilter::Validation);
        }
        self.queue.submit(Some(encoder.finish()));
        if use_scopes {
            if let Some(err) = pollster::block_on(self.device.pop_error_scope()) {
                eprintln!("[wgpu submit] validation while submitting parser batch: {err:#?}");
            }
        }

        // If readback is off, return empty result shells (timers still print).
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
                    if dt_ms >= MINIMUM_TIME_TO_NOT_ELIDE_MS {
                        println!("[gpu_timer] {label}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
                    }
                    prev = t;
                }
            }

            return Ok(ParseResult {
                headers: Vec::new(),
                sc_stream: Vec::new(),
                emit_stream: Vec::new(),
                brackets: BracketsMatchResult {
                    valid: true,
                    final_depth: 0,
                    min_depth: 0,
                    match_for_index: Vec::new(),
                },
                node_kind: Vec::new(),
                parent: Vec::new(),
                debug: DebugOutput::default(),
            });
        }

        // ------------ map & decode staging buffers -------------
        let decoded = readback::DecodedParserReadbacks::map_and_decode(
            &self.device,
            &bufs,
            rb_handles.expect("rb_enabled"),
        )?;

        // Print timers (same as lexer).
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
                if dt_ms >= MINIMUM_TIME_TO_NOT_ELIDE_MS {
                    println!("[gpu_timer] {label}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
                }
                prev = t;
            }
        }

        // Move out the owned debug snapshot (when the feature is on), otherwise default.
        #[allow(unused_mut)]
        let mut debug_sink = {
            #[cfg(feature = "gpu-debug")]
            {
                std::mem::take(&mut debug_output)
            }
            #[cfg(not(feature = "gpu-debug"))]
            {
                DebugOutput::default()
            }
        };

        Ok(ParseResult {
            headers: decoded.headers,
            sc_stream: decoded.sc_stream,
            emit_stream: decoded.emit_stream,
            brackets: BracketsMatchResult {
                valid: decoded.valid,
                final_depth: decoded.final_depth,
                min_depth: decoded.min_depth,
                match_for_index: decoded.match_for_index,
            },
            node_kind: decoded.node_kind,
            parent: decoded.parent,
            debug: std::mem::take(&mut debug_sink),
        })
    }
}

// Optional singleton, mirroring the lexer’s `lex_on_gpu`.
static GPU_PARSER: OnceLock<GpuParser> = OnceLock::new();

pub async fn get_global_parser() -> &'static GpuParser {
    GPU_PARSER.get_or_init(|| pollster::block_on(GpuParser::new()).expect("GPU parser init"))
}
