// src/parser/gpu/driver.rs
//! GPU parser driver, reshaped to mirror the style used by the lexer driver:
//! - Pass bundle + `record_all_passes`
//! - Bind-group cache reuse across passes
//! - Env-gated timers and validation scopes
//! - Optional readback (LANIUS_READBACK), returning empty streams when off

use std::{
    collections::HashMap,
    hash::{Hash, Hasher},
    sync::{Arc, OnceLock},
};

use anyhow::Result;
use encase::ShaderType;
use wgpu;

use super::passes::ll1_blocks_01::LL1_BLOCK_STATUS_WORDS;
use crate::{
    gpu::{
        buffers::{LaniusBuffer, uniform_from_val},
        device,
        passes_core::{BindGroupCache, Pass, PassContext, PassData, bind_group, make_pass_data},
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

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct TokensToKindsParams {
    token_capacity: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct DirectHirParams {
    n_tokens: u32,
}

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

fn stamp_timer(
    timer_ref: &mut Option<&mut GpuTimer>,
    encoder: &mut wgpu::CommandEncoder,
    label: impl Into<String>,
) {
    if let Some(timer) = timer_ref.as_deref_mut() {
        timer.stamp(encoder, label);
    }
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

    tokens_to_kinds: PassData,
    direct_hir: PassData,
    syntax_checker: super::syntax::GpuSyntaxChecker,
    passes: ParserPasses,

    // Bind group cache so passes don’t recreate BGs every dispatch.
    bg_cache: std::sync::Mutex<BindGroupCache>,

    // Resident lexer→parser buffers reused by the compiler path when the parse
    // table identity is unchanged and the previous allocation is large enough.
    resident_buffers: std::sync::Mutex<Option<ResidentParserBufferCache>>,
    resident_direct_bind_groups: std::sync::Mutex<Option<ResidentDirectParserBindGroups>>,
}

pub struct BracketsMatchResult {
    pub valid: bool,
    pub final_depth: i32,
    pub min_depth: i32,
    pub match_for_index: Vec<u32>,
}

#[derive(Clone, Debug)]
pub struct Ll1AcceptResult {
    pub accepted: bool,
    pub error_pos: u32,
    pub error_code: u32,
    pub detail: u32,
    pub steps: u32,
    pub emit_len: u32,
}

#[derive(Clone, Debug)]
pub struct Ll1SeedPlanResult {
    pub accepted: bool,
    pub pos: u32,
    pub error_code: u32,
    pub detail: u32,
    pub steps: u32,
    pub seed_count: u32,
    pub max_depth: u32,
    pub emit_len: u32,
}

#[derive(Clone, Debug)]
pub struct Ll1BlockSummary {
    pub status: u32,
    pub begin: u32,
    pub end: u32,
    pub pos: u32,
    pub steps: u32,
    pub emit_len: u32,
    pub stack_depth: u32,
    pub error_code: u32,
    pub detail: u32,
    pub first_production: u32,
}

pub struct ParseResult {
    pub ll1: Ll1AcceptResult,
    pub ll1_emit_stream: Vec<u32>,
    pub ll1_emit_token_pos: Vec<u32>,
    pub ll1_block_size: u32,
    pub ll1_block_emit_stride: u32,
    pub ll1_block_seed_len: Vec<u32>,
    pub ll1_seed_plan: Ll1SeedPlanResult,
    pub ll1_seeded_blocks: Vec<Ll1BlockSummary>,
    pub ll1_seeded_emit: Vec<u32>,
    pub headers: Vec<ActionHeader>,
    pub sc_stream: Vec<u32>,
    pub emit_stream: Vec<u32>,
    pub brackets: BracketsMatchResult,

    /// Tree outputs (inverted tree arrays), read back from GPU.
    pub node_kind: Vec<u32>,
    pub parent: Vec<u32>,
    pub first_child: Vec<u32>,
    pub next_sibling: Vec<u32>,
    pub subtree_end: Vec<u32>,
    pub hir_kind: Vec<u32>,
    pub hir_token_pos: Vec<u32>,
    pub hir_token_end: Vec<u32>,

    /// Populated by each pass via record_debug(); consumers can copy out snapshots.
    pub debug: DebugOutput,
}

#[derive(Clone, Debug)]
pub struct ResidentParseResult {
    pub ll1: Ll1AcceptResult,
    pub ll1_emit_stream: Vec<u32>,
    pub ll1_emit_token_pos: Vec<u32>,
    pub node_kind: Vec<u32>,
    pub parent: Vec<u32>,
    pub first_child: Vec<u32>,
    pub next_sibling: Vec<u32>,
    pub subtree_end: Vec<u32>,
    pub hir_kind: Vec<u32>,
    pub hir_token_pos: Vec<u32>,
    pub hir_token_end: Vec<u32>,
}

pub struct RecordedResidentSyntaxHirCheck {
    syntax_check: super::syntax::RecordedSyntaxCheck,
    status_readback: wgpu::Buffer,
}

pub struct RecordedResidentLl1HirCheck {
    status_readback: wgpu::Buffer,
}

struct ResidentParserBufferCache {
    token_capacity: u32,
    table_fingerprint: u64,
    buffers: ParserBuffers,
}

struct ResidentDirectParserBindGroups {
    input_fingerprint: u64,
    tokens_to_kinds_params: LaniusBuffer<TokensToKindsParams>,
    direct_hir_params: LaniusBuffer<DirectHirParams>,
    tokens_to_kinds: wgpu::BindGroup,
    direct_hir: wgpu::BindGroup,
}

impl GpuParser {
    pub async fn new() -> Result<Self> {
        Self::new_with_device(device::global()).await
    }

    pub async fn new_with_device(ctx: &device::GpuDevice) -> Result<Self> {
        let device = Arc::clone(&ctx.device);
        let queue = Arc::clone(&ctx.queue);

        Ok(Self {
            device,
            queue,
            timers_supported: ctx.timers_supported,
            tokens_to_kinds: make_tokens_to_kinds_pass(&ctx.device)?,
            direct_hir: make_direct_hir_pass(&ctx.device)?,
            syntax_checker: super::syntax::GpuSyntaxChecker::new(),
            passes: ParserPasses::new(&ctx.device)?,
            bg_cache: std::sync::Mutex::new(BindGroupCache::new()),
            resident_buffers: std::sync::Mutex::new(None),
            resident_direct_bind_groups: std::sync::Mutex::new(None),
        })
    }

    pub fn check_resident_tokens(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
    ) -> Result<()> {
        self.with_checked_resident_parse_artifacts(
            token_capacity,
            token_buf,
            token_count_buf,
            tables,
            |_| Ok::<(), anyhow::Error>(()),
        )??;
        Ok(())
    }

    pub fn with_checked_resident_parse_artifacts<R, E>(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
        consume: impl FnOnce(&ParserBuffers) -> std::result::Result<R, E>,
    ) -> Result<std::result::Result<R, E>> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for(&mut resident_guard, token_capacity, tables);

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.resident_ll1.encoder"),
            });

        self.record_tokens_to_kinds(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            &bufs,
        )?;
        let mut timer_ref: Option<&mut GpuTimer> = None;
        self.record_ll1_resident_passes(&mut encoder, &bufs, true, true, &mut timer_ref)?;

        let status_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.resident_ll1.status"),
            size: 24,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.ll1_status, 0, &status_readback, 0, 24);

        let use_scopes = bool_from_env("LANIUS_VALIDATION_SCOPES", false);
        if use_scopes {
            self.device.push_error_scope(wgpu::ErrorFilter::Validation);
        }
        self.queue.submit(Some(encoder.finish()));
        if use_scopes {
            if let Some(err) = pollster::block_on(self.device.pop_error_scope()) {
                eprintln!(
                    "[wgpu submit] validation while submitting resident parser batch: {err:#?}"
                );
            }
        }

        let slice = status_readback.slice(..);
        slice.map_async(wgpu::MapMode::Read, |_| {});
        let _ = self.device.poll(wgpu::PollType::Wait);
        let mapped = slice.get_mapped_range();
        let words = read_u32_words(&mapped, 6)?;
        drop(mapped);
        status_readback.unmap();

        if words[0] == 0 {
            anyhow::bail!(
                "GPU LL(1) parser rejected token {}: error {} ({}) after {} steps",
                words[1],
                words[2],
                words[3],
                words[4]
            );
        }

        Ok(consume(bufs))
    }

    pub fn with_checked_resident_syntax_hir_artifacts<R, E>(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
        consume: impl FnOnce(&ParserBuffers) -> std::result::Result<R, E>,
    ) -> Result<std::result::Result<R, E>> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for(&mut resident_guard, token_capacity, tables);

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.resident_direct_hir.encoder"),
            });

        let syntax_check = self
            .syntax_checker
            .record_token_buffer_check(
                &self.device,
                &self.queue,
                &mut encoder,
                token_capacity,
                token_buf,
                token_count_buf,
            )
            .map_err(|err| anyhow::anyhow!(err.to_string()))?;
        self.record_tokens_to_kinds(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            &bufs,
        )?;
        self.record_direct_hir(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            &bufs,
        )?;

        let status_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.resident_direct_hir.status"),
            size: 24,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.ll1_status, 0, &status_readback, 0, 24);

        let use_scopes = bool_from_env("LANIUS_VALIDATION_SCOPES", false);
        if use_scopes {
            self.device.push_error_scope(wgpu::ErrorFilter::Validation);
        }
        self.queue.submit(Some(encoder.finish()));
        if use_scopes {
            if let Some(err) = pollster::block_on(self.device.pop_error_scope()) {
                eprintln!(
                    "[wgpu submit] validation while submitting resident direct HIR batch: {err:#?}"
                );
            }
        }

        super::syntax::GpuSyntaxChecker::finish_recorded_check(&self.device, &syntax_check)
            .map_err(|err| anyhow::anyhow!(err.to_string()))?;

        let slice = status_readback.slice(..);
        slice.map_async(wgpu::MapMode::Read, |_| {});
        let _ = self.device.poll(wgpu::PollType::Wait);
        let mapped = slice.get_mapped_range();
        let words = read_u32_words(&mapped, 6)?;
        drop(mapped);
        status_readback.unmap();

        if words[0] == 0 {
            anyhow::bail!(
                "GPU direct HIR parser rejected token {}: error {} ({}) after {} steps",
                words[1],
                words[2],
                words[3],
                words[4]
            );
        }

        Ok(consume(bufs))
    }

    pub fn record_checked_resident_syntax_hir_artifacts<R, E>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
        consume: impl FnOnce(&ParserBuffers, &mut wgpu::CommandEncoder) -> std::result::Result<R, E>,
    ) -> Result<(RecordedResidentSyntaxHirCheck, std::result::Result<R, E>)> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for(&mut resident_guard, token_capacity, tables);

        let syntax_check = self
            .syntax_checker
            .record_token_buffer_check(
                &self.device,
                &self.queue,
                encoder,
                token_capacity,
                token_buf,
                token_count_buf,
            )
            .map_err(|err| anyhow::anyhow!(err.to_string()))?;
        self.record_tokens_to_kinds(encoder, token_capacity, token_buf, token_count_buf, &bufs)?;
        self.record_direct_hir(encoder, token_capacity, token_buf, token_count_buf, &bufs)?;

        let status_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.recorded_direct_hir.status"),
            size: 24,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.ll1_status, 0, &status_readback, 0, 24);

        let consumed = consume(bufs, encoder);
        Ok((
            RecordedResidentSyntaxHirCheck {
                syntax_check,
                status_readback,
            },
            consumed,
        ))
    }

    pub fn record_checked_resident_ll1_hir_artifacts<R, E>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
        timer_ref: &mut Option<&mut GpuTimer>,
        consume: impl FnOnce(
            &ParserBuffers,
            &mut wgpu::CommandEncoder,
            &mut Option<&mut GpuTimer>,
        ) -> std::result::Result<R, E>,
    ) -> Result<(RecordedResidentLl1HirCheck, std::result::Result<R, E>)> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for(&mut resident_guard, token_capacity, tables);

        self.record_tokens_to_kinds(encoder, token_capacity, token_buf, token_count_buf, bufs)?;
        self.record_ll1_resident_passes(encoder, bufs, true, true, timer_ref)?;
        if let Some(timer) = timer_ref.as_deref_mut() {
            timer.stamp(encoder, "parser.done");
        }

        let status_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.recorded_ll1_hir.status"),
            size: 24,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.ll1_status, 0, &status_readback, 0, 24);

        let consumed = consume(bufs, encoder, timer_ref);
        Ok((RecordedResidentLl1HirCheck { status_readback }, consumed))
    }

    pub fn finish_recorded_resident_syntax_hir_check(
        &self,
        recorded: &RecordedResidentSyntaxHirCheck,
    ) -> Result<()> {
        super::syntax::GpuSyntaxChecker::finish_recorded_check(
            &self.device,
            &recorded.syntax_check,
        )
        .map_err(|err| anyhow::anyhow!(err.to_string()))?;

        let slice = recorded.status_readback.slice(..);
        slice.map_async(wgpu::MapMode::Read, |_| {});
        let _ = self.device.poll(wgpu::PollType::Wait);
        let mapped = slice.get_mapped_range();
        let words = read_u32_words(&mapped, 6)?;
        drop(mapped);
        recorded.status_readback.unmap();

        if words[0] == 0 {
            anyhow::bail!(
                "GPU direct HIR parser rejected token {}: error {} ({}) after {} steps",
                words[1],
                words[2],
                words[3],
                words[4]
            );
        }

        Ok(())
    }

    pub fn with_recorded_checked_resident_syntax_hir_artifacts<S, R, E>(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
        record_more: impl FnOnce(&ParserBuffers, &mut wgpu::CommandEncoder) -> std::result::Result<S, E>,
        consume_after_submit: impl FnOnce(&ParserBuffers, S) -> std::result::Result<R, E>,
    ) -> Result<std::result::Result<R, E>> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for(&mut resident_guard, token_capacity, tables);

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.resident_direct_hir.recorded.encoder"),
            });

        let syntax_check = self
            .syntax_checker
            .record_token_buffer_check(
                &self.device,
                &self.queue,
                &mut encoder,
                token_capacity,
                token_buf,
                token_count_buf,
            )
            .map_err(|err| anyhow::anyhow!(err.to_string()))?;
        self.record_tokens_to_kinds(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            &bufs,
        )?;
        self.record_direct_hir(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            &bufs,
        )?;

        let status_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.recorded_direct_hir.status"),
            size: 24,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.ll1_status, 0, &status_readback, 0, 24);

        let recorded_parser = RecordedResidentSyntaxHirCheck {
            syntax_check,
            status_readback,
        };
        let recorded_more = match record_more(bufs, &mut encoder) {
            Ok(recorded) => recorded,
            Err(err) => return Ok(Err(err)),
        };

        let use_scopes = bool_from_env("LANIUS_VALIDATION_SCOPES", false);
        if use_scopes {
            self.device.push_error_scope(wgpu::ErrorFilter::Validation);
        }
        self.queue.submit(Some(encoder.finish()));
        if use_scopes {
            if let Some(err) = pollster::block_on(self.device.pop_error_scope()) {
                eprintln!(
                    "[wgpu submit] validation while submitting recorded direct HIR batch: {err:#?}"
                );
            }
        }

        self.finish_recorded_resident_syntax_hir_check(&recorded_parser)?;
        Ok(consume_after_submit(bufs, recorded_more))
    }

    pub fn with_recorded_checked_resident_ll1_hir_artifacts<S, R, E>(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
        record_more: impl FnOnce(&ParserBuffers, &mut wgpu::CommandEncoder) -> std::result::Result<S, E>,
        consume_after_submit: impl FnOnce(&ParserBuffers, S) -> std::result::Result<R, E>,
    ) -> Result<std::result::Result<R, E>> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for(&mut resident_guard, token_capacity, tables);

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.resident_ll1_hir.recorded.encoder"),
            });

        self.record_tokens_to_kinds(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            &bufs,
        )?;
        let mut timer_ref: Option<&mut GpuTimer> = None;
        self.record_ll1_resident_passes(&mut encoder, &bufs, true, true, &mut timer_ref)?;

        let status_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.recorded_ll1_hir.status"),
            size: 24,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.ll1_status, 0, &status_readback, 0, 24);

        let recorded_parser = RecordedResidentLl1HirCheck { status_readback };
        let recorded_more = match record_more(bufs, &mut encoder) {
            Ok(recorded) => recorded,
            Err(err) => return Ok(Err(err)),
        };

        let use_scopes = bool_from_env("LANIUS_VALIDATION_SCOPES", false);
        if use_scopes {
            self.device.push_error_scope(wgpu::ErrorFilter::Validation);
        }
        self.queue.submit(Some(encoder.finish()));
        if use_scopes {
            if let Some(err) = pollster::block_on(self.device.pop_error_scope()) {
                eprintln!(
                    "[wgpu submit] validation while submitting recorded LL(1) HIR batch: {err:#?}"
                );
            }
        }

        self.finish_recorded_resident_ll1_hir_check(&recorded_parser)?;
        Ok(consume_after_submit(bufs, recorded_more))
    }

    pub fn finish_recorded_resident_ll1_hir_check(
        &self,
        recorded: &RecordedResidentLl1HirCheck,
    ) -> Result<()> {
        let slice = recorded.status_readback.slice(..);
        slice.map_async(wgpu::MapMode::Read, |_| {});
        let _ = self.device.poll(wgpu::PollType::Wait);
        let mapped = slice.get_mapped_range();
        let words = read_u32_words(&mapped, 6)?;
        drop(mapped);
        recorded.status_readback.unmap();

        if words[0] == 0 {
            anyhow::bail!(
                "GPU LL(1) parser rejected token {}: error {} ({}) after {} steps",
                words[1],
                words[2],
                words[3],
                words[4]
            );
        }

        Ok(())
    }

    pub fn with_current_resident_buffers<R>(
        &self,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
        consume: impl FnOnce(&ParserBuffers) -> R,
    ) -> R {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for(&mut resident_guard, token_capacity, tables);
        consume(bufs)
    }

    pub fn parse_resident_tokens(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
    ) -> Result<ResidentParseResult> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for(&mut resident_guard, token_capacity, tables);

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.resident_tree.encoder"),
            });

        self.record_tokens_to_kinds(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            &bufs,
        )?;
        let mut timer_ref: Option<&mut GpuTimer> = None;
        self.record_ll1_resident_passes(&mut encoder, &bufs, true, true, &mut timer_ref)?;

        let status_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.resident_tree.status"),
            size: bufs.ll1_status.byte_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let emit_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.resident_tree.ll1_emit"),
            size: bufs.ll1_emit.byte_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let emit_pos_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.resident_tree.ll1_emit_pos"),
            size: bufs.ll1_emit_pos.byte_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let node_kind_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.resident_tree.node_kind"),
            size: bufs.node_kind.byte_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let parent_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.resident_tree.parent"),
            size: bufs.parent.byte_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let first_child_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.resident_tree.first_child"),
            size: bufs.first_child.byte_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let next_sibling_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.resident_tree.next_sibling"),
            size: bufs.next_sibling.byte_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let subtree_end_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.resident_tree.subtree_end"),
            size: bufs.subtree_end.byte_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let hir_kind_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.resident_tree.hir_kind"),
            size: bufs.hir_kind.byte_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let hir_token_pos_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.resident_tree.hir_token_pos"),
            size: bufs.hir_token_pos.byte_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let hir_token_end_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.resident_tree.hir_token_end"),
            size: bufs.hir_token_end.byte_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });

        encoder.copy_buffer_to_buffer(
            &bufs.ll1_status,
            0,
            &status_readback,
            0,
            bufs.ll1_status.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_emit,
            0,
            &emit_readback,
            0,
            bufs.ll1_emit.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_emit_pos,
            0,
            &emit_pos_readback,
            0,
            bufs.ll1_emit_pos.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.node_kind,
            0,
            &node_kind_readback,
            0,
            bufs.node_kind.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.parent,
            0,
            &parent_readback,
            0,
            bufs.parent.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.first_child,
            0,
            &first_child_readback,
            0,
            bufs.first_child.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.next_sibling,
            0,
            &next_sibling_readback,
            0,
            bufs.next_sibling.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.subtree_end,
            0,
            &subtree_end_readback,
            0,
            bufs.subtree_end.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_kind,
            0,
            &hir_kind_readback,
            0,
            bufs.hir_kind.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_token_pos,
            0,
            &hir_token_pos_readback,
            0,
            bufs.hir_token_pos.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_token_end,
            0,
            &hir_token_end_readback,
            0,
            bufs.hir_token_end.byte_size as u64,
        );

        let use_scopes = bool_from_env("LANIUS_VALIDATION_SCOPES", false);
        if use_scopes {
            self.device.push_error_scope(wgpu::ErrorFilter::Validation);
        }
        self.queue.submit(Some(encoder.finish()));
        if use_scopes {
            if let Some(err) = pollster::block_on(self.device.pop_error_scope()) {
                eprintln!(
                    "[wgpu submit] validation while submitting resident parser tree batch: {err:#?}"
                );
            }
        }

        let map = |buffer: &wgpu::Buffer| {
            buffer.slice(..).map_async(wgpu::MapMode::Read, |_| {});
        };
        map(&status_readback);
        map(&emit_readback);
        map(&emit_pos_readback);
        map(&node_kind_readback);
        map(&parent_readback);
        map(&first_child_readback);
        map(&next_sibling_readback);
        map(&subtree_end_readback);
        map(&hir_kind_readback);
        map(&hir_token_pos_readback);
        map(&hir_token_end_readback);
        let _ = self.device.poll(wgpu::PollType::Wait);

        let ll1_words = {
            let mapped = status_readback.slice(..).get_mapped_range();
            let mut out = [0u32; 6];
            for (i, chunk) in mapped.chunks_exact(4).take(6).enumerate() {
                out[i] = u32::from_le_bytes(chunk.try_into().unwrap());
            }
            drop(mapped);
            status_readback.unmap();
            out
        };
        let emit_len = (ll1_words[5] as usize).min(bufs.ll1_emit.count);

        let ll1_emit_stream = {
            let mapped = emit_readback.slice(..).get_mapped_range();
            let words = read_u32_words(&mapped, emit_len)?;
            drop(mapped);
            emit_readback.unmap();
            words
        };
        let ll1_emit_token_pos = {
            let mapped = emit_pos_readback.slice(..).get_mapped_range();
            let words = read_u32_words(&mapped, emit_len)?;
            drop(mapped);
            emit_pos_readback.unmap();
            words
        };
        let node_kind = {
            let mapped = node_kind_readback.slice(..).get_mapped_range();
            let words = read_u32_words(&mapped, emit_len)?;
            drop(mapped);
            node_kind_readback.unmap();
            words
        };
        let parent = {
            let mapped = parent_readback.slice(..).get_mapped_range();
            let words = read_u32_words(&mapped, emit_len)?;
            drop(mapped);
            parent_readback.unmap();
            words
        };
        let first_child = {
            let mapped = first_child_readback.slice(..).get_mapped_range();
            let words = read_u32_words(&mapped, emit_len)?;
            drop(mapped);
            first_child_readback.unmap();
            words
        };
        let next_sibling = {
            let mapped = next_sibling_readback.slice(..).get_mapped_range();
            let words = read_u32_words(&mapped, emit_len)?;
            drop(mapped);
            next_sibling_readback.unmap();
            words
        };
        let subtree_end = {
            let mapped = subtree_end_readback.slice(..).get_mapped_range();
            let words = read_u32_words(&mapped, emit_len)?;
            drop(mapped);
            subtree_end_readback.unmap();
            words
        };
        let hir_kind = {
            let mapped = hir_kind_readback.slice(..).get_mapped_range();
            let words = read_u32_words(&mapped, emit_len)?;
            drop(mapped);
            hir_kind_readback.unmap();
            words
        };
        let hir_token_pos = {
            let mapped = hir_token_pos_readback.slice(..).get_mapped_range();
            let words = read_u32_words(&mapped, emit_len)?;
            drop(mapped);
            hir_token_pos_readback.unmap();
            words
        };
        let hir_token_end = {
            let mapped = hir_token_end_readback.slice(..).get_mapped_range();
            let words = read_u32_words(&mapped, emit_len)?;
            drop(mapped);
            hir_token_end_readback.unmap();
            words
        };

        Ok(ResidentParseResult {
            ll1: Ll1AcceptResult {
                accepted: ll1_words[0] != 0,
                error_pos: ll1_words[1],
                error_code: ll1_words[2],
                detail: ll1_words[3],
                steps: ll1_words[4],
                emit_len: ll1_words[5],
            },
            ll1_emit_stream,
            ll1_emit_token_pos,
            node_kind,
            parent,
            first_child,
            next_sibling,
            subtree_end,
            hir_kind,
            hir_token_pos,
            hir_token_end,
        })
    }

    fn record_tokens_to_kinds(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let pass = &self.tokens_to_kinds;
        let mut bind_guard = self
            .resident_direct_bind_groups
            .lock()
            .expect("parser.resident_direct_bind_groups poisoned");
        self.ensure_resident_direct_bind_groups(&mut bind_guard, token_buf, token_count_buf, bufs)?;
        let bind_groups = bind_guard
            .as_ref()
            .expect("resident direct parser bind groups allocated");
        write_uniform(
            &self.queue,
            &bind_groups.tokens_to_kinds_params,
            &TokensToKindsParams { token_capacity },
        );

        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("parser.tokens_to_kinds.pass"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(&bind_groups.tokens_to_kinds), &[]);
        compute.dispatch_workgroups((token_capacity + 2).div_ceil(256).max(1), 1, 1);
        Ok(())
    }

    fn record_direct_hir(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let pass = &self.direct_hir;
        let mut bind_guard = self
            .resident_direct_bind_groups
            .lock()
            .expect("parser.resident_direct_bind_groups poisoned");
        self.ensure_resident_direct_bind_groups(&mut bind_guard, token_buf, token_count_buf, bufs)?;
        let bind_groups = bind_guard
            .as_ref()
            .expect("resident direct parser bind groups allocated");
        write_uniform(
            &self.queue,
            &bind_groups.direct_hir_params,
            &DirectHirParams {
                n_tokens: token_capacity,
            },
        );

        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("parser.direct_hir.pass"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(&bind_groups.direct_hir), &[]);
        compute.dispatch_workgroups(token_capacity.saturating_add(1).div_ceil(256).max(1), 1, 1);
        Ok(())
    }

    fn ensure_resident_direct_bind_groups(
        &self,
        slot: &mut Option<ResidentDirectParserBindGroups>,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let fingerprint = buffer_fingerprint(&[
            token_buf,
            token_count_buf,
            &bufs.token_kinds,
            &bufs.token_count,
            &bufs.hir_kind,
            &bufs.hir_token_pos,
            &bufs.hir_token_end,
            &bufs.ll1_status,
        ]);
        if slot
            .as_ref()
            .is_none_or(|cached| cached.input_fingerprint != fingerprint)
        {
            *slot = Some(self.create_resident_direct_bind_groups(
                fingerprint,
                token_buf,
                token_count_buf,
                bufs,
            )?);
        }
        Ok(())
    }

    fn create_resident_direct_bind_groups(
        &self,
        input_fingerprint: u64,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<ResidentDirectParserBindGroups> {
        let tokens_to_kinds_params = uniform_from_val(
            &self.device,
            "parser.tokens_to_kinds.params",
            &TokensToKindsParams { token_capacity: 0 },
        );
        let direct_hir_params = uniform_from_val(
            &self.device,
            "parser.direct_hir.params",
            &DirectHirParams { n_tokens: 0 },
        );

        let tokens_to_kinds_resources: HashMap<String, wgpu::BindingResource<'_>> =
            HashMap::from([
                ("gParams".into(), tokens_to_kinds_params.as_entire_binding()),
                ("token_words".into(), token_buf.as_entire_binding()),
                (
                    "lexer_token_count".into(),
                    token_count_buf.as_entire_binding(),
                ),
                ("token_kinds".into(), bufs.token_kinds.as_entire_binding()),
                (
                    "parser_token_count".into(),
                    bufs.token_count.as_entire_binding(),
                ),
            ]);
        let tokens_to_kinds = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_to_kinds"),
            &self.tokens_to_kinds.bind_group_layouts[0],
            &self.tokens_to_kinds.reflection,
            0,
            &tokens_to_kinds_resources,
        )?;

        let direct_hir_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), direct_hir_params.as_entire_binding()),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("token_count".into(), bufs.token_count.as_entire_binding()),
            ("hir_kind".into(), bufs.hir_kind.as_entire_binding()),
            (
                "hir_token_pos".into(),
                bufs.hir_token_pos.as_entire_binding(),
            ),
            (
                "hir_token_end".into(),
                bufs.hir_token_end.as_entire_binding(),
            ),
            ("hir_status".into(), bufs.ll1_status.as_entire_binding()),
        ]);
        let direct_hir = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_direct_hir"),
            &self.direct_hir.bind_group_layouts[0],
            &self.direct_hir.reflection,
            0,
            &direct_hir_resources,
        )?;

        Ok(ResidentDirectParserBindGroups {
            input_fingerprint,
            tokens_to_kinds_params,
            direct_hir_params,
            tokens_to_kinds,
            direct_hir,
        })
    }

    fn record_ll1_resident_passes(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
        include_tree: bool,
        include_hir_spans: bool,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<()> {
        let mut no_timer: Option<&mut GpuTimer> = None;
        let mut dbg_ref: Option<&mut DebugOutput> = None;
        let mut cache_guard = self.bg_cache.lock().expect("parser.bg_cache poisoned");
        let mut ctx = PassContext {
            device: &self.device,
            encoder,
            buffers: bufs,
            maybe_timer: &mut no_timer,
            maybe_dbg: &mut dbg_ref,
            bg_cache: Some(&mut *cache_guard),
        };

        let n_ll1_blocks = bufs.ll1_n_blocks;
        self.passes.ll1_blocks_02.record_pass(
            &mut ctx,
            crate::gpu::passes_core::InputElements::Elements1D(n_ll1_blocks.saturating_mul(256)),
        )?;
        stamp_timer(timer_ref, ctx.encoder, "parser.ll1_blocks_02");
        self.passes.ll1_blocks_03.record_pass(
            &mut ctx,
            crate::gpu::passes_core::InputElements::Elements1D(n_ll1_blocks.saturating_mul(256)),
        )?;
        stamp_timer(timer_ref, ctx.encoder, "parser.ll1_blocks_03");
        self.passes
            .ll1_blocks_04_scan
            .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
        stamp_timer(timer_ref, ctx.encoder, "parser.ll1_blocks_04_scan");
        self.passes.ll1_blocks_04.record_pass(
            &mut ctx,
            crate::gpu::passes_core::InputElements::Elements1D(
                n_ll1_blocks.max(2).saturating_mul(256),
            ),
        )?;
        stamp_timer(timer_ref, ctx.encoder, "parser.ll1_blocks_04");
        if include_tree {
            self.passes.tree_prefix_01.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(
                    bufs.tree_n_node_blocks.saturating_mul(256),
                ),
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.tree_prefix_01");
            self.passes
                .tree_prefix_02
                .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
            stamp_timer(timer_ref, ctx.encoder, "parser.tree_prefix_02");
            self.passes.tree_prefix_03.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(
                    bufs.tree_capacity.saturating_add(1),
                ),
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.tree_prefix_03");
            self.passes
                .tree_prefix_04
                .record_build(ctx.device, ctx.encoder, ctx.buffers)?;
            stamp_timer(timer_ref, ctx.encoder, "parser.tree_prefix_04");
            self.passes.tree_parent.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(bufs.tree_capacity),
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.tree_parent");
            self.passes.tree_spans.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(bufs.tree_capacity),
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.tree_spans");
            self.passes.hir_nodes.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(bufs.tree_capacity),
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_nodes");
            if include_hir_spans {
                self.passes.hir_spans.record_pass(
                    &mut ctx,
                    crate::gpu::passes_core::InputElements::Elements1D(bufs.tree_capacity),
                )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_spans");
            }
        }
        Ok(())
    }

    fn resident_buffers_for<'a>(
        &self,
        slot: &'a mut Option<ResidentParserBufferCache>,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
    ) -> &'a ParserBuffers {
        let fingerprint = table_fingerprint(tables);
        let wanted_capacity = token_capacity.max(1);
        let needs_allocate = slot.as_ref().is_none_or(|cached| {
            cached.table_fingerprint != fingerprint || cached.token_capacity < wanted_capacity
        });

        if needs_allocate {
            let grown_capacity = slot
                .as_ref()
                .filter(|cached| cached.table_fingerprint == fingerprint)
                .map(|cached| cached.token_capacity.saturating_mul(2))
                .unwrap_or(0)
                .max(wanted_capacity)
                .max(1);
            let dummy_token_kinds = vec![0u32; grown_capacity as usize + 2];
            let action_table_bytes = tables.to_action_header_grid_bytes();
            *slot = Some(ResidentParserBufferCache {
                token_capacity: grown_capacity,
                table_fingerprint: fingerprint,
                buffers: ParserBuffers::new(
                    &self.device,
                    &dummy_token_kinds,
                    tables.n_kinds,
                    &action_table_bytes,
                    tables,
                ),
            });
            self.bg_cache
                .lock()
                .expect("parser.bg_cache poisoned")
                .clear();
            *self
                .resident_direct_bind_groups
                .lock()
                .expect("parser.resident_direct_bind_groups poisoned") = None;
        }
        &slot
            .as_ref()
            .expect("resident parser buffers allocated")
            .buffers
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

        // Parser buffers are per-call, and cached bind groups hold concrete buffer handles.
        self.bg_cache
            .lock()
            .expect("parser.bg_cache poisoned")
            .clear();

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
                ll1: Ll1AcceptResult {
                    accepted: true,
                    error_pos: 0,
                    error_code: 0,
                    detail: 0,
                    steps: 0,
                    emit_len: 0,
                },
                ll1_emit_stream: Vec::new(),
                ll1_emit_token_pos: Vec::new(),
                ll1_block_size: 0,
                ll1_block_emit_stride: 0,
                ll1_block_seed_len: Vec::new(),
                ll1_seed_plan: Ll1SeedPlanResult {
                    accepted: true,
                    pos: 0,
                    error_code: 0,
                    detail: 0,
                    steps: 0,
                    seed_count: 0,
                    max_depth: 0,
                    emit_len: 0,
                },
                ll1_seeded_blocks: Vec::new(),
                ll1_seeded_emit: Vec::new(),
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
                first_child: Vec::new(),
                next_sibling: Vec::new(),
                subtree_end: Vec::new(),
                hir_kind: Vec::new(),
                hir_token_pos: Vec::new(),
                hir_token_end: Vec::new(),
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
            ll1: Ll1AcceptResult {
                accepted: decoded.ll1_status[0] != 0,
                error_pos: decoded.ll1_status[1],
                error_code: decoded.ll1_status[2],
                detail: decoded.ll1_status[3],
                steps: decoded.ll1_status[4],
                emit_len: decoded.ll1_status[5],
            },
            ll1_emit_stream: decoded.ll1_emit_stream,
            ll1_emit_token_pos: decoded.ll1_emit_token_pos,
            ll1_block_size: bufs.ll1_block_size,
            ll1_block_emit_stride: bufs.ll1_block_emit_stride,
            ll1_block_seed_len: decoded.ll1_block_seed_len,
            ll1_seed_plan: decode_ll1_seed_plan(decoded.ll1_seed_plan_status),
            ll1_seeded_blocks: decode_ll1_block_summaries(&decoded.ll1_seeded_status),
            ll1_seeded_emit: decoded.ll1_seeded_emit,
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
            first_child: decoded.first_child,
            next_sibling: decoded.next_sibling,
            subtree_end: decoded.subtree_end,
            hir_kind: decoded.hir_kind,
            hir_token_pos: decoded.hir_token_pos,
            hir_token_end: decoded.hir_token_end,
            debug: std::mem::take(&mut debug_sink),
        })
    }
}

