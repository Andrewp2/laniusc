// src/parser/driver.rs
//! GPU parser driver, reshaped to mirror the style used by the lexer driver:
//! - One compiler-graph schedule shared by resident and one-shot parsing
//! - Bind-group cache reuse across passes
//! - Env-gated timers and validation scopes
//! - Optional readback (LANIUS_READBACK), returning empty streams when off

use std::{
    collections::HashMap,
    hash::{Hash, Hasher},
    sync::{Arc, OnceLock},
};

mod debug;
mod dispatch_args;
mod recorded;
mod resident_buffers;
mod resident_passes;
mod resident_tree;
mod results;
mod support;
mod token_frontend;
use anyhow::{Result, anyhow};
use results::ResidentParserBufferCache;
pub use results::{
    BracketsMatchResult,
    Ll1AcceptResult,
    ParseResult,
    ParserFailure,
    ParserFailureKind,
    RecordedHirSemanticCount,
    RecordedResidentLl1HirCheck,
    ResidentParseResult,
    ResidentParserCapacity,
};
pub use support::get_global_parser;
use support::*;
use token_frontend::ResidentTokenKindOperations;
use wgpu;

use crate::{
    gpu::{
        buffers::{storage_ro_from_bytes, storage_ro_from_u32s},
        device,
        passes_core::{
            BindGroupCache,
            ComputePassBatch,
            Pass,
            PassContext,
            compute_pass_batching_enabled,
            validation_scopes_enabled,
        },
        timer::{GpuTimer, MINIMUM_TIME_TO_NOT_ELIDE_MS},
    },
    lexer::{GpuToken, features::CONSERVATIVE_PARSER_FEATURES},
    parser::{
        buffers::{ActionHeader, ParserBuffers},
        debug::DebugOutput,
        passes::{self, ParserPasses},
        readback,
        tables::PrecomputedParseTables,
    },
};

// ------------ little helpers (match lexer ergonomics) ----------------

/// Resident GPU parser driver and loaded parser pass set.
pub struct GpuParser {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    timers_supported: bool,

    passes: ParserPasses,

    // Bind group cache so passes do not recreate BGs every dispatch.
    bg_cache: std::sync::Mutex<BindGroupCache>,

    // Resident lexer-to-parser buffers reused by the compiler path when the parse
    // table identity is unchanged and the previous allocation is large enough.
    resident_buffers: std::sync::Mutex<Option<ResidentParserBufferCache>>,
    resident_token_kind_operations: std::sync::Mutex<Option<ResidentTokenKindOperations>>,
    resident_token_file_id_copy:
        std::sync::Mutex<Option<(u64, crate::gpu::operations::CopyBufferOperation)>>,
    token_compute_operations:
        std::sync::Mutex<HashMap<String, crate::gpu::operations::ComputeOperation>>,
}

impl GpuParser {
    /// Builds a parser using the global GPU device.
    pub async fn new() -> Result<Self> {
        Self::new_with_device(device::global()).await
    }

    /// Loads parser compute passes for a specific GPU device.
    pub async fn new_with_device(ctx: &device::GpuDevice) -> Result<Self> {
        let device = Arc::clone(&ctx.device);
        let queue = Arc::clone(&ctx.queue);

        Ok(Self {
            device,
            queue,
            timers_supported: ctx.timers_supported,
            passes: ParserPasses::new(&ctx.device)?,
            bg_cache: std::sync::Mutex::new(BindGroupCache::new()),
            resident_buffers: std::sync::Mutex::new(None),
            resident_token_kind_operations: std::sync::Mutex::new(None),
            resident_token_file_id_copy: std::sync::Mutex::new(None),
            token_compute_operations: std::sync::Mutex::new(HashMap::new()),
        })
    }

    /// Records and checks parser work for resident lexer token buffers.
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

    /// Records parser work and exposes checked resident parser buffers to a callback.
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
        let bufs = self.resident_debug_buffers_for(&mut resident_guard, token_capacity, tables);

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
        bufs.clear_operations().record_token_file_id(&mut encoder);
        let mut timer_ref: Option<&mut GpuTimer> = None;
        self.record_ll1_resident_passes(&mut encoder, &bufs, true, true, None, &mut timer_ref)?;

        let status_readback = bufs.ll1_status_readback.buffer.clone();
        bufs.status_readback_operations.record_full(&mut encoder);

