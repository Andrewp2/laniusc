// src/parser/driver.rs
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

mod debug;
mod dispatch_args;
mod recorded;
mod resident_buffers;
mod resident_passes;
mod resident_tree;
mod results;
mod support;
mod token_frontend;
use anyhow::Result;
use results::ResidentParserBufferCache;
pub use results::{
    BracketsMatchResult,
    Ll1AcceptResult,
    Ll1BlockSummary,
    Ll1SeedPlanResult,
    ParseResult,
    RecordedHirSemanticCount,
    RecordedResidentLl1HirCheck,
    ResidentParseResult,
};
pub use support::get_global_parser;
use support::*;
use token_frontend::ResidentTokenKindBindGroups;
use wgpu;

use super::passes::ll1_blocks_01::LL1_BLOCK_STATUS_WORDS;
use crate::{
    gpu::{
        device,
        passes_core::{
            BindGroupCache,
            ComputePassBatch,
            DispatchDim,
            InputElements,
            Pass,
            PassContext,
            PassData,
            bind_group,
            compute_pass_batching_enabled,
            plan_workgroups,
            validation_scopes_enabled,
        },
        timer::{GpuTimer, MINIMUM_TIME_TO_NOT_ELIDE_MS},
    },
    parser::{
        buffers::{ActionHeader, ParserBuffers, resident_projected_tree_capacity_for_tables},
        debug::DebugOutput,
        passes::{self, ParserPasses},
        readback,
        tables::PrecomputedParseTables,
    },
};

// ------------ little helpers (match lexer ergonomics) ----------------

pub struct GpuParser {
    device: Arc<wgpu::Device>,
    queue: Arc<wgpu::Queue>,
    timers_supported: bool,

    token_delimiters_01: PassData,
    token_delimiters_02: PassData,
    token_delimiters_03_owner_local: PassData,
    tokens_brace_context: PassData,
    tokens_bracket_match_01_depth_blocks: PassData,
    tokens_brace_match_01_depth_blocks: PassData,
    tokens_brace_match_02_build_min_tree: PassData,
    tokens_bracket_match_03_pair_pse: PassData,
    tokens_brace_match_03_pair_pse: PassData,
    active_pair_dispatch_args: PassData,
    tree_active_dispatch_args: PassData,
    tree_feature_dispatch_args: PassData,
    tokens_to_kinds: PassData,
    passes: ParserPasses,

    // Bind group cache so passes don’t recreate BGs every dispatch.
    bg_cache: std::sync::Mutex<BindGroupCache>,

    // Resident lexer→parser buffers reused by the compiler path when the parse
    // table identity is unchanged and the previous allocation is large enough.
    resident_buffers: std::sync::Mutex<Option<ResidentParserBufferCache>>,
    resident_token_kind_bind_groups: std::sync::Mutex<Option<ResidentTokenKindBindGroups>>,
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
            token_delimiters_01: make_token_delimiters_01_pass(&ctx.device)?,
            token_delimiters_02: make_token_delimiters_02_pass(&ctx.device)?,
            token_delimiters_03_owner_local: make_token_delimiters_03_owner_local_pass(
                &ctx.device,
            )?,
            tokens_brace_context: make_tokens_brace_context_pass(&ctx.device)?,
            tokens_bracket_match_01_depth_blocks: make_tokens_bracket_match_01_depth_blocks_pass(
                &ctx.device,
            )?,
            tokens_brace_match_01_depth_blocks: make_tokens_brace_match_01_depth_blocks_pass(
                &ctx.device,
            )?,
            tokens_brace_match_02_build_min_tree: make_tokens_brace_match_02_build_min_tree_pass(
                &ctx.device,
            )?,
            tokens_bracket_match_03_pair_pse: make_tokens_bracket_match_03_pair_pse_pass(
                &ctx.device,
            )?,
            tokens_brace_match_03_pair_pse: make_tokens_brace_match_03_pair_pse_pass(&ctx.device)?,
            active_pair_dispatch_args: make_active_pair_dispatch_args_pass(&ctx.device)?,
            tree_active_dispatch_args: make_tree_active_dispatch_args_pass(&ctx.device)?,
            tree_feature_dispatch_args: make_tree_feature_dispatch_args_pass(&ctx.device)?,
            tokens_to_kinds: make_tokens_to_kinds_pass(&ctx.device)?,
            passes: ParserPasses::new(&ctx.device)?,
            bg_cache: std::sync::Mutex::new(BindGroupCache::new()),
            resident_buffers: std::sync::Mutex::new(None),
            resident_token_kind_bind_groups: std::sync::Mutex::new(None),
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
        let mut timer_ref: Option<&mut GpuTimer> = None;
        self.record_ll1_resident_passes(&mut encoder, &bufs, true, true, None, &mut timer_ref)?;

