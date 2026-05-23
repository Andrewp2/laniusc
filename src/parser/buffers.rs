// src/parser/buffers.rs
use encase::ShaderType;

mod scans;
use scans::*;

use crate::gpu::buffers::{
    LaniusBuffer,
    storage_ro_from_bytes,
    storage_ro_from_u32s,
    storage_rw_for_array,
    uniform_from_val,
};

// The seed planner is transitional and still replays from the stream start per
// block. Use coarse fixed blocks to reduce replay count while keeping each
// block's sequential seeded parse bounded.
const LL1_BLOCK_SIZE: u32 = 8192;
const LL1_BLOCK_STACK_CAPACITY: u32 = 2048;
const LL1_BLOCK_EMIT_STRIDE: u32 = 65_536;

fn parser_table_uses_ll1_tree_stream(
    tables: &crate::parser::tables::PrecomputedParseTables,
) -> bool {
    // The live parser follows Pareas/the Parallel LL paper: adjacent token-pair
    // table extraction plus prefix packing and bracket validation. The LL(1)
    // tables remain useful for tests and grammar diagnostics, but the seeded
    // LL(1) replay path is not the production tree stream.
    let _ = tables;
    false
}

fn legacy_pair_capacity_for(tree_stream_uses_ll1: bool, n_pairs: usize) -> usize {
    if tree_stream_uses_ll1 {
        1
    } else {
        n_pairs.max(1)
    }
}

fn alias_storage_buffer<T, U>(source: &LaniusBuffer<T>, count: usize) -> LaniusBuffer<U> {
    LaniusBuffer::new((source.buffer.clone(), source.byte_size as u64), count)
}

fn dispatch_args_buffer(device: &wgpu::Device, label: &str) -> LaniusBuffer<u32> {
    LaniusBuffer::new(
        (
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: 12,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::INDIRECT
                    | wgpu::BufferUsages::COPY_DST
                    | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            }),
            12,
        ),
        3,
    )
}

pub(crate) fn resident_projected_tree_capacity_for_tables(
    n_tokens: u32,
    tables: &crate::parser::tables::PrecomputedParseTables,
) -> u32 {
    let n_pairs = n_tokens.saturating_sub(1);
    let max_emit_len = tables.pp_len.iter().copied().max().unwrap_or(0);
    let total_emit = n_pairs.saturating_mul(max_emit_len);
    resident_projected_tree_capacity(n_tokens, total_emit)
}

