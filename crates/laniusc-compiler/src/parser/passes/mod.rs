//! Parser compute pass bundle and debug recording entry point.

use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::{
        buffers::LaniusBuffer,
        passes_core::{
            DispatchDim,
            InputElements,
            Pass,
            PassContext,
            PassData,
            record_reflected_compute,
        },
        timer::GpuTimer,
    },
    parser::{buffers::ParserBuffers, debug::DebugOutput},
};

#[derive(Clone, Copy)]
pub(in crate::parser) enum CanonicalConstruct {
    CallArgument,
    Parameter,
    TypeArgument,
    GenericParameter,
    Path,
    Field,
    Variant,
    VariantPayload,
    MatchArm,
    MatchPayload,
    ArrayElement,
    Method,
    Predicate,
}

impl CanonicalConstruct {
    pub(in crate::parser) const fn label(self) -> &'static str {
        match self {
            Self::CallArgument => "hir_canonical_call_arg_local",
            Self::Parameter => "hir_canonical_param_local",
            Self::TypeArgument => "hir_canonical_type_arg_local",
            Self::GenericParameter => "hir_canonical_generic_param_local",
            Self::Path => "hir_canonical_path_local",
            Self::Field => "hir_canonical_field_local",
            Self::Variant => "hir_canonical_variant_local",
            Self::VariantPayload => "hir_canonical_variant_payload_local",
            Self::MatchArm => "hir_canonical_match_arm_local",
            Self::MatchPayload => "hir_canonical_match_payload_local",
            Self::ArrayElement => "hir_canonical_array_element_local",
            Self::Method => "hir_canonical_method_local",
            Self::Predicate => "hir_canonical_predicate_local",
        }
    }

    pub(in crate::parser) const fn scan_label(self) -> &'static str {
        match self {
            Self::CallArgument => "hir_canonical_call_arg.scan_blocks",
            Self::Parameter => "hir_canonical_param.scan_blocks",
            Self::TypeArgument => "hir_canonical_type_arg.scan_blocks",
            Self::GenericParameter => "hir_canonical_generic_param.scan_blocks",
            Self::Path => "hir_canonical_path.scan_blocks",
            Self::Field => "hir_canonical_field.scan_blocks",
            Self::Variant => "hir_canonical_variant.scan_blocks",
            Self::VariantPayload => "hir_canonical_variant_payload.scan_blocks",
            Self::MatchArm => "hir_canonical_match_arm.scan_blocks",
            Self::MatchPayload => "hir_canonical_match_payload.scan_blocks",
            Self::ArrayElement => "hir_canonical_array_element.scan_blocks",
            Self::Method => "hir_canonical_method.scan_blocks",
            Self::Predicate => "hir_canonical_predicate.scan_blocks",
        }
    }

    fn flag(self, buffers: &ParserBuffers) -> &LaniusBuffer<u32> {
        match self {
            Self::CallArgument => &buffers.hir_call_arg_family_flag,
            Self::Parameter => &buffers.hir_param_family_flag,
            Self::TypeArgument => &buffers.hir_type_arg_family_flag,
            Self::GenericParameter => &buffers.hir_generic_param_family_flag,
            Self::Path => &buffers.hir_path_family_flag,
            Self::Field => &buffers.hir_field_family_flag,
            Self::Variant => &buffers.hir_variant_family_flag,
            Self::VariantPayload => &buffers.hir_variant_payload_family_flag,
            Self::MatchArm => &buffers.hir_match_arm_family_flag,
            Self::MatchPayload => &buffers.hir_match_payload_family_flag,
            Self::ArrayElement => &buffers.hir_array_element_family_flag,
            Self::Method | Self::Predicate => &buffers.hir_method_family_flag,
        }
    }
}

fn record_canonical_scan(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    passes: &ParserPasses,
    construct: CanonicalConstruct,
) -> Result<()> {
    let resources = HashMap::from([
        (
            "gScan".into(),
            ctx.buffers.hir_canonical_scan_params.as_entire_binding(),
        ),
        (
            "input".into(),
            construct.flag(ctx.buffers).as_entire_binding(),
        ),
        (
            "output_prefix".into(),
            ctx.buffers.hir_semantic_local_prefix.as_entire_binding(),
        ),
        (
            "block_sum".into(),
            ctx.buffers.hir_semantic_block_count.as_entire_binding(),
        ),
    ]);
    record_reflected_compute(
        ctx.device,
        ctx.encoder,
        ctx.maybe_timer,
        ctx.bg_cache.as_deref_mut(),
        ctx.buffers,
        &passes.exclusive_u32_local_scan,
        construct.label(),
        DispatchDim::D1,
        InputElements::Elements1D(ctx.buffers.hir_canonical_capacity),
        &resources,
    )
}

fn record_canonical_compaction_prefix(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    passes: &ParserPasses,
    construct: CanonicalConstruct,
) -> Result<()> {
    record_canonical_scan(ctx, passes, construct)?;
    passes.hir_semantic_prefix_blocks.record_compact_scan(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        ctx.bg_cache
            .as_deref_mut()
            .expect("parser scan requires a bind-group cache"),
        construct.scan_label(),
    )
}

/// Proof that every pass consuming raw expression records has been recorded.
/// Canonical identity takes ownership of the expression arena, so callers
/// cannot cross that boundary without first obtaining this marker.
pub(crate) struct RawExpressionRecordsFinalized(());

pub(crate) fn record_raw_expression_spans(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    passes: &ParserPasses,
    semantic_dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
    tree_dispatch_args: &crate::gpu::buffers::LaniusBuffer<u32>,
) -> Result<RawExpressionRecordsFinalized> {
    passes
        .hir_call_fields
        .record_pass_indirect(ctx, semantic_dispatch_args)?;
    passes
        .hir_call_spans
        .record_pass_indirect(ctx, semantic_dispatch_args)?;
    passes
        .hir_range_spans
        .record_pass_indirect(ctx, tree_dispatch_args)?;
    Ok(RawExpressionRecordsFinalized(()))
}

/// Delimiter pairing and bracket-layer passes.
pub mod brackets;
/// HIR classification, topology, and typed record passes.
pub mod hir;
/// Variable-length parse stream packing passes.
pub mod pack;
pub(in crate::parser) mod tokens;
/// Parser tree recovery passes.
pub mod tree;

/// Loaded compute passes for the parser pipeline.
pub struct ParserPasses {
    pub(in crate::parser) token_frontend: tokens::TokenFrontendPasses,
    pub(in crate::parser) active_pair_dispatch_args: PassData,
    pub(in crate::parser) tree_feature_dispatch_args: PassData,
    pub llp_pairs: pack::find_token_pair_actions::LLPPairsPass,
    pub pack_offsets: pack::scan_pack_offsets::PackOffsetsScanPass,
    pub pack_offsets_status: pack::publish_pack_offset_status::PackOffsetsStatusPass,
    pub pack_totals_blocks: pack::sum_pack_lengths_in_blocks::PackTotalsBlocksPass,
    pub pack_totals_reduce: pack::reduce_pack_length_sums::PackTotalsReducePass,
    pub pack_totals_status: pack::publish_pack_total_status::PackTotalsStatusPass,
    pub pack_varlen: pack::pack_stack_changes_and_productions::PackVarlenPass,
    pub status_from_brackets:
        brackets::combine_pack_and_bracket_status::ParserStatusFromBracketsPass,
    pub source_file_token_end: tree::find_source_file_token_ends::SourceFileTokenEndPass,