        let status_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.resident_ll1.status"),
            size: 24,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.ll1_status, 0, &status_readback, 0, 24);

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
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for_with_tree_capacity(
            &mut resident_guard,
            token_capacity,
            tables,
            tree_capacity_override,
        );

        self.record_tokens_to_kinds_timed(
            encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            bufs,
            timer_ref,
        )?;
        if let Some(token_file_id_buf) = token_file_id_buf {
            let copy_bytes = (token_capacity as u64).saturating_mul(4);
            if copy_bytes > 0 {
                encoder.copy_buffer_to_buffer(
                    token_file_id_buf,
                    0,
                    &bufs.default_token_file_id,
                    0,
                    copy_bytes,
                );
            }
        } else {
            encoder.clear_buffer(&bufs.default_token_file_id, 0, None);
        }
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

    pub fn read_resident_projected_tree_capacity(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        _token_file_id_buf: Option<&wgpu::Buffer>,
        tables: &PrecomputedParseTables,
    ) -> Result<u32> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for_with_tree_capacity(
            &mut resident_guard,
            token_capacity,
            tables,
            Some(1),
        );

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.projected-tree-capacity.encoder"),
            });
        self.record_tokens_to_kinds(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            bufs,
        )?;
        self.record_resident_projected_status(&mut encoder, bufs)?;

        let status_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.projected_tree_capacity.status"),
            size: 24,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.projected_status, 0, &status_readback, 0, 24);
        crate::gpu::passes_core::submit_with_progress(
            &self.queue,
            "parser.projected-tree-capacity",
            encoder.finish(),
        );

        let slice = status_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &slice,
            "parser.projected_tree_capacity.status",
        )?;
        let mapped = slice.get_mapped_range();
        let words = read_u32_words(&mapped, 6)?;
        drop(mapped);
        status_readback.unmap();

        let emit_capacity = if words[0] == 0 && words[2] == 3 {
            words[3]
        } else {
            words[5]
        };
        Ok(emit_capacity.max(1))
    }

    pub fn projected_resident_tree_capacity(
        &self,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
    ) -> u32 {
        resident_projected_tree_capacity_for_tables(token_capacity.max(1), tables)
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
        let bufs = self.resident_buffers_for_with_tree_capacity(
            &mut resident_guard,
            token_capacity,
            tables,
            Some(tree_capacity),
        );
        consume(bufs)
    }

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
            .resident_token_kind_bind_groups
            .lock()
            .expect("parser.resident_token_kind_bind_groups poisoned") = None;
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
                hir_item_kind: Vec::new(),
                hir_item_name_token: Vec::new(),
                hir_item_decl_token: Vec::new(),
                hir_item_namespace: Vec::new(),
                hir_item_visibility: Vec::new(),
                hir_item_path_start: Vec::new(),
                hir_item_path_end: Vec::new(),
                hir_item_file_id: Vec::new(),
                hir_item_import_target_kind: Vec::new(),
                hir_variant_parent_enum: Vec::new(),
                hir_variant_ordinal: Vec::new(),
                hir_variant_payload_start: Vec::new(),
                hir_variant_payload_count: Vec::new(),
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
            hir_item_kind: decoded.hir_item_kind,
            hir_item_name_token: decoded.hir_item_name_token,
            hir_item_decl_token: decoded.hir_item_decl_token,
            hir_item_namespace: decoded.hir_item_namespace,
            hir_item_visibility: decoded.hir_item_visibility,
            hir_item_path_start: decoded.hir_item_path_start,
            hir_item_path_end: decoded.hir_item_path_end,
            hir_item_file_id: decoded.hir_item_file_id,
            hir_item_import_target_kind: decoded.hir_item_import_target_kind,
            hir_variant_parent_enum: decoded.hir_variant_parent_enum,
            hir_variant_ordinal: decoded.hir_variant_ordinal,
            hir_variant_payload_start: decoded.hir_variant_payload_start,
            hir_variant_payload_count: decoded.hir_variant_payload_count,
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

fn plan_parser_compute(pass: &PassData, n_elements: u32) -> Result<(u32, u32, u32)> {
    let [tgsx, tgsy, _] = pass.thread_group_size;
    plan_workgroups(
        DispatchDim::D1,
        InputElements::Elements1D(n_elements),
        [tgsx, tgsy, 1],
    )
}

fn parser_compute_pass_batching_enabled(timer_ref: &mut Option<&mut GpuTimer>) -> bool {
    timer_ref.is_none() && compute_pass_batching_enabled() && !validation_scopes_enabled()
}

fn clear_type_arg_rank_b(encoder: &mut wgpu::CommandEncoder, buffers: &ParserBuffers) {
    let bytes = u64::from(buffers.tree_capacity) * 4;
    for buffer in [
        &buffers.hir_type_arg_owner_b,
        &buffers.hir_type_arg_link_b,
        &buffers.hir_type_arg_rank_b,
    ] {
        encoder.clear_buffer(&buffer.buffer, 0, Some(bytes));
    }
}

fn record_parser_compute(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &'static str,
    n_elements: u32,
) -> Result<()> {
    let (gx, gy, gz) = plan_parser_compute(pass, n_elements)?;
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), &[]);
    compute.dispatch_workgroups(gx, gy, gz);
    Ok(())
}