fn decode_ll1_seed_plan(words: [u32; 8]) -> Ll1SeedPlanResult {
    Ll1SeedPlanResult {
        accepted: words[0] != 0,
        pos: words[1],
        error_code: words[2],
        detail: words[3],
        steps: words[4],
        seed_count: words[5],
        max_depth: words[6],
        emit_len: words[7],
    }
}

fn decode_ll1_block_summaries(words: &[u32]) -> Vec<Ll1BlockSummary> {
    words
        .chunks_exact(LL1_BLOCK_STATUS_WORDS)
        .map(|chunk| Ll1BlockSummary {
            status: chunk[0],
            begin: chunk[1],
            end: chunk[2],
            pos: chunk[3],
            steps: chunk[4],
            emit_len: chunk[5],
            stack_depth: chunk[6],
            error_code: chunk[7],
            detail: chunk[8],
            first_production: chunk[9],
        })
        .collect()
}

fn table_fingerprint(tables: &PrecomputedParseTables) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    tables.n_kinds.hash(&mut hasher);
    tables.n_productions.hash(&mut hasher);
    tables.n_nonterminals.hash(&mut hasher);
    tables.start_nonterminal.hash(&mut hasher);
    tables.sc_superseq.hash(&mut hasher);
    tables.sc_off.hash(&mut hasher);
    tables.sc_len.hash(&mut hasher);
    tables.pp_superseq.hash(&mut hasher);
    tables.pp_off.hash(&mut hasher);
    tables.pp_len.hash(&mut hasher);
    tables.prod_arity.hash(&mut hasher);
    tables.ll1_predict.hash(&mut hasher);
    tables.prod_rhs_off.hash(&mut hasher);
    tables.prod_rhs_len.hash(&mut hasher);
    tables.prod_rhs.hash(&mut hasher);
    hasher.finish()
}

