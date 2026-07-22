use encase::ShaderType;

use super::{
    BracketsBlockPrefixScanStep,
    HirSemanticPrefixScanStep,
    PackOffsetScanStep,
    PackTotalReduceStep,
    TokenDelimiterScanStep,
    TreePrefixMaxBuildStep,
    TreePrefixScanStep,
};
use crate::gpu::buffers::LaniusBuffer;

#[repr(C)]
#[derive(Clone, Copy, ShaderType, Default)]
/// Packed parser action header for one adjacent token-kind pair.
pub struct ActionHeader {
    pub push_len: u32,
    pub emit_len: u32,
    pub pop_tag: u32,
    pub pop_count: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for parser token-delimiter scans.
pub struct TokenDelimiterParams {
    pub n_tokens: u32,
    pub n_blocks: u32,
    pub scan_step: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for token brace/delimiter matching passes.
pub struct TokenBraceMatchParams {
    pub n_tokens: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
/// Dense canonical HIR identity and source span.
pub struct HirCore {
    pub kind: u32,
    pub parent: u32,
    pub token_start: u32,
    pub token_end: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
/// Dense canonical HIR navigation and source-file identity.
pub struct HirLinks {
    pub first_child: u32,
    pub next_sibling: u32,
    pub subtree_end: u32,
    pub file_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
/// Kind-dependent canonical HIR payload.
pub struct HirPayload {
    pub a: u32,
    pub b: u32,
    pub c: u32,
    pub d: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
/// Packed range into one compact HIR side table. Empty owners use
/// `{ start: INVALID, count: 0 }`.
pub struct HirRange {
    pub start: u32,
    pub count: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
pub struct HirCallArg {
    pub call: u32,
    pub value: u32,
    pub ordinal: u32,
    pub file_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
pub struct HirParam {
    pub owner: u32,
    pub name_token: u32,
    pub type_node: u32,
    pub ordinal: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
pub struct HirTypeArg {
    pub owner: u32,
    pub value: u32,
    pub ordinal: u32,
    pub file_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
pub struct HirGenericParam {
    pub owner: u32,
    pub name_token: u32,
    pub kind: u32,
    pub file_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
pub struct HirPath {
    pub owner: u32,
    pub segment_start: u32,
    pub segment_count: u32,
    pub kind: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
pub struct HirPathSegment {
    pub path: u32,
    pub name_token: u32,
    pub ordinal: u32,
    pub file_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
/// A compact aggregate field. `value` is a type for struct declarations and
/// an expression for struct literals, as determined by the dense owner kind.
pub struct HirField {
    pub owner: u32,
    pub name_token: u32,
    pub value: u32,
    pub ordinal: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
pub struct HirVariant {
    pub owner: u32,
    pub name_token: u32,
    pub ordinal: u32,
    pub file_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
pub struct HirVariantPayload {
    pub variant: u32,
    pub type_node: u32,
    pub ordinal: u32,
    pub file_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
pub struct HirMatchArm {
    pub owner: u32,
    pub pattern: u32,
    pub result: u32,
    pub ordinal: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
pub struct HirMatchPayload {
    pub arm: u32,
    pub pattern: u32,
    pub ordinal: u32,
    pub file_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
pub struct HirArrayElement {
    pub array: u32,
    pub value: u32,
    pub ordinal: u32,
    pub file_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
/// One decoded string literal. `node` is a dense canonical HIR ID and the
/// byte range addresses the separately compacted decoded string pool.
pub struct HirString {
    pub node: u32,
    pub data_offset: u32,
    pub decoded_len: u32,
    pub file_id: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
pub struct HirMethodCore {
    pub node: u32,
    pub owner: u32,
    pub impl_node: u32,
    pub name_token: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
pub struct HirMethodSignature {
    pub first_param_token: u32,
    pub impl_receiver_type: u32,
    pub receiver_mode: u32,
    /// Visibility in the low 16 bits and signature flags in the high 16 bits.
    pub metadata: u32,
}

#[repr(C)]
#[derive(Clone, Copy, Debug, Default, ShaderType, PartialEq, Eq)]
/// One compact trait obligation. `subject` is a token for generic bounds and
/// a dense HIR type for trait impls, as selected by the low metadata byte.
/// The remaining metadata bits contain the source file id.
pub struct HirPredicate {
    pub owner: u32,
    pub subject: u32,
    pub bound: u32,
    pub metadata: u32,
}

/// Allocation-free handle set for the compact parser phase artifact.
///
/// Cloning this view only clones `wgpu::Buffer` handles. It deliberately does
/// not expose raw production rows, so consumers migrated to this boundary
/// cannot accidentally re-derive semantics from parser scaffolding.
#[derive(Clone)]
pub struct GpuHirView {
    pub capacity: u32,
    pub count: LaniusBuffer<u32>,
    pub core: LaniusBuffer<HirCore>,
    pub links: LaniusBuffer<HirLinks>,
    pub payload: LaniusBuffer<HirPayload>,
    /// Lexical source-token scope end keyed by dense declaration HIR id.
    pub scope_end: LaniusBuffer<u32>,
    /// Dense nearest enclosing loop keyed by dense HIR id.
    pub nearest_loop: LaniusBuffer<u32>,
    /// Dense nearest enclosing block keyed by dense HIR id.
    pub nearest_block: LaniusBuffer<u32>,
    /// Dense nearest enclosing control-flow statement keyed by dense HIR id.
    pub nearest_control: LaniusBuffer<u32>,
    /// Dense nearest enclosing function keyed by dense HIR id.
    pub nearest_fn: LaniusBuffer<u32>,
    /// Dense return-type HIR id keyed by dense function HIR id.
    pub fn_return_type: LaniusBuffer<u32>,
    /// Dense target-type HIR id keyed by dense type-alias declaration HIR id.
    pub type_alias_target: LaniusBuffer<u32>,
    /// Dense annotated-type HIR id keyed by dense constant declaration HIR id.
    pub const_type: LaniusBuffer<u32>,
    /// Dense initializer-expression HIR id keyed by dense constant declaration HIR id.
    pub const_value: LaniusBuffer<u32>,
    /// Dense expression owner keyed by dense expression HIR id.
    pub expr_parent: LaniusBuffer<u32>,
    /// Final dense expression-tree root keyed by dense expression HIR id.
    pub expr_root: LaniusBuffer<u32>,
    pub call_arg_count: LaniusBuffer<u32>,
    pub call_args: LaniusBuffer<HirCallArg>,
    pub param_count: LaniusBuffer<u32>,
    pub params: LaniusBuffer<HirParam>,
    pub param_ranges: LaniusBuffer<HirRange>,
    pub type_arg_count: LaniusBuffer<u32>,
    pub type_args: LaniusBuffer<HirTypeArg>,
    pub type_arg_ranges: LaniusBuffer<HirRange>,
    pub generic_param_count: LaniusBuffer<u32>,
    pub generic_params: LaniusBuffer<HirGenericParam>,
    pub generic_param_ranges: LaniusBuffer<HirRange>,
    pub path_count: LaniusBuffer<u32>,
    pub paths: LaniusBuffer<HirPath>,
    pub path_segment_count: LaniusBuffer<u32>,
    pub path_segments: LaniusBuffer<HirPathSegment>,
    pub field_count: LaniusBuffer<u32>,
    pub fields: LaniusBuffer<HirField>,
    pub variant_count: LaniusBuffer<u32>,
    pub variants: LaniusBuffer<HirVariant>,
    pub variant_payload_start: LaniusBuffer<u32>,
    pub variant_payload_count: LaniusBuffer<u32>,
    pub variant_payload_row_count: LaniusBuffer<u32>,
    pub variant_payloads: LaniusBuffer<HirVariantPayload>,
    pub match_arm_count: LaniusBuffer<u32>,
    pub match_arms: LaniusBuffer<HirMatchArm>,
    pub match_payload_start: LaniusBuffer<u32>,
    pub match_payload_count: LaniusBuffer<u32>,
    pub match_payload_row_count: LaniusBuffer<u32>,
    pub match_payloads: LaniusBuffer<HirMatchPayload>,
    pub array_element_start: LaniusBuffer<u32>,
    pub array_element_count: LaniusBuffer<u32>,
    pub array_element_row_count: LaniusBuffer<u32>,
    pub array_elements: LaniusBuffer<HirArrayElement>,
    pub string_count: LaniusBuffer<u32>,
    pub strings: LaniusBuffer<HirString>,
    pub string_data_words: LaniusBuffer<u32>,
    pub string_pool_len: LaniusBuffer<u32>,
    pub method_count: LaniusBuffer<u32>,
    pub method_cores: LaniusBuffer<HirMethodCore>,
    pub method_signatures: LaniusBuffer<HirMethodSignature>,
    pub predicate_count: LaniusBuffer<u32>,
    pub predicates: LaniusBuffer<HirPredicate>,
}

/// All GPU-side buffers for the parser pipeline.
///
/// This struct owns resident GPU storage and uniform buffers only; readback and
/// staging buffers live in driver/result objects.
pub struct ParserBuffers {
    pub source_capacity: u32,
    // sizes
    pub n_tokens: u32,
    pub n_kinds: u32,
    pub total_sc: u32,
    pub total_emit: u32,
    pub tree_count_uses_status: bool,
    pub tree_capacity: u32,
    /// Conservative GPU-lexer feature summary used to size optional HIR families.
    pub parser_feature_flags: u32,
    pub hir_array_capacity: u32,
    pub hir_enum_match_capacity: u32,
    pub hir_struct_capacity: u32,
    pub hir_canonical_capacity: u32,

