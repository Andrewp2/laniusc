// src/parser/gpu/driver.rs
use std::sync::Arc;

use anyhow::{Result, anyhow};
use wgpu;

use crate::{
    gpu::{
        buffers::readback_bytes,
        device,
        passes_core::{InputElements, Pass},
        timer::GpuTimer,
    },
    parser::{
        gpu::{
            buffers::{ActionHeader, ParserBuffers},
            debug::DebugOutput,
            passes::{BracketsMatchPass, LLPPairsPass, PackVarlenPass},
        },
        tables::PrecomputedParseTables,
    },
};

pub struct GpuParser {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    timers_supported: bool,

    pass_llp: LLPPairsPass,
    pass_pack: PackVarlenPass,
    pass_brackets: BracketsMatchPass,
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

    /// Populated by each pass via record_debug(); consumers can copy out snapshots.
    pub debug: DebugOutput,
}

impl GpuParser {
    pub async fn new() -> Result<Self> {
        let ctx = device::global();
        let device = ctx.device.clone();
        let queue = ctx.queue.clone();

        let pass_llp = LLPPairsPass::new(&device)?;
        let pass_pack = PackVarlenPass::new(&device)?;
        let pass_brackets = BracketsMatchPass::new(&device)?;

        Ok(Self {
            device,
            queue,
            timers_supported: ctx.timers_supported,
            pass_llp,
            pass_pack,
            pass_brackets,
        })
    }

