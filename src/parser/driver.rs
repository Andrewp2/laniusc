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

mod resident_tree;
mod support;
use anyhow::Result;
use encase::ShaderType;
pub use support::get_global_parser;
use support::*;
use wgpu;

use super::passes::ll1_blocks_01::LL1_BLOCK_STATUS_WORDS;
use crate::{
    gpu::{
        buffers::{LaniusBuffer, uniform_from_val},
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

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct TokensToKindsParams {
    token_capacity: u32,
}

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
    pub hir_semantic_prefix_before_node: Vec<u32>,
    pub hir_semantic_dense_node: Vec<u32>,
    pub hir_semantic_subtree_end: Vec<u32>,
    pub hir_semantic_parent: Vec<u32>,
    pub hir_semantic_first_child: Vec<u32>,
    pub hir_semantic_next_sibling: Vec<u32>,
    pub hir_semantic_depth: Vec<u32>,
    pub hir_semantic_child_index: Vec<u32>,
    pub hir_token_pos: Vec<u32>,
    pub hir_token_end: Vec<u32>,
    pub hir_type_form: Vec<u32>,
    pub hir_type_value_node: Vec<u32>,
    pub hir_type_len_token: Vec<u32>,
    pub hir_type_len_value: Vec<u32>,
    pub hir_type_file_id: Vec<u32>,
    pub hir_type_path_leaf_node: Vec<u32>,
    pub hir_type_arg_start: Vec<u32>,
    pub hir_type_arg_count: Vec<u32>,
    pub hir_type_arg_next: Vec<u32>,
    pub hir_type_alias_target_node: Vec<u32>,
    pub hir_fn_return_type_node: Vec<u32>,
    pub hir_item_kind: Vec<u32>,
    pub hir_item_name_token: Vec<u32>,
    pub hir_item_decl_token: Vec<u32>,
    pub hir_item_namespace: Vec<u32>,
    pub hir_item_visibility: Vec<u32>,
    pub hir_item_path_start: Vec<u32>,
    pub hir_item_path_end: Vec<u32>,
    pub hir_item_file_id: Vec<u32>,
    pub hir_item_import_target_kind: Vec<u32>,
    pub hir_variant_parent_enum: Vec<u32>,
    pub hir_variant_ordinal: Vec<u32>,
    pub hir_variant_payload_start: Vec<u32>,
    pub hir_variant_payload_count: Vec<u32>,
    pub hir_match_scrutinee_node: Vec<u32>,
    pub hir_match_arm_start: Vec<u32>,
    pub hir_match_arm_count: Vec<u32>,
    pub hir_match_arm_next: Vec<u32>,
    pub hir_match_arm_pattern_node: Vec<u32>,
    pub hir_match_arm_payload_start: Vec<u32>,
    pub hir_match_arm_payload_count: Vec<u32>,
    pub hir_match_arm_result_node: Vec<u32>,
    pub hir_match_payload_owner_arm: Vec<u32>,
    pub hir_match_payload_match_node: Vec<u32>,
    pub hir_match_payload_ordinal: Vec<u32>,
    pub hir_call_callee_node: Vec<u32>,
    pub hir_call_arg_start: Vec<u32>,
    pub hir_call_arg_end: Vec<u32>,
    pub hir_call_arg_count: Vec<u32>,
    pub hir_call_arg_parent_call: Vec<u32>,
    pub hir_call_arg_ordinal: Vec<u32>,
    pub hir_array_lit_first_element: Vec<u32>,
    pub hir_array_lit_element_count: Vec<u32>,
    pub hir_array_element_parent_lit: Vec<u32>,
    pub hir_array_element_ordinal: Vec<u32>,
    pub hir_array_element_next: Vec<u32>,
    pub hir_member_receiver_node: Vec<u32>,
    pub hir_member_receiver_token: Vec<u32>,
    pub hir_member_name_token: Vec<u32>,
    pub hir_struct_field_parent_struct: Vec<u32>,
    pub hir_struct_field_ordinal: Vec<u32>,
    pub hir_struct_field_type_node: Vec<u32>,
    pub hir_struct_decl_field_start: Vec<u32>,
    pub hir_struct_decl_field_count: Vec<u32>,
    pub hir_struct_lit_head_node: Vec<u32>,
    pub hir_struct_lit_field_start: Vec<u32>,
    pub hir_struct_lit_field_count: Vec<u32>,
    pub hir_struct_lit_field_parent_lit: Vec<u32>,
    pub hir_struct_lit_field_value_node: Vec<u32>,
    pub hir_struct_lit_field_next: Vec<u32>,

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
    pub hir_semantic_prefix_before_node: Vec<u32>,
    pub hir_semantic_dense_node: Vec<u32>,
    pub hir_semantic_subtree_end: Vec<u32>,
    pub hir_semantic_parent: Vec<u32>,
    pub hir_semantic_first_child: Vec<u32>,
    pub hir_semantic_next_sibling: Vec<u32>,
    pub hir_semantic_depth: Vec<u32>,
    pub hir_semantic_child_index: Vec<u32>,
    pub hir_token_pos: Vec<u32>,
    pub hir_token_end: Vec<u32>,
    pub hir_type_form: Vec<u32>,
    pub hir_type_value_node: Vec<u32>,
    pub hir_type_len_token: Vec<u32>,
    pub hir_type_len_value: Vec<u32>,
    pub hir_type_file_id: Vec<u32>,
    pub hir_type_path_leaf_node: Vec<u32>,
    pub hir_type_arg_start: Vec<u32>,
    pub hir_type_arg_count: Vec<u32>,
    pub hir_type_arg_next: Vec<u32>,
    pub hir_type_alias_target_node: Vec<u32>,
    pub hir_fn_return_type_node: Vec<u32>,
    pub hir_item_kind: Vec<u32>,
    pub hir_item_name_token: Vec<u32>,
    pub hir_item_decl_token: Vec<u32>,
    pub hir_item_namespace: Vec<u32>,
    pub hir_item_visibility: Vec<u32>,
    pub hir_item_path_start: Vec<u32>,
    pub hir_item_path_end: Vec<u32>,
    pub hir_item_file_id: Vec<u32>,
    pub hir_item_import_target_kind: Vec<u32>,
    pub hir_variant_parent_enum: Vec<u32>,
    pub hir_variant_ordinal: Vec<u32>,
    pub hir_variant_payload_start: Vec<u32>,
    pub hir_variant_payload_count: Vec<u32>,
    pub hir_match_scrutinee_node: Vec<u32>,
    pub hir_match_arm_start: Vec<u32>,
    pub hir_match_arm_count: Vec<u32>,
    pub hir_match_arm_next: Vec<u32>,
    pub hir_match_arm_pattern_node: Vec<u32>,
    pub hir_match_arm_payload_start: Vec<u32>,
    pub hir_match_arm_payload_count: Vec<u32>,
    pub hir_match_arm_result_node: Vec<u32>,
    pub hir_match_payload_owner_arm: Vec<u32>,
    pub hir_match_payload_match_node: Vec<u32>,
    pub hir_match_payload_ordinal: Vec<u32>,
    pub hir_call_callee_node: Vec<u32>,
    pub hir_call_arg_start: Vec<u32>,
    pub hir_call_arg_end: Vec<u32>,
    pub hir_call_arg_count: Vec<u32>,
    pub hir_call_arg_parent_call: Vec<u32>,
    pub hir_call_arg_ordinal: Vec<u32>,
    pub hir_array_lit_first_element: Vec<u32>,
    pub hir_array_lit_element_count: Vec<u32>,
    pub hir_array_element_parent_lit: Vec<u32>,
    pub hir_array_element_ordinal: Vec<u32>,
    pub hir_array_element_next: Vec<u32>,
    pub hir_member_receiver_node: Vec<u32>,
    pub hir_member_receiver_token: Vec<u32>,
    pub hir_member_name_token: Vec<u32>,
    pub hir_struct_field_parent_struct: Vec<u32>,
    pub hir_struct_field_ordinal: Vec<u32>,
    pub hir_struct_field_type_node: Vec<u32>,
    pub hir_struct_decl_field_start: Vec<u32>,
    pub hir_struct_decl_field_count: Vec<u32>,
    pub hir_struct_lit_head_node: Vec<u32>,
    pub hir_struct_lit_field_start: Vec<u32>,
    pub hir_struct_lit_field_count: Vec<u32>,
    pub hir_struct_lit_field_parent_lit: Vec<u32>,
    pub hir_struct_lit_field_value_node: Vec<u32>,
    pub hir_struct_lit_field_next: Vec<u32>,
}

pub struct RecordedResidentLl1HirCheck {
    status_readback: wgpu::Buffer,
}

pub struct RecordedHirSemanticCount {
    block_count_readback: wgpu::Buffer,
    block_count_words: usize,
}

struct ResidentParserBufferCache {
    token_capacity: u32,
    tree_capacity_override: Option<u32>,
    table_fingerprint: u64,
    retain_debug_hir_buffers: bool,
    buffers: ParserBuffers,
}

struct ResidentTokenKindBindGroups {
    input_fingerprint: u64,
    tokens_to_kinds_params: LaniusBuffer<TokensToKindsParams>,
    tokens_to_kinds: wgpu::BindGroup,
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

    pub fn record_hir_semantic_count_readback(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<RecordedHirSemanticCount> {
        stamp_timer(timer_ref, encoder, "parser.hir_semantic_count_readback");
        let byte_size = bufs.hir_semantic_count.byte_size as u64;
        let block_count_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.hir_semantic_count"),
            size: byte_size,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(
            &bufs.hir_semantic_count,
            0,
            &block_count_readback,
            0,
            byte_size,
        );

        Ok(RecordedHirSemanticCount {
            block_count_readback,
            block_count_words: bufs.hir_semantic_count.count,
        })
    }

    pub fn finish_recorded_hir_semantic_count(
        &self,
        recorded: &RecordedHirSemanticCount,
    ) -> Result<u32> {
        let slice = recorded.block_count_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &slice,
            "parser.hir_semantic_count",
        )?;
        let mapped = slice.get_mapped_range();
        let words = read_u32_words(&mapped, recorded.block_count_words)?;
        drop(mapped);
        recorded.block_count_readback.unmap();
        Ok(words.into_iter().fold(0u32, u32::saturating_add))
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
        let bufs = self.resident_debug_buffers_for(&mut resident_guard, token_capacity, tables);

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
        self.record_ll1_resident_passes(&mut encoder, &bufs, true, true, None, &mut timer_ref)?;

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
        crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "parser.recorded-ll1-hir",
            encoder.finish(),
            use_scopes,
            "recorded LL(1) HIR batch",
        );

        self.finish_recorded_resident_ll1_hir_check(&recorded_parser)?;
        Ok(consume_after_submit(bufs, recorded_more))
    }

    pub fn finish_recorded_resident_ll1_hir_check(
        &self,
        recorded: &RecordedResidentLl1HirCheck,
    ) -> Result<()> {
        self.finish_recorded_resident_ll1_hir_check_result(recorded)
            .map(|_| ())
    }

    pub fn finish_recorded_resident_ll1_hir_check_result(
        &self,
        recorded: &RecordedResidentLl1HirCheck,
    ) -> Result<Ll1AcceptResult> {
        let slice = recorded.status_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &slice,
            "parser.recorded-ll1-hir.status",
        )?;
        let mapped = slice.get_mapped_range();
        let words = read_u32_words(&mapped, 6)?;
        drop(mapped);
        recorded.status_readback.unmap();

        let result = Ll1AcceptResult {
            accepted: words[0] != 0,
            error_pos: words[1],
            error_code: words[2],
            detail: words[3],
            steps: words[4],
            emit_len: words[5],
        };

        if !result.accepted {
            anyhow::bail!(
                "GPU LL(1) parser rejected token {}: error {} ({}) after {} steps",
                result.error_pos,
                result.error_code,
                result.detail,
                result.steps
            );
        }

        Ok(result)
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

    fn record_tokens_to_kinds(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let mut timer_ref: Option<&mut GpuTimer> = None;
        self.record_tokens_to_kinds_timed(
            encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            bufs,
            &mut timer_ref,
        )
    }

    fn record_tokens_to_kinds_timed(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<()> {
        let pass = &self.tokens_to_kinds;
        let mut bind_guard = self
            .resident_token_kind_bind_groups
            .lock()
            .expect("parser.resident_token_kind_bind_groups poisoned");
        self.ensure_resident_token_kind_bind_groups(
            &mut bind_guard,
            token_buf,
            token_count_buf,
            bufs,
        )?;
        let bind_groups = bind_guard
            .as_ref()
            .expect("resident token-kind parser bind groups allocated");
        self.record_token_delimiters_timed(encoder, token_buf, token_count_buf, bufs, timer_ref)?;
        encoder.clear_buffer(&bufs.token_feature_flags.buffer, 0, Some(4));
        write_uniform(
            &self.queue,
            &bind_groups.tokens_to_kinds_params,
            &TokensToKindsParams { token_capacity },
        );

        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("parser.tokens_to_kinds.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, Some(&bind_groups.tokens_to_kinds), &[]);
            compute.dispatch_workgroups((token_capacity + 2).div_ceil(256).max(1), 1, 1);
        }
        stamp_timer(timer_ref, encoder, "parser.tokens_to_kinds.done");
        Ok(())
    }

    fn record_token_delimiters_timed(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
        timer_ref: &mut Option<&mut GpuTimer>,
    ) -> Result<()> {
        let local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_brace_inblock".into(),
                bufs.token_depth_brace_inblock.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "block_sum_brace".into(),
                bufs.token_block_sum_brace.as_entire_binding(),
            ),
            (
                "block_sum_bracket".into(),
                bufs.token_block_sum_bracket.as_entire_binding(),
            ),
            (
                "top_brace_owner_block".into(),
                bufs.token_top_brace_owner_block.as_entire_binding(),
            ),
            (
                "statement_event_block".into(),
                bufs.token_statement_event_block.as_entire_binding(),
            ),
        ]);
        let local_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_delimiters_01_local"),
            &self.token_delimiters_01.bind_group_layouts[0],
            &self.token_delimiters_01.reflection,
            0,
            &local_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.token_delimiters_01,
            &local_bind_group,
            "parser.tokens.delimiters.local",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.delimiters.local.done");

        self.record_token_delimiter_scan_steps(
            encoder,
            bufs,
            "parser.tokens.delimiters.scan.depth",
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.delimiters.depth_scan.done",
        );
        self.record_token_delimiter_owner_local(encoder, token_buf, token_count_buf, bufs)?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.delimiters.owner_local.done",
        );
        self.record_token_delimiter_scan_steps(
            encoder,
            bufs,
            "parser.tokens.delimiters.scan.owner",
        )?;
        stamp_timer(
            timer_ref,
            encoder,
            "parser.tokens.delimiters.owner_scan.done",
        );

        let context_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_brace_inblock".into(),
                bufs.token_depth_brace_inblock.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_brace".into(),
                bufs.token_block_prefix_brace.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                bufs.token_block_prefix_bracket.as_entire_binding(),
            ),
            (
                "top_brace_owner_block_prefix".into(),
                bufs.token_top_brace_owner_block_prefix.as_entire_binding(),
            ),
            (
                "statement_event_block_prefix".into(),
                bufs.token_statement_event_block_prefix.as_entire_binding(),
            ),
            (
                "brace_semantic_kind".into(),
                bufs.token_brace_semantic_kind.as_entire_binding(),
            ),
            (
                "statement_context_kind".into(),
                bufs.token_statement_context_kind.as_entire_binding(),
            ),
        ]);
        let context_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_brace_context"),
            &self.tokens_brace_context.bind_group_layouts[0],
            &self.tokens_brace_context.reflection,
            0,
            &context_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_brace_context,
            &context_bind_group,
            "parser.tokens.brace_context",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;
        stamp_timer(timer_ref, encoder, "parser.tokens.brace_context.done");

        self.record_token_bracket_matching(encoder, token_buf, token_count_buf, bufs)?;
        stamp_timer(timer_ref, encoder, "parser.tokens.bracket_match.done");

        self.record_token_brace_matching(encoder, token_buf, token_count_buf, bufs)?;
        stamp_timer(timer_ref, encoder, "parser.tokens.brace_match.done");

        Ok(())
    }

    fn record_token_bracket_matching(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let n_tokens = bufs.token_input_capacity.max(1);

        let depth_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_brace_match_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                bufs.token_block_prefix_bracket.as_entire_binding(),
            ),
            (
                "statement_context_kind".into(),
                bufs.token_statement_context_kind.as_entire_binding(),
            ),
            (
                "bracket_semantic_kind".into(),
                bufs.token_bracket_semantic_kind.as_entire_binding(),
            ),
            (
                "brace_match_depth".into(),
                bufs.token_brace_match_depth.as_entire_binding(),
            ),
            (
                "brace_match_block_min".into(),
                bufs.token_brace_match_block_min.as_entire_binding(),
            ),
        ]);
        let depth_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_bracket_match_01_depth_blocks"),
            &self.tokens_bracket_match_01_depth_blocks.bind_group_layouts[0],
            &self.tokens_bracket_match_01_depth_blocks.reflection,
            0,
            &depth_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_bracket_match_01_depth_blocks,
            &depth_bind_group,
            "parser.tokens.bracket_match.depth_blocks",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;

        self.record_token_brace_match_min_tree_build(encoder, bufs)?;

        let pair_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_brace_match_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                bufs.token_block_prefix_bracket.as_entire_binding(),
            ),
            (
                "brace_match_depth".into(),
                bufs.token_brace_match_depth.as_entire_binding(),
            ),
            (
                "brace_match_block_min".into(),
                bufs.token_brace_match_block_min.as_entire_binding(),
            ),
            (
                "brace_match_min_tree".into(),
                bufs.token_brace_match_min_tree.as_entire_binding(),
            ),
            (
                "bracket_semantic_kind".into(),
                bufs.token_bracket_semantic_kind.as_entire_binding(),
            ),
        ]);
        let pair_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_bracket_match_03_pair_pse"),
            &self.tokens_bracket_match_03_pair_pse.bind_group_layouts[0],
            &self.tokens_bracket_match_03_pair_pse.reflection,
            0,
            &pair_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_bracket_match_03_pair_pse,
            &pair_bind_group,
            "parser.tokens.bracket_match.pair_pse",
            n_tokens,
        )?;

        Ok(())
    }

    fn record_token_brace_matching(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let n_tokens = bufs.token_input_capacity.max(1);

        let depth_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_brace_match_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_brace_inblock".into(),
                bufs.token_depth_brace_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_brace".into(),
                bufs.token_block_prefix_brace.as_entire_binding(),
            ),
            (
                "brace_match_depth".into(),
                bufs.token_brace_match_depth.as_entire_binding(),
            ),
            (
                "brace_match_block_min".into(),
                bufs.token_brace_match_block_min.as_entire_binding(),
            ),
        ]);
        let depth_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_brace_match_01_depth_blocks"),
            &self.tokens_brace_match_01_depth_blocks.bind_group_layouts[0],
            &self.tokens_brace_match_01_depth_blocks.reflection,
            0,
            &depth_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_brace_match_01_depth_blocks,
            &depth_bind_group,
            "parser.tokens.brace_match.depth_blocks",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;

        self.record_token_brace_match_min_tree_build(encoder, bufs)?;

        let pair_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_brace_match_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "brace_match_depth".into(),
                bufs.token_brace_match_depth.as_entire_binding(),
            ),
            (
                "brace_match_block_min".into(),
                bufs.token_brace_match_block_min.as_entire_binding(),
            ),
            (
                "brace_match_min_tree".into(),
                bufs.token_brace_match_min_tree.as_entire_binding(),
            ),
            (
                "brace_semantic_kind".into(),
                bufs.token_brace_semantic_kind.as_entire_binding(),
            ),
        ]);
        let pair_bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_brace_match_03_pair_pse"),
            &self.tokens_brace_match_03_pair_pse.bind_group_layouts[0],
            &self.tokens_brace_match_03_pair_pse.reflection,
            0,
            &pair_resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tokens_brace_match_03_pair_pse,
            &pair_bind_group,
            "parser.tokens.brace_match.pair_pse",
            n_tokens,
        )?;

        Ok(())
    }

    fn record_token_brace_match_min_tree_build(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        for step in &bufs.token_brace_match_min_tree_steps {
            let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gMinTree".into(), step.params.as_entire_binding()),
                (
                    "brace_match_block_min".into(),
                    bufs.token_brace_match_block_min.as_entire_binding(),
                ),
                (
                    "brace_match_min_tree".into(),
                    bufs.token_brace_match_min_tree.as_entire_binding(),
                ),
            ]);
            let bind_group = bind_group::create_bind_group_from_reflection(
                &self.device,
                Some("parser_tokens_brace_match_02_build_min_tree"),
                &self.tokens_brace_match_02_build_min_tree.bind_group_layouts[0],
                &self.tokens_brace_match_02_build_min_tree.reflection,
                0,
                &resources,
            )?;
            record_parser_compute(
                encoder,
                &self.tokens_brace_match_02_build_min_tree,
                &bind_group,
                "parser.tokens.brace_match.build_min_tree",
                step.work_items,
            )?;
        }
        Ok(())
    }

    fn record_token_delimiter_scan_steps(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
        label: &'static str,
    ) -> Result<()> {
        for step in &bufs.token_delimiter_scan_steps {
            let prefix_brace_in = if step.read_from_a {
                &bufs.token_prefix_brace_a
            } else {
                &bufs.token_prefix_brace_b
            };
            let prefix_brace_out = if step.write_to_a {
                &bufs.token_prefix_brace_a
            } else {
                &bufs.token_prefix_brace_b
            };
            let prefix_bracket_in = if step.read_from_a {
                &bufs.token_prefix_bracket_a
            } else {
                &bufs.token_prefix_bracket_b
            };
            let prefix_bracket_out = if step.write_to_a {
                &bufs.token_prefix_bracket_a
            } else {
                &bufs.token_prefix_bracket_b
            };
            let top_owner_prefix_in = if step.read_from_a {
                &bufs.token_top_brace_owner_prefix_a
            } else {
                &bufs.token_top_brace_owner_prefix_b
            };
            let top_owner_prefix_out = if step.write_to_a {
                &bufs.token_top_brace_owner_prefix_a
            } else {
                &bufs.token_top_brace_owner_prefix_b
            };
            let statement_event_prefix_in = if step.read_from_a {
                &bufs.token_statement_event_prefix_a
            } else {
                &bufs.token_statement_event_prefix_b
            };
            let statement_event_prefix_out = if step.write_to_a {
                &bufs.token_statement_event_prefix_a
            } else {
                &bufs.token_statement_event_prefix_b
            };
            let scan_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gParams".into(), step.params.as_entire_binding()),
                (
                    "block_sum_brace".into(),
                    bufs.token_block_sum_brace.as_entire_binding(),
                ),
                (
                    "block_sum_bracket".into(),
                    bufs.token_block_sum_bracket.as_entire_binding(),
                ),
                (
                    "prefix_brace_in".into(),
                    prefix_brace_in.as_entire_binding(),
                ),
                (
                    "prefix_bracket_in".into(),
                    prefix_bracket_in.as_entire_binding(),
                ),
                (
                    "top_brace_owner_block".into(),
                    bufs.token_top_brace_owner_block.as_entire_binding(),
                ),
                (
                    "top_brace_owner_prefix_in".into(),
                    top_owner_prefix_in.as_entire_binding(),
                ),
                (
                    "statement_event_block".into(),
                    bufs.token_statement_event_block.as_entire_binding(),
                ),
                (
                    "statement_event_prefix_in".into(),
                    statement_event_prefix_in.as_entire_binding(),
                ),
                (
                    "prefix_brace_out".into(),
                    prefix_brace_out.as_entire_binding(),
                ),
                (
                    "prefix_bracket_out".into(),
                    prefix_bracket_out.as_entire_binding(),
                ),
                (
                    "block_prefix_brace".into(),
                    bufs.token_block_prefix_brace.as_entire_binding(),
                ),
                (
                    "block_prefix_bracket".into(),
                    bufs.token_block_prefix_bracket.as_entire_binding(),
                ),
                (
                    "top_brace_owner_prefix_out".into(),
                    top_owner_prefix_out.as_entire_binding(),
                ),
                (
                    "top_brace_owner_block_prefix".into(),
                    bufs.token_top_brace_owner_block_prefix.as_entire_binding(),
                ),
                (
                    "statement_event_prefix_out".into(),
                    statement_event_prefix_out.as_entire_binding(),
                ),
                (
                    "statement_event_block_prefix".into(),
                    bufs.token_statement_event_block_prefix.as_entire_binding(),
                ),
            ]);
            let scan_bind_group = bind_group::create_bind_group_from_reflection(
                &self.device,
                Some("parser_tokens_delimiters_02_scan"),
                &self.token_delimiters_02.bind_group_layouts[0],
                &self.token_delimiters_02.reflection,
                0,
                &scan_resources,
            )?;
            record_parser_compute(
                encoder,
                &self.token_delimiters_02,
                &scan_bind_group,
                label,
                bufs.token_delimiter_n_blocks,
            )?;
        }
        Ok(())
    }

    fn record_token_delimiter_owner_local(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                bufs.token_delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_brace_inblock".into(),
                bufs.token_depth_brace_inblock.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                bufs.token_depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_brace".into(),
                bufs.token_block_prefix_brace.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                bufs.token_block_prefix_bracket.as_entire_binding(),
            ),
            (
                "top_brace_owner_block".into(),
                bufs.token_top_brace_owner_block.as_entire_binding(),
            ),
            (
                "brace_semantic_kind".into(),
                bufs.token_brace_semantic_kind.as_entire_binding(),
            ),
            (
                "statement_event_block".into(),
                bufs.token_statement_event_block.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tokens_delimiters_03_owner_local"),
            &self.token_delimiters_03_owner_local.bind_group_layouts[0],
            &self.token_delimiters_03_owner_local.reflection,
            0,
            &resources,
        )?;
        record_parser_compute(
            encoder,
            &self.token_delimiters_03_owner_local,
            &bind_group,
            "parser.tokens.delimiters.owner_local",
            bufs.token_delimiter_n_blocks.saturating_mul(256),
        )?;

        Ok(())
    }

    #[doc(hidden)]
    pub fn debug_semantic_token_kinds_for_resident_tokens(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
    ) -> Result<Vec<u32>> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for(&mut resident_guard, token_capacity, tables);

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.semantic_token_kinds.debug.encoder"),
            });
        self.record_tokens_to_kinds(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            bufs,
        )?;

        let count_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.semantic_token_kinds.count"),
            size: 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let kinds_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.semantic_token_kinds"),
            size: bufs.semantic_token_kinds.byte_size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &count_readback, 0, 4);
        encoder.copy_buffer_to_buffer(
            &bufs.semantic_token_kinds,
            0,
            &kinds_readback,
            0,
            bufs.semantic_token_kinds.byte_size as u64,
        );

        crate::gpu::passes_core::submit_with_progress(
            &self.queue,
            "parser.semantic-token-kinds.debug",
            encoder.finish(),
        );

        let count_slice = count_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &count_slice,
            "parser.semantic_token_kinds.count",
        )?;
        let count_mapped = count_slice.get_mapped_range();
        let count_words = read_u32_words(&count_mapped, 1)?;
        drop(count_mapped);
        count_readback.unmap();

        let out_count = count_words[0].saturating_add(2) as usize;
        let read_count = out_count.min(bufs.semantic_token_kinds.count);
        let byte_len = (read_count * 4) as u64;
        let kinds_slice = kinds_readback.slice(0..byte_len);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &kinds_slice,
            "parser.semantic_token_kinds",
        )?;
        let kinds_mapped = kinds_slice.get_mapped_range();
        let words = read_u32_words(&kinds_mapped, read_count)?;
        drop(kinds_mapped);
        kinds_readback.unmap();
        Ok(words)
    }

    #[doc(hidden)]
    pub fn debug_token_feature_flags_for_resident_tokens(
        &self,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        tables: &PrecomputedParseTables,
    ) -> Result<u32> {
        let mut resident_guard = self
            .resident_buffers
            .lock()
            .expect("parser.resident_buffers poisoned");
        let bufs = self.resident_buffers_for(&mut resident_guard, token_capacity, tables);

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("parser.token_feature_flags.debug.encoder"),
            });
        self.record_tokens_to_kinds(
            &mut encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            bufs,
        )?;

        let flags_readback = self.device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.parser.token_feature_flags"),
            size: 4,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&bufs.token_feature_flags, 0, &flags_readback, 0, 4);

        crate::gpu::passes_core::submit_with_progress(
            &self.queue,
            "parser.token-feature-flags.debug",
            encoder.finish(),
        );

        let flags_slice = flags_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(
            &self.device,
            &flags_slice,
            "parser.token_feature_flags",
        )?;
        let flags_mapped = flags_slice.get_mapped_range();
        let words = read_u32_words(&flags_mapped, 1)?;
        drop(flags_mapped);
        flags_readback.unmap();
        Ok(words[0])
    }

    fn ensure_resident_token_kind_bind_groups(
        &self,
        slot: &mut Option<ResidentTokenKindBindGroups>,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let fingerprint = buffer_fingerprint(&[
            token_buf,
            token_count_buf,
            &bufs.semantic_token_kinds,
            &bufs.token_depth_brace_inblock,
            &bufs.token_block_prefix_brace,
            &bufs.token_brace_semantic_kind,
            &bufs.token_bracket_semantic_kind,
            &bufs.token_statement_context_kind,
            &bufs.token_brace_match_depth,
            &bufs.token_brace_match_block_min,
            &bufs.token_brace_match_min_tree,
            &bufs.token_feature_flags,
            &bufs.token_count,
        ]);
        if slot
            .as_ref()
            .is_none_or(|cached| cached.input_fingerprint != fingerprint)
        {
            *slot = Some(self.create_resident_token_kind_bind_groups(
                fingerprint,
                token_buf,
                token_count_buf,
                bufs,
            )?);
        }
        Ok(())
    }

    fn create_resident_token_kind_bind_groups(
        &self,
        input_fingerprint: u64,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        bufs: &ParserBuffers,
    ) -> Result<ResidentTokenKindBindGroups> {
        let tokens_to_kinds_params = uniform_from_val(
            &self.device,
            "parser.tokens_to_kinds.params",
            &TokensToKindsParams { token_capacity: 0 },
        );

        let tokens_to_kinds_resources: HashMap<String, wgpu::BindingResource<'_>> =
            HashMap::from([
                ("gParams".into(), tokens_to_kinds_params.as_entire_binding()),
                ("token_words".into(), token_buf.as_entire_binding()),
                (
                    "lexer_token_count".into(),
                    token_count_buf.as_entire_binding(),
                ),
                (
                    "depth_brace_inblock".into(),
                    bufs.token_depth_brace_inblock.as_entire_binding(),
                ),
                (
                    "block_prefix_brace".into(),
                    bufs.token_block_prefix_brace.as_entire_binding(),
                ),
                (
                    "brace_match_depth".into(),
                    bufs.token_brace_match_depth.as_entire_binding(),
                ),
                (
                    "brace_match_block_min".into(),
                    bufs.token_brace_match_block_min.as_entire_binding(),
                ),
                (
                    "brace_match_min_tree".into(),
                    bufs.token_brace_match_min_tree.as_entire_binding(),
                ),
                (
                    "semantic_token_kinds".into(),
                    bufs.semantic_token_kinds.as_entire_binding(),
                ),
                (
                    "brace_semantic_kind".into(),
                    bufs.token_brace_semantic_kind.as_entire_binding(),
                ),
                (
                    "bracket_semantic_kind".into(),
                    bufs.token_bracket_semantic_kind.as_entire_binding(),
                ),
                (
                    "statement_context_kind".into(),
                    bufs.token_statement_context_kind.as_entire_binding(),
                ),
                (
                    "token_feature_flags".into(),
                    bufs.token_feature_flags.as_entire_binding(),
                ),
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

        Ok(ResidentTokenKindBindGroups {
            input_fingerprint,
            tokens_to_kinds_params,
            tokens_to_kinds,
        })
    }

    fn record_tree_active_dispatch_args(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gTree".into(), bufs.tree_prefix_params.as_entire_binding()),
            ("ll1_status".into(), bufs.ll1_status.as_entire_binding()),
            (
                "tree_active_dispatch_args".into(),
                bufs.tree_active_dispatch_args.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tree_active_dispatch_args"),
            &self.tree_active_dispatch_args.bind_group_layouts[0],
            &self.tree_active_dispatch_args.reflection,
            0,
            &resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tree_active_dispatch_args,
            &bind_group,
            "parser.tree_active_dispatch_args",
            1,
        )
    }

    fn record_tree_feature_dispatch_args(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gTree".into(), bufs.tree_prefix_params.as_entire_binding()),
            ("ll1_status".into(), bufs.ll1_status.as_entire_binding()),
            (
                "token_feature_flags".into(),
                bufs.token_feature_flags.as_entire_binding(),
            ),
            (
                "tree_enum_dispatch_args".into(),
                bufs.tree_enum_dispatch_args.as_entire_binding(),
            ),
            (
                "tree_match_dispatch_args".into(),
                bufs.tree_match_dispatch_args.as_entire_binding(),
            ),
            (
                "tree_struct_dispatch_args".into(),
                bufs.tree_struct_dispatch_args.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_tree_feature_dispatch_args"),
            &self.tree_feature_dispatch_args.bind_group_layouts[0],
            &self.tree_feature_dispatch_args.reflection,
            0,
            &resources,
        )?;
        record_parser_compute(
            encoder,
            &self.tree_feature_dispatch_args,
            &bind_group,
            "parser.tree_feature_dispatch_args",
            1,
        )
    }

    fn record_active_pair_dispatch_args(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), bufs.params_llp.as_entire_binding()),
            ("token_count".into(), bufs.token_count.as_entire_binding()),
            (
                "active_pair_thread_dispatch_args".into(),
                bufs.active_pair_thread_dispatch_args.as_entire_binding(),
            ),
            (
                "active_pair_group_dispatch_args".into(),
                bufs.active_pair_group_dispatch_args.as_entire_binding(),
            ),
        ]);
        let bind_group = bind_group::create_bind_group_from_reflection(
            &self.device,
            Some("parser_active_pair_dispatch_args"),
            &self.active_pair_dispatch_args.bind_group_layouts[0],
            &self.active_pair_dispatch_args.reflection,
            0,
            &resources,
        )?;
        record_parser_compute(
            encoder,
            &self.active_pair_dispatch_args,
            &bind_group,
            "parser.active_pair_dispatch_args",
            1,
        )
    }

    fn record_resident_projected_status(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<()> {
        if bufs.tree_stream_uses_ll1 {
            anyhow::bail!(
                "projected tree capacity readback is only implemented for pair-stream parser buffers"
            );
        }

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

        self.record_active_pair_dispatch_args(ctx.encoder, bufs)?;
        self.passes
            .llp_pairs
            .record_pass_indirect(&mut ctx, &bufs.active_pair_thread_dispatch_args)?;
        self.passes
            .pack_totals_blocks
            .record_pass(ctx.device, ctx.encoder, ctx.buffers)?;
        self.passes
            .pack_totals_reduce
            .record_reduce(ctx.device, ctx.encoder, ctx.buffers)?;
        self.passes
            .pack_totals_status
            .record_pass(ctx.device, ctx.encoder, ctx.buffers)?;
        Ok(())
    }

    fn record_ll1_resident_passes(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ParserBuffers,
        include_tree: bool,
        include_hir_spans: bool,
        literal_source: Option<(u32, &wgpu::Buffer, &wgpu::Buffer)>,
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

        if bufs.tree_stream_uses_ll1 {
            let n_ll1_blocks = bufs.ll1_n_blocks;
            self.passes.ll1_blocks_02.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(
                    n_ll1_blocks.saturating_mul(256),
                ),
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.ll1_blocks_02");
            self.passes.ll1_blocks_03.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(
                    n_ll1_blocks.saturating_mul(256),
                ),
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
        } else {
            self.record_active_pair_dispatch_args(ctx.encoder, bufs)?;
            stamp_timer(timer_ref, ctx.encoder, "parser.active_pair_dispatch_args");
            self.passes
                .llp_pairs
                .record_pass_indirect(&mut ctx, &bufs.active_pair_thread_dispatch_args)?;
            stamp_timer(timer_ref, ctx.encoder, "parser.llp_pairs");
            self.passes.pack_offsets.record_scan_indirect(
                ctx.device,
                ctx.encoder,
                ctx.buffers,
                &bufs.active_pair_thread_dispatch_args,
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.pack_offsets");
            self.passes.pack_offsets_status.record_pass_indirect(
                ctx.device,
                ctx.encoder,
                ctx.buffers,
                &bufs.active_pair_thread_dispatch_args,
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.pack_offsets_status");
            self.passes
                .pack_varlen
                .record_pass_indirect(&mut ctx, &bufs.active_pair_group_dispatch_args)?;
            stamp_timer(timer_ref, ctx.encoder, "parser.pack_varlen");
            ctx.encoder
                .copy_buffer_to_buffer(&bufs.projected_status, 0, &bufs.ll1_status, 0, 24);
        }
        if include_tree {
            self.record_tree_active_dispatch_args(ctx.encoder, bufs)?;
            stamp_timer(timer_ref, ctx.encoder, "parser.tree_active_dispatch_args");
            self.record_tree_feature_dispatch_args(ctx.encoder, bufs)?;
            stamp_timer(timer_ref, ctx.encoder, "parser.tree_feature_dispatch_args");
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
            if parser_compute_pass_batching_enabled(timer_ref) {
                let bg_cache = ctx
                    .bg_cache
                    .as_deref_mut()
                    .expect("parser batching requires bind-group cache");
                let mut batch = ComputePassBatch::begin(ctx.encoder, "parser.tree-records.batch");
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.tree_parent,
                    &bufs.tree_active_dispatch_args,
                )?;
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.tree_spans,
                    &bufs.tree_active_dispatch_args,
                )?;
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.tree_prev_sibling_clear,
                    &bufs.tree_active_dispatch_args,
                )?;
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.tree_prev_sibling_scatter,
                    &bufs.tree_active_dispatch_args,
                )?;
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.hir_nodes,
                    &bufs.tree_active_dispatch_args,
                )?;
            } else {
                self.passes
                    .tree_parent
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.tree_parent");
                self.passes
                    .tree_spans
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.tree_spans");
                self.passes
                    .tree_prev_sibling_clear
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.tree_prev_sibling_clear");
                self.passes
                    .tree_prev_sibling_scatter
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.tree_prev_sibling_scatter");
                self.passes
                    .hir_nodes
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_nodes");
            }
            self.passes.hir_semantic_prefix_local.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(
                    bufs.tree_n_node_blocks.saturating_mul(256),
                ),
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_prefix_local");
            self.passes.hir_semantic_prefix_blocks.record_scan(
                ctx.device,
                ctx.encoder,
                ctx.buffers,
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_prefix_blocks");
            self.passes.hir_semantic_compact_scatter.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(
                    bufs.tree_n_node_blocks.saturating_mul(256),
                ),
            )?;
            stamp_timer(
                timer_ref,
                ctx.encoder,
                "parser.hir_semantic_compact_scatter",
            );
            self.passes.hir_semantic_dispatch_args.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(1),
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_dispatch_args");
            self.passes
                .hir_semantic_subtree_end
                .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_subtree_end");
            self.passes.hir_semantic_parent_init.record_pass(
                &mut ctx,
                crate::gpu::passes_core::InputElements::Elements1D(bufs.tree_capacity),
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_parent_init");
            self.passes.hir_semantic_parent_step.record_steps(
                ctx.device,
                ctx.encoder,
                ctx.buffers,
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_parent_step");
            if parser_compute_pass_batching_enabled(timer_ref) {
                let bg_cache = ctx
                    .bg_cache
                    .as_deref_mut()
                    .expect("parser batching requires bind-group cache");
                let mut batch = ComputePassBatch::begin(ctx.encoder, "parser.semantic-nav.batch");
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.hir_semantic_parent_scatter,
                    &bufs.hir_semantic_dispatch_args,
                )?;
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.hir_semantic_nav,
                    &bufs.hir_semantic_dispatch_args,
                )?;
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.hir_semantic_depth_init,
                    &bufs.hir_semantic_dispatch_args,
                )?;
            } else {
                self.passes
                    .hir_semantic_parent_scatter
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_parent_scatter");
                self.passes
                    .hir_semantic_nav
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_nav");
                self.passes
                    .hir_semantic_depth_init
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_depth_init");
            }
            self.passes.hir_semantic_depth_step.record_steps_indirect(
                ctx.device,
                ctx.encoder,
                ctx.buffers,
                &bufs.hir_semantic_dispatch_args,
            )?;
            stamp_timer(timer_ref, ctx.encoder, "parser.hir_semantic_depth_step");
            if parser_compute_pass_batching_enabled(timer_ref) {
                let bg_cache = ctx
                    .bg_cache
                    .as_deref_mut()
                    .expect("parser batching requires bind-group cache");
                let mut batch =
                    ComputePassBatch::begin(ctx.encoder, "parser.semantic-child-index.batch");
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.hir_semantic_child_index_clear,
                    &bufs.hir_semantic_dispatch_args,
                )?;
                batch.record_pass_indirect_cached(
                    ctx.device,
                    ctx.buffers,
                    bg_cache,
                    &self.passes.hir_semantic_child_index_links,
                    &bufs.hir_semantic_dispatch_args,
                )?;
            } else {
                self.passes
                    .hir_semantic_child_index_clear
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_semantic_child_index_clear",
                );
                self.passes
                    .hir_semantic_child_index_links
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_semantic_child_index_links",
                );
            }
            self.passes
                .hir_semantic_child_index_rank_step
                .record_steps_indirect(
                    ctx.device,
                    ctx.encoder,
                    ctx.buffers,
                    &bufs.hir_semantic_dispatch_args,
                )?;
            stamp_timer(
                timer_ref,
                ctx.encoder,
                "parser.hir_semantic_child_index_rank_step",
            );
            if include_hir_spans {
                if parser_compute_pass_batching_enabled(timer_ref) {
                    let bg_cache = ctx
                        .bg_cache
                        .as_deref_mut()
                        .expect("parser batching requires bind-group cache");
                    let mut batch =
                        ComputePassBatch::begin(ctx.encoder, "parser.hir-type-records.batch");
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_record_clear_base,
                        &bufs.tree_active_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_record_clear_calls,
                        &bufs.tree_active_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_type_fields,
                        &bufs.tree_active_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_type_path_leaf_links,
                        &bufs.tree_active_dispatch_args,
                    )?;
                } else {
                    self.passes
                        .hir_record_clear_base
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_record_clear_base");
                    self.passes
                        .hir_record_clear_calls
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_record_clear_calls");
                    self.passes
                        .hir_type_fields
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_fields");
                    self.passes
                        .hir_type_path_leaf_links
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_path_leaf_links");
                }
                self.passes.hir_type_path_leaf_step.record_steps_indirect(
                    ctx.device,
                    ctx.encoder,
                    ctx.buffers,
                    &bufs.tree_active_dispatch_args,
                )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_path_leaf_step");
                ctx.encoder.clear_buffer(
                    &bufs.hir_type_path_leaf_link_b.buffer,
                    0,
                    Some(u64::from(bufs.tree_capacity) * 4),
                );
                if parser_compute_pass_batching_enabled(timer_ref) {
                    let bg_cache = ctx
                        .bg_cache
                        .as_deref_mut()
                        .expect("parser batching requires bind-group cache");
                    let mut batch =
                        ComputePassBatch::begin(ctx.encoder, "parser.hir-type-links.batch");
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_type_path_leaf_scatter,
                        &bufs.tree_active_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_spans,
                        &bufs.tree_active_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_type_arg_links,
                        &bufs.tree_active_dispatch_args,
                    )?;
                } else {
                    self.passes
                        .hir_type_path_leaf_scatter
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_path_leaf_scatter");
                    self.passes
                        .hir_spans
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_spans");
                    self.passes
                        .hir_type_arg_links
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_arg_links");
                }
                clear_type_arg_rank_b(ctx.encoder, bufs);
                self.passes
                    .hir_list_rank_prefix_local
                    .record_for_owner_link(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_type_fields_params,
                        &bufs.hir_type_arg_owner_a,
                        &bufs.hir_type_arg_link_a,
                    )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_type_arg_rank_prefix_local",
                );
                self.passes
                    .hir_semantic_prefix_blocks
                    .record_list_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_type_arg_rank_prefix_blocks",
                );
                self.passes
                    .hir_list_rank_compact_scatter
                    .record_for_params(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_type_fields_params,
                    )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_type_arg_rank_compact_scatter",
                );
                self.passes.hir_type_arg_rank_step.record_steps_indirect(
                    ctx.device,
                    ctx.encoder,
                    ctx.buffers,
                    &bufs.hir_list_rank_dispatch_args,
                )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_arg_rank_step");
                self.passes
                    .hir_type_arg_scatter
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_arg_scatter");
                if parser_compute_pass_batching_enabled(timer_ref) {
                    let bg_cache = ctx
                        .bg_cache
                        .as_deref_mut()
                        .expect("parser batching requires bind-group cache");
                    let mut batch =
                        ComputePassBatch::begin(ctx.encoder, "parser.hir-enum-links.batch");
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_enum_match_fields,
                        &bufs.tree_active_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_enum_variant_links,
                        &bufs.tree_active_dispatch_args,
                    )?;
                } else {
                    self.passes
                        .hir_enum_match_fields
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_enum_match_fields");
                    self.passes
                        .hir_enum_variant_links
                        .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_enum_variant_links");
                }
                self.passes.hir_enum_rank_prefix_local.record_pass(
                    &mut ctx,
                    crate::gpu::passes_core::InputElements::Elements1D(
                        bufs.tree_n_node_blocks.saturating_mul(256),
                    ),
                )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_enum_rank_prefix_local");
                self.passes
                    .hir_semantic_prefix_blocks
                    .record_enum_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_enum_rank_prefix_blocks");
                self.passes.hir_enum_rank_compact_scatter.record_pass(
                    &mut ctx,
                    crate::gpu::passes_core::InputElements::Elements1D(
                        bufs.tree_n_node_blocks.saturating_mul(256),
                    ),
                )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_enum_rank_compact_scatter",
                );
                self.passes
                    .hir_enum_variant_rank_step
                    .record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_enum_rank_dispatch_args,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_enum_variant_rank_step");
                self.passes
                    .hir_enum_variant_scatter
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_enum_variant_scatter");
                self.passes
                    .hir_item_fields
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_item_fields");
                self.passes
                    .hir_type_alias_owner_init
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_alias_owner_init");
                self.passes
                    .hir_type_alias_owner_step
                    .record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_semantic_dispatch_args,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_alias_owner_step");
                self.passes
                    .hir_type_alias_target
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_type_alias_target");
                self.passes
                    .hir_fn_signature_owner_init
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_fn_signature_owner_init");
                self.passes
                    .hir_fn_signature_owner_step
                    .record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.tree_active_dispatch_args,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_fn_signature_owner_step");
                self.passes
                    .hir_fn_return_type
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_fn_return_type");
                self.passes
                    .hir_param_links
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_param_links");
                self.passes
                    .hir_list_rank_prefix_local
                    .record_for_owner_link(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_param_fields_params,
                        &bufs.hir_param_owner_a,
                        &bufs.hir_param_link_a,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_param_rank_prefix_local");
                self.passes
                    .hir_semantic_prefix_blocks
                    .record_list_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_param_rank_prefix_blocks",
                );
                self.passes
                    .hir_list_rank_compact_scatter
                    .record_for_params(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_param_fields_params,
                    )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_param_rank_compact_scatter",
                );
                self.passes.hir_param_rank_step.record_steps_indirect(
                    ctx.device,
                    ctx.encoder,
                    ctx.buffers,
                    &bufs.hir_list_rank_dispatch_args,
                )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_param_rank_step");
                if parser_compute_pass_batching_enabled(timer_ref) {
                    let bg_cache = ctx
                        .bg_cache
                        .as_deref_mut()
                        .expect("parser batching requires bind-group cache");
                    let mut batch =
                        ComputePassBatch::begin(ctx.encoder, "parser.hir-core-fields.batch");
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_param_fields,
                        &bufs.hir_semantic_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_expr_fields,
                        &bufs.hir_semantic_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_member_fields,
                        &bufs.hir_semantic_dispatch_args,
                    )?;
                    batch.record_pass_indirect_cached(
                        ctx.device,
                        ctx.buffers,
                        bg_cache,
                        &self.passes.hir_stmt_fields,
                        &bufs.hir_semantic_dispatch_args,
                    )?;
                } else {
                    self.passes
                        .hir_param_fields
                        .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_param_fields");
                    self.passes
                        .hir_expr_fields
                        .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_expr_fields");
                    self.passes
                        .hir_member_fields
                        .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_member_fields");
                    self.passes
                        .hir_stmt_fields
                        .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_stmt_fields");
                }
                if let Some((source_len, token_buf, source_buf)) = literal_source {
                    self.passes.hir_literal_values.record_with_source(
                        &self.device,
                        ctx.encoder,
                        bufs,
                        &bufs.tree_active_dispatch_args,
                        source_len,
                        token_buf,
                        source_buf,
                    )?;
                    stamp_timer(timer_ref, ctx.encoder, "parser.hir_literal_values");
                }
                self.passes
                    .hir_call_fields
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_call_fields");
                self.passes
                    .hir_call_arg_links
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_call_arg_links");
                self.passes
                    .hir_list_rank_prefix_local
                    .record_for_owner_link(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_call_fields_params,
                        &bufs.hir_call_arg_owner_a,
                        &bufs.hir_call_arg_link_a,
                    )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_call_arg_rank_prefix_local",
                );
                self.passes
                    .hir_semantic_prefix_blocks
                    .record_list_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_call_arg_rank_prefix_blocks",
                );
                self.passes
                    .hir_list_rank_compact_scatter
                    .record_for_params(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_call_fields_params,
                    )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_call_arg_rank_compact_scatter",
                );
                self.passes
                    .hir_call_arg_ordinal_step
                    .record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_list_rank_dispatch_args,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_call_arg_ordinal_step");
                self.passes
                    .hir_call_arg_ordinal_scatter
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_call_arg_ordinal_scatter",
                );
                self.passes
                    .hir_array_fields
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_array_fields");
                self.passes
                    .hir_array_element_links
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_array_element_links");
                self.passes
                    .hir_list_rank_prefix_local
                    .record_for_owner_link(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_array_fields_params,
                        &bufs.hir_array_element_owner_a,
                        &bufs.hir_array_element_link_a,
                    )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_array_element_rank_prefix_local",
                );
                self.passes
                    .hir_semantic_prefix_blocks
                    .record_list_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_array_element_rank_prefix_blocks",
                );
                self.passes
                    .hir_list_rank_compact_scatter
                    .record_for_params(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_array_fields_params,
                    )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_array_element_rank_compact_scatter",
                );
                self.passes
                    .hir_array_element_rank_step
                    .record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_list_rank_dispatch_args,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_array_element_rank_step");
                self.passes
                    .hir_array_element_scatter
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_array_element_scatter");
                self.passes
                    .hir_match_arm_links
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_match_arm_links");
                self.passes.hir_match_rank_prefix_local.record_pass(
                    &mut ctx,
                    crate::gpu::passes_core::InputElements::Elements1D(
                        bufs.tree_n_node_blocks.saturating_mul(256),
                    ),
                )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_match_rank_prefix_local");
                self.passes
                    .hir_semantic_prefix_blocks
                    .record_match_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_match_rank_prefix_blocks",
                );
                self.passes.hir_match_rank_compact_scatter.record_pass(
                    &mut ctx,
                    crate::gpu::passes_core::InputElements::Elements1D(
                        bufs.tree_n_node_blocks.saturating_mul(256),
                    ),
                )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_match_rank_compact_scatter",
                );
                self.passes.hir_match_arm_rank_step.record_steps_indirect(
                    ctx.device,
                    ctx.encoder,
                    ctx.buffers,
                    &bufs.hir_match_rank_dispatch_args,
                )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_match_arm_rank_step");
                self.passes
                    .hir_match_arm_scatter
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_match_arm_scatter");
                self.passes
                    .hir_struct_fields
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_struct_fields");
                self.passes
                    .hir_struct_field_links
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_struct_field_links");
                self.passes.hir_struct_rank_prefix_local.record_pass(
                    &mut ctx,
                    crate::gpu::passes_core::InputElements::Elements1D(
                        bufs.tree_n_node_blocks.saturating_mul(256),
                    ),
                )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_struct_rank_prefix_local",
                );
                self.passes
                    .hir_semantic_prefix_blocks
                    .record_struct_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_struct_rank_prefix_blocks",
                );
                self.passes.hir_struct_rank_compact_scatter.record_pass(
                    &mut ctx,
                    crate::gpu::passes_core::InputElements::Elements1D(
                        bufs.tree_n_node_blocks.saturating_mul(256),
                    ),
                )?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_struct_rank_compact_scatter",
                );
                self.passes
                    .hir_struct_field_rank_step
                    .record_steps_indirect(
                        ctx.device,
                        ctx.encoder,
                        ctx.buffers,
                        &bufs.hir_struct_rank_dispatch_args,
                    )?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_struct_field_rank_step");
                self.passes
                    .tree_prev_sibling_clear
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(
                    timer_ref,
                    ctx.encoder,
                    "parser.hir_struct_lit_field_next_clear",
                );
                self.passes
                    .hir_struct_field_scatter
                    .record_pass_indirect(&mut ctx, &bufs.tree_active_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_struct_field_scatter");
                self.passes
                    .hir_item_decl_tokens
                    .record_pass_indirect(&mut ctx, &bufs.hir_semantic_dispatch_args)?;
                stamp_timer(timer_ref, ctx.encoder, "parser.hir_item_decl_tokens");
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
        self.resident_buffers_for_with_tree_capacity_and_debug(
            slot,
            token_capacity,
            tables,
            None,
            false,
        )
    }

    fn resident_debug_buffers_for<'a>(
        &self,
        slot: &'a mut Option<ResidentParserBufferCache>,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
    ) -> &'a ParserBuffers {
        self.resident_buffers_for_with_tree_capacity_and_debug(
            slot,
            token_capacity,
            tables,
            None,
            true,
        )
    }

    fn resident_buffers_for_with_tree_capacity<'a>(
        &self,
        slot: &'a mut Option<ResidentParserBufferCache>,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
    ) -> &'a ParserBuffers {
        self.resident_buffers_for_with_tree_capacity_and_debug(
            slot,
            token_capacity,
            tables,
            tree_capacity_override,
            false,
        )
    }

    fn resident_buffers_for_with_tree_capacity_and_debug<'a>(
        &self,
        slot: &'a mut Option<ResidentParserBufferCache>,
        token_capacity: u32,
        tables: &PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
        retain_debug_hir_buffers: bool,
    ) -> &'a ParserBuffers {
        let fingerprint = table_fingerprint(tables);
        let wanted_capacity = token_capacity.max(1);
        let needs_allocate = slot.as_ref().is_none_or(|cached| {
            cached.table_fingerprint != fingerprint
                || cached.token_capacity != wanted_capacity
                || cached.retain_debug_hir_buffers != retain_debug_hir_buffers
                || match (cached.tree_capacity_override, tree_capacity_override) {
                    (None, None) => false,
                    (Some(_), None) | (None, Some(_)) => true,
                    (Some(_), Some(wanted_tree_capacity)) => {
                        cached.buffers.tree_capacity != wanted_tree_capacity.max(1)
                    }
                }
        });

        if needs_allocate {
            *slot = None;
            self.bg_cache
                .lock()
                .expect("parser.bg_cache poisoned")
                .clear();
            *self
                .resident_token_kind_bind_groups
                .lock()
                .expect("parser.resident_token_kind_bind_groups poisoned") = None;
            let _ = self.device.poll(wgpu::PollType::wait_indefinitely());

            // Resident parser buffers dominate VRAM because tree/HIR scratch scales
            // from token capacity. Allocate the exact required capacity instead of
            // doubling across increasing benchmark sizes.
            let allocated_capacity = wanted_capacity;
            let action_table_bytes = tables.to_action_header_grid_bytes();
            *slot = Some(ResidentParserBufferCache {
                token_capacity: allocated_capacity,
                tree_capacity_override,
                table_fingerprint: fingerprint,
                retain_debug_hir_buffers,
                buffers: ParserBuffers::new_resident_capacity_with_tree_capacity_and_debug(
                    &self.device,
                    wanted_capacity,
                    tables.n_kinds,
                    &action_table_bytes,
                    tables,
                    tree_capacity_override,
                    retain_debug_hir_buffers,
                ),
            });
            self.bg_cache
                .lock()
                .expect("parser.bg_cache poisoned")
                .clear();
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