    // canonical LL(1) parser tables and outputs
    pub ll1_predict: LaniusBuffer<u32>,
    pub ll1_prod_rhs_off: LaniusBuffer<u32>,
    pub ll1_prod_rhs_len: LaniusBuffer<u32>,
    pub ll1_prod_rhs: LaniusBuffer<u32>,
    pub ll1_emit: LaniusBuffer<u32>,
    pub ll1_emit_pos: LaniusBuffer<u32>,
    pub ll1_status: LaniusBuffer<u32>,

    // pair-to-header
    pub params_llp: LaniusBuffer<super::super::passes::llp_pairs::LLPParams>,
    pub semantic_token_kinds: LaniusBuffer<u32>,
    pub token_delimiter_params: LaniusBuffer<TokenDelimiterParams>,
    pub token_delimiter_scan_steps: Vec<TokenDelimiterScanStep>,
    pub token_input_capacity: u32,
    pub token_delimiter_n_blocks: u32,
    pub token_depth_paren_inblock: LaniusBuffer<i32>,
    pub token_depth_brace_inblock: LaniusBuffer<i32>,
    pub token_depth_bracket_inblock: LaniusBuffer<i32>,
    pub token_depth_angle_inblock: LaniusBuffer<i32>,
    pub token_block_sum_paren: LaniusBuffer<i32>,
    pub token_block_sum_brace: LaniusBuffer<i32>,
    pub token_block_sum_bracket: LaniusBuffer<i32>,
    pub token_block_sum_angle: LaniusBuffer<i32>,
    pub token_prefix_paren_a: LaniusBuffer<i32>,
    pub token_prefix_paren_b: LaniusBuffer<i32>,
    pub token_block_prefix_paren: LaniusBuffer<i32>,
    pub token_prefix_brace_a: LaniusBuffer<i32>,
    pub token_prefix_brace_b: LaniusBuffer<i32>,
    pub token_block_prefix_brace: LaniusBuffer<i32>,
    pub token_prefix_bracket_a: LaniusBuffer<i32>,
    pub token_prefix_bracket_b: LaniusBuffer<i32>,
    pub token_block_prefix_bracket: LaniusBuffer<i32>,
    pub token_prefix_angle_a: LaniusBuffer<i32>,
    pub token_prefix_angle_b: LaniusBuffer<i32>,
    pub token_block_prefix_angle: LaniusBuffer<i32>,
    pub token_top_brace_owner_block: LaniusBuffer<u32>,
    pub token_top_brace_owner_prefix_a: LaniusBuffer<u32>,
    pub token_top_brace_owner_prefix_b: LaniusBuffer<u32>,
    pub token_top_brace_owner_block_prefix: LaniusBuffer<u32>,
    pub token_statement_event_block: LaniusBuffer<u32>,
    pub token_statement_event_prefix_a: LaniusBuffer<u32>,
    pub token_statement_event_prefix_b: LaniusBuffer<u32>,
    pub token_statement_event_block_prefix: LaniusBuffer<u32>,
    pub token_brace_semantic_kind: LaniusBuffer<u32>,
    pub token_braced_rhs_statement_kind: LaniusBuffer<u32>,
    pub token_bracket_semantic_kind: LaniusBuffer<u32>,
    pub token_statement_context_kind: LaniusBuffer<u32>,
    pub token_impl_header_kind: LaniusBuffer<u32>,
    pub token_impl_context_event: LaniusBuffer<u32>,
    pub token_type_path_context_kind: LaniusBuffer<u32>,
    pub token_where_context_event: LaniusBuffer<u32>,
    pub token_match_pattern_context_event: LaniusBuffer<u32>,
    // Parser-owned contextual splitting for a raw `>>` token.  The local and
    // block summaries use the clamped stack-effect monoid (sum, min-prefix),
    // so expression shifts cannot make later generic nesting negative.
    pub token_generic_shr_block_sum: LaniusBuffer<i32>,
    pub token_generic_shr_block_min: LaniusBuffer<i32>,
    pub token_generic_shr_prefix_sum_a: LaniusBuffer<i32>,
    pub token_generic_shr_prefix_sum_b: LaniusBuffer<i32>,
    pub token_generic_shr_prefix_min_a: LaniusBuffer<i32>,
    pub token_generic_shr_prefix_min_b: LaniusBuffer<i32>,
    pub token_generic_shr_block_prefix_sum: LaniusBuffer<i32>,
    pub token_generic_shr_block_prefix_min: LaniusBuffer<i32>,
    // Delimiter-pair match records.
    pub token_brace_match_params: LaniusBuffer<TokenBraceMatchParams>,
    pub token_brace_match_depth: LaniusBuffer<i32>,
    pub token_brace_match_block_min: LaniusBuffer<i32>,
    pub token_brace_match_min_tree_base: u32,
    pub token_brace_match_min_tree: LaniusBuffer<i32>,
    pub token_brace_match_min_tree_steps: Vec<TreePrefixMaxBuildStep>,
    pub token_bracket_match_depth: LaniusBuffer<i32>,
    pub token_bracket_match_block_min: LaniusBuffer<i32>,
    pub token_bracket_match_min_tree: LaniusBuffer<i32>,
    pub token_paren_match_depth: LaniusBuffer<i32>,
    pub token_paren_match_block_min: LaniusBuffer<i32>,
    pub token_paren_match_min_tree: LaniusBuffer<i32>,
    pub token_angle_match_depth: LaniusBuffer<i32>,
    pub token_angle_match_block_min: LaniusBuffer<i32>,
    pub token_angle_match_min_tree: LaniusBuffer<i32>,
    pub token_feature_flags: LaniusBuffer<u32>,
    pub token_count: LaniusBuffer<u32>,
    pub default_token_file_id: LaniusBuffer<u32>,
    pub source_file_token_end_params:
        LaniusBuffer<super::super::passes::source_file_token_end::Params>,
    pub source_file_token_end: LaniusBuffer<u32>,
    pub active_pair_thread_dispatch_args: LaniusBuffer<u32>,
    pub active_pair_group_dispatch_args: LaniusBuffer<u32>,
    pub action_table: LaniusBuffer<u8>,
    pub out_headers: LaniusBuffer<ActionHeader>,