    /// One-shot GPU parse pipeline:
    ///   1) pair → headers
    ///   2) pack var-len streams (stack-change + emits)
    ///   3) bracket validation + match map
    ///
    /// Returns all readbacks you’ll want in one struct, and prints GPU timing if supported.
    pub async fn parse(
        &self,
        token_kinds_u32: &[u32],
        tables: &PrecomputedParseTables,
    ) -> Result<ParseResult> {
        // Build the headers grid bytes from the 7-array tables.
        // (This just gives the per-(prev,this) push/pop counts for pass #1.)
        let action_table_bytes = tables.to_action_header_grid_bytes();
        let n_kinds = tables.n_kinds;

        // Build all GPU-side buffers sized for this input.
        let bufs = ParserBuffers::new(
            &self.device,
            token_kinds_u32,
            n_kinds,
            &action_table_bytes,
            tables,
        );

        // Optional GPU timer (enabled if supported); we always pass it through when present.
        let mut maybe_timer = if self.timers_supported {
            Some(GpuTimer::new(&self.device, &self.queue, 128))
        } else {
            None
        };

        // Real debug capture (we do not pass None here).
        let mut debug_output = DebugOutput::default();
        let mut dbg_opt: Option<&mut DebugOutput> = Some(&mut debug_output);

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.pipeline.encoder"),
            });

        if let Some(t) = maybe_timer.as_mut() {
            t.reset();
            t.stamp(&mut encoder, "BEGIN");
        }

        // 1) pair → headers
        self.pass_llp.record_pass(
            &self.device,
            &mut encoder,
            &bufs,
            InputElements::Elements1D(bufs.n_tokens.saturating_sub(1)),
            &mut maybe_timer.as_mut(),
            &mut dbg_opt,
        )?;

        // 2) pack var-len streams (writes out_sc + out_emit)
        self.pass_pack.record_pass(
            &self.device,
            &mut encoder,
            &bufs,
            InputElements::Elements1D(bufs.n_tokens.saturating_sub(1)),
            &mut maybe_timer.as_mut(),
            &mut dbg_opt,
        )?;

        // 3) bracket validation on the packed stack-change stream
        self.pass_brackets.record_pass(
            &self.device,
            &mut encoder,
            &bufs,
            // Single-thread pass; dispatch 1 group to avoid redundant no-ops.
            InputElements::Elements1D(1),
            &mut maybe_timer.as_mut(),
            &mut dbg_opt,
        )?;

        // Readbacks: headers, out_sc, out_emit, bracket outputs (match/depths/valid)
        let rb_headers = readback_bytes(
            &self.device,
            "rb.parser.out_headers",
            bufs.out_headers.byte_size,
            1,
        );
        let rb_sc = readback_bytes(
            &self.device,
            "rb.parser.out_sc",
            (bufs.total_sc.max(1) * 4) as usize,
            1,
        );
        let rb_emit = readback_bytes(
            &self.device,
            "rb.parser.out_emit",
            (bufs.total_emit.max(1) * 4) as usize,
            1,
        );
        let rb_match = readback_bytes(
            &self.device,
            "rb.parser.match_for_index",
            bufs.match_for_index.byte_size,
            1,
        );
        let rb_depths = readback_bytes(
            &self.device,
            "rb.parser.depths_out",
            bufs.depths_out.byte_size,
            1,
        );
        let rb_valid = readback_bytes(
            &self.device,
            "rb.parser.valid_out",
            bufs.valid_out.byte_size,
            1,
        );

        // Copy to staging
        encoder.copy_buffer_to_buffer(
            &bufs.out_headers,
            0,
            &rb_headers,
            0,
            bufs.out_headers.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(&bufs.out_sc, 0, &rb_sc, 0, bufs.out_sc.byte_size as u64);
        encoder.copy_buffer_to_buffer(
            &bufs.out_emit,
            0,
            &rb_emit,
            0,
            bufs.out_emit.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.match_for_index,
            0,
            &rb_match,
            0,
            bufs.match_for_index.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.depths_out,
            0,
            &rb_depths,
            0,
            bufs.depths_out.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.valid_out,
            0,
            &rb_valid,
            0,
            bufs.valid_out.byte_size as u64,
        );

        if let Some(t) = maybe_timer.as_mut() {
            t.stamp(&mut encoder, "resolve timers");
            t.resolve(&mut encoder);
        }

        self.queue.submit(Some(encoder.finish()));

        // Map readbacks
        let map_all = |b: &wgpu::Buffer| {
            let sl = b.slice(..);
            sl.map_async(wgpu::MapMode::Read, |_| {});
        };
        map_all(&rb_headers);
        map_all(&rb_sc);
        map_all(&rb_emit);
        map_all(&rb_match);
        map_all(&rb_depths);
        map_all(&rb_valid);

        // Wait for GPU
        let _ = self.device.poll(wgpu::PollType::Wait);

        // Decode headers
        let headers = {
            let data = rb_headers.slice(..).get_mapped_range();
            let count = (bufs.n_tokens.saturating_sub(1)) as usize;
            decode_action_headers(&data, count)?
        };
        rb_headers.unmap();

        // Decode streams
        let sc_stream = {
            let data = rb_sc.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(bufs.total_sc as usize);
            for chunk in data.chunks_exact(4) {
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            v
        };
        rb_sc.unmap();

        let emit_stream = {
            let data = rb_emit.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(bufs.total_emit as usize);
            for chunk in data.chunks_exact(4) {
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            v
        };
        rb_emit.unmap();

        // Decode bracket outputs
        let match_for_index = {
            let data = rb_match.slice(..).get_mapped_range();
            let mut v = Vec::with_capacity(bufs.match_for_index.count);
            for chunk in data.chunks_exact(4) {
                v.push(u32::from_le_bytes(chunk.try_into().unwrap()));
            }
            v
        };
        rb_match.unmap();

        let (final_depth, min_depth) = {
            let data = rb_depths.slice(..).get_mapped_range();
            let fd = i32::from_le_bytes(data[0..4].try_into().unwrap());
            let md = i32::from_le_bytes(data[4..8].try_into().unwrap());
            (fd, md)
        };
        rb_depths.unmap();

        let valid = {
            let data = rb_valid.slice(..).get_mapped_range();
            u32::from_le_bytes(data[0..4].try_into().unwrap()) != 0
        };
        rb_valid.unmap();

        // Emit timer results if available (same style as the lexer).
        if let Some(timer) = maybe_timer {
            if let Some(vals) = timer.try_read(&self.device) {
                if !vals.is_empty() {
                    let period_ns = timer.period_ns() as f64;
                    let t0 = vals[0].1;
                    let mut prev = t0;
                    for (label, t) in vals {
                        let dt_ms = ((t - prev) as f64 * period_ns) / 1.0e6;
                        let total_ms = ((t - t0) as f64 * period_ns) / 1.0e6;
                        // Keep the log tidy: skip tiny deltas
                        if dt_ms >= 0.5 {
                            println!("[gpu_timer] {label}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
                        }
                        prev = t;
                    }
                }
            }
        }

        Ok(ParseResult {
            headers,
            sc_stream,
            emit_stream,
            brackets: BracketsMatchResult {
                valid,
                final_depth,
                min_depth,
                match_for_index,
            },
            debug: debug_output, // caller can inspect snapshots if compiled in
        })
    }
}

// --------- helpers / result types ----------

fn decode_action_headers(bytes: &[u8], count: usize) -> Result<Vec<ActionHeader>> {
    let stride = std::mem::size_of::<ActionHeader>();
    if bytes.len() < stride * count {
        return Err(anyhow!("out_headers readback too small"));
    }
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        let off = i * stride;
        let push_len = u32::from_le_bytes(bytes[off + 0..off + 4].try_into().unwrap());
        let emit_len = u32::from_le_bytes(bytes[off + 4..off + 8].try_into().unwrap());
        let pop_tag = u32::from_le_bytes(bytes[off + 8..off + 12].try_into().unwrap());
        let pop_count = u32::from_le_bytes(bytes[off + 12..off + 16].try_into().unwrap());
        out.push(ActionHeader {
            push_len,
            emit_len,
            pop_tag,
            pop_count,
        });
    }
    Ok(out)
}