        let use_scopes = bool_from_env("LANIUS_VALIDATION_SCOPES", false);
        crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "parser.resident-ll1",
            encoder.finish(),
            use_scopes,
            "resident parser batch",
        );

        let slice = status_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &slice,
            "parser.resident-ll1.status",
        )?;
        let mapped = slice.get_mapped_range();
        let words = read_u32_words(&mapped, 6)?;
        drop(mapped);
        status_readback.unmap();

        let result = Ll1AcceptResult::from_status_words(&words);
        if !result.accepted {
            anyhow::bail!("{}", result.rejection_message());
        }

        Ok(consume(bufs))
    }

    /// Records LL, tree, and HIR work for resident token buffers.
    pub fn record_checked_resident_ll1_hir_artifacts<R, E>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: Option<&wgpu::Buffer>,
        source_len: u32,
        source_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
        timer_ref: &mut Option<&mut GpuTimer>,
        consume: impl FnOnce(
            &ParserBuffers,
            &mut wgpu::CommandEncoder,
            &mut Option<&mut GpuTimer>,
        ) -> std::result::Result<R, E>,
    ) -> Result<(RecordedResidentLl1HirCheck, std::result::Result<R, E>)> {
        self.record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
            encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            token_file_id_buf,
            source_len,
            source_buf,
            tables,
            None,
            timer_ref,
            consume,
        )
    }

    #[allow(clippy::too_many_arguments)]
    /// Records LL, tree, and HIR work with an explicit tree-capacity override.
    pub fn record_checked_resident_ll1_hir_artifacts_with_tree_capacity<R, E>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: Option<&wgpu::Buffer>,
        source_len: u32,
        source_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
        timer_ref: &mut Option<&mut GpuTimer>,
        consume: impl FnOnce(
            &ParserBuffers,
            &mut wgpu::CommandEncoder,
            &mut Option<&mut GpuTimer>,
        ) -> std::result::Result<R, E>,
    ) -> Result<(RecordedResidentLl1HirCheck, std::result::Result<R, E>)> {
        self.record_checked_resident_ll1_hir_artifacts_impl(
            encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            token_file_id_buf,
            source_len,
            source_buf,
            tables,
            tree_capacity_override,
            CONSERVATIVE_PARSER_FEATURES,
            true,
            timer_ref,
            consume,
        )
    }

    #[allow(clippy::too_many_arguments)]
    /// Records LL, tree, and HIR work with exact tree capacity and conservative
    /// GPU-derived optional-family feature flags.
    pub fn record_checked_resident_ll1_hir_artifacts_with_tree_capacity_and_features<R, E>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: Option<&wgpu::Buffer>,
        source_len: u32,
        source_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
        parser_feature_flags: u32,
        timer_ref: &mut Option<&mut GpuTimer>,
        consume: impl FnOnce(
            &ParserBuffers,
            &mut wgpu::CommandEncoder,
            &mut Option<&mut GpuTimer>,
        ) -> std::result::Result<R, E>,
    ) -> Result<(RecordedResidentLl1HirCheck, std::result::Result<R, E>)> {
        self.record_checked_resident_ll1_hir_artifacts_impl(
            encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            token_file_id_buf,
            source_len,
            source_buf,
            tables,
            tree_capacity_override,
            parser_feature_flags,
            false,
            timer_ref,
            consume,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn record_checked_resident_ll1_hir_artifacts_impl<R, E>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: Option<&wgpu::Buffer>,
        source_len: u32,
        source_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
        parser_feature_flags: u32,
        retain_debug_hir_buffers: bool,
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
        let bufs = self.resident_buffers_for_with_tree_capacity_and_debug(
            &mut resident_guard,
            token_capacity,
            source_len,
            tables,
            tree_capacity_override,
            retain_debug_hir_buffers,
            parser_feature_flags,
        );
        if crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false) {
            eprintln!(
                "[gpu_compile_host_timer] parser.optional_capacities: flags=0x{parser_feature_flags:08x} tree={} arrays={} enum_match={} structs={}",
                bufs.tree_capacity,
                bufs.hir_array_capacity,
                bufs.hir_enum_match_capacity,
                bufs.hir_struct_capacity,
            );
        }

        // Dependent parser dispatches (prefix scans and pointer jumps) require
        // storage visibility between iterations. A single compute pass does
        // not provide those barriers, so parser-wide coalescing is invalid.
        let parser_batch = crate::gpu::passes_core::DeferredComputeBatchGuard::begin(
            false,
            "parser.resident.batch",
        );

        let active_tree_capacity = tree_capacity_override
            .unwrap_or(bufs.tree_capacity)
            .min(bufs.tree_capacity)
            .max(1);
        let cleared_bytes = bufs.clear_job_storage(encoder, active_tree_capacity);
        if crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false) {
            let (allocations, bytes) = bufs.resettable_storage_totals();
            eprintln!(
                "[gpu_compile_host_timer] parser.workspace_clear: allocations={allocations} active_bytes={cleared_bytes} resident_bytes={bytes}"
            );
            for (label, active_bytes) in bufs.largest_resettable_storage(active_tree_capacity, 24) {
                eprintln!(
                    "[gpu_compile_host_timer] parser.workspace_clear.allocation: label={label} active_bytes={active_bytes}"
                );
            }
        }

        self.record_tokens_to_kinds_timed(
            encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            bufs,
            timer_ref,
        )?;
        self.record_token_file_ids(encoder, bufs, token_file_id_buf, token_capacity)?;
        self.record_ll1_resident_passes(
            encoder,
            bufs,
            true,
            true,
            Some((source_len, token_buf, source_buf)),
            timer_ref,
        )?;
        if let Some(timer) = timer_ref.as_deref_mut() {
            timer.stamp(encoder, "parser.done");
        }

        let status_readback = bufs.ll1_status_readback.buffer.clone();
        bufs.status_readback_operations.record_full(encoder);
        drop(parser_batch);

        let consumed = consume(bufs, encoder, timer_ref);
        Ok((RecordedResidentLl1HirCheck { status_readback }, consumed))
    }

    /// Records partial-parse capacity work and reads back the required tree capacity.
    pub fn read_resident_partial_parse_tree_capacity(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: Option<&wgpu::Buffer>,
        tables: &PrecomputedParseTables,
    ) -> Result<u32> {
        Ok(self
            .measure_resident_partial_parse_capacity(
                token_capacity,
                token_buf,
                token_count_buf,
                token_file_id_buf,
                tables,
            )?
            .tree_capacity)
    }

    /// Measures exact tree capacity and semantic parser-family feature flags
    /// in one GPU submission/readback boundary.
    pub fn measure_resident_partial_parse_capacity(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: Option<&wgpu::Buffer>,
        tables: &PrecomputedParseTables,
    ) -> Result<ResidentParserCapacity> {
        // Once a full parser workspace exists, use its partial-parse storage
        // to size ordinary edits. This preserves every buffer and bind-group
        // identity while still measuring the changed token stream on the GPU.
        // The partial parser reports the required output size even when it
        // exceeds the resident tree capacity, so callers can grow safely.
        {
            let mut resident = self
                .resident_buffers
                .lock()
                .expect("parser.resident_buffers poisoned");
            if let Some(cached) = resident.as_mut().filter(|cached| {
                cached.table_fingerprint == table_fingerprint(tables)
                    && cached.token_capacity >= token_capacity.max(1)
            }) {
                cached
                    .buffers
                    .set_active_token_capacity(&self.queue, token_capacity.max(1));
                return self.measure_partial_parse_capacity_with_buffers(
                    token_capacity,
                    token_buf,
                    token_count_buf,
                    token_file_id_buf,
                    &cached.buffers,
                    "parser.partial-parse-capacity.resident",
                );
            }
        }

        // This probe uses a temporary parser allocation. Cached token-front-end
        // bind groups may still reference the preceding resident allocation,
        // so invalidate them before recording into the temporary buffers.
        *self
            .resident_token_kind_operations
            .lock()
            .expect("parser.resident_token_kind_operations poisoned") = None;
        self.token_compute_operations
            .lock()
            .expect("parser.token_compute_operations poisoned")
            .clear();
        self.bg_cache
            .lock()
            .expect("parser.bg_cache poisoned")
            .clear();

        // Capacity measurement needs only the partial-parse buffers with a
        // one-row tree. Keep that temporary allocation out of the full parser
        // cache so daemon jobs do not evict and recreate the resident HIR.
        let mut capacity_buffers = None;
        let bufs = self.resident_buffers_for_with_tree_capacity(
            &mut capacity_buffers,
            token_capacity,
            tables,
            Some(1),
        );

        let result = self.measure_partial_parse_capacity_with_buffers(
            token_capacity,
            token_buf,
            token_count_buf,
            token_file_id_buf,
            bufs,
            "parser.partial-parse-tree-capacity",
        );

        // The capacity probe deliberately uses temporary parser buffers, but
        // token-frontend bind groups are cached on `GpuParser`. Do not let
        // those bind groups outlive the temporary buffers and get reused by
        // the following full resident parse when GPU buffer ids are recycled.
        *self
            .resident_token_kind_operations
            .lock()
            .expect("parser.resident_token_kind_operations poisoned") = None;
        self.token_compute_operations
            .lock()
            .expect("parser.token_compute_operations poisoned")
            .clear();
        self.bg_cache
            .lock()
            .expect("parser.bg_cache poisoned")
            .clear();
        result
    }

    fn measure_partial_parse_capacity_with_buffers(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: Option<&wgpu::Buffer>,
        bufs: &ParserBuffers,
        submission_label: &'static str,
    ) -> Result<ResidentParserCapacity> {
        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.partial-parse-tree-capacity.encoder"),
            });
        self.record_tokens_to_kinds(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            bufs,
        )?;
        self.record_token_file_ids(&mut encoder, bufs, token_file_id_buf, token_capacity)?;
        self.record_resident_partial_parse_status(&mut encoder, bufs)?;

        let status_readback = &bufs.ll1_status_readback.buffer;
        bufs.status_readback_operations.record_partial(&mut encoder);
        crate::gpu::passes_core::submit_with_progress(
            &self.queue,
            submission_label,
            encoder.finish(),
        );

        let slice = status_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &slice,
            "parser.partial_parse_tree_capacity.status",
        )?;
        let mapped = slice.get_mapped_range();
        let words = read_u32_words(&mapped, 7)?;
        drop(mapped);
        status_readback.unmap();

        let emit_capacity = if words[0] == 0 && words[2] == 3 {
            words[3]
        } else {
            words[5]
        };
        Ok(ResidentParserCapacity {
            tree_capacity: emit_capacity.max(1),
            parser_feature_flags: words[6],
        })
    }

    /// Borrows current resident parser buffers sized for the provided token capacity.
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

    /// Clones the compact HIR handles from the parser's current resident job.
    ///
    /// This is the phase boundary used by graph-owned consumers after parsing:
    /// it cannot allocate a differently sized parser cache and it exposes none
    /// of the raw production/tree scratch that compact HIR replaced.
    #[cfg(test)]
    pub(crate) fn current_resident_hir(&self) -> Option<crate::parser::buffers::GpuHirView> {
        let resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        resident_guard.as_ref().map(|resident| {
            crate::parser::buffers::GpuHirView::from_parser_buffers(&resident.buffers)
        })
    }

    /// Borrows current resident parser buffers with an explicit tree capacity.
    pub fn with_current_resident_buffers_with_tree_capacity<R>(
        &self,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
        tree_capacity: u32,
        consume: impl FnOnce(&ParserBuffers) -> R,
    ) -> R {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for_with_tree_capacity_and_debug(
            &mut resident_guard,
            token_capacity,
            token_capacity,
            tables,
            Some(tree_capacity),
            true,
            CONSERVATIVE_PARSER_FEATURES,
        );
        consume(bufs)
    }

    /// Borrows current resident buffers with feature-aware optional-family capacities.
    pub fn with_current_resident_buffers_with_tree_capacity_and_features<R>(
        &self,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
        tree_capacity: u32,
        parser_feature_flags: u32,
        consume: impl FnOnce(&ParserBuffers) -> R,
    ) -> R {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for_with_tree_capacity_and_features(
            &mut resident_guard,
            token_capacity,
            tables,
            Some(tree_capacity),
            parser_feature_flags,
        );
        consume(bufs)
    }

    /// Releases resident parser buffers and cached parser bind groups.
    pub fn release_current_resident_buffers(&self) {
        *self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned") = None;
        self.bg_cache
            .lock()
            .expect("parser.bg_cache poisoned")
            .clear();
        *self
            .resident_token_kind_operations
            .lock()
            .expect("parser.resident_token_kind_operations poisoned") = None;
        self.token_compute_operations
            .lock()
            .expect("parser.token_compute_operations poisoned")
            .clear();
    }

    /// Parses resident token buffers and reads back the debug parse result.
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
        let bufs = self.resident_debug_buffers_for(&mut resident_guard, token_capacity, tables);

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
        self.record_ll1_resident_passes(&mut encoder, &bufs, true, true, None, &mut timer_ref)?;
        self.finish_resident_tree_readback(encoder, bufs)
    }

    /// Source-aware variant of the resident parser debug path. This records
    /// string literal extraction and decoding exactly as compilation does.
    #[doc(hidden)]
    pub fn parse_resident_tokens_with_source(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        source_len: u32,
        source_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
    ) -> Result<ResidentParseResult> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_debug_buffers_for(&mut resident_guard, token_capacity, tables);

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.resident_tree.source_aware.encoder"),
            });
        self.record_tokens_to_kinds(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            bufs,
        )?;
        let mut timer_ref: Option<&mut GpuTimer> = None;
        self.record_ll1_resident_passes(
            &mut encoder,
            bufs,
            true,
            true,
            Some((source_len, token_buf, source_buf)),
            &mut timer_ref,
        )?;
        self.finish_resident_tree_readback(encoder, bufs)
    }

    /// Debug/test helper for classifying raw lexer token kinds into the parser
    /// semantic token alphabet used by one-shot parser buffers.
    #[doc(hidden)]
    pub fn debug_semantic_token_kinds_for_raw_token_kinds(
        &self,
        token_kinds_u32: &[u32],
        tables: &PrecomputedParseTables,
    ) -> Result<Vec<u32>> {
        let raw_kinds = raw_token_kinds_without_optional_sentinels(token_kinds_u32);
        let token_count = u32::try_from(raw_kinds.len())
            .map_err(|_| anyhow!("one-shot parser token count exceeds u32::MAX"))?;
        let token_capacity = token_count.max(1);
        let raw_token_bytes = raw_token_kind_rows(raw_kinds, token_capacity as usize);
        let raw_token_buf = storage_ro_from_bytes::<GpuToken>(
            &self.device,
            "parser.one_shot.raw_token_rows",
            &raw_token_bytes,
            token_capacity as usize,
        );
        let raw_token_count_buf = storage_ro_from_u32s(
            &self.device,
            "parser.one_shot.raw_token_count",
            &[token_count],
        );

        self.debug_semantic_token_kinds_for_resident_tokens(
            token_capacity,
            &raw_token_buf,
            &raw_token_count_buf,
            tables,
        )
    }

    /// One-shot GPU parse pipeline from raw lexer token kinds.
    ///
    /// The input may include parser sentinel `0` words at the beginning/end; they
    /// are ignored before the parser token frontend classifies the raw lexer
    /// kinds into the semantic parser alphabet.
    pub async fn parse(
        &self,
        token_kinds_u32: &[u32],
        tables: &PrecomputedParseTables,
    ) -> Result<ParseResult> {
        let semantic_token_kinds =
            self.debug_semantic_token_kinds_for_raw_token_kinds(token_kinds_u32, tables)?;
        if let Some((index, kind)) =
            semantic_token_kinds
                .iter()
                .copied()
                .enumerate()
                .find(|(_, kind)| {
                    if *kind < tables.n_kinds {
                        return false;
                    }
                    // A contextual raw `>>` represents two virtual generic-close
                    // tokens in one row. The parser shaders recognize the high-bit
                    // tag and unpack the two 15-bit semantic kinds before indexing
                    // grammar tables.
                    let inner = *kind & 0x7fff;
                    let outer = (*kind >> 15) & 0x7fff;
                    (*kind & 0x8000_0000) == 0 || inner >= tables.n_kinds || outer >= tables.n_kinds
                })
        {
            let raw = raw_token_kinds_without_optional_sentinels(token_kinds_u32);
            let raw_index = index.saturating_sub(1);
            let raw_window_start = raw_index.saturating_sub(2);
            let raw_window_end = (raw_index + 3).min(raw.len());
            return Err(anyhow!(
                "GPU token frontend produced semantic kind {kind} at row {index}, outside grammar kind count {}; corresponding raw-token window {:?} at rows {raw_window_start}..{raw_window_end}",
                tables.n_kinds,
                &raw[raw_window_start..raw_window_end],
            ));
        }
        self.parse_classified_token_kinds(&semantic_token_kinds, tables)
            .await
    }

    /// One-shot GPU parse pipeline from already-classified semantic parser token kinds.
    pub async fn parse_classified_token_kinds(
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
            &self.passes,
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

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.pipeline.encoder"),
            });

        if let Some(t) = maybe_timer.as_mut() {
            t.reset();
            t.stamp(&mut encoder, "BEGIN");
        }

        // One-shot parsing uses the same graph-owned schedule as resident
        // compilation. Only allocation/readback policy differs between these
        // entry points; maintaining a second direct-dispatch pass list allowed
        // the executable schedule to diverge from the compiler graph.
        let mut timer_ref = maybe_timer.as_mut();
        self.record_ll1_resident_passes(&mut encoder, &bufs, true, true, None, &mut timer_ref)?;

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
        crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "parser.batch",
            encoder.finish(),
            use_scopes,
            "parser batch",
        );

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
                        eprintln!("[gpu_timer] {label}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
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
                hir_semantic_prefix_before_node: Vec::new(),
                hir_semantic_dense_node: Vec::new(),
                hir_semantic_subtree_end: Vec::new(),
                hir_semantic_parent: Vec::new(),
                hir_semantic_first_child: Vec::new(),
                hir_semantic_next_sibling: Vec::new(),
                hir_semantic_depth: Vec::new(),
                hir_semantic_child_index: Vec::new(),
                hir_token_pos: Vec::new(),
                hir_token_end: Vec::new(),
                hir_type_form: Vec::new(),
                hir_type_value_node: Vec::new(),
                hir_type_len_token: Vec::new(),
                hir_type_len_value: Vec::new(),
                hir_type_file_id: Vec::new(),
                hir_type_path_leaf_node: Vec::new(),
                hir_type_arg_start: Vec::new(),
                hir_type_arg_count: Vec::new(),
                hir_type_arg_next: Vec::new(),
                hir_type_alias_target_node: Vec::new(),
                hir_fn_return_type_node: Vec::new(),
                hir_method_signature_flags: Vec::new(),
                hir_stmt_record_kind: Vec::new(),
                hir_stmt_record_operand0: Vec::new(),
                hir_stmt_record_operand1: Vec::new(),
                hir_stmt_record_operand2: Vec::new(),
                hir_stmt_scope_end: Vec::new(),
                hir_item_kind: Vec::new(),
                hir_item_name_token: Vec::new(),
                hir_item_decl_token: Vec::new(),
                hir_item_namespace: Vec::new(),
                hir_item_visibility: Vec::new(),
                hir_item_path_start: Vec::new(),
                hir_item_path_end: Vec::new(),
                hir_item_path_node: Vec::new(),
                hir_item_file_id: Vec::new(),
                hir_item_import_target_kind: Vec::new(),
                hir_variant_parent_enum: Vec::new(),
                hir_variant_ordinal: Vec::new(),
                hir_variant_payload_start: Vec::new(),
                hir_variant_payload_count: Vec::new(),
                hir_variant_payload_node: Vec::new(),
                hir_match_scrutinee_node: Vec::new(),
                hir_match_arm_start: Vec::new(),
                hir_match_arm_count: Vec::new(),
                hir_match_arm_next: Vec::new(),
                hir_match_arm_pattern_node: Vec::new(),
                hir_match_arm_payload_start: Vec::new(),
                hir_match_arm_payload_count: Vec::new(),
                hir_match_arm_result_node: Vec::new(),
                hir_match_payload_owner_arm: Vec::new(),
                hir_match_payload_match_node: Vec::new(),
                hir_match_payload_ordinal: Vec::new(),
                hir_call_callee_node: Vec::new(),
                hir_call_arg_start: Vec::new(),
                hir_call_arg_end: Vec::new(),
                hir_call_arg_count: Vec::new(),
                hir_call_arg_parent_call: Vec::new(),
                hir_call_arg_ordinal: Vec::new(),
                hir_array_lit_first_element: Vec::new(),
                hir_array_lit_element_count: Vec::new(),
                hir_array_element_parent_lit: Vec::new(),
                hir_array_element_ordinal: Vec::new(),
                hir_array_element_next: Vec::new(),
                hir_expr_string_start: Vec::new(),
                hir_expr_string_len: Vec::new(),
                hir_member_receiver_node: Vec::new(),
                hir_member_receiver_token: Vec::new(),
                hir_member_name_token: Vec::new(),
                hir_struct_field_parent_struct: Vec::new(),
                hir_struct_field_ordinal: Vec::new(),
                hir_struct_field_type_node: Vec::new(),
                hir_struct_decl_field_start: Vec::new(),
                hir_struct_decl_field_count: Vec::new(),
                hir_struct_lit_head_node: Vec::new(),
                hir_struct_lit_field_start: Vec::new(),
                hir_struct_lit_field_count: Vec::new(),
                hir_struct_lit_field_parent_lit: Vec::new(),
                hir_struct_lit_field_value_node: Vec::new(),
                hir_struct_lit_field_next: Vec::new(),
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
                    eprintln!("[gpu_timer] {label}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
                }
                prev = t;
            }
        }

        let mut debug_sink = DebugOutput::default();

        Ok(ParseResult {
            ll1: Ll1AcceptResult {
                accepted: decoded.ll1_status[0] != 0,
                error_pos: decoded.ll1_status[1],
                error_code: decoded.ll1_status[2],
                detail: decoded.ll1_status[3],
                steps: decoded.ll1_status[4],
                emit_len: decoded.ll1_status[5],
            },
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
            hir_semantic_prefix_before_node: decoded.hir_semantic_prefix_before_node,
            hir_semantic_dense_node: decoded.hir_semantic_dense_node,
            hir_semantic_subtree_end: decoded.hir_semantic_subtree_end,
            hir_semantic_parent: decoded.hir_semantic_parent,
            hir_semantic_first_child: decoded.hir_semantic_first_child,
            hir_semantic_next_sibling: decoded.hir_semantic_next_sibling,
            hir_semantic_depth: decoded.hir_semantic_depth,
            hir_semantic_child_index: decoded.hir_semantic_child_index,
            hir_token_pos: decoded.hir_token_pos,
            hir_token_end: decoded.hir_token_end,
            hir_type_form: decoded.hir_type_form,
            hir_type_value_node: decoded.hir_type_value_node,
            hir_type_len_token: decoded.hir_type_len_token,
            hir_type_len_value: decoded.hir_type_len_value,
            hir_type_file_id: decoded.hir_type_file_id,
            hir_type_path_leaf_node: decoded.hir_type_path_leaf_node,
            hir_type_arg_start: decoded.hir_type_arg_start,
            hir_type_arg_count: decoded.hir_type_arg_count,
            hir_type_arg_next: decoded.hir_type_arg_next,
            hir_type_alias_target_node: decoded.hir_type_alias_target_node,
            hir_fn_return_type_node: decoded.hir_fn_return_type_node,
            hir_method_signature_flags: decoded.hir_method_signature_flags,
            hir_stmt_record_kind: decoded.hir_stmt_record_kind,
            hir_stmt_record_operand0: decoded.hir_stmt_record_operand0,
            hir_stmt_record_operand1: decoded.hir_stmt_record_operand1,
            hir_stmt_record_operand2: decoded.hir_stmt_record_operand2,
            hir_stmt_scope_end: decoded.hir_stmt_scope_end,
            hir_item_kind: decoded.hir_item_kind,
            hir_item_name_token: decoded.hir_item_name_token,
            hir_item_decl_token: decoded.hir_item_decl_token,
            hir_item_namespace: decoded.hir_item_namespace,
            hir_item_visibility: decoded.hir_item_visibility,
            hir_item_path_start: decoded.hir_item_path_start,
            hir_item_path_end: decoded.hir_item_path_end,
            hir_item_path_node: decoded.hir_item_path_node,
            hir_item_file_id: decoded.hir_item_file_id,
            hir_item_import_target_kind: decoded.hir_item_import_target_kind,
            hir_variant_parent_enum: decoded.hir_variant_parent_enum,
            hir_variant_ordinal: decoded.hir_variant_ordinal,
            hir_variant_payload_start: decoded.hir_variant_payload_start,
            hir_variant_payload_count: decoded.hir_variant_payload_count,
            hir_variant_payload_node: decoded.hir_variant_payload_node,
            hir_match_scrutinee_node: decoded.hir_match_scrutinee_node,
            hir_match_arm_start: decoded.hir_match_arm_start,
            hir_match_arm_count: decoded.hir_match_arm_count,
            hir_match_arm_next: decoded.hir_match_arm_next,
            hir_match_arm_pattern_node: decoded.hir_match_arm_pattern_node,
            hir_match_arm_payload_start: decoded.hir_match_arm_payload_start,
            hir_match_arm_payload_count: decoded.hir_match_arm_payload_count,
            hir_match_arm_result_node: decoded.hir_match_arm_result_node,
            hir_match_payload_owner_arm: decoded.hir_match_payload_owner_arm,
            hir_match_payload_match_node: decoded.hir_match_payload_match_node,
            hir_match_payload_ordinal: decoded.hir_match_payload_ordinal,
            hir_call_callee_node: decoded.hir_call_callee_node,
            hir_call_arg_start: decoded.hir_call_arg_start,
            hir_call_arg_end: decoded.hir_call_arg_end,
            hir_call_arg_count: decoded.hir_call_arg_count,
            hir_call_arg_parent_call: decoded.hir_call_arg_parent_call,
            hir_call_arg_ordinal: decoded.hir_call_arg_ordinal,
            hir_array_lit_first_element: decoded.hir_array_lit_first_element,
            hir_array_lit_element_count: decoded.hir_array_lit_element_count,
            hir_array_element_parent_lit: decoded.hir_array_element_parent_lit,
            hir_array_element_ordinal: decoded.hir_array_element_ordinal,
            hir_array_element_next: decoded.hir_array_element_next,
            hir_expr_string_start: decoded.hir_expr_string_start,
            hir_expr_string_len: decoded.hir_expr_string_len,
            hir_member_receiver_node: decoded.hir_member_receiver_node,
            hir_member_receiver_token: decoded.hir_member_receiver_token,
            hir_member_name_token: decoded.hir_member_name_token,
            hir_struct_field_parent_struct: decoded.hir_struct_field_parent_struct,
            hir_struct_field_ordinal: decoded.hir_struct_field_ordinal,
            hir_struct_field_type_node: decoded.hir_struct_field_type_node,
            hir_struct_decl_field_start: decoded.hir_struct_decl_field_start,
            hir_struct_decl_field_count: decoded.hir_struct_decl_field_count,
            hir_struct_lit_head_node: decoded.hir_struct_lit_head_node,
            hir_struct_lit_field_start: decoded.hir_struct_lit_field_start,
            hir_struct_lit_field_count: decoded.hir_struct_lit_field_count,
            hir_struct_lit_field_parent_lit: decoded.hir_struct_lit_field_parent_lit,
            hir_struct_lit_field_value_node: decoded.hir_struct_lit_field_value_node,
            hir_struct_lit_field_next: decoded.hir_struct_lit_field_next,
            debug: std::mem::take(&mut debug_sink),
        })
    }
}