    // pack varlen
    pub params_pack: LaniusBuffer<super::super::passes::pack::varlen::PackParams>,
    pub sc_offsets: LaniusBuffer<u32>,
    pub emit_offsets: LaniusBuffer<u32>,
    pub pack_sc_prefix_a: LaniusBuffer<u32>,
    pub pack_sc_prefix_b: LaniusBuffer<u32>,
    pub pack_emit_prefix_a: LaniusBuffer<u32>,
    pub pack_emit_prefix_b: LaniusBuffer<u32>,
    pub pack_offset_scan_steps: Vec<PackOffsetScanStep>,
    pub pack_total_reduce_steps: Vec<PackTotalReduceStep>,
    pub partial_parse_status: LaniusBuffer<u32>,
    pub tables_blob: LaniusBuffer<u32>,
    pub out_sc: LaniusBuffer<u32>,
    pub out_emit: LaniusBuffer<u32>,
    pub out_emit_pos: LaniusBuffer<u32>,

    // -------- Brackets (parallel) --------
    pub b01_params: LaniusBuffer<super::super::passes::brackets::scan_inblock::Params>,
    pub b02_params: LaniusBuffer<super::super::passes::brackets::scan_block_prefix::Params>,
    pub b02_scan_steps: Vec<BracketsBlockPrefixScanStep>,
    pub b03_params: LaniusBuffer<super::super::passes::brackets::apply_prefix::Params>,
    pub b07_params: LaniusBuffer<super::super::passes::brackets::pse_pair::Params>, // PSE-style pair-by-layer
    pub b_clear_matches_params: LaniusBuffer<super::super::passes::brackets::clear_matches::Params>,
    pub emit_stack_matches: bool,
    pub b_min_tree_base: u32,
    pub b_min_tree: LaniusBuffer<i32>,
    pub b_min_tree_steps: Vec<TreePrefixMaxBuildStep>,
    pub b_exscan_inblock: LaniusBuffer<i32>,
    pub b_block_sum: LaniusBuffer<i32>,
    pub b_block_minpref: LaniusBuffer<i32>,
    pub b_block_row_min: LaniusBuffer<i32>,
    pub b_block_maxdepth: LaniusBuffer<i32>,
    pub b_block_prefix: LaniusBuffer<i32>,
    pub b_block_prefix_sum_a: LaniusBuffer<i32>,
    pub b_block_prefix_sum_b: LaniusBuffer<i32>,
    pub b_block_prefix_min_a: LaniusBuffer<i32>,
    pub b_block_prefix_min_b: LaniusBuffer<i32>,