    // Bracket matching passes
    pub scan_bracket_depths_in_blocks:
        brackets::scan_bracket_depths_in_blocks::BracketsScanInblockPass,
    pub scan_bracket_blocks: brackets::scan_bracket_blocks::BracketsScanBlockPrefixPass,
    pub apply_bracket_block_prefix: brackets::apply_bracket_block_prefix::BracketsApplyPrefixPass,
    pub b_clear_matches: brackets::clear_bracket_matches::BracketsClearMatchesPass,
    pub b_min_tree: brackets::build_bracket_min_tree::BracketsMinTreePass,
    pub pair_brackets_by_layer: brackets::pair_brackets_by_layer::BracketsPsePairPass,

    // Tree building pass
    pub sum_arity_deficits_in_blocks: tree::sum_arity_deficits_in_blocks::TreePrefixLocalPass,
    pub scan_arity_deficit_blocks: tree::scan_arity_deficit_blocks::TreePrefixScanBlocksPass,
    pub apply_arity_deficit_prefix: tree::apply_arity_deficit_prefix::TreePrefixApplyPass,
    pub build_deficit_max_tree: tree::build_deficit_max_tree::TreePrefixMaxBuildPass,
    pub tree_active_dispatch_args:
        tree::write_active_node_dispatch_args::TreeActiveDispatchArgsPass,
    pub tree_parent: tree::find_tree_parents::TreeParentPass,
    pub tree_spans: tree::find_tree_spans::TreeSpansPass,
    pub tree_depth_block_max: tree::find_tree_depth_block_maxima::TreeDepthBlockMaxPass,
    pub tree_depth_schedule: tree::schedule_tree_depth_jumps::TreeDepthSchedulePass,
    pub tree_prev_sibling_clear: tree::clear_previous_siblings::TreePrevSiblingClearPass,
    pub tree_prev_sibling_scatter: tree::scatter_previous_siblings::TreePrevSiblingScatterPass,