impl GpuParser {
    fn record_token_file_ids(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        source: Option<&wgpu::Buffer>,
        token_capacity: u32,
    ) -> Result<()> {
        if let Some(source) = source {
            let bytes = u64::from(token_capacity).saturating_mul(4);
            if bytes != 0 {
                let fingerprint = buffer_fingerprint(&[source, &buffers.default_token_file_id]);
                let mut cached = self
                    .resident_token_file_id_copy
                    .lock()
                    .expect("parser.resident_token_file_id_copy poisoned");
                if cached
                    .as_ref()
                    .is_none_or(|(cached_fingerprint, _)| *cached_fingerprint != fingerprint)
                {
                    *cached = Some((
                        fingerprint,
                        buffers
                            .compiler_graph
                            .token_file_id_copy_operation(source, &buffers.default_token_file_id)?,
                    ));
                }
                cached
                    .as_ref()
                    .expect("token file-id copy operation was initialized")
                    .1
                    .record_size(encoder, bytes);
            }
        } else {
            buffers.clear_operations().record_token_file_id(encoder);
        }
        Ok(())
    }
}

fn raw_token_kinds_without_optional_sentinels(token_kinds_u32: &[u32]) -> &[u32] {
    let mut start = 0usize;
    let mut end = token_kinds_u32.len();
    if token_kinds_u32.first().copied() == Some(0) {
        start = 1;
    }
    if end > start && token_kinds_u32[end - 1] == 0 {
        end -= 1;
    }
    &token_kinds_u32[start..end]
}

fn raw_token_kind_rows(raw_kinds: &[u32], row_count: usize) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(row_count.saturating_mul(3 * std::mem::size_of::<u32>()));
    for i in 0..row_count {
        let kind = raw_kinds.get(i).copied().unwrap_or(0);
        let start = u32::try_from(i).unwrap_or(u32::MAX);
        bytes.extend_from_slice(&kind.to_le_bytes());
        bytes.extend_from_slice(&start.to_le_bytes());
        bytes.extend_from_slice(&1u32.to_le_bytes());
    }
    bytes
}

fn parser_compute_pass_batching_enabled(_timer_ref: &mut Option<&mut GpuTimer>) -> bool {
    _timer_ref.is_none() && compute_pass_batching_enabled() && !validation_scopes_enabled()
}

fn parser_dependency_batching_enabled(_timer_ref: &mut Option<&mut GpuTimer>) -> bool {
    false
}