    pub depths_out: LaniusBuffer<i32>, // [final, min, conservative max active layer]
    pub valid_out: LaniusBuffer<u32>,

    pub b_layer: LaniusBuffer<u32>,
    pub match_for_index: LaniusBuffer<u32>,

    // counts used at dispatch
    pub b_n_blocks: u32,

    // -------- Tree parent recovery --------
    pub tree_prefix_params: LaniusBuffer<super::super::passes::tree::prefix::local::Params>,
    pub tree_prefix_scan_steps: Vec<TreePrefixScanStep>,
    pub tree_n_node_blocks: u32,
    pub tree_n_prefix_blocks: u32,
    pub tree_active_dispatch_args: LaniusBuffer<u32>,
    pub tree_enum_dispatch_args: LaniusBuffer<u32>,
    pub tree_match_dispatch_args: LaniusBuffer<u32>,
    pub tree_struct_dispatch_args: LaniusBuffer<u32>,
    pub tree_pointer_jump_dispatch_args: LaniusBuffer<u32>,
    pub hir_semantic_dispatch_args: LaniusBuffer<u32>,
    pub hir_semantic_depth_block_max: LaniusBuffer<u32>,
    pub hir_semantic_pointer_jump_dispatch_args: LaniusBuffer<u32>,
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
    pub tree_params: LaniusBuffer<super::super::passes::tree::parent::Params>,
    pub tree_span_params: LaniusBuffer<super::super::passes::tree::spans::Params>,
    pub tree_prev_sibling_params:
        LaniusBuffer<super::super::passes::tree::prev::sibling::clear::Params>,
    pub prod_arity: LaniusBuffer<u32>,
    pub node_kind: LaniusBuffer<u32>,
    pub parent: LaniusBuffer<u32>,
    pub first_child: LaniusBuffer<u32>,
    pub next_sibling: LaniusBuffer<u32>,
    pub prev_sibling: LaniusBuffer<u32>,
    pub subtree_end: LaniusBuffer<u32>,