    // HIR-facing classification
    pub hir_nodes: hir::records::classify_hir_nodes::HirNodesPass,
    pub hir_semantic_prefix_local: hir::semantic::mark_semantic_rows::HirSemanticPrefixLocalPass,
    pub hir_semantic_prefix_blocks:
        hir::semantic::scan_semantic_blocks::HirSemanticPrefixBlocksPass,
    pub hir_semantic_compact_scatter:
        hir::semantic::list_semantic_rows::HirSemanticCompactScatterPass,
    pub hir_semantic_dispatch_args:
        hir::semantic::write_semantic_dispatch_args::HirSemanticDispatchArgsPass,
    pub hir_semantic_subtree_end:
        hir::semantic::project_semantic_subtree_ends::HirSemanticSubtreeEndPass,
    pub hir_semantic_end_rows: hir::semantic::build_semantic_end_heaps::HirSemanticEndRowsPass,
    pub hir_semantic_end_blocks: hir::semantic::build_semantic_end_heaps::HirSemanticEndBlocksPass,
    pub hir_semantic_end_top: hir::semantic::build_semantic_end_heaps::HirSemanticEndTopPass,
    pub hir_semantic_parent_traverse:
        hir::semantic::find_semantic_parents::HirSemanticParentTraversePass,
    pub hir_tree_relations: hir::semantic::walk_semantic_parents::TreeRelationOperation,
    pub hir_semantic_nav: hir::semantic::project_semantic_navigation::HirSemanticNavPass,
    pub hir_semantic_child_index_blocks:
        hir::semantic::build_child_index_heaps::HirSemanticChildIndexBlocksPass,
    pub hir_semantic_child_index_top:
        hir::semantic::build_child_index_heaps::HirSemanticChildIndexTopPass,
    pub hir_semantic_child_index_traverse:
        hir::semantic::find_child_indices::HirSemanticChildIndexTraversePass,
    pub hir_record_clear_base: hir::records::clear_hir_records::HirRecordClearBasePass,
    pub hir_record_clear_calls:
        hir::records::clear_call_and_member_records::HirRecordClearCallsPass,
    pub hir_spans: hir::spans::compute_hir_spans::HirSpansPass,
    pub hir_type_fields: hir::records::extract_type_records::HirTypeFieldsPass,
    pub hir_type_path_leaf_scatter:
        hir::types::publish_type_path_leaves::HirTypePathLeafScatterPass,
    pub hir_path_segment_root: hir::paths::seed_path_roots::HirPathSegmentRootPass,
    pub hir_path_segment_scatter: hir::paths::publish_path_segments::HirPathSegmentScatterPass,
    pub hir_list_rank_prefix_local: hir::lists::mark_list_rows::HirListRankPrefixLocalPass,
    pub hir_list_rank_compact_scatter: hir::lists::compact_list_rows::HirListRankCompactScatterPass,
    pub hir_list_rank_step: hir::lists::rank_list_rows::HirListRankStepOperation,
    pub hir_type_arg_links: hir::lists::link_type_args::HirTypeArgLinksPass,
    pub hir_type_arg_scatter: hir::lists::publish_type_args::HirTypeArgScatterPass,
    pub hir_type_root_owner_init: hir::types::seed_type_roots::HirTypeRootOwnerInitPass,
    pub hir_type_root_owner_step: hir::types::walk_type_roots::HirTypeRootOwnerStepPass,
    pub hir_type_alias_owner_init: hir::types::seed_type_alias_owners::HirTypeAliasOwnerInitPass,
    pub hir_type_alias_owner_step: hir::types::walk_type_alias_owners::HirTypeAliasOwnerStepPass,
    pub hir_type_alias_target: hir::types::find_type_alias_targets::HirTypeAliasTargetPass,
    pub hir_method_signature_status:
        hir::items::mark_method_signatures::HirMethodSignatureStatusPass,
    pub hir_item_fields: hir::items::extract_item_records::HirItemFieldsPass,
    pub hir_canonical_mark: hir::canonical::mark_canonical_rows::HirCanonicalMarkPass,
    pub hir_canonical_local: hir::canonical::count_canonical_rows_in_blocks::HirCanonicalLocalPass,
    pub hir_canonical_scatter: hir::canonical::list_canonical_rows::HirCanonicalScatterPass,
    pub hir_canonical_stmt_compact:
        hir::canonical::gather_canonical_stmts::HirCanonicalStmtCompactPass,
    pub hir_canonical_identity_aliases:
        hir::canonical::map_canonical_aliases::HirCanonicalIdentityAliasesPass,
    pub hir_canonical_end_rows: hir::canonical::build_canonical_end_heaps::HirCanonicalEndRowsPass,
    pub hir_canonical_end_blocks:
        hir::canonical::build_canonical_end_heaps::HirCanonicalEndBlocksPass,
    pub hir_canonical_end_top: hir::canonical::build_canonical_end_heaps::HirCanonicalEndTopPass,
    pub hir_canonical_core: hir::canonical::build_canonical_rows::HirCanonicalCorePass,
    pub hir_canonical_nav: hir::canonical::build_canonical_links::HirCanonicalNavPass,
    pub hir_canonical_expr_forest_edges:
        hir::canonical::build_expr_forest_edges::HirCanonicalExprForestEdgesPass,
    pub hir_canonical_expr_forest_root_init:
        hir::canonical::seed_expr_forest_roots::HirCanonicalExprForestRootInitPass,
    pub hir_canonical_expr_forest_root_step:
        hir::canonical::walk_expr_forest_roots::HirCanonicalExprForestRootStepPass,
    pub hir_canonical_validate: hir::canonical::validate_canonical_hir::HirCanonicalValidatePass,
    pub hir_canonical_decl_index_clear:
        hir::canonical::index_declarations_by_name::HirCanonicalDeclIndexClearPass,
    pub hir_canonical_decl_index_scatter:
        hir::canonical::index_declarations_by_name::HirCanonicalDeclIndexScatterPass,
    pub hir_canonical_call_arg_mark:
        hir::lists::mark_canonical_call_args::HirCanonicalCallArgMarkPass,
    pub exclusive_u32_local_scan: PassData,
    pub hir_canonical_call_arg_scatter:
        hir::lists::scatter_canonical_call_args::HirCanonicalCallArgScatterPass,
    pub hir_canonical_param_mark: hir::params::mark_canonical_params::HirCanonicalParamMarkPass,
    pub hir_canonical_param_scatter:
        hir::params::scatter_canonical_params::HirCanonicalParamScatterPass,
    pub hir_canonical_type_arg_mark:
        hir::lists::mark_canonical_type_args::HirCanonicalTypeArgMarkPass,
    pub hir_canonical_type_arg_scatter:
        hir::lists::scatter_canonical_type_args::HirCanonicalTypeArgScatterPass,
    pub hir_canonical_generic_param_candidate_mark:
        hir::items::mark_generic_param_candidates::HirCanonicalGenericParamCandidateMarkPass,
    pub hir_canonical_generic_param_finalize:
        hir::items::finish_canonical_generic_params::HirCanonicalGenericParamFinalizePass,
    pub hir_canonical_generic_param_scatter:
        hir::items::scatter_canonical_generic_params::HirCanonicalGenericParamScatterPass,
    pub hir_canonical_path_segment_mark:
        hir::paths::mark_canonical_path_segments::HirCanonicalPathSegmentMarkPass,
    pub hir_canonical_path_segment_scatter:
        hir::paths::scatter_canonical_path_segments::HirCanonicalPathSegmentScatterPass,
    pub hir_canonical_path_mark: hir::paths::mark_canonical_paths::HirCanonicalPathMarkPass,
    pub hir_canonical_path_scatter:
        hir::paths::scatter_canonical_paths::HirCanonicalPathScatterPass,
    pub hir_canonical_field_mark: hir::structs::mark_canonical_fields::HirCanonicalFieldMarkPass,
    pub hir_canonical_field_scatter:
        hir::structs::scatter_canonical_fields::HirCanonicalFieldScatterPass,
    pub hir_canonical_variant_mark:
        hir::enums::mark_canonical_variants::HirCanonicalVariantMarkPass,
    pub hir_canonical_variant_scatter:
        hir::enums::scatter_canonical_variants::HirCanonicalVariantScatterPass,
    pub hir_canonical_variant_payload_owner_init:
        hir::enums::seed_variant_payload_owners::HirCanonicalVariantPayloadOwnerInitPass,
    pub hir_canonical_variant_payload_scatter:
        hir::enums::scatter_canonical_variant_payloads::HirCanonicalVariantPayloadScatterPass,
    pub hir_canonical_variant_payload_ordinal:
        hir::enums::number_canonical_variant_payloads::HirCanonicalVariantPayloadOrdinalPass,
    pub hir_canonical_match_arm_mark:
        hir::matches::mark_canonical_match_arms::HirCanonicalMatchArmMarkPass,
    pub hir_canonical_match_arm_scatter:
        hir::matches::scatter_canonical_match_arms::HirCanonicalMatchArmScatterPass,
    pub hir_canonical_match_payload_mark:
        hir::matches::mark_canonical_match_payloads::HirCanonicalMatchPayloadMarkPass,
    pub hir_canonical_match_payload_scatter:
        hir::matches::scatter_canonical_match_payloads::HirCanonicalMatchPayloadScatterPass,
    pub hir_canonical_array_element_mark:
        hir::lists::mark_canonical_array_elements::HirCanonicalArrayElementMarkPass,
    pub hir_canonical_array_element_scatter:
        hir::lists::scatter_canonical_array_elements::HirCanonicalArrayElementScatterPass,
    pub hir_canonical_string_scatter:
        hir::strings::scatter_canonical_strings::HirCanonicalStringScatterPass,
    pub hir_canonical_method_mark: hir::items::mark_canonical_methods::HirCanonicalMethodMarkPass,
    pub hir_canonical_method_scatter:
        hir::items::scatter_canonical_methods::HirCanonicalMethodScatterPass,
    pub hir_canonical_predicate_finalize:
        hir::items::finish_canonical_predicates::HirCanonicalPredicateFinalizePass,
    pub hir_canonical_predicate_scatter:
        hir::items::scatter_canonical_predicates::HirCanonicalPredicateScatterPass,
    pub hir_param_links: hir::params::link_params::HirParamLinksPass,
    pub hir_param_id_clear: hir::params::clear_param_bases::HirParamIdClearPass,
    pub hir_param_id_base: hir::params::find_param_bases::HirParamIdBasePass,
    pub hir_param_id_apply: hir::params::number_params::HirParamIdApplyPass,
    pub hir_param_fields: hir::params::extract_param_records::HirParamFieldsPass,
    pub hir_method_fields: hir::items::extract_method_records::HirMethodFieldsPass,
    pub hir_expr_fields: hir::records::extract_expr_records::HirExprFieldsPass,
    pub hir_expr_result_root_step: hir::records::walk_expr_result_roots::HirExprResultRootStepPass,
    pub hir_binary_span_apply: hir::spans::apply_binary_spans::HirBinarySpanApplyPass,
    pub hir_binary_span_step: hir::spans::walk_binary_spans::HirBinarySpanStepPass,
    pub hir_binary_spans: hir::spans::seed_binary_spans::HirBinarySpansPass,
    pub hir_postfix_fields: hir::records::extract_postfix_records::HirPostfixFieldsPass,
    pub hir_member_spans: hir::spans::widen_member_spans::HirMemberSpansPass,
    pub hir_range_spans: hir::spans::trim_range_spans::HirRangeSpansPass,
    pub hir_stmt_fields: hir::records::extract_stmt_records::HirStmtFieldsPass,
    pub hir_stmt_scope: hir::context::finish_stmt_scopes::HirStmtScopePass,
    pub hir_literal_values: hir::records::extract_literal_values::HirLiteralValuesPass,
    pub hir_float_values: hir::records::convert_float_literals::HirFloatValuesPass,
    pub hir_string_compact_local: hir::strings::mark_string_rows::HirStringCompactLocalPass,
    pub hir_string_compact_scatter: hir::strings::list_string_rows::HirStringCompactScatterPass,
    pub hir_string_offset_local: hir::strings::scan_string_lengths::HirStringOffsetLocalPass,
    pub hir_string_offset_scatter: hir::strings::publish_string_offsets::HirStringOffsetScatterPass,
    pub hir_string_decode: hir::strings::decode_strings::HirStringDecodePass,
    pub hir_call_fields: hir::records::extract_call_records::HirCallFieldsPass,
    pub hir_call_spans: hir::spans::widen_call_spans::HirCallSpansPass,
    pub hir_call_arg_links: hir::lists::link_call_args::HirCallArgLinksPass,
    pub hir_call_arg_ordinal_scatter:
        hir::lists::publish_call_arg_ordinals::HirCallArgOrdinalScatterPass,
    pub hir_array_element_links: hir::lists::link_array_elements::HirArrayElementLinksPass,
    pub hir_array_element_scatter: hir::lists::publish_array_elements::HirArrayElementScatterPass,
    pub hir_enum_variant_links: hir::enums::link_enum_variants::HirEnumVariantLinksPass,
    pub hir_enum_rank_prefix_local: hir::enums::mark_enum_rows::HirEnumRankPrefixLocalPass,
    pub hir_enum_rank_compact_scatter: hir::enums::list_enum_rows::HirEnumRankCompactScatterPass,
    pub hir_enum_variant_rank_step: hir::enums::rank_enum_variants::HirEnumVariantRankStepPass,
    pub hir_enum_variant_scatter: hir::enums::publish_enum_variants::HirEnumVariantScatterPass,
    pub hir_match_arm_owner_init: hir::matches::seed_match_arm_owners::HirMatchArmOwnerInitPass,
    pub hir_match_arm_links: hir::matches::link_match_arms::HirMatchArmLinksPass,
    pub hir_match_rank_prefix_local: hir::matches::mark_match_rows::HirMatchRankPrefixLocalPass,
    pub hir_match_rank_compact_scatter:
        hir::matches::list_match_rows::HirMatchRankCompactScatterPass,
    pub hir_match_arm_rank_step: hir::matches::rank_match_arms::HirMatchArmRankStepPass,
    pub hir_match_arm_scatter: hir::matches::publish_match_arms::HirMatchArmScatterPass,
    pub hir_context_relations_init:
        hir::context::seed_context_relations::HirContextRelationsInitPass,
    pub hir_context_relations_step:
        hir::context::walk_context_relations::HirContextRelationsStepPass,
    pub hir_context_relations_step_small:
        hir::context::walk_small_context_relations::HirContextRelationsStepSmallPass,
    pub hir_context_relations_scatter:
        hir::context::publish_context_relations::HirContextRelationsScatterPass,
    pub hir_struct_field_links: hir::structs::link_struct_fields::HirStructFieldLinksPass,
    pub hir_struct_lit_spans: hir::spans::widen_struct_literal_spans::HirStructLitSpansPass,
    pub hir_struct_rank_compact_scatter:
        hir::structs::list_struct_fields::HirStructRankCompactScatterPass,
    pub hir_struct_field_rank_step: hir::structs::rank_struct_fields::HirStructFieldRankStepPass,
    pub hir_struct_field_scatter: hir::structs::publish_struct_fields::HirStructFieldScatterPass,
}

