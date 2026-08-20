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

    pub(in crate::parser) const fn scan_labels(self) -> (&'static str, &'static str) {
        match self {
            Self::CallArgument => (
                "hir_canonical_call_arg_prefix_01_blocks.up",
                "hir_canonical_call_arg_prefix_01_blocks.down",
            ),
            Self::Parameter => (
                "hir_canonical_param_prefix_01_blocks.up",
                "hir_canonical_param_prefix_01_blocks.down",
            ),
            Self::TypeArgument => (
                "hir_canonical_type_arg_prefix_01_blocks.up",
                "hir_canonical_type_arg_prefix_01_blocks.down",
            ),
            Self::GenericParameter => (
                "hir_canonical_generic_param_prefix_01_blocks.up",
                "hir_canonical_generic_param_prefix_01_blocks.down",
            ),
            Self::Path => (
                "hir_canonical_path_prefix_01_blocks.up",
                "hir_canonical_path_prefix_01_blocks.down",
            ),
            Self::Field => (
                "hir_canonical_field_prefix_01_blocks.up",
                "hir_canonical_field_prefix_01_blocks.down",
            ),
            Self::Variant => (
                "hir_canonical_variant_prefix_01_blocks.up",
                "hir_canonical_variant_prefix_01_blocks.down",
            ),
            Self::VariantPayload => (
                "hir_canonical_variant_payload_prefix_01_blocks.up",
                "hir_canonical_variant_payload_prefix_01_blocks.down",
            ),
            Self::MatchArm => (
                "hir_canonical_match_arm_prefix_01_blocks.up",
                "hir_canonical_match_arm_prefix_01_blocks.down",
            ),
            Self::MatchPayload => (
                "hir_canonical_match_payload_prefix_01_blocks.up",
                "hir_canonical_match_payload_prefix_01_blocks.down",
            ),
            Self::ArrayElement => (
                "hir_canonical_array_element_prefix_01_blocks.up",
                "hir_canonical_array_element_prefix_01_blocks.down",
            ),
            Self::Method => (
                "hir_canonical_method_prefix_01_blocks.up",
                "hir_canonical_method_prefix_01_blocks.down",
            ),
            Self::Predicate => (
                "hir_canonical_predicate_prefix_01_blocks.up",
                "hir_canonical_predicate_prefix_01_blocks.down",
            ),
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
    let (up, down) = construct.scan_labels();
    passes.hir_semantic_prefix_blocks.record_compact_scan(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        ctx.bg_cache
            .as_deref_mut()
            .expect("parser scan requires a bind-group cache"),
        up,
        down,
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
/// Active adjacent-pair parse table pass.
pub mod llp_pairs;
/// Variable-length parse stream packing passes.
pub mod pack;
/// Source-file token boundary pass.
pub mod source_file_token_end;
/// Parser acceptance status passes.
pub mod status;
pub(in crate::parser) mod token_frontend;
/// Parser tree recovery passes.
pub mod tree;

/// Loaded compute passes for the parser pipeline.
pub struct ParserPasses {
    pub(in crate::parser) token_frontend: token_frontend::TokenFrontendPasses,
    pub(in crate::parser) active_pair_dispatch_args: PassData,
    pub(in crate::parser) tree_feature_dispatch_args: PassData,
    pub llp_pairs: llp_pairs::LLPPairsPass,
    pub pack_offsets: pack::offsets::PackOffsetsScanPass,
    pub pack_offsets_status: pack::offsets::status::PackOffsetsStatusPass,
    pub pack_totals_blocks: pack::totals::blocks::PackTotalsBlocksPass,
    pub pack_totals_reduce: pack::totals::reduce::PackTotalsReducePass,
    pub pack_totals_status: pack::totals::status::PackTotalsStatusPass,
    pub pack_varlen: pack::varlen::PackVarlenPass,
    pub status_from_brackets: status::ParserStatusFromBracketsPass,
    pub source_file_token_end: source_file_token_end::SourceFileTokenEndPass,

    // Bracket matching passes
    pub b01: brackets::scan_inblock::BracketsScanInblockPass,
    pub b02: brackets::scan_block_prefix::BracketsScanBlockPrefixPass,
    pub b03: brackets::apply_prefix::BracketsApplyPrefixPass,
    pub b_clear_matches: brackets::clear_matches::BracketsClearMatchesPass,
    pub b_min_tree: brackets::min_tree::BracketsMinTreePass,
    pub pse04: brackets::pse_pair::BracketsPsePairPass, // Replaces b07

    // Tree building pass
    pub tree_prefix_01: tree::prefix::local::TreePrefixLocalPass,
    pub tree_prefix_02: tree::prefix::scan_blocks::TreePrefixScanBlocksPass,
    pub tree_prefix_03: tree::prefix::apply::TreePrefixApplyPass,
    pub tree_prefix_04: tree::prefix::build_max_tree::TreePrefixMaxBuildPass,
    pub tree_active_dispatch_args: tree::active_dispatch_args::TreeActiveDispatchArgsPass,
    pub tree_parent: tree::parent::TreeParentPass,
    pub tree_spans: tree::spans::TreeSpansPass,
    pub tree_depth_traverse: tree::depth::traverse::TreeDepthTraversePass,
    pub tree_depth_block_max: tree::depth::block_max::TreeDepthBlockMaxPass,
    pub tree_depth_schedule: tree::depth::schedule::TreeDepthSchedulePass,
    pub tree_prev_sibling_clear: tree::prev::sibling::clear::TreePrevSiblingClearPass,
    pub tree_prev_sibling_scatter: tree::prev::sibling::scatter::TreePrevSiblingScatterPass,

    // HIR-facing classification
    pub hir_nodes: hir::nodes::HirNodesPass,
    pub hir_semantic_prefix_local: hir::semantic::prefix::local::HirSemanticPrefixLocalPass,
    pub hir_semantic_prefix_blocks: hir::semantic::prefix::blocks::HirSemanticPrefixBlocksPass,
    pub hir_semantic_compact_scatter: hir::semantic::compact_scatter::HirSemanticCompactScatterPass,
    pub hir_semantic_dispatch_args: hir::semantic::dispatch_args::HirSemanticDispatchArgsPass,
    pub hir_semantic_subtree_end: hir::semantic::subtree_end::HirSemanticSubtreeEndPass,
    pub hir_semantic_parent_traverse:
        hir::semantic::parent::traverse::HirSemanticParentTraversePass,
    pub hir_tree_relations: hir::semantic::parent::step::TreeRelationOperation,
    pub hir_semantic_nav: hir::semantic::nav::HirSemanticNavPass,
    pub hir_semantic_child_index_traverse:
        hir::semantic::child::index::traverse::HirSemanticChildIndexTraversePass,
    pub hir_record_clear_base: hir::record::clear::base::HirRecordClearBasePass,
    pub hir_record_clear_calls: hir::record::clear::calls::HirRecordClearCallsPass,
    pub hir_spans: hir::spans::HirSpansPass,
    pub hir_type_fields: hir::types::fields::HirTypeFieldsPass,
    pub hir_type_path_leaf_step: hir::types::path::leaf::step::HirTypePathLeafStepPass,
    pub hir_type_path_leaf_scatter: hir::types::path::leaf::scatter::HirTypePathLeafScatterPass,
    pub hir_path_segment_root: hir::path::segment::root::HirPathSegmentRootPass,
    pub hir_path_segment_links: hir::path::segment::links::HirPathSegmentLinksPass,
    pub hir_path_segment_step: hir::path::segment::step::HirPathSegmentStepPass,
    pub hir_path_segment_scatter: hir::path::segment::scatter::HirPathSegmentScatterPass,
    pub hir_list_rank_prefix_local: hir::list::rank::prefix_local::HirListRankPrefixLocalPass,
    pub hir_list_rank_compact_scatter:
        hir::list::rank::compact_scatter::HirListRankCompactScatterPass,
    pub hir_list_rank_step: hir::list::rank::step::HirListRankStepOperation,
    pub hir_type_arg_links: hir::types::arg::links::HirTypeArgLinksPass,
    pub hir_type_arg_scatter: hir::types::arg::scatter::HirTypeArgScatterPass,
    pub hir_type_root_owner_init: hir::types::root::init::HirTypeRootOwnerInitPass,
    pub hir_type_root_owner_step: hir::types::root::step::HirTypeRootOwnerStepPass,
    pub hir_type_alias_owner_init: hir::types::alias::owner::init::HirTypeAliasOwnerInitPass,
    pub hir_type_alias_owner_step: hir::types::alias::owner::step::HirTypeAliasOwnerStepPass,
    pub hir_type_alias_target: hir::types::alias::target::HirTypeAliasTargetPass,
    pub hir_fn_return_type: hir::functions::return_type::HirFnReturnTypePass,
    pub hir_method_signature_status: hir::method::signature_status::HirMethodSignatureStatusPass,
    pub hir_item_fields: hir::item::fields::HirItemFieldsPass,
    pub hir_canonical_mark: hir::canonical::mark::HirCanonicalMarkPass,
    pub hir_canonical_local: hir::canonical::local::HirCanonicalLocalPass,
    pub hir_canonical_scatter: hir::canonical::scatter::HirCanonicalScatterPass,
    pub hir_canonical_stmt_compact: hir::canonical::stmt_compact::HirCanonicalStmtCompactPass,
    pub hir_canonical_identity_aliases:
        hir::canonical::identity_aliases::HirCanonicalIdentityAliasesPass,
    pub hir_canonical_core: hir::canonical::core::HirCanonicalCorePass,
    pub hir_canonical_nav: hir::canonical::nav::HirCanonicalNavPass,
    pub hir_canonical_expr_forest_edges:
        hir::canonical::expr_forest::edges::HirCanonicalExprForestEdgesPass,
    pub hir_canonical_expr_forest_root_init:
        hir::canonical::expr_forest::root_init::HirCanonicalExprForestRootInitPass,
    pub hir_canonical_expr_forest_root_step:
        hir::canonical::expr_forest::root_step::HirCanonicalExprForestRootStepPass,
    pub hir_canonical_validate: hir::canonical::validate::HirCanonicalValidatePass,
    pub hir_canonical_decl_index_clear: hir::canonical::decl_index::HirCanonicalDeclIndexClearPass,
    pub hir_canonical_decl_index_scatter:
        hir::canonical::decl_index::HirCanonicalDeclIndexScatterPass,
    pub hir_canonical_call_arg_mark: hir::canonical::call_args::mark::HirCanonicalCallArgMarkPass,
    pub exclusive_u32_local_scan: PassData,
    pub hir_canonical_call_arg_scatter:
        hir::canonical::call_args::scatter::HirCanonicalCallArgScatterPass,
    pub hir_canonical_param_mark: hir::canonical::params::mark::HirCanonicalParamMarkPass,
    pub hir_canonical_param_scatter: hir::canonical::params::scatter::HirCanonicalParamScatterPass,
    pub hir_canonical_type_arg_mark: hir::canonical::type_args::mark::HirCanonicalTypeArgMarkPass,
    pub hir_canonical_type_arg_scatter:
        hir::canonical::type_args::scatter::HirCanonicalTypeArgScatterPass,
    pub hir_canonical_generic_param_candidate_mark:
        hir::canonical::generic_params::candidate_mark::HirCanonicalGenericParamCandidateMarkPass,
    pub hir_canonical_generic_param_finalize:
        hir::canonical::generic_params::finalize::HirCanonicalGenericParamFinalizePass,
    pub hir_canonical_generic_param_scatter:
        hir::canonical::generic_params::scatter::HirCanonicalGenericParamScatterPass,
    pub hir_canonical_path_segment_mark:
        hir::canonical::paths::segments::mark::HirCanonicalPathSegmentMarkPass,
    pub hir_canonical_path_segment_scatter:
        hir::canonical::paths::segments::scatter::HirCanonicalPathSegmentScatterPass,
    pub hir_canonical_path_mark: hir::canonical::paths::mark::HirCanonicalPathMarkPass,
    pub hir_canonical_path_scatter: hir::canonical::paths::scatter::HirCanonicalPathScatterPass,
    pub hir_canonical_field_mark: hir::canonical::fields::mark::HirCanonicalFieldMarkPass,
    pub hir_canonical_field_scatter: hir::canonical::fields::scatter::HirCanonicalFieldScatterPass,
    pub hir_canonical_variant_mark: hir::canonical::variants::mark::HirCanonicalVariantMarkPass,
    pub hir_canonical_variant_scatter:
        hir::canonical::variants::scatter::HirCanonicalVariantScatterPass,
    pub hir_canonical_variant_payload_owner_init:
        hir::canonical::variants::payload_owner_init::HirCanonicalVariantPayloadOwnerInitPass,
    pub hir_canonical_variant_payload_scatter:
        hir::canonical::variants::payload_scatter::HirCanonicalVariantPayloadScatterPass,
    pub hir_canonical_variant_payload_ordinal:
        hir::canonical::variants::payload_ordinal::HirCanonicalVariantPayloadOrdinalPass,
    pub hir_canonical_match_arm_mark:
        hir::canonical::matches::arms::mark::HirCanonicalMatchArmMarkPass,
    pub hir_canonical_match_arm_scatter:
        hir::canonical::matches::arms::scatter::HirCanonicalMatchArmScatterPass,
    pub hir_canonical_match_payload_mark:
        hir::canonical::matches::payloads::mark::HirCanonicalMatchPayloadMarkPass,
    pub hir_canonical_match_payload_scatter:
        hir::canonical::matches::payloads::scatter::HirCanonicalMatchPayloadScatterPass,
    pub hir_canonical_array_element_mark:
        hir::canonical::array_elements::mark::HirCanonicalArrayElementMarkPass,
    pub hir_canonical_array_element_scatter:
        hir::canonical::array_elements::scatter::HirCanonicalArrayElementScatterPass,
    pub hir_canonical_string_scatter:
        hir::canonical::strings::scatter::HirCanonicalStringScatterPass,
    pub hir_canonical_method_mark: hir::canonical::methods::mark::HirCanonicalMethodMarkPass,
    pub hir_canonical_method_scatter:
        hir::canonical::methods::scatter::HirCanonicalMethodScatterPass,
    pub hir_canonical_predicate_finalize:
        hir::canonical::predicates::finalize::HirCanonicalPredicateFinalizePass,
    pub hir_canonical_predicate_scatter:
        hir::canonical::predicates::scatter::HirCanonicalPredicateScatterPass,
    pub hir_param_links: hir::param::links::HirParamLinksPass,
    pub hir_param_id_clear: hir::param::id_clear::HirParamIdClearPass,
    pub hir_param_id_base: hir::param::id_base::HirParamIdBasePass,
    pub hir_param_id_apply: hir::param::id_apply::HirParamIdApplyPass,
    pub hir_param_fields: hir::param::fields::HirParamFieldsPass,
    pub hir_method_fields: hir::method::fields::HirMethodFieldsPass,
    pub hir_expr_fields: hir::expr::fields::HirExprFieldsPass,
    pub hir_expr_result_root_step: hir::expr::result_root_step::HirExprResultRootStepPass,
    pub hir_binary_span_apply: hir::binary::span::apply::HirBinarySpanApplyPass,
    pub hir_binary_span_step: hir::binary::span::step::HirBinarySpanStepPass,
    pub hir_binary_spans: hir::binary::spans::HirBinarySpansPass,
    pub hir_postfix_fields: hir::postfix_fields::HirPostfixFieldsPass,
    pub hir_member_spans: hir::member::spans::HirMemberSpansPass,
    pub hir_range_spans: hir::range_spans::HirRangeSpansPass,
    pub hir_stmt_fields: hir::stmt_fields::HirStmtFieldsPass,
    pub hir_stmt_scope: hir::stmt_scope::HirStmtScopePass,
    pub hir_literal_values: hir::literal_values::HirLiteralValuesPass,
    pub hir_string_compact_local: hir::string::compact_local::HirStringCompactLocalPass,
    pub hir_string_compact_scatter: hir::string::compact_scatter::HirStringCompactScatterPass,
    pub hir_string_offset_local: hir::string::offset_local::HirStringOffsetLocalPass,
    pub hir_string_offset_scatter: hir::string::offset_scatter::HirStringOffsetScatterPass,
    pub hir_string_decode: hir::string::decode::HirStringDecodePass,
    pub hir_call_fields: hir::call::fields::HirCallFieldsPass,
    pub hir_call_spans: hir::call::spans::HirCallSpansPass,
    pub hir_call_arg_links: hir::call::arg::links::HirCallArgLinksPass,
    pub hir_call_arg_ordinal_scatter:
        hir::call::arg::ordinal::scatter::HirCallArgOrdinalScatterPass,
    pub hir_array_element_links: hir::array::element::links::HirArrayElementLinksPass,
    pub hir_array_element_scatter: hir::array::element::scatter::HirArrayElementScatterPass,
    pub hir_enum_variant_links: hir::enums::variant::links::HirEnumVariantLinksPass,
    pub hir_enum_rank_prefix_local: hir::enums::rank::prefix_local::HirEnumRankPrefixLocalPass,
    pub hir_enum_rank_compact_scatter:
        hir::enums::rank::compact_scatter::HirEnumRankCompactScatterPass,
    pub hir_enum_variant_rank_step: hir::enums::variant::rank_step::HirEnumVariantRankStepPass,
    pub hir_enum_variant_scatter: hir::enums::variant::scatter::HirEnumVariantScatterPass,
    pub hir_match_arm_owner_init: hir::matches::arm::owner_init::HirMatchArmOwnerInitPass,
    pub hir_match_arm_links: hir::matches::arm::links::HirMatchArmLinksPass,
    pub hir_match_rank_prefix_local: hir::matches::rank::prefix_local::HirMatchRankPrefixLocalPass,
    pub hir_match_rank_compact_scatter:
        hir::matches::rank::compact_scatter::HirMatchRankCompactScatterPass,
    pub hir_match_arm_rank_step: hir::matches::arm::rank_step::HirMatchArmRankStepPass,
    pub hir_match_arm_scatter: hir::matches::arm::scatter::HirMatchArmScatterPass,
    pub hir_context_relations_init: hir::context::relations::init::HirContextRelationsInitPass,
    pub hir_context_relations_step: hir::context::relations::step::HirContextRelationsStepPass,
    pub hir_context_relations_step_small:
        hir::context::relations::step_small::HirContextRelationsStepSmallPass,
    pub hir_context_relations_scatter:
        hir::context::relations::scatter::HirContextRelationsScatterPass,
    pub hir_struct_fields: hir::structs::fields::HirStructFieldsPass,
    pub hir_struct_field_links: hir::structs::field::links::HirStructFieldLinksPass,
    pub hir_struct_lit_spans: hir::structs::lit_spans::HirStructLitSpansPass,
    pub hir_struct_rank_prefix_local:
        hir::structs::rank::prefix_local::HirStructRankPrefixLocalPass,
    pub hir_struct_rank_compact_scatter:
        hir::structs::rank::compact_scatter::HirStructRankCompactScatterPass,
    pub hir_struct_field_rank_step: hir::structs::field::rank_step::HirStructFieldRankStepPass,
    pub hir_struct_field_scatter: hir::structs::field::scatter::HirStructFieldScatterPass,
}

impl ParserPasses {
    /// Loads every parser compute pass for a GPU device.
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            token_frontend: token_frontend::TokenFrontendPasses::new(device)?,
            active_pair_dispatch_args: crate::gpu::passes_core::make_main_pass!(
                device,
                "parser_active_pair_dispatch_args",
                shader: "parser/active_pair_dispatch_args"
            )?,
            tree_feature_dispatch_args: crate::gpu::passes_core::make_main_pass!(
                device,
                "parser_tree_feature_dispatch_args",
                shader: "parser/tree/feature_dispatch_args"
            )?,
            llp_pairs: llp_pairs::LLPPairsPass::new(device)?,
            pack_offsets: pack::offsets::PackOffsetsScanPass::new(device)?,
            pack_offsets_status: pack::offsets::status::PackOffsetsStatusPass::new(device)?,
            pack_totals_blocks: pack::totals::blocks::PackTotalsBlocksPass::new(device)?,
            pack_totals_reduce: pack::totals::reduce::PackTotalsReducePass::new(device)?,
            pack_totals_status: pack::totals::status::PackTotalsStatusPass::new(device)?,
            pack_varlen: pack::varlen::PackVarlenPass::new(device)?,
            status_from_brackets: status::ParserStatusFromBracketsPass::new(device)?,
            source_file_token_end: source_file_token_end::SourceFileTokenEndPass::new(device)?,

            b01: brackets::scan_inblock::BracketsScanInblockPass::new(device)?,
            b02: brackets::scan_block_prefix::BracketsScanBlockPrefixPass::new(device)?,
            b03: brackets::apply_prefix::BracketsApplyPrefixPass::new(device)?,
            b_clear_matches: brackets::clear_matches::BracketsClearMatchesPass::new(device)?,
            b_min_tree: brackets::min_tree::BracketsMinTreePass::new(device)?,
            pse04: brackets::pse_pair::BracketsPsePairPass::new(device)?,

            tree_parent: tree::parent::TreeParentPass::new(device)?,
            tree_prefix_01: tree::prefix::local::TreePrefixLocalPass::new(device)?,
            tree_prefix_02: tree::prefix::scan_blocks::TreePrefixScanBlocksPass::new(device)?,
            tree_prefix_03: tree::prefix::apply::TreePrefixApplyPass::new(device)?,
            tree_prefix_04: tree::prefix::build_max_tree::TreePrefixMaxBuildPass::new(device)?,
            tree_active_dispatch_args:
                tree::active_dispatch_args::TreeActiveDispatchArgsPass::new(device)?,
            tree_spans: tree::spans::TreeSpansPass::new(device)?,
            tree_depth_traverse: tree::depth::traverse::TreeDepthTraversePass::new(device)?,
            tree_depth_block_max: tree::depth::block_max::TreeDepthBlockMaxPass::new(device)?,
            tree_depth_schedule: tree::depth::schedule::TreeDepthSchedulePass::new(device)?,
            tree_prev_sibling_clear: tree::prev::sibling::clear::TreePrevSiblingClearPass::new(
                device,
            )?,
            tree_prev_sibling_scatter:
                tree::prev::sibling::scatter::TreePrevSiblingScatterPass::new(device)?,
            hir_nodes: hir::nodes::HirNodesPass::new(device)?,
            hir_semantic_prefix_local:
                hir::semantic::prefix::local::HirSemanticPrefixLocalPass::new(device)?,
            hir_semantic_prefix_blocks:
                hir::semantic::prefix::blocks::HirSemanticPrefixBlocksPass::new(device)?,
            hir_semantic_compact_scatter:
                hir::semantic::compact_scatter::HirSemanticCompactScatterPass::new(device)?,
            hir_semantic_dispatch_args:
                hir::semantic::dispatch_args::HirSemanticDispatchArgsPass::new(device)?,
            hir_semantic_subtree_end: hir::semantic::subtree_end::HirSemanticSubtreeEndPass::new(
                device,
            )?,
            hir_semantic_parent_traverse:
                hir::semantic::parent::traverse::HirSemanticParentTraversePass::new(device)?,
            hir_tree_relations: hir::semantic::parent::step::TreeRelationOperation::new(
                device,
            )?,
            hir_semantic_nav: hir::semantic::nav::HirSemanticNavPass::new(device)?,
            hir_semantic_child_index_traverse:
                hir::semantic::child::index::traverse::HirSemanticChildIndexTraversePass::new(
                    device,
                )?,
            hir_record_clear_base: hir::record::clear::base::HirRecordClearBasePass::new(device)?,
            hir_record_clear_calls: hir::record::clear::calls::HirRecordClearCallsPass::new(
                device,
            )?,
            hir_spans: hir::spans::HirSpansPass::new(device)?,
            hir_type_fields: hir::types::fields::HirTypeFieldsPass::new(device)?,
            hir_type_path_leaf_step: hir::types::path::leaf::step::HirTypePathLeafStepPass::new(
                device,
            )?,
            hir_type_path_leaf_scatter:
                hir::types::path::leaf::scatter::HirTypePathLeafScatterPass::new(device)?,
            hir_path_segment_root: hir::path::segment::root::HirPathSegmentRootPass::new(device)?,
            hir_path_segment_links: hir::path::segment::links::HirPathSegmentLinksPass::new(
                device,
            )?,
            hir_path_segment_step: hir::path::segment::step::HirPathSegmentStepPass::new(device)?,
            hir_path_segment_scatter: hir::path::segment::scatter::HirPathSegmentScatterPass::new(
                device,
            )?,
            hir_list_rank_prefix_local:
                hir::list::rank::prefix_local::HirListRankPrefixLocalPass::new(device)?,
            hir_list_rank_compact_scatter:
                hir::list::rank::compact_scatter::HirListRankCompactScatterPass::new(device)?,
            hir_list_rank_step: hir::list::rank::step::HirListRankStepOperation::new(device)?,
            hir_type_arg_links: hir::types::arg::links::HirTypeArgLinksPass::new(device)?,
            hir_type_arg_scatter: hir::types::arg::scatter::HirTypeArgScatterPass::new(device)?,
            hir_type_root_owner_init: hir::types::root::init::HirTypeRootOwnerInitPass::new(
                device,
            )?,
            hir_type_root_owner_step: hir::types::root::step::HirTypeRootOwnerStepPass::new(
                device,
            )?,
            hir_type_alias_owner_init:
                hir::types::alias::owner::init::HirTypeAliasOwnerInitPass::new(device)?,
            hir_type_alias_owner_step:
                hir::types::alias::owner::step::HirTypeAliasOwnerStepPass::new(device)?,
            hir_type_alias_target: hir::types::alias::target::HirTypeAliasTargetPass::new(device)?,
            hir_fn_return_type: hir::functions::return_type::HirFnReturnTypePass::new(device)?,
            hir_method_signature_status:
                hir::method::signature_status::HirMethodSignatureStatusPass::new(device)?,
            hir_item_fields: hir::item::fields::HirItemFieldsPass::new(device)?,
            hir_canonical_mark: hir::canonical::mark::HirCanonicalMarkPass::new(device)?,
            hir_canonical_local: hir::canonical::local::HirCanonicalLocalPass::new(device)?,
            hir_canonical_scatter: hir::canonical::scatter::HirCanonicalScatterPass::new(device)?,
            hir_canonical_stmt_compact:
                hir::canonical::stmt_compact::HirCanonicalStmtCompactPass::new(device)?,
            hir_canonical_identity_aliases:
                hir::canonical::identity_aliases::HirCanonicalIdentityAliasesPass::new(device)?,
            hir_canonical_core: hir::canonical::core::HirCanonicalCorePass::new(device)?,
            hir_canonical_nav: hir::canonical::nav::HirCanonicalNavPass::new(device)?,
            hir_canonical_expr_forest_edges:
                hir::canonical::expr_forest::edges::HirCanonicalExprForestEdgesPass::new(
                    device,
                )?,
            hir_canonical_expr_forest_root_init:
                hir::canonical::expr_forest::root_init::HirCanonicalExprForestRootInitPass::new(
                    device,
                )?,
            hir_canonical_expr_forest_root_step:
                hir::canonical::expr_forest::root_step::HirCanonicalExprForestRootStepPass::new(
                    device,
                )?,
            hir_canonical_validate: hir::canonical::validate::HirCanonicalValidatePass::new(
                device,
            )?,
            hir_canonical_decl_index_clear:
                hir::canonical::decl_index::HirCanonicalDeclIndexClearPass::new(device)?,
            hir_canonical_decl_index_scatter:
                hir::canonical::decl_index::HirCanonicalDeclIndexScatterPass::new(device)?,
            hir_canonical_call_arg_mark:
                hir::canonical::call_args::mark::HirCanonicalCallArgMarkPass::new(device)?,
            exclusive_u32_local_scan: crate::gpu::passes_core::make_main_pass!(
                device,
                "exclusive_u32_local_scan",
                shader: "scan/exclusive_u32_local"
            )?,
            hir_canonical_call_arg_scatter:
                hir::canonical::call_args::scatter::HirCanonicalCallArgScatterPass::new(device)?,
            hir_canonical_param_mark: hir::canonical::params::mark::HirCanonicalParamMarkPass::new(
                device,
            )?,
            hir_canonical_param_scatter:
                hir::canonical::params::scatter::HirCanonicalParamScatterPass::new(device)?,
            hir_canonical_type_arg_mark:
                hir::canonical::type_args::mark::HirCanonicalTypeArgMarkPass::new(device)?,
            hir_canonical_type_arg_scatter:
                hir::canonical::type_args::scatter::HirCanonicalTypeArgScatterPass::new(device)?,
            hir_canonical_generic_param_candidate_mark:
                hir::canonical::generic_params::candidate_mark::HirCanonicalGenericParamCandidateMarkPass::new(device)?,
            hir_canonical_generic_param_finalize:
                hir::canonical::generic_params::finalize::HirCanonicalGenericParamFinalizePass::new(device)?,
            hir_canonical_generic_param_scatter:
                hir::canonical::generic_params::scatter::HirCanonicalGenericParamScatterPass::new(device)?,
            hir_canonical_path_segment_mark:
                hir::canonical::paths::segments::mark::HirCanonicalPathSegmentMarkPass::new(device)?,
            hir_canonical_path_segment_scatter:
                hir::canonical::paths::segments::scatter::HirCanonicalPathSegmentScatterPass::new(device)?,
            hir_canonical_path_mark:
                hir::canonical::paths::mark::HirCanonicalPathMarkPass::new(device)?,
            hir_canonical_path_scatter:
                hir::canonical::paths::scatter::HirCanonicalPathScatterPass::new(device)?,
            hir_canonical_field_mark:
                hir::canonical::fields::mark::HirCanonicalFieldMarkPass::new(device)?,
            hir_canonical_field_scatter:
                hir::canonical::fields::scatter::HirCanonicalFieldScatterPass::new(device)?,
            hir_canonical_variant_mark:
                hir::canonical::variants::mark::HirCanonicalVariantMarkPass::new(device)?,
            hir_canonical_variant_scatter:
                hir::canonical::variants::scatter::HirCanonicalVariantScatterPass::new(device)?,
            hir_canonical_variant_payload_owner_init:
                hir::canonical::variants::payload_owner_init::HirCanonicalVariantPayloadOwnerInitPass::new(device)?,
            hir_canonical_variant_payload_scatter:
                hir::canonical::variants::payload_scatter::HirCanonicalVariantPayloadScatterPass::new(device)?,
            hir_canonical_variant_payload_ordinal:
                hir::canonical::variants::payload_ordinal::HirCanonicalVariantPayloadOrdinalPass::new(device)?,
            hir_canonical_match_arm_mark:
                hir::canonical::matches::arms::mark::HirCanonicalMatchArmMarkPass::new(device)?,
            hir_canonical_match_arm_scatter:
                hir::canonical::matches::arms::scatter::HirCanonicalMatchArmScatterPass::new(device)?,
            hir_canonical_match_payload_mark:
                hir::canonical::matches::payloads::mark::HirCanonicalMatchPayloadMarkPass::new(device)?,
            hir_canonical_match_payload_scatter:
                hir::canonical::matches::payloads::scatter::HirCanonicalMatchPayloadScatterPass::new(device)?,
            hir_canonical_array_element_mark:
                hir::canonical::array_elements::mark::HirCanonicalArrayElementMarkPass::new(device)?,
            hir_canonical_array_element_scatter:
                hir::canonical::array_elements::scatter::HirCanonicalArrayElementScatterPass::new(device)?,
            hir_param_links: hir::param::links::HirParamLinksPass::new(device)?,
            hir_param_id_clear: hir::param::id_clear::HirParamIdClearPass::new(device)?,
            hir_param_id_base: hir::param::id_base::HirParamIdBasePass::new(device)?,
            hir_param_id_apply: hir::param::id_apply::HirParamIdApplyPass::new(device)?,
            hir_param_fields: hir::param::fields::HirParamFieldsPass::new(device)?,
            hir_method_fields: hir::method::fields::HirMethodFieldsPass::new(device)?,
            hir_expr_fields: hir::expr::fields::HirExprFieldsPass::new(device)?,
            hir_expr_result_root_step: hir::expr::result_root_step::HirExprResultRootStepPass::new(
                device,
            )?,
            hir_binary_span_apply: hir::binary::span::apply::HirBinarySpanApplyPass::new(device)?,
            hir_binary_span_step: hir::binary::span::step::HirBinarySpanStepPass::new(device)?,
            hir_binary_spans: hir::binary::spans::HirBinarySpansPass::new(device)?,
            hir_postfix_fields: hir::postfix_fields::HirPostfixFieldsPass::new(device)?,
            hir_member_spans: hir::member::spans::HirMemberSpansPass::new(device)?,
            hir_range_spans: hir::range_spans::HirRangeSpansPass::new(device)?,
            hir_stmt_fields: hir::stmt_fields::HirStmtFieldsPass::new(device)?,
            hir_stmt_scope: hir::stmt_scope::HirStmtScopePass::new(device)?,
            hir_literal_values: hir::literal_values::HirLiteralValuesPass::new(device)?,
            hir_string_compact_local: hir::string::compact_local::HirStringCompactLocalPass::new(
                device,
            )?,
            hir_string_compact_scatter:
                hir::string::compact_scatter::HirStringCompactScatterPass::new(device)?,
            hir_string_offset_local: hir::string::offset_local::HirStringOffsetLocalPass::new(
                device,
            )?,
            hir_string_offset_scatter:
                hir::string::offset_scatter::HirStringOffsetScatterPass::new(device)?,
            hir_string_decode: hir::string::decode::HirStringDecodePass::new(device)?,
            hir_canonical_string_scatter:
                hir::canonical::strings::scatter::HirCanonicalStringScatterPass::new(device)?,
            hir_canonical_method_mark:
                hir::canonical::methods::mark::HirCanonicalMethodMarkPass::new(device)?,
            hir_canonical_method_scatter:
                hir::canonical::methods::scatter::HirCanonicalMethodScatterPass::new(device)?,
            hir_canonical_predicate_finalize:
                hir::canonical::predicates::finalize::HirCanonicalPredicateFinalizePass::new(device)?,
            hir_canonical_predicate_scatter:
                hir::canonical::predicates::scatter::HirCanonicalPredicateScatterPass::new(device)?,
            hir_call_fields: hir::call::fields::HirCallFieldsPass::new(device)?,
            hir_call_spans: hir::call::spans::HirCallSpansPass::new(device)?,
            hir_call_arg_links: hir::call::arg::links::HirCallArgLinksPass::new(device)?,
            hir_call_arg_ordinal_scatter:
                hir::call::arg::ordinal::scatter::HirCallArgOrdinalScatterPass::new(device)?,
            hir_array_element_links: hir::array::element::links::HirArrayElementLinksPass::new(
                device,
            )?,
            hir_array_element_scatter:
                hir::array::element::scatter::HirArrayElementScatterPass::new(device)?,
            hir_enum_variant_links: hir::enums::variant::links::HirEnumVariantLinksPass::new(
                device,
            )?,
            hir_enum_rank_prefix_local:
                hir::enums::rank::prefix_local::HirEnumRankPrefixLocalPass::new(device)?,
            hir_enum_rank_compact_scatter:
                hir::enums::rank::compact_scatter::HirEnumRankCompactScatterPass::new(device)?,
            hir_enum_variant_rank_step:
                hir::enums::variant::rank_step::HirEnumVariantRankStepPass::new(device)?,
            hir_enum_variant_scatter: hir::enums::variant::scatter::HirEnumVariantScatterPass::new(
                device,
            )?,
            hir_match_arm_owner_init:
                hir::matches::arm::owner_init::HirMatchArmOwnerInitPass::new(device)?,
            hir_match_arm_links: hir::matches::arm::links::HirMatchArmLinksPass::new(device)?,
            hir_match_rank_prefix_local:
                hir::matches::rank::prefix_local::HirMatchRankPrefixLocalPass::new(device)?,
            hir_match_rank_compact_scatter:
                hir::matches::rank::compact_scatter::HirMatchRankCompactScatterPass::new(device)?,
            hir_match_arm_rank_step: hir::matches::arm::rank_step::HirMatchArmRankStepPass::new(
                device,
            )?,
            hir_match_arm_scatter: hir::matches::arm::scatter::HirMatchArmScatterPass::new(device)?,
            hir_context_relations_init:
                hir::context::relations::init::HirContextRelationsInitPass::new(device)?,
            hir_context_relations_step:
                hir::context::relations::step::HirContextRelationsStepPass::new(device)?,
            hir_context_relations_step_small:
                hir::context::relations::step_small::HirContextRelationsStepSmallPass::new(device)?,
            hir_context_relations_scatter:
                hir::context::relations::scatter::HirContextRelationsScatterPass::new(device)?,
            hir_struct_fields: hir::structs::fields::HirStructFieldsPass::new(device)?,
            hir_struct_field_links: hir::structs::field::links::HirStructFieldLinksPass::new(
                device,
            )?,
            hir_struct_lit_spans: hir::structs::lit_spans::HirStructLitSpansPass::new(device)?,
            hir_struct_rank_prefix_local:
                hir::structs::rank::prefix_local::HirStructRankPrefixLocalPass::new(device)?,
            hir_struct_rank_compact_scatter:
                hir::structs::rank::compact_scatter::HirStructRankCompactScatterPass::new(device)?,
            hir_struct_field_rank_step:
                hir::structs::field::rank_step::HirStructFieldRankStepPass::new(device)?,
            hir_struct_field_scatter: hir::structs::field::scatter::HirStructFieldScatterPass::new(
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
    p.hir_canonical_variant_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::Variant)?;
    p.hir_canonical_variant_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);

    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_VARIANT_PAYLOAD_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_variant_payload_owner_init
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_tree_relations.record_canonical_steps(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        hir::semantic::parent::step::CANONICAL_VARIANT_PAYLOAD_OWNER,
        ctx.bg_cache
            .as_deref_mut()
            .expect("debug parser requires a bind-group cache"),
    )?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::VariantPayload)?;
    p.hir_canonical_variant_payload_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    p.hir_canonical_variant_payload_ordinal
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
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
    // The local scan consumes atomic anchor winners. Keep this as an explicit
    // pass boundary: same-pass dispatch ordering does not provide a portable
    // storage-memory barrier for atomics through wgpu backends.
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
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
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    p.hir_canonical_identity_aliases
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
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
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    Ok(())
}

/// Compacts call arguments immediately after their raw owner/rank relation is
/// finalized, before the shared raw-family workspace is reused.
pub fn record_canonical_call_arguments(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1D;

    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_CALL_ARGUMENT_CLEAR,
        ctx.encoder,
    )?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::CallArgument)?;
    p.hir_canonical_call_arg_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
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
    p.hir_canonical_array_element_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::ArrayElement)?;
    p.hir_canonical_array_element_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
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
    p.hir_canonical_match_arm_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::MatchArm)?;
    p.hir_canonical_match_arm_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);

    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_MATCH_PAYLOAD_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_match_payload_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::MatchPayload)?;
    p.hir_canonical_match_payload_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
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
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
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
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);

    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_TYPE_ARGUMENT_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_type_arg_mark
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::TypeArgument)?;
    p.hir_canonical_type_arg_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
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

    p.hir_canonical_core
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    stamp_parser_timer(timer_ref, ctx.encoder, "parser.hir_canonical.core");
    p.hir_canonical_nav
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    stamp_parser_timer(timer_ref, ctx.encoder, "parser.hir_canonical.nav");
    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_EXPR_FOREST_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_expr_forest_edges
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
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
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
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
        crate::parser::compiler_graph::HIR_PATH_SEGMENT_SCAN_UP,
        crate::parser::compiler_graph::HIR_PATH_SEGMENT_SCAN_DOWN,
    )?;
    p.hir_canonical_path_segment_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    ctx.buffers.clear_operations().record_phase(
        crate::parser::compiler_graph::hir::CANONICAL_PATH_CLEAR,
        ctx.encoder,
    )?;
    p.hir_canonical_path_mark
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    record_canonical_compaction_prefix(ctx, p, CanonicalConstruct::Path)?;
    p.hir_canonical_path_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    p.hir_canonical_string_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
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
        crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
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
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
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
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    p.hir_canonical_decl_index_clear
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    p.hir_canonical_decl_index_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
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

    p.b01
        .record_pass_indirect(ctx, &ctx.buffers.active_stack_thread_dispatch_args)?;
    stamp_parser_timer(timer_ref, ctx.encoder, "parser.stack_effect.histogram");
    p.b02.record_scan(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        ctx.bg_cache
            .as_deref_mut()
            .expect("parser stack validation requires a bind-group cache"),
    )?;
    stamp_parser_timer(timer_ref, ctx.encoder, "parser.stack_effect.histogram_scan");
    p.b03
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
    p.pse04
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