fn resident_projected_tree_capacity(_n_tokens: u32, total_emit: u32) -> u32 {
    total_emit.max(1)
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType, Default)]
pub struct ActionHeader {
    pub push_len: u32,
    pub emit_len: u32,
    pub pop_tag: u32,
    pub pop_count: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct TokenDelimiterParams {
    pub n_tokens: u32,
    pub n_blocks: u32,
    pub scan_step: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct TokenBraceMatchParams {
    pub n_tokens: u32,
}

/// All GPU-side buffers for the parser pipeline (no readbacks/staging here).
pub struct ParserBuffers {
    // sizes
    pub n_tokens: u32,
    pub n_kinds: u32,
    pub total_sc: u32,
    pub total_emit: u32,
    pub tree_stream_uses_ll1: bool,
    pub tree_count_uses_status: bool,
    pub tree_capacity: u32,

    // canonical LL(1) outputs flattened from seeded block parsing
    pub ll1_predict: LaniusBuffer<u32>,
    pub ll1_prod_rhs_off: LaniusBuffer<u32>,
    pub ll1_prod_rhs_len: LaniusBuffer<u32>,
    pub ll1_prod_rhs: LaniusBuffer<u32>,
    pub ll1_emit: LaniusBuffer<u32>,
    pub ll1_emit_pos: LaniusBuffer<u32>,
    pub ll1_status: LaniusBuffer<u32>,

    // block-local LL(1) production summaries
    pub ll1_block_size: u32,
    pub ll1_n_blocks: u32,
    pub ll1_block_emit_stride: u32,
    pub ll1_params_base: super::passes::ll1_blocks_01::LL1BlocksParams,
    pub params_ll1_blocks: LaniusBuffer<super::passes::ll1_blocks_01::LL1BlocksParams>,
    pub ll1_block_seed_len: LaniusBuffer<u32>,
    pub ll1_block_seed_stack: LaniusBuffer<u32>,
    pub ll1_seed_plan_status: LaniusBuffer<u32>,
    pub ll1_seeded_status: LaniusBuffer<u32>,
    pub ll1_seeded_emit: LaniusBuffer<u32>,
    pub ll1_seeded_emit_pos: LaniusBuffer<u32>,
    pub ll1_emit_prefix_a: LaniusBuffer<u32>,
    pub ll1_emit_prefix_b: LaniusBuffer<u32>,
    pub ll1_status_summary_a: LaniusBuffer<u32>,
    pub ll1_status_summary_b: LaniusBuffer<u32>,
    pub ll1_emit_prefix_scan_steps: Vec<LL1EmitPrefixScanStep>,

    // pair→header
    pub params_llp: LaniusBuffer<super::passes::llp_pairs::LLPParams>,
    pub semantic_token_kinds: LaniusBuffer<u32>,
    pub token_delimiter_params: LaniusBuffer<TokenDelimiterParams>,
    pub token_delimiter_scan_steps: Vec<TokenDelimiterScanStep>,
    pub token_input_capacity: u32,
    pub token_delimiter_n_blocks: u32,
    pub token_depth_brace_inblock: LaniusBuffer<i32>,
    pub token_depth_bracket_inblock: LaniusBuffer<i32>,
    pub token_block_sum_brace: LaniusBuffer<i32>,
    pub token_block_sum_bracket: LaniusBuffer<i32>,
    pub token_prefix_brace_a: LaniusBuffer<i32>,
    pub token_prefix_brace_b: LaniusBuffer<i32>,
    pub token_block_prefix_brace: LaniusBuffer<i32>,
    pub token_prefix_bracket_a: LaniusBuffer<i32>,
    pub token_prefix_bracket_b: LaniusBuffer<i32>,
    pub token_block_prefix_bracket: LaniusBuffer<i32>,
    pub token_top_brace_owner_block: LaniusBuffer<u32>,
    pub token_top_brace_owner_prefix_a: LaniusBuffer<u32>,
    pub token_top_brace_owner_prefix_b: LaniusBuffer<u32>,
    pub token_top_brace_owner_block_prefix: LaniusBuffer<u32>,
    pub token_statement_event_block: LaniusBuffer<u32>,
    pub token_statement_event_prefix_a: LaniusBuffer<u32>,
    pub token_statement_event_prefix_b: LaniusBuffer<u32>,
    pub token_statement_event_block_prefix: LaniusBuffer<u32>,
    pub token_brace_semantic_kind: LaniusBuffer<u32>,
    pub token_bracket_semantic_kind: LaniusBuffer<u32>,
    pub token_statement_context_kind: LaniusBuffer<u32>,
    // Delimiter-pair scratch reused by brace and bracket PSE matching passes.
    pub token_brace_match_params: LaniusBuffer<TokenBraceMatchParams>,
    pub token_brace_match_depth: LaniusBuffer<i32>,
    pub token_brace_match_block_min: LaniusBuffer<i32>,
    pub token_brace_match_min_tree_base: u32,
    pub token_brace_match_min_tree: LaniusBuffer<i32>,
    pub token_brace_match_min_tree_steps: Vec<TreePrefixMaxBuildStep>,
    pub token_feature_flags: LaniusBuffer<u32>,
    pub token_count: LaniusBuffer<u32>,
    pub default_token_file_id: LaniusBuffer<u32>,
    pub active_pair_thread_dispatch_args: LaniusBuffer<u32>,
    pub active_pair_group_dispatch_args: LaniusBuffer<u32>,
    pub action_table: LaniusBuffer<u8>,
    pub out_headers: LaniusBuffer<ActionHeader>,

    // pack varlen
    pub params_pack: LaniusBuffer<super::passes::pack_varlen::PackParams>,
    pub sc_offsets: LaniusBuffer<u32>,
    pub emit_offsets: LaniusBuffer<u32>,
    pub pack_sc_prefix_a: LaniusBuffer<u32>,
    pub pack_sc_prefix_b: LaniusBuffer<u32>,
    pub pack_emit_prefix_a: LaniusBuffer<u32>,
    pub pack_emit_prefix_b: LaniusBuffer<u32>,
    pub pack_offset_scan_steps: Vec<PackOffsetScanStep>,
    pub pack_total_reduce_steps: Vec<PackTotalReduceStep>,
    pub projected_status: LaniusBuffer<u32>,
    pub tables_blob: LaniusBuffer<u32>,
    pub out_sc: LaniusBuffer<u32>,
    pub out_emit: LaniusBuffer<u32>,
    pub out_emit_pos: LaniusBuffer<u32>,

    // -------- Brackets (parallel) --------
    pub b01_params: LaniusBuffer<super::passes::brackets_01::Params>,
    pub b02_params: LaniusBuffer<super::passes::brackets_02::Params>,
    pub b02_scan_steps: Vec<BracketsBlockPrefixScanStep>,
    pub b03_params: LaniusBuffer<super::passes::brackets_03::Params>,
    pub b04_params: LaniusBuffer<super::passes::brackets_04::Params>,
    pub b05_params: LaniusBuffer<super::passes::brackets_05::Params>,
    pub b06_params: LaniusBuffer<super::passes::brackets_06::Params>,
    pub b07_params: LaniusBuffer<super::passes::brackets_pse_04::Params>, // PSE-style pair-by-layer
    pub b05_scan_steps: Vec<BracketsHistogramScanStep>,

    pub b_exscan_inblock: LaniusBuffer<i32>,
    pub b_block_sum: LaniusBuffer<i32>,
    pub b_block_minpref: LaniusBuffer<i32>,
    pub b_block_maxdepth: LaniusBuffer<i32>,
    pub b_block_prefix: LaniusBuffer<i32>,
    pub b_block_prefix_sum_a: LaniusBuffer<i32>,
    pub b_block_prefix_sum_b: LaniusBuffer<i32>,
    pub b_block_prefix_min_a: LaniusBuffer<i32>,
    pub b_block_prefix_min_b: LaniusBuffer<i32>,

    pub depths_out: LaniusBuffer<i32>, // [final, min]
    pub valid_out: LaniusBuffer<u32>,

    pub b_depth_exscan: LaniusBuffer<i32>,
    pub b_layer: LaniusBuffer<u32>,

    pub b_hist_push: LaniusBuffer<u32>,
    pub b_hist_pop: LaniusBuffer<u32>,
    pub b_off_push: LaniusBuffer<u32>,
    pub b_off_pop: LaniusBuffer<u32>,
    pub b_cur_push: LaniusBuffer<u32>,
    pub b_cur_pop: LaniusBuffer<u32>,
    pub b_pushes_by_layer: LaniusBuffer<u32>,
    pub b_pops_by_layer: LaniusBuffer<u32>,
    pub b_slot_for_index: LaniusBuffer<u32>,
    pub match_for_index: LaniusBuffer<u32>,

    // counts used at dispatch
    pub b_n_blocks: u32,
    pub b_n_layers: u32,

    // -------- Tree parent recovery --------
    pub tree_prefix_params: LaniusBuffer<super::passes::tree_prefix_01::Params>,
    pub tree_prefix_scan_steps: Vec<TreePrefixScanStep>,
    pub tree_n_node_blocks: u32,
    pub tree_n_prefix_blocks: u32,
    pub tree_active_dispatch_args: LaniusBuffer<u32>,
    pub tree_enum_dispatch_args: LaniusBuffer<u32>,
    pub tree_match_dispatch_args: LaniusBuffer<u32>,
    pub tree_struct_dispatch_args: LaniusBuffer<u32>,
    pub hir_semantic_dispatch_args: LaniusBuffer<u32>,
    pub tree_prefix_inblock: LaniusBuffer<i32>,
    pub tree_block_sum: LaniusBuffer<i32>,
    pub tree_block_prefix_a: LaniusBuffer<i32>,
    pub tree_block_prefix_b: LaniusBuffer<i32>,
    pub tree_block_prefix: LaniusBuffer<i32>,
    pub tree_prefix: LaniusBuffer<i32>,
    pub tree_prefix_block_max: LaniusBuffer<i32>,
    pub tree_prefix_block_max_tree_base: u32,
    pub tree_prefix_block_max_tree: LaniusBuffer<i32>,
    pub tree_prefix_max_build_steps: Vec<TreePrefixMaxBuildStep>,
    pub tree_params: LaniusBuffer<super::passes::tree_parent::Params>,
    pub tree_span_params: LaniusBuffer<super::passes::tree_spans::Params>,
    pub tree_prev_sibling_params: LaniusBuffer<super::passes::tree_prev_sibling_clear::Params>,
    pub prod_arity: LaniusBuffer<u32>,
    pub node_kind: LaniusBuffer<u32>,
    pub parent: LaniusBuffer<u32>,
    pub first_child: LaniusBuffer<u32>,
    pub next_sibling: LaniusBuffer<u32>,
    pub prev_sibling: LaniusBuffer<u32>,
    pub subtree_end: LaniusBuffer<u32>,

    // -------- HIR-facing classification --------
    pub hir_params: LaniusBuffer<super::passes::hir_nodes::Params>,
    pub hir_span_params: LaniusBuffer<super::passes::hir_spans::Params>,
    pub hir_type_fields_params: LaniusBuffer<super::passes::hir_type_fields::Params>,
    pub hir_item_fields_params: LaniusBuffer<super::passes::hir_item_fields::Params>,
    pub hir_param_fields_params: LaniusBuffer<super::passes::hir_param_fields::Params>,
    pub hir_expr_fields_params: LaniusBuffer<super::passes::hir_expr_fields::Params>,
    pub hir_member_fields_params: LaniusBuffer<super::passes::hir_member_fields::Params>,
    pub hir_stmt_fields_params: LaniusBuffer<super::passes::hir_stmt_fields::Params>,
    pub hir_call_fields_params: LaniusBuffer<super::passes::hir_call_fields::Params>,
    pub hir_array_fields_params: LaniusBuffer<super::passes::hir_array_fields::Params>,
    pub hir_enum_match_fields_params: LaniusBuffer<super::passes::hir_enum_match_fields::Params>,
    pub hir_struct_fields_params: LaniusBuffer<super::passes::hir_struct_fields::Params>,
    pub hir_kind: LaniusBuffer<u32>,
    pub hir_semantic_block_count: LaniusBuffer<u32>,
    pub hir_semantic_prefix_scan_steps: Vec<HirSemanticPrefixScanStep>,
    pub hir_semantic_flag: LaniusBuffer<u32>,
    pub hir_semantic_local_prefix: LaniusBuffer<u32>,
    pub hir_semantic_block_prefix_a: LaniusBuffer<u32>,
    pub hir_semantic_block_prefix_b: LaniusBuffer<u32>,
    pub hir_node_dense_id: LaniusBuffer<u32>,
    pub hir_semantic_prefix_before_node: LaniusBuffer<u32>,
    pub hir_semantic_dense_node: LaniusBuffer<u32>,
    pub hir_semantic_subtree_end: LaniusBuffer<u32>,
    pub hir_semantic_parent: LaniusBuffer<u32>,
    pub hir_semantic_first_child: LaniusBuffer<u32>,
    pub hir_semantic_next_sibling: LaniusBuffer<u32>,
    pub hir_semantic_depth: LaniusBuffer<u32>,
    pub hir_semantic_child_index: LaniusBuffer<u32>,
    pub hir_semantic_parent_link_a: LaniusBuffer<u32>,
    pub hir_semantic_parent_link_b: LaniusBuffer<u32>,
    pub hir_semantic_parent_value_a: LaniusBuffer<u32>,
    pub hir_semantic_parent_value_b: LaniusBuffer<u32>,
    pub hir_semantic_depth_link_a: LaniusBuffer<u32>,
    pub hir_semantic_depth_link_b: LaniusBuffer<u32>,
    pub hir_semantic_depth_value_a: LaniusBuffer<u32>,
    pub hir_semantic_depth_value_b: LaniusBuffer<u32>,
    pub hir_semantic_child_index_link_a: LaniusBuffer<u32>,
    pub hir_semantic_child_index_link_b: LaniusBuffer<u32>,
    pub hir_semantic_child_index_rank_a: LaniusBuffer<u32>,
    pub hir_semantic_child_index_rank_b: LaniusBuffer<u32>,
    pub hir_semantic_count: LaniusBuffer<u32>,
    pub hir_token_pos: LaniusBuffer<u32>,
    pub hir_token_end: LaniusBuffer<u32>,
    pub hir_token_file_id: LaniusBuffer<u32>,
    pub hir_type_form: LaniusBuffer<u32>,
    pub hir_type_value_node: LaniusBuffer<u32>,
    pub hir_type_len_token: LaniusBuffer<u32>,
    pub hir_type_len_value: LaniusBuffer<u32>,
    pub hir_type_file_id: LaniusBuffer<u32>,
    pub hir_type_path_leaf_node: LaniusBuffer<u32>,
    pub hir_type_path_leaf_link_a: LaniusBuffer<u32>,
    pub hir_type_path_leaf_link_b: LaniusBuffer<u32>,
    pub hir_type_path_leaf_value_a: LaniusBuffer<u32>,
    pub hir_type_path_leaf_value_b: LaniusBuffer<u32>,
    pub hir_type_arg_start: LaniusBuffer<u32>,
    pub hir_type_arg_count: LaniusBuffer<u32>,
    pub hir_type_arg_next: LaniusBuffer<u32>,
    pub hir_type_alias_target_node: LaniusBuffer<u32>,
    pub hir_fn_return_type_node: LaniusBuffer<u32>,
    pub hir_fn_signature_owner_link_a: LaniusBuffer<u32>,
    pub hir_fn_signature_owner_link_b: LaniusBuffer<u32>,
    pub hir_fn_signature_return_owner_a: LaniusBuffer<u32>,
    pub hir_fn_signature_return_owner_b: LaniusBuffer<u32>,
    pub hir_fn_signature_function_owner_a: LaniusBuffer<u32>,
    pub hir_fn_signature_function_owner_b: LaniusBuffer<u32>,
    pub hir_type_arg_owner_a: LaniusBuffer<u32>,
    pub hir_type_arg_owner_b: LaniusBuffer<u32>,
    pub hir_type_arg_link_a: LaniusBuffer<u32>,
    pub hir_type_arg_link_b: LaniusBuffer<u32>,
    pub hir_type_arg_rank_a: LaniusBuffer<u32>,
    pub hir_type_arg_rank_b: LaniusBuffer<u32>,
    pub hir_type_arg_previous: LaniusBuffer<u32>,
    pub hir_type_alias_owner_link_a: LaniusBuffer<u32>,
    pub hir_type_alias_owner_link_b: LaniusBuffer<u32>,
    pub hir_type_alias_owner_value_a: LaniusBuffer<u32>,
    pub hir_type_alias_owner_value_b: LaniusBuffer<u32>,
    pub hir_item_kind: LaniusBuffer<u32>,
    pub hir_item_name_token: LaniusBuffer<u32>,
    pub hir_item_decl_token: LaniusBuffer<u32>,
    pub hir_item_namespace: LaniusBuffer<u32>,
    pub hir_item_visibility: LaniusBuffer<u32>,
    pub hir_item_path_start: LaniusBuffer<u32>,
    pub hir_item_path_end: LaniusBuffer<u32>,
    pub hir_item_file_id: LaniusBuffer<u32>,
    pub hir_item_import_target_kind: LaniusBuffer<u32>,
    pub hir_param_record: LaniusBuffer<u32>,
    pub hir_param_owner_a: LaniusBuffer<u32>,
    pub hir_param_owner_b: LaniusBuffer<u32>,
    pub hir_param_link_a: LaniusBuffer<u32>,
    pub hir_param_link_b: LaniusBuffer<u32>,
    pub hir_param_rank_a: LaniusBuffer<u32>,
    pub hir_param_rank_b: LaniusBuffer<u32>,
    pub hir_param_previous: LaniusBuffer<u32>,
    pub hir_variant_parent_enum: LaniusBuffer<u32>,
    pub hir_variant_ordinal: LaniusBuffer<u32>,
    pub hir_variant_payload_start: LaniusBuffer<u32>,
    pub hir_variant_payload_count: LaniusBuffer<u32>,
    pub hir_variant_owner_a: LaniusBuffer<u32>,
    pub hir_variant_owner_b: LaniusBuffer<u32>,
    pub hir_variant_link_a: LaniusBuffer<u32>,
    pub hir_variant_link_b: LaniusBuffer<u32>,
    pub hir_variant_rank_a: LaniusBuffer<u32>,
    pub hir_variant_rank_b: LaniusBuffer<u32>,
    pub hir_variant_payload_owner_a: LaniusBuffer<u32>,
    pub hir_variant_payload_owner_b: LaniusBuffer<u32>,
    pub hir_variant_payload_link_a: LaniusBuffer<u32>,
    pub hir_variant_payload_link_b: LaniusBuffer<u32>,
    pub hir_variant_payload_rank_a: LaniusBuffer<u32>,
    pub hir_variant_payload_rank_b: LaniusBuffer<u32>,
    pub hir_list_rank_flag: LaniusBuffer<u32>,
    pub hir_list_rank_local_prefix: LaniusBuffer<u32>,
    pub hir_list_rank_block_sum: LaniusBuffer<u32>,
    pub hir_list_rank_block_prefix_a: LaniusBuffer<u32>,
    pub hir_list_rank_block_prefix_b: LaniusBuffer<u32>,
    pub hir_list_rank_node: LaniusBuffer<u32>,
    pub hir_list_rank_count: LaniusBuffer<u32>,
    pub hir_list_rank_dispatch_args: LaniusBuffer<u32>,
    pub hir_enum_rank_flag: LaniusBuffer<u32>,
    pub hir_enum_rank_local_prefix: LaniusBuffer<u32>,
    pub hir_enum_rank_block_sum: LaniusBuffer<u32>,
    pub hir_enum_rank_block_prefix_a: LaniusBuffer<u32>,
    pub hir_enum_rank_block_prefix_b: LaniusBuffer<u32>,
    pub hir_enum_rank_node: LaniusBuffer<u32>,
    pub hir_enum_rank_count: LaniusBuffer<u32>,
    pub hir_enum_rank_dispatch_args: LaniusBuffer<u32>,
    pub hir_match_scrutinee_node: LaniusBuffer<u32>,
    pub hir_match_arm_start: LaniusBuffer<u32>,
    pub hir_match_arm_count: LaniusBuffer<u32>,
    pub hir_match_arm_next: LaniusBuffer<u32>,
    pub hir_match_arm_pattern_node: LaniusBuffer<u32>,
    pub hir_match_arm_payload_start: LaniusBuffer<u32>,
    pub hir_match_arm_payload_count: LaniusBuffer<u32>,
    pub hir_match_arm_result_node: LaniusBuffer<u32>,
    pub hir_match_payload_owner_arm: LaniusBuffer<u32>,
    pub hir_match_payload_match_node: LaniusBuffer<u32>,
    pub hir_match_payload_ordinal: LaniusBuffer<u32>,
    pub hir_match_arm_owner_a: LaniusBuffer<u32>,
    pub hir_match_arm_owner_b: LaniusBuffer<u32>,
    pub hir_match_arm_link_a: LaniusBuffer<u32>,
    pub hir_match_arm_link_b: LaniusBuffer<u32>,
    pub hir_match_arm_rank_a: LaniusBuffer<u32>,
    pub hir_match_arm_rank_b: LaniusBuffer<u32>,
    pub hir_match_arm_previous: LaniusBuffer<u32>,
    pub hir_match_payload_owner_a: LaniusBuffer<u32>,
    pub hir_match_payload_owner_b: LaniusBuffer<u32>,
    pub hir_match_payload_link_a: LaniusBuffer<u32>,
    pub hir_match_payload_link_b: LaniusBuffer<u32>,
    pub hir_match_payload_rank_a: LaniusBuffer<u32>,
    pub hir_match_payload_rank_b: LaniusBuffer<u32>,
    pub hir_match_rank_flag: LaniusBuffer<u32>,
    pub hir_match_rank_local_prefix: LaniusBuffer<u32>,
    pub hir_match_rank_block_sum: LaniusBuffer<u32>,
    pub hir_match_rank_block_prefix_a: LaniusBuffer<u32>,
    pub hir_match_rank_block_prefix_b: LaniusBuffer<u32>,
    pub hir_match_rank_node: LaniusBuffer<u32>,
    pub hir_match_rank_count: LaniusBuffer<u32>,
    pub hir_match_rank_dispatch_args: LaniusBuffer<u32>,
    pub hir_call_callee_node: LaniusBuffer<u32>,
    pub hir_call_arg_start: LaniusBuffer<u32>,
    pub hir_call_arg_end: LaniusBuffer<u32>,
    pub hir_call_arg_count: LaniusBuffer<u32>,
    // Packed `parent_call_node | ordinal << 28` call-argument record. The
    // legacy `hir_call_arg_ordinal` view aliases this storage so older host
    // readback APIs can decode parent and ordinal separately without keeping a
    // second tree-capacity GPU buffer.
    pub hir_call_arg_parent_call: LaniusBuffer<u32>,
    pub hir_call_arg_ordinal: LaniusBuffer<u32>,
    pub hir_call_arg_owner_a: LaniusBuffer<u32>,
    pub hir_call_arg_owner_b: LaniusBuffer<u32>,
    pub hir_call_arg_link_a: LaniusBuffer<u32>,
    pub hir_call_arg_link_b: LaniusBuffer<u32>,
    pub hir_call_arg_rank_a: LaniusBuffer<u32>,
    pub hir_call_arg_rank_b: LaniusBuffer<u32>,
    pub hir_array_lit_first_element: LaniusBuffer<u32>,
    pub hir_array_lit_element_count: LaniusBuffer<u32>,
    pub hir_array_element_parent_lit: LaniusBuffer<u32>,
    pub hir_array_element_ordinal: LaniusBuffer<u32>,
    pub hir_array_element_next: LaniusBuffer<u32>,
    pub hir_array_element_owner_a: LaniusBuffer<u32>,
    pub hir_array_element_owner_b: LaniusBuffer<u32>,
    pub hir_array_element_link_a: LaniusBuffer<u32>,
    pub hir_array_element_link_b: LaniusBuffer<u32>,
    pub hir_array_element_rank_a: LaniusBuffer<u32>,
    pub hir_array_element_rank_b: LaniusBuffer<u32>,
    pub hir_array_element_previous: LaniusBuffer<u32>,
    // Compatibility-sized dummies. `hir_expr_record` is the authoritative
    // expression metadata buffer; these are kept at one word until older
    // host-facing debug surfaces are fully removed.
    pub hir_expr_form: LaniusBuffer<u32>,
    pub hir_expr_left_node: LaniusBuffer<u32>,
    pub hir_expr_right_node: LaniusBuffer<u32>,
    pub hir_expr_value_token: LaniusBuffer<u32>,
    pub hir_expr_record: LaniusBuffer<u32>,
    pub hir_expr_int_value: LaniusBuffer<u32>,
    pub hir_member_receiver_node: LaniusBuffer<u32>,
    pub hir_member_receiver_token: LaniusBuffer<u32>,
    pub hir_member_name_token: LaniusBuffer<u32>,
    pub hir_stmt_record: LaniusBuffer<u32>,
    pub hir_struct_field_parent_struct: LaniusBuffer<u32>,
    pub hir_struct_field_ordinal: LaniusBuffer<u32>,
    pub hir_struct_field_type_node: LaniusBuffer<u32>,
    pub hir_struct_decl_field_start: LaniusBuffer<u32>,
    pub hir_struct_decl_field_count: LaniusBuffer<u32>,
    pub hir_struct_lit_head_node: LaniusBuffer<u32>,
    pub hir_struct_lit_field_start: LaniusBuffer<u32>,
    pub hir_struct_lit_field_count: LaniusBuffer<u32>,
    pub hir_struct_lit_field_parent_lit: LaniusBuffer<u32>,
    pub hir_struct_lit_field_value_node: LaniusBuffer<u32>,
    pub hir_struct_lit_field_next: LaniusBuffer<u32>,
    pub hir_struct_field_owner_a: LaniusBuffer<u32>,
    pub hir_struct_field_owner_b: LaniusBuffer<u32>,
    pub hir_struct_field_link_a: LaniusBuffer<u32>,
    pub hir_struct_field_link_b: LaniusBuffer<u32>,
    pub hir_struct_field_rank_a: LaniusBuffer<u32>,
    pub hir_struct_field_rank_b: LaniusBuffer<u32>,
    pub hir_struct_lit_field_owner_a: LaniusBuffer<u32>,
    pub hir_struct_lit_field_owner_b: LaniusBuffer<u32>,
    pub hir_struct_lit_field_link_a: LaniusBuffer<u32>,
    pub hir_struct_lit_field_link_b: LaniusBuffer<u32>,
    pub hir_struct_lit_field_rank_a: LaniusBuffer<u32>,
    pub hir_struct_lit_field_rank_b: LaniusBuffer<u32>,
    pub hir_struct_lit_field_previous: LaniusBuffer<u32>,
    pub hir_struct_rank_flag: LaniusBuffer<u32>,
    pub hir_struct_rank_local_prefix: LaniusBuffer<u32>,
    pub hir_struct_rank_block_sum: LaniusBuffer<u32>,
    pub hir_struct_rank_block_prefix_a: LaniusBuffer<u32>,
    pub hir_struct_rank_block_prefix_b: LaniusBuffer<u32>,
    pub hir_struct_rank_node: LaniusBuffer<u32>,
    pub hir_struct_rank_count: LaniusBuffer<u32>,
    pub hir_struct_rank_dispatch_args: LaniusBuffer<u32>,
}

pub struct LL1EmitPrefixScanStep {
    pub params: LaniusBuffer<super::passes::ll1_blocks_01::LL1BlocksParams>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct PackOffsetScanStep {
    pub params: LaniusBuffer<super::passes::pack_offsets::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct PackTotalReduceStep {
    pub params: LaniusBuffer<super::passes::pack_totals_reduce::Params>,
    pub item_count: u32,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct TokenDelimiterScanStep {
    pub params: LaniusBuffer<TokenDelimiterParams>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct HirSemanticPrefixScanStep {
    pub params: LaniusBuffer<super::passes::hir_semantic_prefix_blocks::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

impl ParserBuffers {
    pub fn new(
        device: &wgpu::Device,
        token_kinds_u32: &[u32],
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
    ) -> Self {
        Self::new_with_sizing(
            device,
            token_kinds_u32.len() as u32,
            Some(token_kinds_u32),
            n_kinds,
            action_table_bytes,
            tables,
            false,
            false,
            true,
            None,
        )
    }

    pub fn new_resident_capacity(
        device: &wgpu::Device,
        token_capacity: u32,
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
    ) -> Self {
        Self::new_resident_capacity_with_tree_capacity(
            device,
            token_capacity,
            n_kinds,
            action_table_bytes,
            tables,
            None,
        )
    }

    pub fn new_resident_capacity_with_tree_capacity(
        device: &wgpu::Device,
        token_capacity: u32,
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
    ) -> Self {
        Self::new_resident_capacity_with_tree_capacity_and_debug(
            device,
            token_capacity,
            n_kinds,
            action_table_bytes,
            tables,
            tree_capacity_override,
            false,
        )
    }

    pub fn new_resident_capacity_with_tree_capacity_and_debug(
        device: &wgpu::Device,
        token_capacity: u32,
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
        tree_capacity_override: Option<u32>,
        retain_debug_hir_buffers: bool,
    ) -> Self {
        let n_tokens = token_capacity.saturating_add(2);
        Self::new_with_sizing(
            device,
            n_tokens,
            None,
            n_kinds,
            action_table_bytes,
            tables,
            true,
            false,
            retain_debug_hir_buffers,
            tree_capacity_override,
        )
    }

    fn new_with_sizing(
        device: &wgpu::Device,
        n_tokens: u32,
        token_kinds_u32: Option<&[u32]>,
        n_kinds: u32,
        action_table_bytes: &[u8],
        tables: &crate::parser::tables::PrecomputedParseTables,
        resident_projected_capacity: bool,
        prefer_ll1_tree_stream: bool,
        retain_debug_hir_buffers: bool,
        tree_capacity_override: Option<u32>,
    ) -> Self {
        let n_pairs = n_tokens.saturating_sub(1) as usize;
        let token_input_capacity = n_tokens.saturating_sub(2).max(1);
        let token_delimiter_n_blocks = token_input_capacity.div_ceil(256).max(1);
        let tree_stream_uses_ll1 =
            prefer_ll1_tree_stream && parser_table_uses_ll1_tree_stream(tables);
        let legacy_pair_capacity = legacy_pair_capacity_for(tree_stream_uses_ll1, n_pairs);

        let ll1_stack_capacity = if tree_stream_uses_ll1 {
            n_tokens.saturating_mul(8).saturating_add(1024).max(1)
        } else {
            1
        };
        let ll1_max_steps = if tree_stream_uses_ll1 {
            n_tokens
                .saturating_mul(64)
                .saturating_add(tables.n_productions)
                .saturating_add(1024)
                .max(1)
        } else {
            1
        };
        let ll1_fill_production = tables
            .prod_arity
            .iter()
            .position(|arity| *arity == 0)
            .unwrap_or(0) as u32;
        let empty = [0u32];
        let ll1_predict_src = if tables.ll1_predict.is_empty() {
            &empty[..]
        } else {
            &tables.ll1_predict
        };
        let ll1_rhs_off_src = if tables.prod_rhs_off.is_empty() {
            &empty[..]
        } else {
            &tables.prod_rhs_off
        };
        let ll1_rhs_len_src = if tables.prod_rhs_len.is_empty() {
            &empty[..]
        } else {
            &tables.prod_rhs_len
        };
        let ll1_rhs_src = if tables.prod_rhs.is_empty() {
            &empty[..]
        } else {
            &tables.prod_rhs
        };
        let ll1_predict = storage_ro_from_u32s(device, "parser.ll1_predict", ll1_predict_src);
        let ll1_prod_rhs_off =
            storage_ro_from_u32s(device, "parser.ll1_prod_rhs_off", ll1_rhs_off_src);
        let ll1_prod_rhs_len =
            storage_ro_from_u32s(device, "parser.ll1_prod_rhs_len", ll1_rhs_len_src);
        let ll1_prod_rhs = storage_ro_from_u32s(device, "parser.ll1_prod_rhs", ll1_rhs_src);
        let ll1_emit =
            storage_rw_for_array::<u32>(device, "parser.ll1_emit", ll1_stack_capacity as usize);
        let ll1_emit_pos =
            storage_rw_for_array::<u32>(device, "parser.ll1_emit_pos", ll1_stack_capacity as usize);
        let ll1_status = storage_rw_for_array::<u32>(device, "parser.ll1_status", 6);

        let stream_has_soi = token_kinds_u32
            .map(|kinds| kinds.first().copied() == Some(0))
            .unwrap_or(true);
        let first_input = if n_tokens > 1 && stream_has_soi { 1 } else { 0 };
        // Match the canonical LL(1) stream: the last token is the EOF sentinel and is not
        // consumed as ordinary input.
        let input_end = n_tokens.saturating_sub(1);
        let n_input_tokens = input_end.saturating_sub(first_input);
        let token_count = storage_ro_from_u32s(device, "parser.token_count", &[n_input_tokens]);
        let active_pair_thread_dispatch_args =
            dispatch_args_buffer(device, "parser.active_pair_thread_dispatch_args");
        let active_pair_group_dispatch_args =
            dispatch_args_buffer(device, "parser.active_pair_group_dispatch_args");
        let ll1_n_blocks = if tree_stream_uses_ll1 {
            n_input_tokens.div_ceil(LL1_BLOCK_SIZE).max(1)
        } else {
            1
        };
        let ll1_block_emit_stride = if tree_stream_uses_ll1 {
            LL1_BLOCK_EMIT_STRIDE
        } else {
            1
        };
        let ll1_params_base = super::passes::ll1_blocks_01::LL1BlocksParams {
            n_tokens,
            n_kinds,
            n_nonterminals: tables.n_nonterminals,
            n_productions: tables.n_productions,
            start_nonterminal: tables.start_nonterminal,
            first_input,
            input_end,
            n_blocks: ll1_n_blocks,
            block_size: LL1_BLOCK_SIZE,
            stack_capacity: LL1_BLOCK_STACK_CAPACITY,
            emit_stride: ll1_block_emit_stride,
            max_steps: ll1_max_steps,
            fill_production: ll1_fill_production,
            emit_scan_step: 0,
            emit_capacity: ll1_stack_capacity,
        };
        let params_ll1_blocks =
            uniform_from_val(device, "parser.params_ll1_blocks", &ll1_params_base);
        let ll1_block_seed_len =
            storage_rw_for_array::<u32>(device, "parser.ll1_block_seed_len", ll1_n_blocks as usize);
        let ll1_block_seed_stack = storage_rw_for_array::<u32>(
            device,
            "parser.ll1_block_seed_stack",
            (ll1_n_blocks as usize + 1) * LL1_BLOCK_STACK_CAPACITY as usize,
        );
        let ll1_seed_plan_status = storage_rw_for_array::<u32>(
            device,
            "parser.ll1_seed_plan_status",
            super::passes::ll1_blocks_02::LL1_SEED_PLAN_STATUS_WORDS,
        );
        let ll1_seeded_status = storage_rw_for_array::<u32>(
            device,
            "parser.ll1_seeded_status",
            ll1_n_blocks as usize * super::passes::ll1_blocks_01::LL1_BLOCK_STATUS_WORDS,
        );
        let ll1_seeded_emit = storage_rw_for_array::<u32>(
            device,
            "parser.ll1_seeded_emit",
            ll1_n_blocks as usize * ll1_block_emit_stride as usize,
        );
        let ll1_seeded_emit_pos = storage_rw_for_array::<u32>(
            device,
            "parser.ll1_seeded_emit_pos",
            ll1_n_blocks as usize * ll1_block_emit_stride as usize,
        );
        let ll1_emit_prefix_a =
            storage_rw_for_array::<u32>(device, "parser.ll1_emit_prefix_a", ll1_n_blocks as usize);
        let ll1_emit_prefix_b =
            storage_rw_for_array::<u32>(device, "parser.ll1_emit_prefix_b", ll1_n_blocks as usize);
        let ll1_status_summary_a = storage_rw_for_array::<u32>(
            device,
            "parser.ll1_status_summary_a",
            ll1_n_blocks as usize * 4,
        );
        let ll1_status_summary_b = storage_rw_for_array::<u32>(
            device,
            "parser.ll1_status_summary_b",
            ll1_n_blocks as usize * 4,
        );
        let ll1_emit_prefix_scan_steps =
            make_ll1_emit_prefix_scan_steps(device, ll1_params_base, ll1_n_blocks);

        // ---------- Pair→Header ----------
        let semantic_token_kinds = if let Some(kinds) = token_kinds_u32 {
            // Test/debug one-shot parsing receives already-classified parser
            // token kinds. Resident compilation fills this buffer on the GPU
            // with `tokens_to_kinds` instead.
            storage_ro_from_u32s(device, "parser.semantic_token_kinds.input", kinds)
        } else {
            storage_rw_for_array::<u32>(device, "parser.semantic_token_kinds", n_tokens as usize)
        };
        let token_delimiter_params = uniform_from_val(
            device,
            "parser.token_delimiters.params",
            &TokenDelimiterParams {
                n_tokens: token_input_capacity,
                n_blocks: token_delimiter_n_blocks,
                scan_step: 0,
            },
        );
        let token_delimiter_scan_steps =
            make_token_delimiter_scan_steps(device, token_input_capacity, token_delimiter_n_blocks);
        let token_depth_brace_inblock = storage_rw_for_array::<i32>(
            device,
            "parser.token_depth_brace_inblock",
            token_input_capacity as usize,
        );
        let token_depth_bracket_inblock = storage_rw_for_array::<i32>(
            device,
            "parser.token_depth_bracket_inblock",
            n_tokens.max(1) as usize,
        );
        let token_block_sum_brace = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_sum_brace",
            token_delimiter_n_blocks as usize,
        );
        let token_block_sum_bracket = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_sum_bracket",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_brace_a = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_brace_a",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_brace_b = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_brace_b",
            token_delimiter_n_blocks as usize,
        );
        let token_block_prefix_brace = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_prefix_brace",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_bracket_a = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_bracket_a",
            token_delimiter_n_blocks as usize,
        );
        let token_prefix_bracket_b = storage_rw_for_array::<i32>(
            device,
            "parser.token_prefix_bracket_b",
            token_delimiter_n_blocks as usize,
        );
        let token_block_prefix_bracket = storage_rw_for_array::<i32>(
            device,
            "parser.token_block_prefix_bracket",
            token_delimiter_n_blocks as usize,
        );
        let token_top_brace_owner_block = storage_rw_for_array::<u32>(
            device,
            "parser.token_top_brace_owner_block",
            token_delimiter_n_blocks as usize,
        );
        let token_top_brace_owner_prefix_a = storage_rw_for_array::<u32>(
            device,
            "parser.token_top_brace_owner_prefix_a",
            token_delimiter_n_blocks as usize,
        );
        let token_top_brace_owner_prefix_b = storage_rw_for_array::<u32>(
            device,
            "parser.token_top_brace_owner_prefix_b",
            token_delimiter_n_blocks as usize,
        );
        let token_top_brace_owner_block_prefix = storage_rw_for_array::<u32>(
            device,
            "parser.token_top_brace_owner_block_prefix",
            token_delimiter_n_blocks as usize,
        );
        let token_statement_event_block = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_event_block",
            token_delimiter_n_blocks as usize,
        );
        let token_statement_event_prefix_a = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_event_prefix_a",
            token_delimiter_n_blocks as usize,
        );
        let token_statement_event_prefix_b = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_event_prefix_b",
            token_delimiter_n_blocks as usize,
        );
        let token_statement_event_block_prefix = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_event_block_prefix",
            token_delimiter_n_blocks as usize,
        );
        let token_brace_semantic_kind = storage_rw_for_array::<u32>(
            device,
            "parser.token_brace_semantic_kind",
            n_tokens.max(1) as usize,
        );
        let token_bracket_semantic_kind = storage_rw_for_array::<u32>(
            device,
            "parser.token_bracket_semantic_kind",
            token_input_capacity as usize,
        );
        let token_statement_context_kind = storage_rw_for_array::<u32>(
            device,
            "parser.token_statement_context_kind",
            token_input_capacity as usize,
        );
        let token_brace_match_params = uniform_from_val(
            device,
            "parser.token_brace_match.params",
            &TokenBraceMatchParams {
                n_tokens: token_input_capacity,
            },
        );
        let token_brace_match_depth = storage_rw_for_array::<i32>(
            device,
            "parser.token_brace_match_depth",
            token_input_capacity as usize,
        );
        let token_brace_match_block_min = storage_rw_for_array::<i32>(
            device,
            "parser.token_brace_match_block_min",
            token_delimiter_n_blocks as usize,
        );
        let token_brace_match_min_tree_base =
            next_power_of_two_u32(token_delimiter_n_blocks).max(1);
        let token_brace_match_min_tree = storage_rw_for_array::<i32>(
            device,
            "parser.token_brace_match_min_tree",
            token_brace_match_min_tree_base.saturating_mul(2) as usize,
        );
        let token_brace_match_min_tree_steps = make_tree_prefix_max_build_steps(
            device,
            token_delimiter_n_blocks,
            token_brace_match_min_tree_base,
        );
        let token_feature_flags = if token_kinds_u32.is_some() {
            storage_ro_from_u32s(
                device,
                "parser.token_feature_flags.conservative",
                &[u32::MAX],
            )
        } else {
            storage_ro_from_u32s(device, "parser.token_feature_flags", &[0])
        };

        let params_llp = uniform_from_val(
            device,
            "parser.params_llp",
            &super::passes::llp_pairs::LLPParams { n_tokens, n_kinds },
        );

        let action_table = if action_table_bytes.is_empty() {
            let one = vec![0u8; core::mem::size_of::<ActionHeader>()];
            storage_ro_from_bytes::<u8>(device, "parser.action_table", &one, one.len())
        } else {
            storage_ro_from_bytes::<u8>(
                device,
                "parser.action_table",
                action_table_bytes,
                action_table_bytes.len(),
            )
        };

        let out_headers: LaniusBuffer<ActionHeader> = storage_rw_for_array::<ActionHeader>(
            device,
            "parser.out_headers",
            legacy_pair_capacity.saturating_add(1),
        );

        // ---------- Pack varlen ----------
        let (mut acc_sc, mut acc_emit) = (0u32, 0u32);

        if tree_stream_uses_ll1 {
            // LL(1) mode does not record the older pair/pack/bracket passes. Keep
            // their fields as one-word compatibility buffers instead of scaling
            // dead scratch allocations with token capacity.
        } else if resident_projected_capacity {
            let max_sc_len = tables.sc_len.iter().copied().max().unwrap_or(0);
            let max_emit_len = tables.pp_len.iter().copied().max().unwrap_or(0);
            acc_sc = (n_pairs as u32).saturating_mul(max_sc_len);
            acc_emit = (n_pairs as u32).saturating_mul(max_emit_len);
        } else {
            let token_kinds_u32 =
                token_kinds_u32.expect("non-resident parser sizing requires explicit token kinds");
            for i in 0..n_pairs {
                let prev = token_kinds_u32[i];
                let thisk = token_kinds_u32[i + 1];
                let idx2d = (prev as usize) * (n_kinds as usize) + (thisk as usize);
                acc_sc += tables.sc_len[idx2d];
                acc_emit += tables.pp_len[idx2d];
            }
        }
        let total_sc = acc_sc;
        let total_emit = acc_emit;
        let tree_count_uses_status = tree_stream_uses_ll1 || resident_projected_capacity;
        let tree_capacity = tree_capacity_override
            .unwrap_or_else(|| {
                if tree_count_uses_status {
                    if tree_stream_uses_ll1 {
                        ll1_stack_capacity
                    } else {
                        resident_projected_tree_capacity(n_tokens, total_emit)
                    }
                } else {
                    total_emit
                }
            })
            .max(1);
        let emit_capacity = if resident_projected_capacity {
            tree_capacity
        } else {
            total_emit.max(1)
        };

        let mut blob: Vec<u32> = Vec::with_capacity(
            tables.sc_superseq.len()
                + tables.sc_off.len()
                + tables.sc_len.len()
                + tables.pp_superseq.len()
                + tables.pp_off.len()
                + tables.pp_len.len(),
        );

        let sc_superseq_off = blob.len() as u32;
        blob.extend_from_slice(&tables.sc_superseq);

        let sc_off_off = blob.len() as u32;
        blob.extend_from_slice(&tables.sc_off);

        let sc_len_off = blob.len() as u32;
        blob.extend_from_slice(&tables.sc_len);

        let pp_superseq_off = blob.len() as u32;
        blob.extend_from_slice(&tables.pp_superseq);

        let pp_off_off = blob.len() as u32;
        blob.extend_from_slice(&tables.pp_off);

        let pp_len_off = blob.len() as u32;
        blob.extend_from_slice(&tables.pp_len);

        let params_pack = uniform_from_val(
            device,
            "pack.params",
            &super::passes::pack_varlen::PackParams {
                n_tokens,
                n_kinds,
                total_sc,
                total_emit,
                sc_capacity: if resident_projected_capacity {
                    1
                } else {
                    total_sc.max(1)
                },
                emit_capacity,
                sc_superseq_off,
                sc_off_off,
                sc_len_off,
                pp_superseq_off,
                pp_off_off,
                pp_len_off,
            },
        );

        let n_pack_pairs = legacy_pair_capacity;
        let sc_offsets = storage_rw_for_array::<u32>(device, "pack.sc_offsets", n_pack_pairs);
        let emit_offsets = storage_rw_for_array::<u32>(device, "pack.emit_offsets", n_pack_pairs);
        let pack_sc_prefix_a =
            storage_rw_for_array::<u32>(device, "pack.sc_prefix_a", n_pack_pairs);
        let pack_sc_prefix_b =
            storage_rw_for_array::<u32>(device, "pack.sc_prefix_b", n_pack_pairs);
        let pack_emit_prefix_a =
            storage_rw_for_array::<u32>(device, "pack.emit_prefix_a", n_pack_pairs);
        let pack_emit_prefix_b =
            storage_rw_for_array::<u32>(device, "pack.emit_prefix_b", n_pack_pairs);
        let pack_offset_scan_steps =
            make_pack_offset_scan_steps(device, n_tokens.saturating_sub(1));
        let pack_total_reduce_steps =
            make_pack_total_reduce_steps(device, n_tokens.saturating_sub(1));
        let projected_status = storage_rw_for_array::<u32>(device, "pack.projected_status", 6);
        let tables_blob = storage_ro_from_u32s(device, "pack.tables_blob", &blob);

        let out_sc = storage_rw_for_array::<u32>(
            device,
            "pack.out_sc",
            if resident_projected_capacity {
                1
            } else {
                total_sc.max(1) as usize
            },
        );
        let out_emit = storage_rw_for_array::<u32>(device, "pack.out_emit", emit_capacity as usize);
        let out_emit_pos =
            storage_rw_for_array::<u32>(device, "pack.out_emit_pos", emit_capacity as usize);

        // ---------- Brackets (parallel) ----------
        //
        // The resident LLP pipeline builds tree/HIR from the packed production
        // stream and never records the older bracket passes. Keep these buffers
        // compatibility-sized in that path; otherwise long inputs allocate GiB
        // of scratch that no recorded pass can read.
        const WG: u32 = 256;
        let bracket_capacity = if resident_projected_capacity {
            1
        } else {
            total_sc.max(1)
        };
        let n_blocks = if resident_projected_capacity {
            1
        } else {
            total_sc.div_ceil(WG).max(1)
        };

        let b01_params = uniform_from_val(
            device,
            "brackets.b01.params",
            &super::passes::brackets_01::Params {
                n_sc: total_sc,
                wg_size: WG,
            },
        );
        let b02_params = uniform_from_val(
            device,
            "brackets.b02.params",
            &super::passes::brackets_02::Params {
                n_blocks,
                scan_step: 0,
            },
        );
        let b02_scan_steps = make_brackets_block_prefix_scan_steps(device, n_blocks);
        let b03_params = uniform_from_val(
            device,
            "brackets.b03.params",
            &super::passes::brackets_03::Params {
                n_sc: total_sc,
                wg_size: WG,
            },
        );

        // layers upper bound = #pushes ≤ total_sc; +2 for safety. Resident and
        // LL(1) modes never record bracket passes, so one layer is enough for
        // bindings.
        let n_layers = if resident_projected_capacity || tree_stream_uses_ll1 {
            1
        } else {
            total_sc.saturating_add(2).max(1)
        };

        let b04_params = uniform_from_val(
            device,
            "brackets.b04.params",
            &super::passes::brackets_04::Params {
                n_sc: total_sc,
                n_layers,
            },
        );
        let b05_params = uniform_from_val(
            device,
            "brackets.b05.params",
            &super::passes::brackets_05::Params {
                n_layers,
                scan_step: 0,
            },
        );
        let b05_scan_steps = make_brackets_histogram_scan_steps(device, n_layers);
        let b06_params = uniform_from_val(
            device,
            "brackets.b06.params",
            &super::passes::brackets_06::Params {
                n_sc: total_sc,
                n_layers,
            },
        );
        let b07_params = uniform_from_val(
            device,
            "brackets.b07.params",
            &super::passes::brackets_pse_04::Params {
                n_sc: total_sc,
                n_layers,
                typed_check: 1,
            },
        );

        let b_exscan_inblock = storage_rw_for_array::<i32>(
            device,
            "brackets.exscan_inblock",
            bracket_capacity as usize,
        );
        let b_block_sum =
            storage_rw_for_array::<i32>(device, "brackets.block_sum", n_blocks as usize);
        let b_block_minpref =
            storage_rw_for_array::<i32>(device, "brackets.block_minpref", n_blocks as usize);
        let b_block_maxdepth =
            storage_rw_for_array::<i32>(device, "brackets.block_maxdepth", n_blocks as usize);
        let b_block_prefix =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix", n_blocks as usize);
        let b_block_prefix_sum_a =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix_sum_a", n_blocks as usize);
        let b_block_prefix_sum_b =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix_sum_b", n_blocks as usize);
        let b_block_prefix_min_a =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix_min_a", n_blocks as usize);
        let b_block_prefix_min_b =
            storage_rw_for_array::<i32>(device, "brackets.block_prefix_min_b", n_blocks as usize);

        let depths_out = storage_rw_for_array::<i32>(device, "brackets.depths_out", 2);
        let valid_out = storage_rw_for_array::<u32>(device, "brackets.valid_out", 1);

        let b_depth_exscan =
            storage_rw_for_array::<i32>(device, "brackets.depth_exscan", bracket_capacity as usize);
        let b_layer =
            storage_rw_for_array::<u32>(device, "brackets.layer", bracket_capacity as usize);

        let b_hist_push =
            storage_rw_for_array::<u32>(device, "brackets.hist_push", n_layers as usize);
        let b_hist_pop =
            storage_rw_for_array::<u32>(device, "brackets.hist_pop", n_layers as usize);
        let b_off_push =
            storage_rw_for_array::<u32>(device, "brackets.off_push", n_layers as usize);
        let b_off_pop = storage_rw_for_array::<u32>(device, "brackets.off_pop", n_layers as usize);
        let b_cur_push =
            storage_rw_for_array::<u32>(device, "brackets.cur_push", n_layers as usize);
        let b_cur_pop = storage_rw_for_array::<u32>(device, "brackets.cur_pop", n_layers as usize);
        let b_pushes_by_layer = storage_rw_for_array::<u32>(
            device,
            "brackets.pushes_by_layer",
            bracket_capacity as usize,
        );
        let b_pops_by_layer = storage_rw_for_array::<u32>(
            device,
            "brackets.pops_by_layer",
            bracket_capacity as usize,
        );
        let b_slot_for_index = storage_rw_for_array::<u32>(
            device,
            "brackets.slot_for_index",
            bracket_capacity as usize,
        );
        let match_for_index = storage_rw_for_array::<u32>(
            device,
            "brackets.match_for_index",
            bracket_capacity as usize,
        );

        // ---------- Tree parent recovery ----------
        let tree_n_node_blocks = tree_capacity.div_ceil(WG).max(1);
        let tree_n_prefix_blocks = tree_capacity.saturating_add(1).div_ceil(WG).max(1);
        let tree_prefix_params_base = super::passes::tree_prefix_01::Params {
            n: tree_capacity,
            uses_ll1: u32::from(tree_count_uses_status),
            n_node_blocks: tree_n_node_blocks,
            n_prefix_blocks: tree_n_prefix_blocks,
            scan_step: 0,
        };
        let tree_prefix_params = uniform_from_val(
            device,
            "parser.tree_prefix.params",
            &tree_prefix_params_base,
        );
        let tree_active_dispatch_args =
            dispatch_args_buffer(device, "parser.tree_active_dispatch_args");
        let tree_enum_dispatch_args =
            dispatch_args_buffer(device, "parser.tree_enum_dispatch_args");
        let tree_match_dispatch_args =
            dispatch_args_buffer(device, "parser.tree_match_dispatch_args");
        let tree_struct_dispatch_args =
            dispatch_args_buffer(device, "parser.tree_struct_dispatch_args");
        let hir_semantic_dispatch_args =
            dispatch_args_buffer(device, "parser.hir_semantic_dispatch_args");
        let tree_prefix_scan_steps =
            make_tree_prefix_scan_steps(device, tree_prefix_params_base, tree_n_node_blocks);
        let tree_prefix_inblock = storage_rw_for_array::<i32>(
            device,
            "parser.tree_prefix_inblock",
            tree_capacity as usize,
        );
        let tree_block_sum = storage_rw_for_array::<i32>(
            device,
            "parser.tree_block_sum",
            tree_n_node_blocks as usize,
        );
        let tree_block_prefix_a = storage_rw_for_array::<i32>(
            device,
            "parser.tree_block_prefix_a",
            tree_n_node_blocks as usize,
        );
        let tree_block_prefix_b = storage_rw_for_array::<i32>(
            device,
            "parser.tree_block_prefix_b",
            tree_n_node_blocks as usize,
        );
        let tree_block_prefix = storage_rw_for_array::<i32>(
            device,
            "parser.tree_block_prefix",
            tree_n_node_blocks as usize,
        );
        let tree_prefix =
            storage_rw_for_array::<i32>(device, "parser.tree_prefix", tree_capacity as usize + 1);
        let tree_prefix_block_max = storage_rw_for_array::<i32>(
            device,
            "parser.tree_prefix_block_max",
            tree_n_prefix_blocks as usize,
        );
        let tree_prefix_block_max_tree_base = next_power_of_two_u32(tree_n_prefix_blocks).max(1);
        let tree_prefix_block_max_tree = storage_rw_for_array::<i32>(
            device,
            "parser.tree_prefix_block_max_tree",
            tree_prefix_block_max_tree_base.saturating_mul(2) as usize,
        );
        let tree_prefix_max_build_steps = make_tree_prefix_max_build_steps(
            device,
            tree_n_prefix_blocks,
            tree_prefix_block_max_tree_base,
        );

        // Shared tables/outputs
        let prod_arity = storage_ro_from_u32s(device, "parser.prod_arity", &tables.prod_arity);
        let node_kind =
            storage_rw_for_array::<u32>(device, "parser.node_kind", tree_capacity as usize);
        let parent = storage_rw_for_array::<u32>(device, "parser.parent", tree_capacity as usize);
        let tree_params = uniform_from_val(
            device,
            "parser.tree_parent.params",
            &super::passes::tree_parent::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
                n_prefix_blocks: tree_n_prefix_blocks,
                max_tree_leaf_base: tree_prefix_block_max_tree_base,
            },
        );
        let tree_span_params = uniform_from_val(
            device,
            "parser.tree_spans.params",
            &super::passes::tree_spans::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
                n_prefix_blocks: tree_n_prefix_blocks,
                max_tree_leaf_base: tree_prefix_block_max_tree_base,
            },
        );
        let tree_prev_sibling_params = uniform_from_val(
            device,
            "parser.tree_prev_sibling.params",
            &super::passes::tree_prev_sibling_clear::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let first_child =
            storage_rw_for_array::<u32>(device, "parser.first_child", tree_capacity as usize);
        let next_sibling =
            storage_rw_for_array::<u32>(device, "parser.next_sibling", tree_capacity as usize);
        let prev_sibling =
            storage_rw_for_array::<u32>(device, "parser.prev_sibling", tree_capacity as usize);
        let subtree_end =
            storage_rw_for_array::<u32>(device, "parser.subtree_end", tree_capacity as usize);
        let hir_params = uniform_from_val(
            device,
            "parser.hir_nodes.params",
            &super::passes::hir_nodes::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let hir_span_params = uniform_from_val(
            device,
            "parser.hir_spans.params",
            &super::passes::hir_spans::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let hir_type_fields_params = uniform_from_val(
            device,
            "parser.hir_type_fields.params",
            &super::passes::hir_type_fields::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let hir_item_fields_params = uniform_from_val(
            device,
            "parser.hir_item_fields.params",
            &super::passes::hir_item_fields::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let hir_param_fields_params = uniform_from_val(
            device,
            "parser.hir_param_fields.params",
            &super::passes::hir_param_fields::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let hir_expr_fields_params = uniform_from_val(
            device,
            "parser.hir_expr_fields.params",
            &super::passes::hir_expr_fields::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let hir_member_fields_params = uniform_from_val(
            device,
            "parser.hir_member_fields.params",
            &super::passes::hir_member_fields::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let hir_stmt_fields_params = uniform_from_val(
            device,
            "parser.hir_stmt_fields.params",
            &super::passes::hir_stmt_fields::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let hir_call_fields_params = uniform_from_val(
            device,
            "parser.hir_call_fields.params",
            &super::passes::hir_call_fields::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let hir_array_fields_params = uniform_from_val(
            device,
            "parser.hir_array_fields.params",
            &super::passes::hir_array_fields::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let hir_enum_match_fields_params = uniform_from_val(
            device,
            "parser.hir_enum_match_fields.params",
            &super::passes::hir_enum_match_fields::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let hir_struct_fields_params = uniform_from_val(
            device,
            "parser.hir_struct_fields.params",
            &super::passes::hir_struct_fields::Params {
                n: tree_capacity,
                uses_ll1: u32::from(tree_count_uses_status),
            },
        );
        let hir_kind =
            storage_rw_for_array::<u32>(device, "parser.hir_kind", tree_capacity as usize);
        let hir_semantic_block_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_block_count",
            tree_n_node_blocks as usize,
        );
        let hir_semantic_prefix_scan_steps =
            make_hir_semantic_prefix_scan_steps(device, tree_n_node_blocks);
        let hir_semantic_flag =
            alias_storage_buffer::<i32, u32>(&tree_prefix, tree_capacity as usize);
        let hir_semantic_local_prefix =
            alias_storage_buffer::<i32, u32>(&tree_prefix_inblock, tree_capacity as usize);
        let hir_semantic_block_prefix_a =
            alias_storage_buffer::<i32, u32>(&tree_block_prefix_a, tree_n_node_blocks as usize);
        let hir_semantic_block_prefix_b =
            alias_storage_buffer::<i32, u32>(&tree_block_prefix_b, tree_n_node_blocks as usize);
        let hir_node_dense_id = if resident_projected_capacity {
            // The resident pipeline's later stages consume the dense-to-node
            // map and semantic count. Until a stage needs original-node to
            // dense-row lookups, keep that scatter output transient and reuse
            // dead packed-production storage before HIR type metadata
            // overwrites the same buffer.
            alias_storage_buffer::<u32, u32>(&out_emit, tree_capacity as usize)
        } else {
            storage_rw_for_array::<u32>(device, "parser.hir_node_dense_id", tree_capacity as usize)
        };
        let hir_semantic_prefix_before_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_prefix_before_node",
            tree_capacity as usize,
        );
        let hir_semantic_dense_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_dense_node",
            tree_capacity as usize,
        );
        let reuse_semantic_debug_buffers = resident_projected_capacity && !retain_debug_hir_buffers;
        let hir_semantic_subtree_end = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_subtree_end",
            tree_capacity as usize,
        );
        let hir_semantic_count =
            storage_rw_for_array::<u32>(device, "parser.hir_semantic_count", 1);
        let hir_semantic_parent = if reuse_semantic_debug_buffers {
            // `hir_semantic_prefix_before_node` is only live until
            // `hir_semantic_subtree_end` projects dense ranges. Production
            // resident compilation does not read it back, so the durable dense
            // parent records can reuse that tree-sized allocation.
            alias_storage_buffer::<u32, u32>(
                &hir_semantic_prefix_before_node,
                tree_capacity as usize,
            )
        } else {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_semantic_parent",
                tree_capacity as usize,
            )
        };
        let hir_semantic_first_child = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_first_child",
            tree_capacity as usize,
        );
        let hir_semantic_next_sibling = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_next_sibling",
            tree_capacity as usize,
        );
        let hir_semantic_depth = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_depth",
            tree_capacity as usize,
        );
        let hir_semantic_child_index = storage_rw_for_array::<u32>(
            device,
            "parser.hir_semantic_child_index",
            tree_capacity as usize,
        );
        // Shared scratch for Pareas-style linked-list pointer jumping. The
        // durable HIR outputs remain in their own buffers; these workspaces are
        // overwritten by each list-family link/rank/scatter sequence.
        let hir_list0_owner_a =
            storage_rw_for_array::<u32>(device, "parser.hir_list0_owner_a", tree_capacity as usize);
        let hir_list0_owner_b =
            storage_rw_for_array::<u32>(device, "parser.hir_list0_owner_b", tree_capacity as usize);
        let hir_list0_link_a =
            storage_rw_for_array::<u32>(device, "parser.hir_list0_link_a", tree_capacity as usize);
        let hir_list0_link_b =
            storage_rw_for_array::<u32>(device, "parser.hir_list0_link_b", tree_capacity as usize);
        let hir_list0_rank_a =
            storage_rw_for_array::<u32>(device, "parser.hir_list0_rank_a", tree_capacity as usize);
        let hir_list0_rank_b =
            storage_rw_for_array::<u32>(device, "parser.hir_list0_rank_b", tree_capacity as usize);
        let hir_list1_owner_a =
            storage_rw_for_array::<u32>(device, "parser.hir_list1_owner_a", tree_capacity as usize);
        let hir_list1_owner_b =
            storage_rw_for_array::<u32>(device, "parser.hir_list1_owner_b", tree_capacity as usize);
        let hir_list1_link_a =
            storage_rw_for_array::<u32>(device, "parser.hir_list1_link_a", tree_capacity as usize);
        let hir_list1_link_b =
            storage_rw_for_array::<u32>(device, "parser.hir_list1_link_b", tree_capacity as usize);
        let hir_list1_rank_a =
            storage_rw_for_array::<u32>(device, "parser.hir_list1_rank_a", tree_capacity as usize);
        let hir_list1_rank_b =
            storage_rw_for_array::<u32>(device, "parser.hir_list1_rank_b", tree_capacity as usize);
        let hir_semantic_parent_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_semantic_parent_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_semantic_parent_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_semantic_parent_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_semantic_depth_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_semantic_depth_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_semantic_depth_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_semantic_depth_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_semantic_child_index_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_semantic_child_index_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_semantic_child_index_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_semantic_child_index_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_token_pos =
            storage_rw_for_array::<u32>(device, "parser.hir_token_pos", tree_capacity as usize);
        let hir_token_end =
            storage_rw_for_array::<u32>(device, "parser.hir_token_end", tree_capacity as usize);
        let hir_token_file_id =
            storage_rw_for_array::<u32>(device, "parser.hir_token_file_id", tree_capacity as usize);
        let (hir_type_form, hir_type_value_node, hir_type_len_token, hir_type_len_value) =
            if resident_projected_capacity {
                // Resident compilation does not expose packed productions as
                // parser debug artifacts. After `hir_nodes`, the production
                // streams and tree-prefix scratch are dead, so reuse them for
                // tree-sized type metadata.
                (
                    alias_storage_buffer::<u32, u32>(&out_emit, tree_capacity as usize),
                    alias_storage_buffer::<u32, u32>(&out_emit_pos, tree_capacity as usize),
                    alias_storage_buffer::<i32, u32>(&tree_prefix_inblock, tree_capacity as usize),
                    alias_storage_buffer::<i32, u32>(&tree_prefix, tree_capacity as usize),
                )
            } else {
                (
                    storage_rw_for_array::<u32>(
                        device,
                        "parser.hir_type_form",
                        tree_capacity as usize,
                    ),
                    storage_rw_for_array::<u32>(
                        device,
                        "parser.hir_type_value_node",
                        tree_capacity as usize,
                    ),
                    storage_rw_for_array::<u32>(
                        device,
                        "parser.hir_type_len_token",
                        tree_capacity as usize,
                    ),
                    storage_rw_for_array::<u32>(
                        device,
                        "parser.hir_type_len_value",
                        tree_capacity as usize,
                    ),
                )
            };
        let hir_type_file_id =
            alias_storage_buffer::<u32, u32>(&hir_token_file_id, tree_capacity as usize);
        // Right-recursive list families use a previous-node record only from
        // their link pass through the immediately following scatter pass.
        // Reuse one scratch buffer across those phases; durable next/start/count
        // records remain separately allocated below.
        let hir_previous_scratch = storage_rw_for_array::<u32>(
            device,
            "parser.hir_previous_scratch",
            tree_capacity as usize,
        );

        let hir_type_path_leaf_node = if reuse_semantic_debug_buffers {
            // `hir_semantic_subtree_end` is read only by `hir_semantic_nav`.
            // HIR type metadata starts later, so production can reuse this
            // debug navigation buffer for the durable type leaf record.
            alias_storage_buffer::<u32, u32>(&hir_semantic_subtree_end, tree_capacity as usize)
        } else {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_type_path_leaf_node",
                tree_capacity as usize,
            )
        };
        let hir_type_path_leaf_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_type_path_leaf_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_type_path_leaf_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_type_path_leaf_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_type_arg_start = if reuse_semantic_debug_buffers {
            // Dense first-child is a debug navigation output. Later HIR type
            // passes overwrite it with type-argument starts.
            alias_storage_buffer::<u32, u32>(&hir_semantic_first_child, tree_capacity as usize)
        } else {
            storage_rw_for_array::<u32>(device, "parser.hir_type_arg_start", tree_capacity as usize)
        };
        let hir_type_arg_count = if reuse_semantic_debug_buffers {
            // Dense next-sibling is consumed by child-index linking before HIR
            // type passes clear and fill type-argument counts.
            alias_storage_buffer::<u32, u32>(&hir_semantic_next_sibling, tree_capacity as usize)
        } else {
            storage_rw_for_array::<u32>(device, "parser.hir_type_arg_count", tree_capacity as usize)
        };
        let hir_type_arg_next =
            storage_rw_for_array::<u32>(device, "parser.hir_type_arg_next", tree_capacity as usize);
        let hir_type_alias_target_node = if reuse_semantic_debug_buffers {
            // Dense depth is not consumed after construction; HIR record clear
            // overwrites it before type-alias target projection.
            alias_storage_buffer::<u32, u32>(&hir_semantic_depth, tree_capacity as usize)
        } else {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_type_alias_target_node",
                tree_capacity as usize,
            )
        };
        let hir_fn_return_type_node = if reuse_semantic_debug_buffers {
            // Dense child-index is similarly debug-only after construction and
            // can become the function return-type record in production.
            alias_storage_buffer::<u32, u32>(&hir_semantic_child_index, tree_capacity as usize)
        } else {
            storage_rw_for_array::<u32>(
                device,
                "parser.hir_fn_return_type_node",
                tree_capacity as usize,
            )
        };
        // Function-signature ownership is a transient pointer-jump family. It
        // starts after type-alias ownership has been consumed and finishes
        // before parameter/list passes reuse the shared scratch.
        let hir_fn_signature_owner_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_fn_signature_owner_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_fn_signature_return_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_fn_signature_return_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_fn_signature_function_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_fn_signature_function_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_type_arg_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_type_arg_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_type_arg_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_type_arg_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_type_arg_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_type_arg_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_type_arg_previous =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let hir_type_alias_owner_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_type_alias_owner_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_type_alias_owner_value_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_type_alias_owner_value_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_item_kind =
            storage_rw_for_array::<u32>(device, "parser.hir_item_kind", tree_capacity as usize);
        let hir_item_name_token = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_name_token",
            tree_capacity as usize,
        );
        // `hir_item_decl_token` is a late projection from `hir_item_kind` and
        // `hir_token_pos`. The scheduler writes it after all pointer-jump list
        // families are done, so it can reuse list scratch instead of retaining
        // one more tree-sized allocation.
        let hir_item_decl_token =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_item_namespace = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_namespace",
            tree_capacity as usize,
        );
        let hir_item_visibility = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_visibility",
            tree_capacity as usize,
        );
        let hir_item_path_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_path_start",
            tree_capacity as usize,
        );
        let hir_item_path_end =
            storage_rw_for_array::<u32>(device, "parser.hir_item_path_end", tree_capacity as usize);
        let hir_item_file_id =
            alias_storage_buffer::<u32, u32>(&hir_token_file_id, tree_capacity as usize);
        let hir_item_import_target_kind = storage_rw_for_array::<u32>(
            device,
            "parser.hir_item_import_target_kind",
            tree_capacity as usize,
        );
        let hir_param_record = storage_rw_for_array::<u32>(
            device,
            "parser.hir_param_record",
            tree_capacity.saturating_mul(4) as usize,
        );
        let hir_param_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_param_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_param_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_param_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_param_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_param_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_param_previous =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let hir_variant_parent_enum = storage_rw_for_array::<u32>(
            device,
            "parser.hir_variant_parent_enum",
            tree_capacity as usize,
        );
        let hir_variant_ordinal = storage_rw_for_array::<u32>(
            device,
            "parser.hir_variant_ordinal",
            tree_capacity as usize,
        );
        let hir_variant_payload_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_variant_payload_start",
            tree_capacity as usize,
        );
        let hir_variant_payload_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_variant_payload_count",
            tree_capacity as usize,
        );
        let hir_variant_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_variant_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_variant_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_variant_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_variant_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_variant_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_variant_payload_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_a, tree_capacity as usize);
        let hir_variant_payload_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_b, tree_capacity as usize);
        let hir_variant_payload_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_a, tree_capacity as usize);
        let hir_variant_payload_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_b, tree_capacity as usize);
        let hir_variant_payload_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_a, tree_capacity as usize);
        let hir_variant_payload_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_b, tree_capacity as usize);
        let hir_rank_flag =
            storage_rw_for_array::<u32>(device, "parser.hir_rank_flag", tree_capacity as usize);
        let hir_rank_local_prefix = storage_rw_for_array::<u32>(
            device,
            "parser.hir_rank_local_prefix",
            tree_capacity as usize,
        );
        let hir_rank_block_sum = storage_rw_for_array::<u32>(
            device,
            "parser.hir_rank_block_sum",
            tree_n_node_blocks as usize,
        );
        let hir_rank_block_prefix_a = storage_rw_for_array::<u32>(
            device,
            "parser.hir_rank_block_prefix_a",
            tree_n_node_blocks as usize,
        );
        let hir_rank_block_prefix_b = storage_rw_for_array::<u32>(
            device,
            "parser.hir_rank_block_prefix_b",
            tree_n_node_blocks as usize,
        );
        let hir_rank_node =
            storage_rw_for_array::<u32>(device, "parser.hir_rank_node", tree_capacity as usize);
        let hir_rank_count = storage_rw_for_array::<u32>(device, "parser.hir_rank_count", 1);
        let hir_rank_dispatch_args = dispatch_args_buffer(device, "parser.hir_rank_dispatch_args");
        let hir_list_rank_flag =
            alias_storage_buffer::<u32, u32>(&hir_rank_flag, tree_capacity as usize);
        let hir_list_rank_local_prefix =
            alias_storage_buffer::<u32, u32>(&hir_rank_local_prefix, tree_capacity as usize);
        let hir_list_rank_block_sum =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_sum, tree_n_node_blocks as usize);
        let hir_list_rank_block_prefix_a =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_a, tree_n_node_blocks as usize);
        let hir_list_rank_block_prefix_b =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_b, tree_n_node_blocks as usize);
        let hir_list_rank_node =
            alias_storage_buffer::<u32, u32>(&hir_rank_node, tree_capacity as usize);
        let hir_list_rank_count = alias_storage_buffer::<u32, u32>(&hir_rank_count, 1);
        let hir_list_rank_dispatch_args =
            alias_storage_buffer::<u32, u32>(&hir_rank_dispatch_args, 3);
        let hir_enum_rank_flag =
            alias_storage_buffer::<u32, u32>(&hir_rank_flag, tree_capacity as usize);
        let hir_enum_rank_local_prefix =
            alias_storage_buffer::<u32, u32>(&hir_rank_local_prefix, tree_capacity as usize);
        let hir_enum_rank_block_sum =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_sum, tree_n_node_blocks as usize);
        let hir_enum_rank_block_prefix_a =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_a, tree_n_node_blocks as usize);
        let hir_enum_rank_block_prefix_b =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_b, tree_n_node_blocks as usize);
        let hir_enum_rank_node =
            alias_storage_buffer::<u32, u32>(&hir_rank_node, tree_capacity as usize);
        let hir_enum_rank_count = alias_storage_buffer::<u32, u32>(&hir_rank_count, 1);
        let hir_enum_rank_dispatch_args =
            alias_storage_buffer::<u32, u32>(&hir_rank_dispatch_args, 3);
        let hir_match_scrutinee_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_scrutinee_node",
            tree_capacity as usize,
        );
        let hir_match_arm_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_start",
            tree_capacity as usize,
        );
        let hir_match_arm_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_count",
            tree_capacity as usize,
        );
        let hir_match_arm_next = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_next",
            tree_capacity as usize,
        );
        let hir_match_arm_pattern_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_pattern_node",
            tree_capacity as usize,
        );
        let hir_match_arm_payload_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_payload_start",
            tree_capacity as usize,
        );
        let hir_match_arm_payload_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_payload_count",
            tree_capacity as usize,
        );
        let hir_match_arm_result_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_arm_result_node",
            tree_capacity as usize,
        );
        let hir_match_payload_owner_arm = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_payload_owner_arm",
            tree_capacity as usize,
        );
        let hir_match_payload_match_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_payload_match_node",
            tree_capacity as usize,
        );
        let hir_match_payload_ordinal = storage_rw_for_array::<u32>(
            device,
            "parser.hir_match_payload_ordinal",
            tree_capacity as usize,
        );
        let hir_match_arm_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_match_arm_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_match_arm_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_match_arm_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_match_arm_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_match_arm_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_match_arm_previous =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let hir_match_payload_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_a, tree_capacity as usize);
        let hir_match_payload_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_b, tree_capacity as usize);
        let hir_match_payload_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_a, tree_capacity as usize);
        let hir_match_payload_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_b, tree_capacity as usize);
        let hir_match_payload_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_a, tree_capacity as usize);
        let hir_match_payload_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_b, tree_capacity as usize);
        let hir_match_rank_flag =
            alias_storage_buffer::<u32, u32>(&hir_rank_flag, tree_capacity as usize);
        let hir_match_rank_local_prefix =
            alias_storage_buffer::<u32, u32>(&hir_rank_local_prefix, tree_capacity as usize);
        let hir_match_rank_block_sum =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_sum, tree_n_node_blocks as usize);
        let hir_match_rank_block_prefix_a =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_a, tree_n_node_blocks as usize);
        let hir_match_rank_block_prefix_b =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_b, tree_n_node_blocks as usize);
        let hir_match_rank_node =
            alias_storage_buffer::<u32, u32>(&hir_rank_node, tree_capacity as usize);
        let hir_match_rank_count = alias_storage_buffer::<u32, u32>(&hir_rank_count, 1);
        let hir_match_rank_dispatch_args =
            alias_storage_buffer::<u32, u32>(&hir_rank_dispatch_args, 3);
        let hir_call_callee_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_callee_node",
            tree_capacity as usize,
        );
        let hir_call_arg_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_arg_start",
            tree_capacity as usize,
        );
        let hir_call_arg_end =
            storage_rw_for_array::<u32>(device, "parser.hir_call_arg_end", tree_capacity as usize);
        let hir_call_arg_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_arg_count",
            tree_capacity as usize,
        );
        let hir_call_arg_parent_call = storage_rw_for_array::<u32>(
            device,
            "parser.hir_call_arg_parent_ordinal",
            tree_capacity as usize,
        );
        let hir_call_arg_ordinal =
            alias_storage_buffer::<u32, u32>(&hir_call_arg_parent_call, tree_capacity as usize);
        let hir_call_arg_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_call_arg_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_call_arg_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_call_arg_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_call_arg_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_call_arg_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_array_lit_first_element = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_lit_first_element",
            tree_capacity as usize,
        );
        let hir_array_lit_element_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_lit_element_count",
            tree_capacity as usize,
        );
        let hir_array_element_parent_lit = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_element_parent_lit",
            tree_capacity as usize,
        );
        let hir_array_element_ordinal = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_element_ordinal",
            tree_capacity as usize,
        );
        let hir_array_element_next = storage_rw_for_array::<u32>(
            device,
            "parser.hir_array_element_next",
            tree_capacity as usize,
        );
        let hir_array_element_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_array_element_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_array_element_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_array_element_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_array_element_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_array_element_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_array_element_previous =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let hir_expr_form = storage_rw_for_array::<u32>(device, "parser.hir_expr_form", 1);
        let hir_expr_left_node =
            storage_rw_for_array::<u32>(device, "parser.hir_expr_left_node", 1);
        let hir_expr_right_node =
            storage_rw_for_array::<u32>(device, "parser.hir_expr_right_node", 1);
        let hir_expr_value_token =
            storage_rw_for_array::<u32>(device, "parser.hir_expr_value_token", 1);
        let hir_expr_record = storage_rw_for_array::<u32>(
            device,
            "parser.hir_expr_record",
            tree_capacity.saturating_mul(4) as usize,
        );
        let hir_expr_int_value = storage_rw_for_array::<u32>(
            device,
            "parser.hir_expr_int_value",
            tree_capacity as usize,
        );
        let hir_member_receiver_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_member_receiver_node",
            tree_capacity as usize,
        );
        let hir_member_receiver_token = storage_rw_for_array::<u32>(
            device,
            "parser.hir_member_receiver_token",
            tree_capacity as usize,
        );
        let hir_member_name_token = storage_rw_for_array::<u32>(
            device,
            "parser.hir_member_name_token",
            tree_capacity as usize,
        );
        let hir_stmt_record = storage_rw_for_array::<u32>(
            device,
            "parser.hir_stmt_record",
            tree_capacity.saturating_mul(4) as usize,
        );
        let hir_struct_field_parent_struct = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_field_parent_struct",
            tree_capacity as usize,
        );
        let hir_struct_field_ordinal = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_field_ordinal",
            tree_capacity as usize,
        );
        let hir_struct_field_type_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_field_type_node",
            tree_capacity as usize,
        );
        let hir_struct_decl_field_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_decl_field_start",
            tree_capacity as usize,
        );
        let hir_struct_decl_field_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_decl_field_count",
            tree_capacity as usize,
        );
        let hir_struct_lit_head_node = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_head_node",
            tree_capacity as usize,
        );
        let hir_struct_lit_field_start = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_field_start",
            tree_capacity as usize,
        );
        let hir_struct_lit_field_count = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_field_count",
            tree_capacity as usize,
        );
        let hir_struct_lit_field_parent_lit = storage_rw_for_array::<u32>(
            device,
            "parser.hir_struct_lit_field_parent_lit",
            tree_capacity as usize,
        );
        // Struct declaration fields and struct literal fields are disjoint HIR
        // node kinds. Store their per-field type/value child links in one
        // tree-capacity row and expose context-specific views to downstream
        // consumers.
        let hir_struct_lit_field_value_node =
            alias_storage_buffer::<u32, u32>(&hir_struct_field_type_node, tree_capacity as usize);
        // `prev_sibling` is consumed for the last time by
        // `hir_struct_field_links`. The following rank/scatter passes do not
        // read it, so the final struct-literal next-link output can reuse that
        // tree-sized buffer instead of retaining one more parser allocation.
        let hir_struct_lit_field_next =
            alias_storage_buffer::<u32, u32>(&prev_sibling, tree_capacity as usize);
        let hir_struct_field_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_a, tree_capacity as usize);
        let hir_struct_field_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_owner_b, tree_capacity as usize);
        let hir_struct_field_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_a, tree_capacity as usize);
        let hir_struct_field_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_link_b, tree_capacity as usize);
        let hir_struct_field_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_a, tree_capacity as usize);
        let hir_struct_field_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list0_rank_b, tree_capacity as usize);
        let hir_struct_lit_field_owner_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_a, tree_capacity as usize);
        let hir_struct_lit_field_owner_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_owner_b, tree_capacity as usize);
        let hir_struct_lit_field_link_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_a, tree_capacity as usize);
        let hir_struct_lit_field_link_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_link_b, tree_capacity as usize);
        let hir_struct_lit_field_rank_a =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_a, tree_capacity as usize);
        let hir_struct_lit_field_rank_b =
            alias_storage_buffer::<u32, u32>(&hir_list1_rank_b, tree_capacity as usize);
        let hir_struct_lit_field_previous =
            alias_storage_buffer::<u32, u32>(&hir_previous_scratch, tree_capacity as usize);
        let hir_struct_rank_flag =
            alias_storage_buffer::<u32, u32>(&hir_rank_flag, tree_capacity as usize);
        let hir_struct_rank_local_prefix =
            alias_storage_buffer::<u32, u32>(&hir_rank_local_prefix, tree_capacity as usize);
        let hir_struct_rank_block_sum =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_sum, tree_n_node_blocks as usize);
        let hir_struct_rank_block_prefix_a =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_a, tree_n_node_blocks as usize);
        let hir_struct_rank_block_prefix_b =
            alias_storage_buffer::<u32, u32>(&hir_rank_block_prefix_b, tree_n_node_blocks as usize);
        let hir_struct_rank_node =
            alias_storage_buffer::<u32, u32>(&hir_rank_node, tree_capacity as usize);
        let hir_struct_rank_count = alias_storage_buffer::<u32, u32>(&hir_rank_count, 1);
        let hir_struct_rank_dispatch_args =
            alias_storage_buffer::<u32, u32>(&hir_rank_dispatch_args, 3);
        let default_token_file_id = storage_rw_for_array::<u32>(
            device,
            "parser.default_token_file_id",
            n_tokens.max(1) as usize,
        );

        Self {
            n_tokens,
            n_kinds,
            total_sc,
            total_emit,
            tree_stream_uses_ll1,
            tree_count_uses_status,
            tree_capacity,

            ll1_predict,
            ll1_prod_rhs_off,
            ll1_prod_rhs_len,
            ll1_prod_rhs,
            ll1_emit,
            ll1_emit_pos,
            ll1_status,
            ll1_block_size: LL1_BLOCK_SIZE,
            ll1_n_blocks,
            ll1_block_emit_stride,
            ll1_params_base,
            params_ll1_blocks,
            ll1_block_seed_len,
            ll1_block_seed_stack,
            ll1_seed_plan_status,
            ll1_seeded_status,
            ll1_seeded_emit,
            ll1_seeded_emit_pos,
            ll1_emit_prefix_a,
            ll1_emit_prefix_b,
            ll1_status_summary_a,
            ll1_status_summary_b,
            ll1_emit_prefix_scan_steps,

            params_llp,
            semantic_token_kinds,
            token_delimiter_params,
            token_delimiter_scan_steps,
            token_input_capacity,
            token_delimiter_n_blocks,
            token_depth_brace_inblock,
            token_depth_bracket_inblock,
            token_block_sum_brace,
            token_block_sum_bracket,
            token_prefix_brace_a,
            token_prefix_brace_b,
            token_block_prefix_brace,
            token_prefix_bracket_a,
            token_prefix_bracket_b,
            token_block_prefix_bracket,
            token_top_brace_owner_block,
            token_top_brace_owner_prefix_a,
            token_top_brace_owner_prefix_b,
            token_top_brace_owner_block_prefix,
            token_statement_event_block,
            token_statement_event_prefix_a,
            token_statement_event_prefix_b,
            token_statement_event_block_prefix,
            token_brace_semantic_kind,
            token_bracket_semantic_kind,
            token_statement_context_kind,
            token_brace_match_params,
            token_brace_match_depth,
            token_brace_match_block_min,
            token_brace_match_min_tree_base,
            token_brace_match_min_tree,
            token_brace_match_min_tree_steps,
            token_feature_flags,
            token_count,
            default_token_file_id,
            active_pair_thread_dispatch_args,
            active_pair_group_dispatch_args,
            action_table,
            out_headers,

            params_pack,
            sc_offsets,
            emit_offsets,
            pack_sc_prefix_a,
            pack_sc_prefix_b,
            pack_emit_prefix_a,
            pack_emit_prefix_b,
            pack_offset_scan_steps,
            pack_total_reduce_steps,
            projected_status,
            tables_blob,
            out_sc,
            out_emit,
            out_emit_pos,

            b01_params,
            b02_params,
            b02_scan_steps,
            b03_params,
            b04_params,
            b05_params,
            b06_params,
            b07_params,
            b05_scan_steps,

            b_exscan_inblock,
            b_block_sum,
            b_block_minpref,
            b_block_maxdepth,
            b_block_prefix,
            b_block_prefix_sum_a,
            b_block_prefix_sum_b,
            b_block_prefix_min_a,
            b_block_prefix_min_b,

            depths_out,
            valid_out,

            b_depth_exscan,
            b_layer,

            b_hist_push,
            b_hist_pop,
            b_off_push,
            b_off_pop,
            b_cur_push,
            b_cur_pop,
            b_pushes_by_layer,
            b_pops_by_layer,
            b_slot_for_index,
            match_for_index,

            b_n_blocks: n_blocks,
            b_n_layers: n_layers,

            // Tree parent recovery
            tree_prefix_params,
            tree_prefix_scan_steps,
            tree_n_node_blocks,
            tree_n_prefix_blocks,
            tree_active_dispatch_args,
            tree_enum_dispatch_args,
            tree_match_dispatch_args,
            tree_struct_dispatch_args,
            hir_semantic_dispatch_args,
            tree_prefix_inblock,
            tree_block_sum,
            tree_block_prefix_a,
            tree_block_prefix_b,
            tree_block_prefix,
            tree_prefix,
            tree_prefix_block_max,
            tree_prefix_block_max_tree_base,
            tree_prefix_block_max_tree,
            tree_prefix_max_build_steps,
            tree_params,
            tree_span_params,
            tree_prev_sibling_params,
            prod_arity,
            node_kind,
            parent,
            first_child,
            next_sibling,
            prev_sibling,
            subtree_end,

            // HIR-facing classification
            hir_params,
            hir_span_params,
            hir_type_fields_params,
            hir_item_fields_params,
            hir_param_fields_params,
            hir_expr_fields_params,
            hir_member_fields_params,
            hir_stmt_fields_params,
            hir_call_fields_params,
            hir_array_fields_params,
            hir_enum_match_fields_params,
            hir_struct_fields_params,
            hir_kind,
            hir_semantic_block_count,
            hir_semantic_prefix_scan_steps,
            hir_semantic_flag,
            hir_semantic_local_prefix,
            hir_semantic_block_prefix_a,
            hir_semantic_block_prefix_b,
            hir_node_dense_id,
            hir_semantic_prefix_before_node,
            hir_semantic_dense_node,
            hir_semantic_subtree_end,
            hir_semantic_parent,
            hir_semantic_first_child,
            hir_semantic_next_sibling,
            hir_semantic_depth,
            hir_semantic_child_index,
            hir_semantic_parent_link_a,
            hir_semantic_parent_link_b,
            hir_semantic_parent_value_a,
            hir_semantic_parent_value_b,
            hir_semantic_depth_link_a,
            hir_semantic_depth_link_b,
            hir_semantic_depth_value_a,
            hir_semantic_depth_value_b,
            hir_semantic_child_index_link_a,
            hir_semantic_child_index_link_b,
            hir_semantic_child_index_rank_a,
            hir_semantic_child_index_rank_b,
            hir_semantic_count,
            hir_token_pos,
            hir_token_end,
            hir_token_file_id,
            hir_type_form,
            hir_type_value_node,
            hir_type_len_token,
            hir_type_len_value,
            hir_type_file_id,
            hir_type_path_leaf_node,
            hir_type_path_leaf_link_a,
            hir_type_path_leaf_link_b,
            hir_type_path_leaf_value_a,
            hir_type_path_leaf_value_b,
            hir_type_arg_start,
            hir_type_arg_count,
            hir_type_arg_next,
            hir_type_alias_target_node,
            hir_fn_return_type_node,
            hir_fn_signature_owner_link_a,
            hir_fn_signature_owner_link_b,
            hir_fn_signature_return_owner_a,
            hir_fn_signature_return_owner_b,
            hir_fn_signature_function_owner_a,
            hir_fn_signature_function_owner_b,
            hir_type_arg_owner_a,
            hir_type_arg_owner_b,
            hir_type_arg_link_a,
            hir_type_arg_link_b,
            hir_type_arg_rank_a,
            hir_type_arg_rank_b,
            hir_type_arg_previous,
            hir_type_alias_owner_link_a,
            hir_type_alias_owner_link_b,
            hir_type_alias_owner_value_a,
            hir_type_alias_owner_value_b,
            hir_item_kind,
            hir_item_name_token,
            hir_item_decl_token,
            hir_item_namespace,
            hir_item_visibility,
            hir_item_path_start,
            hir_item_path_end,
            hir_item_file_id,
            hir_item_import_target_kind,
            hir_param_record,
            hir_param_owner_a,
            hir_param_owner_b,
            hir_param_link_a,
            hir_param_link_b,
            hir_param_rank_a,
            hir_param_rank_b,
            hir_param_previous,
            hir_variant_parent_enum,
            hir_variant_ordinal,
            hir_variant_payload_start,
            hir_variant_payload_count,
            hir_variant_owner_a,
            hir_variant_owner_b,
            hir_variant_link_a,
            hir_variant_link_b,
            hir_variant_rank_a,
            hir_variant_rank_b,
            hir_variant_payload_owner_a,
            hir_variant_payload_owner_b,
            hir_variant_payload_link_a,
            hir_variant_payload_link_b,
            hir_variant_payload_rank_a,
            hir_variant_payload_rank_b,
            hir_list_rank_flag,
            hir_list_rank_local_prefix,
            hir_list_rank_block_sum,
            hir_list_rank_block_prefix_a,
            hir_list_rank_block_prefix_b,
            hir_list_rank_node,
            hir_list_rank_count,
            hir_list_rank_dispatch_args,
            hir_enum_rank_flag,
            hir_enum_rank_local_prefix,
            hir_enum_rank_block_sum,
            hir_enum_rank_block_prefix_a,
            hir_enum_rank_block_prefix_b,
            hir_enum_rank_node,
            hir_enum_rank_count,
            hir_enum_rank_dispatch_args,
            hir_match_scrutinee_node,
            hir_match_arm_start,
            hir_match_arm_count,
            hir_match_arm_next,
            hir_match_arm_pattern_node,
            hir_match_arm_payload_start,
            hir_match_arm_payload_count,
            hir_match_arm_result_node,
            hir_match_payload_owner_arm,
            hir_match_payload_match_node,
            hir_match_payload_ordinal,
            hir_match_arm_owner_a,
            hir_match_arm_owner_b,
            hir_match_arm_link_a,
            hir_match_arm_link_b,
            hir_match_arm_rank_a,
            hir_match_arm_rank_b,
            hir_match_arm_previous,
            hir_match_payload_owner_a,
            hir_match_payload_owner_b,
            hir_match_payload_link_a,
            hir_match_payload_link_b,
            hir_match_payload_rank_a,
            hir_match_payload_rank_b,
            hir_match_rank_flag,
            hir_match_rank_local_prefix,
            hir_match_rank_block_sum,
            hir_match_rank_block_prefix_a,
            hir_match_rank_block_prefix_b,
            hir_match_rank_node,
            hir_match_rank_count,
            hir_match_rank_dispatch_args,
            hir_call_callee_node,
            hir_call_arg_start,
            hir_call_arg_end,
            hir_call_arg_count,
            hir_call_arg_parent_call,
            hir_call_arg_ordinal,
            hir_call_arg_owner_a,
            hir_call_arg_owner_b,
            hir_call_arg_link_a,
            hir_call_arg_link_b,
            hir_call_arg_rank_a,
            hir_call_arg_rank_b,
            hir_array_lit_first_element,
            hir_array_lit_element_count,
            hir_array_element_parent_lit,
            hir_array_element_ordinal,
            hir_array_element_next,
            hir_array_element_owner_a,
            hir_array_element_owner_b,
            hir_array_element_link_a,
            hir_array_element_link_b,
            hir_array_element_rank_a,
            hir_array_element_rank_b,
            hir_array_element_previous,
            hir_expr_form,
            hir_expr_left_node,
            hir_expr_right_node,
            hir_expr_value_token,
            hir_expr_record,
            hir_expr_int_value,
            hir_member_receiver_node,
            hir_member_receiver_token,
            hir_member_name_token,
            hir_stmt_record,
            hir_struct_field_parent_struct,
            hir_struct_field_ordinal,
            hir_struct_field_type_node,
            hir_struct_decl_field_start,
            hir_struct_decl_field_count,
            hir_struct_lit_head_node,
            hir_struct_lit_field_start,
            hir_struct_lit_field_count,
            hir_struct_lit_field_parent_lit,
            hir_struct_lit_field_value_node,
            hir_struct_lit_field_next,
            hir_struct_field_owner_a,
            hir_struct_field_owner_b,
            hir_struct_field_link_a,
            hir_struct_field_link_b,
            hir_struct_field_rank_a,
            hir_struct_field_rank_b,
            hir_struct_lit_field_owner_a,
            hir_struct_lit_field_owner_b,
            hir_struct_lit_field_link_a,
            hir_struct_lit_field_link_b,
            hir_struct_lit_field_rank_a,
            hir_struct_lit_field_rank_b,
            hir_struct_lit_field_previous,
            hir_struct_rank_flag,
            hir_struct_rank_local_prefix,
            hir_struct_rank_block_sum,
            hir_struct_rank_block_prefix_a,
            hir_struct_rank_block_prefix_b,
            hir_struct_rank_node,
            hir_struct_rank_count,
            hir_struct_rank_dispatch_args,
        }
    }
}