impl ParserPasses {
    /// Loads every parser compute pass for a GPU device.
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            token_frontend: tokens::TokenFrontendPasses::new(device)?,
            active_pair_dispatch_args: crate::gpu::passes_core::make_main_pass!(
                device,
                "parser_active_pair_dispatch_args",
                shader: "parser/pack/write_token_pair_dispatch_args"
            )?,
            tree_feature_dispatch_args: crate::gpu::passes_core::make_main_pass!(
                device,
                "parser_tree_feature_dispatch_args",
                shader: "parser/tree/write_feature_dispatch_args"
            )?,
            llp_pairs: pack::find_token_pair_actions::LLPPairsPass::new(device)?,
            pack_offsets: pack::scan_pack_offsets::PackOffsetsScanPass::new(device)?,
            pack_offsets_status: pack::publish_pack_offset_status::PackOffsetsStatusPass::new(device)?,
            pack_totals_blocks: pack::sum_pack_lengths_in_blocks::PackTotalsBlocksPass::new(device)?,
            pack_totals_reduce: pack::reduce_pack_length_sums::PackTotalsReducePass::new(device)?,
            pack_totals_status: pack::publish_pack_total_status::PackTotalsStatusPass::new(device)?,
            pack_varlen: pack::pack_stack_changes_and_productions::PackVarlenPass::new(device)?,
            status_from_brackets: brackets::combine_pack_and_bracket_status::ParserStatusFromBracketsPass::new(device)?,
            source_file_token_end: tree::find_source_file_token_ends::SourceFileTokenEndPass::new(device)?,

            scan_bracket_depths_in_blocks: brackets::scan_bracket_depths_in_blocks::BracketsScanInblockPass::new(device)?,
            scan_bracket_blocks: brackets::scan_bracket_blocks::BracketsScanBlockPrefixPass::new(device)?,
            apply_bracket_block_prefix: brackets::apply_bracket_block_prefix::BracketsApplyPrefixPass::new(device)?,
            b_clear_matches: brackets::clear_bracket_matches::BracketsClearMatchesPass::new(device)?,
            b_min_tree: brackets::build_bracket_min_tree::BracketsMinTreePass::new(device)?,
            pair_brackets_by_layer: brackets::pair_brackets_by_layer::BracketsPsePairPass::new(device)?,