fn buffer_fingerprint(buffers: &[&wgpu::Buffer]) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    for buffer in buffers {
        buffer.hash(&mut hasher);
    }
    hasher.finish()
}

fn write_uniform<T>(queue: &wgpu::Queue, buffer: &LaniusBuffer<T>, value: &T)
where
    T: encase::ShaderType + encase::internal::WriteInto,
{
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(value)
        .expect("failed to write parser uniform buffer");
    queue.write_buffer(buffer, 0, ub.as_ref());
}

// Optional singleton, mirroring the lexer’s `lex_on_gpu`.
static GPU_PARSER: OnceLock<GpuParser> = OnceLock::new();

pub async fn get_global_parser() -> &'static GpuParser {
    GPU_PARSER.get_or_init(|| pollster::block_on(GpuParser::new()).expect("GPU parser init"))
}

fn make_tokens_to_kinds_pass(device: &wgpu::Device) -> Result<PassData> {
    make_pass_data(
        device,
        "parser_tokens_to_kinds",
        "main",
        include_bytes!(concat!(env!("OUT_DIR"), "/shaders/tokens_to_kinds.spv")),
        include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/tokens_to_kinds.reflect.json"
        )),
    )
}

fn make_direct_hir_pass(device: &wgpu::Device) -> Result<PassData> {
    make_pass_data(
        device,
        "parser_direct_hir",
        "main",
        include_bytes!(concat!(env!("OUT_DIR"), "/shaders/direct_hir.spv")),
        include_bytes!(concat!(env!("OUT_DIR"), "/shaders/direct_hir.reflect.json")),
    )
}

fn read_u32_words(bytes: &[u8], count: usize) -> Result<Vec<u32>> {
    if bytes.len() < count * 4 {
        anyhow::bail!("parser status readback was truncated");
    }
    let mut out = Vec::with_capacity(count);
    for chunk in bytes.chunks_exact(4).take(count) {
        out.push(u32::from_le_bytes(chunk.try_into().unwrap()));
    }
    Ok(out)
}