    // -------- HIR-facing classification --------
    pub hir_params: LaniusBuffer<super::super::passes::hir::nodes::Params>,
    pub hir_span_params: LaniusBuffer<super::super::passes::hir::spans::Params>,
    pub hir_type_fields_params: LaniusBuffer<super::super::passes::hir::types::fields::Params>,
    pub hir_item_fields_params: LaniusBuffer<super::super::passes::hir::item::fields::Params>,
    pub hir_param_fields_params: LaniusBuffer<super::super::passes::hir::param::fields::Params>,
    pub hir_method_fields_params: LaniusBuffer<super::super::passes::hir::method::fields::Params>,
    pub hir_expr_fields_params: LaniusBuffer<super::super::passes::hir::expr::fields::Params>,
    pub hir_member_fields_params: LaniusBuffer<super::super::passes::hir::member::fields::Params>,
    pub hir_stmt_fields_params: LaniusBuffer<super::super::passes::hir::stmt_fields::Params>,
    pub hir_call_fields_params: LaniusBuffer<super::super::passes::hir::call::fields::Params>,
    pub hir_array_fields_params: LaniusBuffer<super::super::passes::hir::array::fields::Params>,
    pub hir_enum_match_fields_params:
        LaniusBuffer<super::super::passes::hir::enums::match_fields::Params>,
    pub hir_struct_fields_params: LaniusBuffer<super::super::passes::hir::structs::fields::Params>,
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
    // -------- Canonical dense HIR phase boundary --------
    pub hir_canonical_params:
        LaniusBuffer<super::super::passes::hir::canonical::CanonicalHirParams>,
    pub hir_canonical_count: LaniusBuffer<u32>,
    pub hir_canonical_status: LaniusBuffer<u32>,
    /// Winning raw-node-plus-one for each source-token anchor. Zero means no
    /// canonical node claimed the token.
    pub hir_canonical_anchor_owner: LaniusBuffer<u32>,
    /// Prefix-before value for every raw parse node. It is a dense id only
    /// when `hir_semantic_flag[raw]` is set by the canonical mark pass.
    pub hir_canonical_prefix_before_raw: LaniusBuffer<u32>,
    pub hir_canonical_dense_to_raw: LaniusBuffer<u32>,
    pub hir_canonical_raw_to_dense: LaniusBuffer<u32>,
    pub hir_core: LaniusBuffer<HirCore>,
    pub hir_links: LaniusBuffer<HirLinks>,
    pub hir_payload: LaniusBuffer<HirPayload>,
    pub hir_canonical_scope_end: LaniusBuffer<u32>,
    pub hir_canonical_nearest_loop: LaniusBuffer<u32>,
    pub hir_canonical_nearest_block: LaniusBuffer<u32>,
    pub hir_canonical_nearest_control: LaniusBuffer<u32>,
    pub hir_canonical_nearest_fn: LaniusBuffer<u32>,
    pub hir_canonical_fn_return_type: LaniusBuffer<u32>,
    pub hir_canonical_type_alias_target: LaniusBuffer<u32>,
    pub hir_canonical_const_type: LaniusBuffer<u32>,
    pub hir_canonical_const_value: LaniusBuffer<u32>,
    pub hir_canonical_expr_parent_encoded: LaniusBuffer<u32>,
    pub hir_canonical_expr_parent: LaniusBuffer<u32>,
    pub hir_canonical_expr_root: LaniusBuffer<u32>,
    pub hir_canonical_expr_root_scratch: LaniusBuffer<u32>,
    pub hir_canonical_expr_forest_status: LaniusBuffer<u32>,
    pub hir_call_arg_table_count: LaniusBuffer<u32>,
    pub hir_call_arg_family_flag: LaniusBuffer<u32>,
    pub hir_call_args: LaniusBuffer<HirCallArg>,
    pub hir_param_table_count: LaniusBuffer<u32>,
    pub hir_param_family_flag: LaniusBuffer<u32>,
    pub hir_param_rows: LaniusBuffer<HirParam>,
    pub hir_param_ranges: LaniusBuffer<HirRange>,
    pub hir_type_arg_table_count: LaniusBuffer<u32>,
    pub hir_type_arg_family_flag: LaniusBuffer<u32>,
    pub hir_type_arg_rows: LaniusBuffer<HirTypeArg>,
    pub hir_type_arg_ranges: LaniusBuffer<HirRange>,
    pub hir_generic_param_table_count: LaniusBuffer<u32>,
    pub hir_generic_param_family_flag: LaniusBuffer<u32>,
    pub hir_generic_param_rows: LaniusBuffer<HirGenericParam>,
    pub hir_generic_param_ranges: LaniusBuffer<HirRange>,
    pub hir_path_table_count: LaniusBuffer<u32>,
    pub hir_path_family_flag: LaniusBuffer<u32>,
    pub hir_path_rows: LaniusBuffer<HirPath>,
    pub hir_path_segment_table_count: LaniusBuffer<u32>,
    pub hir_path_segment_family_flag: LaniusBuffer<u32>,
    pub hir_path_segment_rows: LaniusBuffer<HirPathSegment>,
    pub hir_field_table_count: LaniusBuffer<u32>,
    pub hir_field_family_flag: LaniusBuffer<u32>,
    pub hir_field_rows: LaniusBuffer<HirField>,
    pub hir_variant_table_count: LaniusBuffer<u32>,
    pub hir_variant_family_flag: LaniusBuffer<u32>,
    pub hir_variant_rows: LaniusBuffer<HirVariant>,
    pub hir_variant_raw_to_row: LaniusBuffer<u32>,
    pub hir_variant_compact_payload_start: LaniusBuffer<u32>,
    pub hir_variant_compact_payload_count: LaniusBuffer<u32>,
    pub hir_variant_payload_table_count: LaniusBuffer<u32>,
    pub hir_variant_payload_family_flag: LaniusBuffer<u32>,
    pub hir_variant_payload_rows: LaniusBuffer<HirVariantPayload>,
    pub hir_match_arm_table_count: LaniusBuffer<u32>,
    pub hir_match_arm_family_flag: LaniusBuffer<u32>,
    /// Phase-local raw match-arm to compact-row map. This aliases the variant
    /// map because all compact variant payloads have been materialized before
    /// compact match construction begins.
    pub hir_match_arm_raw_to_row: LaniusBuffer<u32>,
    pub hir_match_arm_rows: LaniusBuffer<HirMatchArm>,
    pub hir_match_compact_payload_start: LaniusBuffer<u32>,
    pub hir_match_compact_payload_count: LaniusBuffer<u32>,
    pub hir_match_payload_table_count: LaniusBuffer<u32>,
    pub hir_match_payload_family_flag: LaniusBuffer<u32>,
    pub hir_match_payload_rows: LaniusBuffer<HirMatchPayload>,
    pub hir_array_compact_element_start: LaniusBuffer<u32>,
    pub hir_array_compact_element_count: LaniusBuffer<u32>,
    pub hir_array_element_table_count: LaniusBuffer<u32>,
    pub hir_array_element_family_flag: LaniusBuffer<u32>,
    pub hir_array_element_rows: LaniusBuffer<HirArrayElement>,
    pub hir_canonical_string_rows: LaniusBuffer<HirString>,
    pub hir_method_table_count: LaniusBuffer<u32>,
    pub hir_method_family_flag: LaniusBuffer<u32>,
    pub hir_method_core_rows: LaniusBuffer<HirMethodCore>,
    pub hir_method_signature_rows: LaniusBuffer<HirMethodSignature>,
    pub hir_predicate_table_count: LaniusBuffer<u32>,
    pub hir_predicate_rows: LaniusBuffer<HirPredicate>,
    pub hir_token_pos: LaniusBuffer<u32>,
    pub hir_token_end: LaniusBuffer<u32>,
    pub hir_token_file_id: LaniusBuffer<u32>,
    pub hir_type_form: LaniusBuffer<u32>,
    pub hir_type_value_node: LaniusBuffer<u32>,
    pub hir_type_len_token: LaniusBuffer<u32>,
    pub hir_type_len_value: LaniusBuffer<u32>,
    pub hir_type_file_id: LaniusBuffer<u32>,
    pub hir_type_path_leaf_node: LaniusBuffer<u32>,
    pub hir_bound_path_owner_by_leaf: LaniusBuffer<u32>,
    pub hir_path_root_owner: LaniusBuffer<u32>,
    pub hir_path_segment_owner_a: LaniusBuffer<u32>,
    pub hir_path_segment_owner_b: LaniusBuffer<u32>,
    pub hir_path_segment_link_a: LaniusBuffer<u32>,
    pub hir_path_segment_link_b: LaniusBuffer<u32>,
    pub hir_path_segment_rank_a: LaniusBuffer<u32>,
    pub hir_path_segment_rank_b: LaniusBuffer<u32>,
    pub hir_path_segment_count: LaniusBuffer<u32>,
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
    /// Topmost parser-owned type-expression root for every HIR type node.
    pub hir_type_root_owner: LaniusBuffer<u32>,
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
    pub hir_item_path_node: LaniusBuffer<u32>,
    pub hir_item_file_id: LaniusBuffer<u32>,
    pub hir_item_import_target_kind: LaniusBuffer<u32>,
    pub hir_param_record: LaniusBuffer<u32>,
    pub hir_param_type_node: LaniusBuffer<u32>,
    pub hir_method_owner_node: LaniusBuffer<u32>,
    pub hir_method_impl_node: LaniusBuffer<u32>,
    pub hir_method_name_token: LaniusBuffer<u32>,
    pub hir_method_first_param_token: LaniusBuffer<u32>,
    pub hir_method_receiver_mode: LaniusBuffer<u32>,
    pub hir_method_visibility: LaniusBuffer<u32>,
    pub hir_method_signature_flags: LaniusBuffer<u32>,
    pub hir_method_impl_receiver_type_node: LaniusBuffer<u32>,
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
    pub hir_variant_payload_node: LaniusBuffer<u32>,
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
    pub hir_match_pattern_owner_arm: LaniusBuffer<u32>,
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
    pub hir_call_callee_path_node: LaniusBuffer<u32>,
    pub hir_call_parent_by_callee: LaniusBuffer<u32>,
    pub hir_call_context_stmt_node: LaniusBuffer<u32>,
    pub hir_call_arg_start: LaniusBuffer<u32>,
    pub hir_call_arg_end: LaniusBuffer<u32>,
    pub hir_call_arg_count: LaniusBuffer<u32>,
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
    pub hir_array_lit_context_stmt_node: LaniusBuffer<u32>,
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
    pub hir_expr_name_role: LaniusBuffer<u32>,
    pub hir_expr_result_node: LaniusBuffer<u32>,
    pub hir_expr_result_root_node: LaniusBuffer<u32>,
    pub hir_expr_result_root_scratch_node: LaniusBuffer<u32>,
    pub hir_expr_parent_node: LaniusBuffer<u32>,
    pub hir_expr_forest_root_node: LaniusBuffer<u32>,
    pub hir_expr_forest_status: LaniusBuffer<u32>,
    pub hir_binary_span_link_a: LaniusBuffer<u32>,
    pub hir_binary_span_link_b: LaniusBuffer<u32>,
    pub hir_binary_span_start_a: LaniusBuffer<u32>,
    pub hir_binary_span_start_b: LaniusBuffer<u32>,
    pub hir_expr_int_value: LaniusBuffer<u32>,
    pub hir_expr_float_bits: LaniusBuffer<u32>,
    pub hir_expr_string_start: LaniusBuffer<u32>,
    pub hir_expr_string_len: LaniusBuffer<u32>,
    pub hir_string_data_offset: LaniusBuffer<u32>,
    pub hir_string_decoded_len: LaniusBuffer<u32>,
    pub hir_string_data_words: LaniusBuffer<u32>,
    pub hir_string_pool_len: LaniusBuffer<u32>,
    pub hir_string_node: LaniusBuffer<u32>,
    pub hir_string_count: LaniusBuffer<u32>,
    pub hir_member_receiver_node: LaniusBuffer<u32>,
    pub hir_member_receiver_token: LaniusBuffer<u32>,
    pub hir_member_name_token: LaniusBuffer<u32>,
    pub hir_stmt_record: LaniusBuffer<u32>,
    pub hir_stmt_scope_end: LaniusBuffer<u32>,
    pub hir_nearest_stmt_node: LaniusBuffer<u32>,
    pub hir_nearest_block_node: LaniusBuffer<u32>,
    pub hir_nearest_enclosing_control_node: LaniusBuffer<u32>,
    pub hir_nearest_loop_node: LaniusBuffer<u32>,
    pub hir_nearest_fn_node: LaniusBuffer<u32>,
    pub hir_nearest_array_element_node: LaniusBuffer<u32>,
    pub hir_struct_field_parent_struct: LaniusBuffer<u32>,
    pub hir_struct_field_ordinal: LaniusBuffer<u32>,
    pub hir_struct_field_type_node: LaniusBuffer<u32>,
    pub hir_struct_decl_field_start: LaniusBuffer<u32>,
    pub hir_struct_decl_field_count: LaniusBuffer<u32>,
    pub hir_struct_lit_head_node: LaniusBuffer<u32>,
    pub hir_struct_lit_context_stmt_node: LaniusBuffer<u32>,
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
    pub hir_stmt_context_link_a: LaniusBuffer<u32>,
    pub hir_stmt_context_link_b: LaniusBuffer<u32>,
    pub hir_contextual_stmt_value_a: LaniusBuffer<u32>,
    pub hir_contextual_stmt_value_b: LaniusBuffer<u32>,
    pub hir_nearest_stmt_value_a: LaniusBuffer<u32>,
    pub hir_nearest_stmt_value_b: LaniusBuffer<u32>,
    pub hir_nearest_block_value_a: LaniusBuffer<u32>,
    pub hir_nearest_block_value_b: LaniusBuffer<u32>,
    pub hir_nearest_enclosing_control_value_a: LaniusBuffer<u32>,
    pub hir_nearest_enclosing_control_value_b: LaniusBuffer<u32>,
    pub hir_nearest_loop_value_a: LaniusBuffer<u32>,
    pub hir_nearest_loop_value_b: LaniusBuffer<u32>,
    pub hir_nearest_fn_value_a: LaniusBuffer<u32>,
    pub hir_nearest_fn_value_b: LaniusBuffer<u32>,
    pub hir_nearest_array_element_value_a: LaniusBuffer<u32>,
    pub hir_nearest_array_element_value_b: LaniusBuffer<u32>,
    pub hir_struct_rank_flag: LaniusBuffer<u32>,
    pub hir_struct_rank_local_prefix: LaniusBuffer<u32>,
    pub hir_struct_rank_block_sum: LaniusBuffer<u32>,
    pub hir_struct_rank_block_prefix_a: LaniusBuffer<u32>,
    pub hir_struct_rank_block_prefix_b: LaniusBuffer<u32>,
    pub hir_struct_rank_node: LaniusBuffer<u32>,
    pub hir_struct_rank_count: LaniusBuffer<u32>,
    pub hir_struct_rank_dispatch_args: LaniusBuffer<u32>,
}

impl GpuHirView {
    pub fn from_parser_buffers(buffers: &ParserBuffers) -> Self {
        Self {
            capacity: buffers.hir_canonical_capacity,
            count: buffers.hir_canonical_count.clone(),
            core: buffers.hir_core.clone(),
            links: buffers.hir_links.clone(),
            payload: buffers.hir_payload.clone(),
            scope_end: buffers.hir_canonical_scope_end.clone(),
            nearest_loop: buffers.hir_canonical_nearest_loop.clone(),
            nearest_block: buffers.hir_canonical_nearest_block.clone(),
            nearest_control: buffers.hir_canonical_nearest_control.clone(),
            nearest_fn: buffers.hir_canonical_nearest_fn.clone(),
            fn_return_type: buffers.hir_canonical_fn_return_type.clone(),
            type_alias_target: buffers.hir_canonical_type_alias_target.clone(),
            const_type: buffers.hir_canonical_const_type.clone(),
            const_value: buffers.hir_canonical_const_value.clone(),
            expr_parent: buffers.hir_canonical_expr_parent.clone(),
            expr_root: buffers.hir_canonical_expr_root.clone(),
            call_arg_count: buffers.hir_call_arg_table_count.clone(),
            call_args: buffers.hir_call_args.clone(),
            param_count: buffers.hir_param_table_count.clone(),
            params: buffers.hir_param_rows.clone(),
            param_ranges: buffers.hir_param_ranges.clone(),
            type_arg_count: buffers.hir_type_arg_table_count.clone(),
            type_args: buffers.hir_type_arg_rows.clone(),
            type_arg_ranges: buffers.hir_type_arg_ranges.clone(),
            generic_param_count: buffers.hir_generic_param_table_count.clone(),
            generic_params: buffers.hir_generic_param_rows.clone(),
            generic_param_ranges: buffers.hir_generic_param_ranges.clone(),
            path_count: buffers.hir_path_table_count.clone(),
            paths: buffers.hir_path_rows.clone(),
            path_segment_count: buffers.hir_path_segment_table_count.clone(),
            path_segments: buffers.hir_path_segment_rows.clone(),
            field_count: buffers.hir_field_table_count.clone(),
            fields: buffers.hir_field_rows.clone(),
            variant_count: buffers.hir_variant_table_count.clone(),
            variants: buffers.hir_variant_rows.clone(),
            variant_payload_start: buffers.hir_variant_compact_payload_start.clone(),
            variant_payload_count: buffers.hir_variant_compact_payload_count.clone(),
            variant_payload_row_count: buffers.hir_variant_payload_table_count.clone(),
            variant_payloads: buffers.hir_variant_payload_rows.clone(),
            match_arm_count: buffers.hir_match_arm_table_count.clone(),
            match_arms: buffers.hir_match_arm_rows.clone(),
            match_payload_start: buffers.hir_match_compact_payload_start.clone(),
            match_payload_count: buffers.hir_match_compact_payload_count.clone(),
            match_payload_row_count: buffers.hir_match_payload_table_count.clone(),
            match_payloads: buffers.hir_match_payload_rows.clone(),
            array_element_start: buffers.hir_array_compact_element_start.clone(),
            array_element_count: buffers.hir_array_compact_element_count.clone(),
            array_element_row_count: buffers.hir_array_element_table_count.clone(),
            array_elements: buffers.hir_array_element_rows.clone(),
            string_count: buffers.hir_string_count.clone(),
            strings: buffers.hir_canonical_string_rows.clone(),
            string_data_words: buffers.hir_string_data_words.clone(),
            string_pool_len: buffers.hir_string_pool_len.clone(),
            method_count: buffers.hir_method_table_count.clone(),
            method_cores: buffers.hir_method_core_rows.clone(),
            method_signatures: buffers.hir_method_signature_rows.clone(),
            predicate_count: buffers.hir_predicate_table_count.clone(),
            predicates: buffers.hir_predicate_rows.clone(),
        }
    }
}