            tree_parent: tree::find_tree_parents::TreeParentPass::new(device)?,
            sum_arity_deficits_in_blocks: tree::sum_arity_deficits_in_blocks::TreePrefixLocalPass::new(device)?,
            scan_arity_deficit_blocks: tree::scan_arity_deficit_blocks::TreePrefixScanBlocksPass::new(device)?,
            apply_arity_deficit_prefix: tree::apply_arity_deficit_prefix::TreePrefixApplyPass::new(device)?,
            build_deficit_max_tree: tree::build_deficit_max_tree::TreePrefixMaxBuildPass::new(device)?,
            tree_active_dispatch_args:
                tree::write_active_node_dispatch_args::TreeActiveDispatchArgsPass::new(device)?,
            tree_spans: tree::find_tree_spans::TreeSpansPass::new(device)?,
            tree_depth_block_max: tree::find_tree_depth_block_maxima::TreeDepthBlockMaxPass::new(device)?,
            tree_depth_schedule: tree::schedule_tree_depth_jumps::TreeDepthSchedulePass::new(device)?,
            tree_prev_sibling_clear: tree::clear_previous_siblings::TreePrevSiblingClearPass::new(
                device,
            )?,
            tree_prev_sibling_scatter:
                tree::scatter_previous_siblings::TreePrevSiblingScatterPass::new(device)?,
            hir_nodes: hir::records::classify_hir_nodes::HirNodesPass::new(device)?,
            hir_semantic_prefix_local:
                hir::semantic::mark_semantic_rows::HirSemanticPrefixLocalPass::new(device)?,
            hir_semantic_prefix_blocks:
                hir::semantic::scan_semantic_blocks::HirSemanticPrefixBlocksPass::new(device)?,
            hir_semantic_compact_scatter:
                hir::semantic::list_semantic_rows::HirSemanticCompactScatterPass::new(device)?,
            hir_semantic_dispatch_args:
                hir::semantic::write_semantic_dispatch_args::HirSemanticDispatchArgsPass::new(device)?,
            hir_semantic_subtree_end: hir::semantic::project_semantic_subtree_ends::HirSemanticSubtreeEndPass::new(
                device,
            )?,
            hir_semantic_end_rows:
                hir::semantic::build_semantic_end_heaps::HirSemanticEndRowsPass::new(device)?,
            hir_semantic_end_blocks:
                hir::semantic::build_semantic_end_heaps::HirSemanticEndBlocksPass::new(device)?,
            hir_semantic_end_top:
                hir::semantic::build_semantic_end_heaps::HirSemanticEndTopPass::new(device)?,
            hir_semantic_parent_traverse:
                hir::semantic::find_semantic_parents::HirSemanticParentTraversePass::new(device)?,
            hir_tree_relations: hir::semantic::walk_semantic_parents::TreeRelationOperation::new(
                device,
            )?,
            hir_semantic_nav: hir::semantic::project_semantic_navigation::HirSemanticNavPass::new(device)?,
            hir_semantic_child_index_blocks:
                hir::semantic::build_child_index_heaps::HirSemanticChildIndexBlocksPass::new(
                    device,
                )?,
            hir_semantic_child_index_top:
                hir::semantic::build_child_index_heaps::HirSemanticChildIndexTopPass::new(
                    device,
                )?,
            hir_semantic_child_index_traverse:
                hir::semantic::find_child_indices::HirSemanticChildIndexTraversePass::new(
                    device,
                )?,
            hir_record_clear_base: hir::records::clear_hir_records::HirRecordClearBasePass::new(device)?,
            hir_record_clear_calls: hir::records::clear_call_and_member_records::HirRecordClearCallsPass::new(
                device,
            )?,
            hir_spans: hir::spans::compute_hir_spans::HirSpansPass::new(device)?,
            hir_type_fields: hir::records::extract_type_records::HirTypeFieldsPass::new(device)?,
            hir_type_path_leaf_scatter:
                hir::types::publish_type_path_leaves::HirTypePathLeafScatterPass::new(device)?,
            hir_path_segment_root: hir::paths::seed_path_roots::HirPathSegmentRootPass::new(device)?,
            hir_path_segment_scatter: hir::paths::publish_path_segments::HirPathSegmentScatterPass::new(
                device,
            )?,
            hir_list_rank_prefix_local:
                hir::lists::mark_list_rows::HirListRankPrefixLocalPass::new(device)?,
            hir_list_rank_compact_scatter:
                hir::lists::compact_list_rows::HirListRankCompactScatterPass::new(device)?,
            hir_list_rank_step: hir::lists::rank_list_rows::HirListRankStepOperation::new(device)?,
            hir_type_arg_links: hir::lists::link_type_args::HirTypeArgLinksPass::new(device)?,
            hir_type_arg_scatter: hir::lists::publish_type_args::HirTypeArgScatterPass::new(device)?,
            hir_type_root_owner_init: hir::types::seed_type_roots::HirTypeRootOwnerInitPass::new(
                device,
            )?,
            hir_type_root_owner_step: hir::types::walk_type_roots::HirTypeRootOwnerStepPass::new(
                device,
            )?,
            hir_type_alias_owner_init:
                hir::types::seed_type_alias_owners::HirTypeAliasOwnerInitPass::new(device)?,
            hir_type_alias_owner_step:
                hir::types::walk_type_alias_owners::HirTypeAliasOwnerStepPass::new(device)?,
            hir_type_alias_target: hir::types::find_type_alias_targets::HirTypeAliasTargetPass::new(device)?,
            hir_method_signature_status:
                hir::items::mark_method_signatures::HirMethodSignatureStatusPass::new(device)?,
            hir_item_fields: hir::items::extract_item_records::HirItemFieldsPass::new(device)?,
            hir_canonical_mark: hir::canonical::mark_canonical_rows::HirCanonicalMarkPass::new(device)?,
            hir_canonical_local: hir::canonical::count_canonical_rows_in_blocks::HirCanonicalLocalPass::new(device)?,
            hir_canonical_scatter: hir::canonical::list_canonical_rows::HirCanonicalScatterPass::new(device)?,
            hir_canonical_stmt_compact:
                hir::canonical::gather_canonical_stmts::HirCanonicalStmtCompactPass::new(device)?,
            hir_canonical_identity_aliases:
                hir::canonical::map_canonical_aliases::HirCanonicalIdentityAliasesPass::new(device)?,
            hir_canonical_end_rows: hir::canonical::build_canonical_end_heaps::HirCanonicalEndRowsPass::new(device)?,
            hir_canonical_end_blocks:
                hir::canonical::build_canonical_end_heaps::HirCanonicalEndBlocksPass::new(device)?,
            hir_canonical_end_top: hir::canonical::build_canonical_end_heaps::HirCanonicalEndTopPass::new(device)?,
            hir_canonical_core: hir::canonical::build_canonical_rows::HirCanonicalCorePass::new(device)?,
            hir_canonical_nav: hir::canonical::build_canonical_links::HirCanonicalNavPass::new(device)?,
            hir_canonical_expr_forest_edges:
                hir::canonical::build_expr_forest_edges::HirCanonicalExprForestEdgesPass::new(
                    device,
                )?,
            hir_canonical_expr_forest_root_init:
                hir::canonical::seed_expr_forest_roots::HirCanonicalExprForestRootInitPass::new(
                    device,
                )?,
            hir_canonical_expr_forest_root_step:
                hir::canonical::walk_expr_forest_roots::HirCanonicalExprForestRootStepPass::new(
                    device,
                )?,
            hir_canonical_validate: hir::canonical::validate_canonical_hir::HirCanonicalValidatePass::new(
                device,
            )?,
            hir_canonical_decl_index_clear:
                hir::canonical::index_declarations_by_name::HirCanonicalDeclIndexClearPass::new(device)?,
            hir_canonical_decl_index_scatter:
                hir::canonical::index_declarations_by_name::HirCanonicalDeclIndexScatterPass::new(device)?,
            hir_canonical_call_arg_mark:
                hir::lists::mark_canonical_call_args::HirCanonicalCallArgMarkPass::new(device)?,
            exclusive_u32_local_scan: crate::gpu::passes_core::make_main_pass!(
                device,
                "exclusive_u32_local_scan",
                shader: "scan/blocks/scan_word_blocks_exclusively"
            )?,
            hir_canonical_call_arg_scatter:
                hir::lists::scatter_canonical_call_args::HirCanonicalCallArgScatterPass::new(device)?,
            hir_canonical_param_mark: hir::params::mark_canonical_params::HirCanonicalParamMarkPass::new(
                device,
            )?,
            hir_canonical_param_scatter:
                hir::params::scatter_canonical_params::HirCanonicalParamScatterPass::new(device)?,
            hir_canonical_type_arg_mark:
                hir::lists::mark_canonical_type_args::HirCanonicalTypeArgMarkPass::new(device)?,
            hir_canonical_type_arg_scatter:
                hir::lists::scatter_canonical_type_args::HirCanonicalTypeArgScatterPass::new(device)?,
            hir_canonical_generic_param_candidate_mark:
                hir::items::mark_generic_param_candidates::HirCanonicalGenericParamCandidateMarkPass::new(device)?,
            hir_canonical_generic_param_finalize:
                hir::items::finish_canonical_generic_params::HirCanonicalGenericParamFinalizePass::new(device)?,
            hir_canonical_generic_param_scatter:
                hir::items::scatter_canonical_generic_params::HirCanonicalGenericParamScatterPass::new(device)?,
            hir_canonical_path_segment_mark:
                hir::paths::mark_canonical_path_segments::HirCanonicalPathSegmentMarkPass::new(device)?,
            hir_canonical_path_segment_scatter:
                hir::paths::scatter_canonical_path_segments::HirCanonicalPathSegmentScatterPass::new(device)?,
            hir_canonical_path_mark:
                hir::paths::mark_canonical_paths::HirCanonicalPathMarkPass::new(device)?,
            hir_canonical_path_scatter:
                hir::paths::scatter_canonical_paths::HirCanonicalPathScatterPass::new(device)?,
            hir_canonical_field_mark:
                hir::structs::mark_canonical_fields::HirCanonicalFieldMarkPass::new(device)?,
            hir_canonical_field_scatter:
                hir::structs::scatter_canonical_fields::HirCanonicalFieldScatterPass::new(device)?,
            hir_canonical_variant_mark:
                hir::enums::mark_canonical_variants::HirCanonicalVariantMarkPass::new(device)?,
            hir_canonical_variant_scatter:
                hir::enums::scatter_canonical_variants::HirCanonicalVariantScatterPass::new(device)?,
            hir_canonical_variant_payload_owner_init:
                hir::enums::seed_variant_payload_owners::HirCanonicalVariantPayloadOwnerInitPass::new(device)?,
            hir_canonical_variant_payload_scatter:
                hir::enums::scatter_canonical_variant_payloads::HirCanonicalVariantPayloadScatterPass::new(device)?,
            hir_canonical_variant_payload_ordinal:
                hir::enums::number_canonical_variant_payloads::HirCanonicalVariantPayloadOrdinalPass::new(device)?,
            hir_canonical_match_arm_mark:
                hir::matches::mark_canonical_match_arms::HirCanonicalMatchArmMarkPass::new(device)?,
            hir_canonical_match_arm_scatter:
                hir::matches::scatter_canonical_match_arms::HirCanonicalMatchArmScatterPass::new(device)?,
            hir_canonical_match_payload_mark:
                hir::matches::mark_canonical_match_payloads::HirCanonicalMatchPayloadMarkPass::new(device)?,
            hir_canonical_match_payload_scatter:
                hir::matches::scatter_canonical_match_payloads::HirCanonicalMatchPayloadScatterPass::new(device)?,
            hir_canonical_array_element_mark:
                hir::lists::mark_canonical_array_elements::HirCanonicalArrayElementMarkPass::new(device)?,
            hir_canonical_array_element_scatter:
                hir::lists::scatter_canonical_array_elements::HirCanonicalArrayElementScatterPass::new(device)?,
            hir_param_links: hir::params::link_params::HirParamLinksPass::new(device)?,
            hir_param_id_clear: hir::params::clear_param_bases::HirParamIdClearPass::new(device)?,
            hir_param_id_base: hir::params::find_param_bases::HirParamIdBasePass::new(device)?,
            hir_param_id_apply: hir::params::number_params::HirParamIdApplyPass::new(device)?,
            hir_param_fields: hir::params::extract_param_records::HirParamFieldsPass::new(device)?,
            hir_method_fields: hir::items::extract_method_records::HirMethodFieldsPass::new(device)?,
            hir_expr_fields: hir::records::extract_expr_records::HirExprFieldsPass::new(device)?,
            hir_expr_result_root_step: hir::records::walk_expr_result_roots::HirExprResultRootStepPass::new(
                device,
            )?,
            hir_binary_span_apply: hir::spans::apply_binary_spans::HirBinarySpanApplyPass::new(device)?,
            hir_binary_span_step: hir::spans::walk_binary_spans::HirBinarySpanStepPass::new(device)?,
            hir_binary_spans: hir::spans::seed_binary_spans::HirBinarySpansPass::new(device)?,
            hir_postfix_fields: hir::records::extract_postfix_records::HirPostfixFieldsPass::new(device)?,
            hir_member_spans: hir::spans::widen_member_spans::HirMemberSpansPass::new(device)?,
            hir_range_spans: hir::spans::trim_range_spans::HirRangeSpansPass::new(device)?,
            hir_stmt_fields: hir::records::extract_stmt_records::HirStmtFieldsPass::new(device)?,
            hir_stmt_scope: hir::context::finish_stmt_scopes::HirStmtScopePass::new(device)?,
            hir_literal_values: hir::records::extract_literal_values::HirLiteralValuesPass::new(device)?,
            hir_float_values: hir::records::convert_float_literals::HirFloatValuesPass::new(device)?,
            hir_string_compact_local: hir::strings::mark_string_rows::HirStringCompactLocalPass::new(
                device,
            )?,
            hir_string_compact_scatter:
                hir::strings::list_string_rows::HirStringCompactScatterPass::new(device)?,
            hir_string_offset_local: hir::strings::scan_string_lengths::HirStringOffsetLocalPass::new(
                device,
            )?,
            hir_string_offset_scatter:
                hir::strings::publish_string_offsets::HirStringOffsetScatterPass::new(device)?,
            hir_string_decode: hir::strings::decode_strings::HirStringDecodePass::new(device)?,
            hir_canonical_string_scatter:
                hir::strings::scatter_canonical_strings::HirCanonicalStringScatterPass::new(device)?,
            hir_canonical_method_mark:
                hir::items::mark_canonical_methods::HirCanonicalMethodMarkPass::new(device)?,
            hir_canonical_method_scatter:
                hir::items::scatter_canonical_methods::HirCanonicalMethodScatterPass::new(device)?,
            hir_canonical_predicate_finalize:
                hir::items::finish_canonical_predicates::HirCanonicalPredicateFinalizePass::new(device)?,
            hir_canonical_predicate_scatter:
                hir::items::scatter_canonical_predicates::HirCanonicalPredicateScatterPass::new(device)?,
            hir_call_fields: hir::records::extract_call_records::HirCallFieldsPass::new(device)?,
            hir_call_spans: hir::spans::widen_call_spans::HirCallSpansPass::new(device)?,
            hir_call_arg_links: hir::lists::link_call_args::HirCallArgLinksPass::new(device)?,
            hir_call_arg_ordinal_scatter:
                hir::lists::publish_call_arg_ordinals::HirCallArgOrdinalScatterPass::new(device)?,
            hir_array_element_links: hir::lists::link_array_elements::HirArrayElementLinksPass::new(
                device,
            )?,
            hir_array_element_scatter:
                hir::lists::publish_array_elements::HirArrayElementScatterPass::new(device)?,
            hir_enum_variant_links: hir::enums::link_enum_variants::HirEnumVariantLinksPass::new(
                device,
            )?,
            hir_enum_rank_prefix_local:
                hir::enums::mark_enum_rows::HirEnumRankPrefixLocalPass::new(device)?,
            hir_enum_rank_compact_scatter:
                hir::enums::list_enum_rows::HirEnumRankCompactScatterPass::new(device)?,
            hir_enum_variant_rank_step:
                hir::enums::rank_enum_variants::HirEnumVariantRankStepPass::new(device)?,
            hir_enum_variant_scatter: hir::enums::publish_enum_variants::HirEnumVariantScatterPass::new(
                device,
            )?,
            hir_match_arm_owner_init:
                hir::matches::seed_match_arm_owners::HirMatchArmOwnerInitPass::new(device)?,
            hir_match_arm_links: hir::matches::link_match_arms::HirMatchArmLinksPass::new(device)?,
            hir_match_rank_prefix_local:
                hir::matches::mark_match_rows::HirMatchRankPrefixLocalPass::new(device)?,
            hir_match_rank_compact_scatter:
                hir::matches::list_match_rows::HirMatchRankCompactScatterPass::new(device)?,
            hir_match_arm_rank_step: hir::matches::rank_match_arms::HirMatchArmRankStepPass::new(
                device,
            )?,
            hir_match_arm_scatter: hir::matches::publish_match_arms::HirMatchArmScatterPass::new(device)?,
            hir_context_relations_init:
                hir::context::seed_context_relations::HirContextRelationsInitPass::new(device)?,
            hir_context_relations_step:
                hir::context::walk_context_relations::HirContextRelationsStepPass::new(device)?,
            hir_context_relations_step_small:
                hir::context::walk_small_context_relations::HirContextRelationsStepSmallPass::new(device)?,
            hir_context_relations_scatter:
                hir::context::publish_context_relations::HirContextRelationsScatterPass::new(device)?,
            hir_struct_field_links: hir::structs::link_struct_fields::HirStructFieldLinksPass::new(
                device,
            )?,
            hir_struct_lit_spans: hir::spans::widen_struct_literal_spans::HirStructLitSpansPass::new(device)?,
            hir_struct_rank_compact_scatter:
                hir::structs::list_struct_fields::HirStructRankCompactScatterPass::new(device)?,
            hir_struct_field_rank_step:
                hir::structs::rank_struct_fields::HirStructFieldRankStepPass::new(device)?,
            hir_struct_field_scatter: hir::structs::publish_struct_fields::HirStructFieldScatterPass::new(
                device,
            )?,
        })
    }
}