pub struct BracketsHistogramScanStep {
    pub params: LaniusBuffer<super::passes::brackets_05::Params>,
    pub read_from_offsets: bool,
    pub write_to_offsets: bool,
}

pub struct BracketsBlockPrefixScanStep {
    pub params: LaniusBuffer<super::passes::brackets_02::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct TreePrefixScanStep {
    pub params: LaniusBuffer<super::passes::tree_prefix_01::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct TreePrefixMaxBuildStep {
    pub params: LaniusBuffer<super::passes::tree_prefix_04::Params>,
    pub work_items: u32,
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::parser::tables::PrecomputedParseTables;

    #[test]
    fn live_parser_does_not_select_legacy_ll1_tree_stream() {
        let mut tables = PrecomputedParseTables::new(4, 1);
        tables.n_nonterminals = 1;
        tables.ll1_predict = vec![0; tables.n_kinds as usize];
        tables.pp_superseq = vec![1, 2, 3];

        assert!(!parser_table_uses_ll1_tree_stream(&tables));
    }

    #[test]
    fn legacy_pair_capacity_only_shrinks_when_legacy_ll1_mode_is_explicit() {
        assert_eq!(legacy_pair_capacity_for(false, 50_000), 50_000);
        assert_eq!(legacy_pair_capacity_for(true, 50_000), 1);
        assert_eq!(legacy_pair_capacity_for(false, 0), 1);
    }

    #[test]
    fn resident_tree_capacity_is_capacity_derived_and_bounded() {
        assert_eq!(
            resident_projected_tree_capacity(10_000, 1_000_000),
            1_000_000
        );
        assert_eq!(resident_projected_tree_capacity(10_000, 25_000), 25_000);
        assert_eq!(resident_projected_tree_capacity(0, 0), 1);
    }

    #[test]
    fn resident_tree_capacity_from_tables_is_bounded_by_table_projection() {
        let mut tables = PrecomputedParseTables::new(4, 1);
        tables.pp_len = vec![0, 7, 3, 1];

        assert_eq!(
            resident_projected_tree_capacity_for_tables(10_000, &tables),
            69_993
        );
    }
}