/// Records the debug parser pipeline in pass order.

/// Compacts enum variants and their payload types before the shared raw-family
/// columns are reassigned to call reconstruction.
pub fn record_canonical_variants(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1D;

    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_VARIANT_CLEAR,
        ctx.encoder,
    )?;
    // Over the enum family's rows, where the variant arrays are defined.
    p.hir_canonical_variant_mark
        .record_pass_indirect(ctx, &ctx.buffers.hir_enum_rank_dispatch_args)?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::Variant)?;
    p.hir_canonical_variant_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;

    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_VARIANT_PAYLOAD_CLEAR,
        ctx.encoder,
    )?;
    // The owner init also lists the payload types and the variant-field
    // chains above them, so it covers every block of the tree; the walk runs
    // over that list only.
    p.hir_canonical_variant_payload_owner_init
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    let invocation = hir::lists::ListRankInvocation::VariantPayloadOwners;
    p.hir_semantic_prefix_blocks.record_list_rank_scan(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        ctx.bg_cache
            .as_deref_mut()
            .expect("debug parser requires a bind-group cache"),
        invocation,
    )?;
    p.hir_list_rank_compact_scatter.record_for_params(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_type_fields_params,
        ctx.bg_cache
            .as_deref_mut()
            .expect("debug parser requires a bind-group cache"),
        invocation,
    )?;
    p.hir_tree_relations.record_canonical_row_steps(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        hir::semantic::walk_semantic_parents::CANONICAL_VARIANT_PAYLOAD_OWNER,
        ctx.bg_cache
            .as_deref_mut()
            .expect("debug parser requires a bind-group cache"),
    )?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::VariantPayload)?;
    p.hir_canonical_variant_payload_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    p.hir_canonical_variant_payload_ordinal
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    Ok(())
}

/// Selects token-anchored semantic nodes and establishes the stable dense/raw
/// identity maps before later HIR enrichment allocates family metadata.
pub(crate) fn record_canonical_hir_identity_maps(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1D;

    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::HIR_CANONICAL_IDENTITY_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_canonical_identity_scan(
            ctx.device,
            ctx.encoder,
            ctx.buffers,
            ctx.bg_cache
                .as_deref_mut()
                .expect("parser canonical identity requires a bind-group cache"),
        )?;
    p.hir_canonical_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_identity_aliases
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    Ok(())
}

/// Gathers finalized raw statement/expression records using the durable dense
/// identity map. The prefix-scan scratch used to create that map has already
/// been released to subsequent HIR operations.
pub(crate) fn record_canonical_hir_record_compaction(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
    _raw_expression_records: RawExpressionRecordsFinalized,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1D;

    p.hir_canonical_stmt_compact
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    Ok(())
}

/// Compacts call arguments immediately after their raw owner/rank relation is
/// finalized, before the shared raw-family workspace is reused.
pub fn record_canonical_call_arguments(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
) -> Result<(), anyhow::Error> {
    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_CALL_ARGUMENT_CLEAR,
        ctx.encoder,
    )?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::CallArgument)?;
    // Over the call argument list that the argument links pass built: the
    // argument arrays are defined on those rows only.
    let buffers = ctx.buffers;
    p.hir_canonical_call_arg_scatter
        .record_pass_indirect(ctx, &buffers.hir_list_rank_dispatch_args)?;
    Ok(())
}

/// Compacts array elements immediately after raw list ranking, so later raw
/// HIR families may reuse the same phase-local storage.
pub fn record_canonical_array_elements(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1D;

    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_ARRAY_ELEMENT_CLEAR,
        ctx.encoder,
    )?;
    // Over the array element list that the element links pass built.
    p.hir_canonical_array_element_mark
        .record_pass_indirect(ctx, &ctx.buffers.hir_list_rank_dispatch_args)?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::ArrayElement)?;
    p.hir_canonical_array_element_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    Ok(())
}

/// Compacts match arms and their pattern payloads as soon as raw match-list
/// ranking completes, before the shared raw-family slots are reassigned.
pub fn record_canonical_matches(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1D;

    clear_canonical_match_outputs(ctx)?;
    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_MATCH_ARM_CLEAR,
        ctx.encoder,
    )?;
    let buffers = ctx.buffers;
    p.hir_canonical_match_arm_mark
        .record_pass_indirect(ctx, &buffers.hir_match_rank_dispatch_args)?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::MatchArm)?;
    p.hir_canonical_match_arm_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;

    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_MATCH_PAYLOAD_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_match_payload_mark
        .record_pass_indirect(ctx, &buffers.hir_match_rank_dispatch_args)?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::MatchPayload)?;
    p.hir_canonical_match_payload_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    Ok(())
}

/// Publishes an empty compact match family when feature classification proved
/// that the source unit contains no match expressions. This avoids recording
/// the raw-tree match pipeline or binding its intentionally one-row absent
/// family sentinels as tree-sized writable arrays.
pub fn clear_canonical_match_outputs(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
) -> Result<(), anyhow::Error> {
    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_MATCH_OUTPUTS_CLEAR,
        ctx.encoder,
    )
}

/// Compacts declaration and literal fields after struct list ranking. Field
/// ranges share the canonical owner-range storage used by match expressions;
/// the owner kinds are disjoint.
pub fn record_canonical_fields(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1D;

    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_FIELD_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_field_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::Field)?;
    p.hir_canonical_field_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    Ok(())
}

fn record_canonical_params_and_type_args(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1D;

    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_PARAMETER_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_param_mark
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::Parameter)?;
    p.hir_canonical_param_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;

    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_TYPE_ARGUMENT_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_type_arg_mark
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::TypeArgument)?;
    p.hir_canonical_type_arg_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    Ok(())
}

/// Materializes compact navigation, payloads, and side tables after raw
/// classification passes have populated the facts referenced by canonical
/// nodes. Identity compaction has already completed.
pub fn record_canonical_hir_materialization(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
    timer_ref: &mut Option<&mut GpuTimer>,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1D;

    record_canonical_params_and_type_args(ctx, p)?;
    stamp_parser_timer(
        timer_ref,
        ctx.encoder,
        "parser.hir_canonical.params_and_type_args",
    );

    p.hir_canonical_end_rows
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    p.hir_canonical_end_blocks.record_pass(
        ctx,
        E1D(hir::canonical::build_canonical_end_heaps::leaf_base(
            ctx.buffers.hir_canonical_capacity,
        )),
    )?;
    p.hir_canonical_end_top.record_pass(ctx, E1D(256))?;
    p.hir_canonical_core
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    stamp_parser_timer(timer_ref, ctx.encoder, "parser.hir_canonical.core");
    p.hir_canonical_nav
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    stamp_parser_timer(timer_ref, ctx.encoder, "parser.hir_canonical.nav");
    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_EXPR_FOREST_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_expr_forest_edges
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    p.hir_canonical_expr_forest_root_init
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    p.hir_canonical_expr_forest_root_step.record_steps(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        ctx.bg_cache
            .as_deref_mut()
            .expect("debug parser requires a bind-group cache"),
    )?;
    stamp_parser_timer(timer_ref, ctx.encoder, "parser.hir_canonical.expr_forest");
    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_GENERIC_PARAMETER_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_generic_param_candidate_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_generic_param_finalize
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::GenericParameter)?;
    p.hir_canonical_generic_param_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    stamp_parser_timer(
        timer_ref,
        ctx.encoder,
        "parser.hir_canonical.generic_params",
    );
    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_PATH_SEGMENT_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_path_segment_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_semantic_prefix_blocks.record_semantic_scan_as(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        ctx.bg_cache
            .as_deref_mut()
            .expect("parser path scan requires a bind-group cache"),
        crate::parser::compiler_graph::HIR_PATH_SEGMENT_SCAN,
    )?;
    p.hir_canonical_path_segment_scatter
        .record_pass_indirect(ctx, &ctx.buffers.tree_active_dispatch_args)?;
    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_PATH_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_path_mark
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::Path)?;
    p.hir_canonical_path_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    p.hir_canonical_string_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    stamp_parser_timer(timer_ref, ctx.encoder, "parser.hir_canonical.paths");
    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_METHOD_CLEAR,
        ctx.encoder,
    )?;
    if ctx.buffers.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_PREDICATES != 0 {
        p.hir_canonical_method_mark
            .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
        record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::Method)?;
        p.hir_canonical_method_scatter
            .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    }
    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_PREDICATE_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_predicate_finalize
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::Predicate)?;
    p.hir_canonical_predicate_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    stamp_parser_timer(
        timer_ref,
        ctx.encoder,
        "parser.hir_canonical.methods_and_predicates",
    );
    p.hir_canonical_validate
        // The validation rows are canonical-HIR bounded, but the same pass
        // also publishes the raw semantic-row alias map. Dispatch across the
        // raw capacity so every parser row receives an explicit dense-ID
        // result before the type checker starts.
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_decl_index_clear
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    p.hir_canonical_decl_index_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    stamp_parser_timer(
        timer_ref,
        ctx.encoder,
        "parser.hir_canonical.validation_and_decl_index",
    );
    crate::gpu::buffers::record_tracked_buffer_phase_snapshot("compact_hir_materialized");
    Ok(())
}

/// Records stack-effect validation and publishes the combined parser status.
pub fn record_stack_effect_validation(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
    timer_ref: &mut Option<&mut GpuTimer>,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1D;

    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::STACK_EFFECT_CLEAR,
        ctx.encoder,
    )?;

    p.scan_bracket_depths_in_blocks
        .record_pass_indirect(ctx, &ctx.buffers.active_stack_thread_dispatch_args)?;
    stamp_parser_timer(timer_ref, ctx.encoder, "parser.stack_effect.histogram");
    p.scan_bracket_blocks.record_scan(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        ctx.bg_cache
            .as_deref_mut()
            .expect("parser stack validation requires a bind-group cache"),
    )?;
    stamp_parser_timer(timer_ref, ctx.encoder, "parser.stack_effect.histogram_scan");
    p.apply_bracket_block_prefix
        .record_pass_indirect(ctx, &ctx.buffers.active_stack_thread_dispatch_args)?;
    stamp_parser_timer(timer_ref, ctx.encoder, "parser.stack_effect.offsets");
    p.b_min_tree.record_build(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        ctx.bg_cache
            .as_deref_mut()
            .expect("parser stack validation requires a bind-group cache"),
    )?;
    stamp_parser_timer(timer_ref, ctx.encoder, "parser.stack_effect.min_tree");
    if ctx.buffers.emit_stack_matches {
        p.b_clear_matches
            .record_pass_indirect(ctx, &ctx.buffers.active_stack_thread_dispatch_args)?;
    }
    p.pair_brackets_by_layer
        .record_pass_indirect(ctx, &ctx.buffers.active_stack_thread_dispatch_args)?;
    stamp_parser_timer(timer_ref, ctx.encoder, "parser.stack_effect.pair_pse");
    p.status_from_brackets.record_pass(ctx, E1D(1))?;
    stamp_parser_timer(timer_ref, ctx.encoder, "parser.stack_effect.status");

    Ok(())
}

fn stamp_parser_timer(
    timer_ref: &mut Option<&mut GpuTimer>,
    encoder: &mut wgpu::CommandEncoder,
    label: &'static str,
) {
    if let Some(timer) = timer_ref.as_deref_mut() {
        timer.stamp(encoder, label);
    }
}
