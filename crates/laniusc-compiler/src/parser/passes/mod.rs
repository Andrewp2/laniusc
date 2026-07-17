//! Parser compute pass bundle and debug recording entry point.

use anyhow::Result;

use crate::{
    gpu::{
        passes_core::{InputElements, Pass, PassContext},
        timer::GpuTimer,
    },
    parser::{buffers::ParserBuffers, debug::DebugOutput},
};

fn parser_clear_buffer(
    encoder: &mut wgpu::CommandEncoder,
    buffer: &wgpu::Buffer,
    offset: u64,
    size: Option<u64>,
) {
    crate::gpu::passes_core::flush_deferred_compute(encoder);
    encoder.clear_buffer(buffer, offset, size);
}

fn parser_copy_buffer_to_buffer(
    encoder: &mut wgpu::CommandEncoder,
    source: &wgpu::Buffer,
    source_offset: u64,
    destination: &wgpu::Buffer,
    destination_offset: u64,
    size: u64,
) {
    crate::gpu::passes_core::flush_deferred_compute(encoder);
    encoder.copy_buffer_to_buffer(source, source_offset, destination, destination_offset, size);
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
/// Parser tree recovery passes.
pub mod tree;

/// Loaded compute passes for the parser pipeline.
pub struct ParserPasses {
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
    pub b04: brackets::histogram_layers::BracketsHistogramLayersPass,
    pub b05: brackets::scan_histograms::BracketsScanHistogramsPass,
    pub b06: brackets::scatter_by_layer::BracketsScatterByLayerPass,
    pub pair_radix: brackets::pair_radix::BracketsPairRadixPass,
    pub pse04: brackets::pse_pair::BracketsPsePairPass, // Replaces b07

    // Tree building pass
    pub tree_prefix_01: tree::prefix::local::TreePrefixLocalPass,
    pub tree_prefix_02: tree::prefix::scan_blocks::TreePrefixScanBlocksPass,
    pub tree_prefix_03: tree::prefix::apply::TreePrefixApplyPass,
    pub tree_prefix_04: tree::prefix::build_max_tree::TreePrefixMaxBuildPass,
    pub tree_parent: tree::parent::TreeParentPass,
    pub tree_spans: tree::spans::TreeSpansPass,
    pub tree_depth_init: tree::depth::init::TreeDepthInitPass,
    pub tree_depth_step: tree::depth::step::TreeDepthStepPass,
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
    pub hir_semantic_parent_init: hir::semantic::parent::init::HirSemanticParentInitPass,
    pub hir_semantic_parent_step: hir::semantic::parent::step::HirSemanticParentStepPass,
    pub hir_semantic_parent_scatter: hir::semantic::parent::scatter::HirSemanticParentScatterPass,
    pub hir_semantic_nav: hir::semantic::nav::HirSemanticNavPass,
    pub hir_semantic_depth_init: hir::semantic::depth::init::HirSemanticDepthInitPass,
    pub hir_semantic_depth_step: hir::semantic::depth::step::HirSemanticDepthStepPass,
    pub hir_semantic_depth_block_max: hir::semantic::depth::block_max::HirSemanticDepthBlockMaxPass,
    pub hir_semantic_depth_schedule: hir::semantic::depth::schedule::HirSemanticDepthSchedulePass,
    pub hir_semantic_child_index_clear:
        hir::semantic::child::index::clear::HirSemanticChildIndexClearPass,
    pub hir_semantic_child_index_links:
        hir::semantic::child::index::links::HirSemanticChildIndexLinksPass,
    pub hir_semantic_child_index_block_init:
        hir::semantic::child::index::block_init::HirSemanticChildIndexBlockInitPass,
    pub hir_semantic_child_index_rank_step:
        hir::semantic::child::index::rank_step::HirSemanticChildIndexRankStepPass,
    pub hir_record_clear_base: hir::record::clear::base::HirRecordClearBasePass,
    pub hir_record_clear_calls: hir::record::clear::calls::HirRecordClearCallsPass,
    pub hir_spans: hir::spans::HirSpansPass,
    pub hir_type_fields: hir::types::fields::HirTypeFieldsPass,
    pub hir_type_path_leaf_links: hir::types::path::leaf::links::HirTypePathLeafLinksPass,
    pub hir_type_path_leaf_step: hir::types::path::leaf::step::HirTypePathLeafStepPass,
    pub hir_type_path_leaf_scatter: hir::types::path::leaf::scatter::HirTypePathLeafScatterPass,
    pub hir_path_segment_root: hir::path::segment::root::HirPathSegmentRootPass,
    pub hir_path_segment_links: hir::path::segment::links::HirPathSegmentLinksPass,
    pub hir_path_segment_step: hir::path::segment::step::HirPathSegmentStepPass,
    pub hir_path_segment_scatter: hir::path::segment::scatter::HirPathSegmentScatterPass,
    pub hir_list_rank_prefix_local: hir::list::rank::prefix_local::HirListRankPrefixLocalPass,
    pub hir_list_rank_compact_scatter:
        hir::list::rank::compact_scatter::HirListRankCompactScatterPass,
    pub hir_type_arg_links: hir::types::arg::links::HirTypeArgLinksPass,
    pub hir_type_arg_rank_step: hir::types::arg::rank_step::HirTypeArgRankStepPass,
    pub hir_type_arg_scatter: hir::types::arg::scatter::HirTypeArgScatterPass,
    pub hir_type_root_owner_init: hir::types::root::init::HirTypeRootOwnerInitPass,
    pub hir_type_root_owner_step: hir::types::root::step::HirTypeRootOwnerStepPass,
    pub hir_type_alias_owner_init: hir::types::alias::owner::init::HirTypeAliasOwnerInitPass,
    pub hir_type_alias_owner_step: hir::types::alias::owner::step::HirTypeAliasOwnerStepPass,
    pub hir_type_alias_target: hir::types::alias::target::HirTypeAliasTargetPass,
    pub hir_fn_signature_owner_init:
        hir::functions::signature::owner::init::HirFnSignatureOwnerInitPass,
    pub hir_fn_signature_owner_step:
        hir::functions::signature::owner::step::HirFnSignatureOwnerStepPass,
    pub hir_fn_return_type: hir::functions::return_type::HirFnReturnTypePass,
    pub hir_method_signature_status: hir::method::signature_status::HirMethodSignatureStatusPass,
    pub hir_item_fields: hir::item::fields::HirItemFieldsPass,
    pub hir_item_decl_tokens: hir::item::decl_tokens::HirItemDeclTokensPass,
    pub hir_canonical_mark: hir::canonical::mark::HirCanonicalMarkPass,
    pub hir_canonical_local: hir::canonical::local::HirCanonicalLocalPass,
    pub hir_canonical_scatter: hir::canonical::scatter::HirCanonicalScatterPass,
    pub hir_canonical_parent_init: hir::canonical::parent_init::HirCanonicalParentInitPass,
    pub hir_canonical_core: hir::canonical::core::HirCanonicalCorePass,
    pub hir_canonical_nav: hir::canonical::nav::HirCanonicalNavPass,
    pub hir_canonical_validate: hir::canonical::validate::HirCanonicalValidatePass,
    pub hir_canonical_call_arg_mark: hir::canonical::call_args::mark::HirCanonicalCallArgMarkPass,
    pub hir_canonical_call_arg_local:
        hir::canonical::call_args::local::HirCanonicalCallArgLocalPass,
    pub hir_canonical_call_arg_scatter:
        hir::canonical::call_args::scatter::HirCanonicalCallArgScatterPass,
    pub hir_canonical_param_mark: hir::canonical::params::mark::HirCanonicalParamMarkPass,
    pub hir_canonical_param_local: hir::canonical::params::local::HirCanonicalParamLocalPass,
    pub hir_canonical_param_scatter: hir::canonical::params::scatter::HirCanonicalParamScatterPass,
    pub hir_canonical_type_arg_mark: hir::canonical::type_args::mark::HirCanonicalTypeArgMarkPass,
    pub hir_canonical_type_arg_local:
        hir::canonical::type_args::local::HirCanonicalTypeArgLocalPass,
    pub hir_canonical_type_arg_scatter:
        hir::canonical::type_args::scatter::HirCanonicalTypeArgScatterPass,
    pub hir_canonical_generic_param_owner_init:
        hir::canonical::generic_params::owner_init::HirCanonicalGenericParamOwnerInitPass,
    pub hir_canonical_generic_param_finalize:
        hir::canonical::generic_params::finalize::HirCanonicalGenericParamFinalizePass,
    pub hir_canonical_generic_param_local:
        hir::canonical::generic_params::local::HirCanonicalGenericParamLocalPass,
    pub hir_canonical_generic_param_scatter:
        hir::canonical::generic_params::scatter::HirCanonicalGenericParamScatterPass,
    pub hir_canonical_path_segment_mark:
        hir::canonical::paths::segments::mark::HirCanonicalPathSegmentMarkPass,
    pub hir_canonical_path_segment_local:
        hir::canonical::paths::segments::local::HirCanonicalPathSegmentLocalPass,
    pub hir_canonical_path_segment_scatter:
        hir::canonical::paths::segments::scatter::HirCanonicalPathSegmentScatterPass,
    pub hir_canonical_path_mark: hir::canonical::paths::mark::HirCanonicalPathMarkPass,
    pub hir_canonical_path_local: hir::canonical::paths::local::HirCanonicalPathLocalPass,
    pub hir_canonical_path_scatter: hir::canonical::paths::scatter::HirCanonicalPathScatterPass,
    pub hir_canonical_field_mark: hir::canonical::fields::mark::HirCanonicalFieldMarkPass,
    pub hir_canonical_field_local: hir::canonical::fields::local::HirCanonicalFieldLocalPass,
    pub hir_canonical_field_scatter: hir::canonical::fields::scatter::HirCanonicalFieldScatterPass,
    pub hir_canonical_variant_mark: hir::canonical::variants::mark::HirCanonicalVariantMarkPass,
    pub hir_canonical_variant_local: hir::canonical::variants::local::HirCanonicalVariantLocalPass,
    pub hir_canonical_variant_scatter:
        hir::canonical::variants::scatter::HirCanonicalVariantScatterPass,
    pub hir_canonical_variant_payload_owner_init:
        hir::canonical::variants::payload_owner_init::HirCanonicalVariantPayloadOwnerInitPass,
    pub hir_canonical_variant_payload_local:
        hir::canonical::variants::payload_local::HirCanonicalVariantPayloadLocalPass,
    pub hir_canonical_variant_payload_scatter:
        hir::canonical::variants::payload_scatter::HirCanonicalVariantPayloadScatterPass,
    pub hir_canonical_variant_payload_ordinal:
        hir::canonical::variants::payload_ordinal::HirCanonicalVariantPayloadOrdinalPass,
    pub hir_canonical_match_arm_mark:
        hir::canonical::matches::arms::mark::HirCanonicalMatchArmMarkPass,
    pub hir_canonical_match_arm_local:
        hir::canonical::matches::arms::local::HirCanonicalMatchArmLocalPass,
    pub hir_canonical_match_arm_scatter:
        hir::canonical::matches::arms::scatter::HirCanonicalMatchArmScatterPass,
    pub hir_canonical_match_payload_mark:
        hir::canonical::matches::payloads::mark::HirCanonicalMatchPayloadMarkPass,
    pub hir_canonical_match_payload_local:
        hir::canonical::matches::payloads::local::HirCanonicalMatchPayloadLocalPass,
    pub hir_canonical_match_payload_scatter:
        hir::canonical::matches::payloads::scatter::HirCanonicalMatchPayloadScatterPass,
    pub hir_canonical_array_element_mark:
        hir::canonical::array_elements::mark::HirCanonicalArrayElementMarkPass,
    pub hir_canonical_array_element_local:
        hir::canonical::array_elements::local::HirCanonicalArrayElementLocalPass,
    pub hir_canonical_array_element_scatter:
        hir::canonical::array_elements::scatter::HirCanonicalArrayElementScatterPass,
    pub hir_canonical_string_scatter:
        hir::canonical::strings::scatter::HirCanonicalStringScatterPass,
    pub hir_canonical_method_mark: hir::canonical::methods::mark::HirCanonicalMethodMarkPass,
    pub hir_canonical_method_local: hir::canonical::methods::local::HirCanonicalMethodLocalPass,
    pub hir_canonical_method_scatter:
        hir::canonical::methods::scatter::HirCanonicalMethodScatterPass,
    pub hir_canonical_predicate_subject_init:
        hir::canonical::predicates::subject_init::HirCanonicalPredicateSubjectInitPass,
    pub hir_canonical_predicate_finalize:
        hir::canonical::predicates::finalize::HirCanonicalPredicateFinalizePass,
    pub hir_canonical_predicate_local:
        hir::canonical::predicates::local::HirCanonicalPredicateLocalPass,
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
    pub hir_expr_forest_edges: hir::expr::forest::edges::HirExprForestEdgesPass,
    pub hir_expr_forest_root_init: hir::expr::forest::root_init::HirExprForestRootInitPass,
    pub hir_expr_forest_root_step: hir::expr::forest::root_step::HirExprForestRootStepPass,
    pub hir_binary_span_apply: hir::binary::span::apply::HirBinarySpanApplyPass,
    pub hir_binary_span_step: hir::binary::span::step::HirBinarySpanStepPass,
    pub hir_binary_spans: hir::binary::spans::HirBinarySpansPass,
    pub hir_index_spans: hir::index_spans::HirIndexSpansPass,
    pub hir_member_fields: hir::member::fields::HirMemberFieldsPass,
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
    pub hir_call_arg_ordinal_step: hir::call::arg::ordinal::step::HirCallArgOrdinalStepPass,
    pub hir_call_arg_ordinal_scatter:
        hir::call::arg::ordinal::scatter::HirCallArgOrdinalScatterPass,
    pub hir_array_fields: hir::array::fields::HirArrayFieldsPass,
    pub hir_array_element_links: hir::array::element::links::HirArrayElementLinksPass,
    pub hir_array_element_rank_step: hir::array::element::rank_step::HirArrayElementRankStepPass,
    pub hir_array_element_scatter: hir::array::element::scatter::HirArrayElementScatterPass,
    pub hir_enum_match_fields: hir::enums::match_fields::HirEnumMatchFieldsPass,
    pub hir_enum_variant_links: hir::enums::variant::links::HirEnumVariantLinksPass,
    pub hir_enum_rank_prefix_local: hir::enums::rank::prefix_local::HirEnumRankPrefixLocalPass,
    pub hir_enum_rank_compact_scatter:
        hir::enums::rank::compact_scatter::HirEnumRankCompactScatterPass,
    pub hir_enum_variant_rank_step: hir::enums::variant::rank_step::HirEnumVariantRankStepPass,
    pub hir_enum_variant_scatter: hir::enums::variant::scatter::HirEnumVariantScatterPass,
    pub hir_match_arm_links: hir::matches::arm::links::HirMatchArmLinksPass,
    pub hir_match_rank_prefix_local: hir::matches::rank::prefix_local::HirMatchRankPrefixLocalPass,
    pub hir_match_rank_compact_scatter:
        hir::matches::rank::compact_scatter::HirMatchRankCompactScatterPass,
    pub hir_match_arm_rank_step: hir::matches::arm::rank_step::HirMatchArmRankStepPass,
    pub hir_match_arm_scatter: hir::matches::arm::scatter::HirMatchArmScatterPass,
    pub hir_struct_fields: hir::structs::fields::HirStructFieldsPass,
    pub hir_context_relations_init: hir::context::relations::init::HirContextRelationsInitPass,
    pub hir_context_relations_step: hir::context::relations::step::HirContextRelationsStepPass,
    pub hir_context_relations_step_small:
        hir::context::relations::step_small::HirContextRelationsStepSmallPass,
    pub hir_context_relations_scatter:
        hir::context::relations::scatter::HirContextRelationsScatterPass,
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
            b04: brackets::histogram_layers::BracketsHistogramLayersPass::new(device)?,
            b05: brackets::scan_histograms::BracketsScanHistogramsPass::new(device)?,
            b06: brackets::scatter_by_layer::BracketsScatterByLayerPass::new(device)?,
            pair_radix: brackets::pair_radix::BracketsPairRadixPass::new(device)?,
            pse04: brackets::pse_pair::BracketsPsePairPass::new(device)?,

            tree_parent: tree::parent::TreeParentPass::new(device)?,
            tree_prefix_01: tree::prefix::local::TreePrefixLocalPass::new(device)?,
            tree_prefix_02: tree::prefix::scan_blocks::TreePrefixScanBlocksPass::new(device)?,
            tree_prefix_03: tree::prefix::apply::TreePrefixApplyPass::new(device)?,
            tree_prefix_04: tree::prefix::build_max_tree::TreePrefixMaxBuildPass::new(device)?,
            tree_spans: tree::spans::TreeSpansPass::new(device)?,
            tree_depth_init: tree::depth::init::TreeDepthInitPass::new(device)?,
            tree_depth_step: tree::depth::step::TreeDepthStepPass::new(device)?,
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
            hir_semantic_parent_init: hir::semantic::parent::init::HirSemanticParentInitPass::new(
                device,
            )?,
            hir_semantic_parent_step: hir::semantic::parent::step::HirSemanticParentStepPass::new(
                device,
            )?,
            hir_semantic_parent_scatter:
                hir::semantic::parent::scatter::HirSemanticParentScatterPass::new(device)?,
            hir_semantic_nav: hir::semantic::nav::HirSemanticNavPass::new(device)?,
            hir_semantic_depth_init: hir::semantic::depth::init::HirSemanticDepthInitPass::new(
                device,
            )?,
            hir_semantic_depth_step: hir::semantic::depth::step::HirSemanticDepthStepPass::new(
                device,
            )?,
            hir_semantic_depth_block_max:
                hir::semantic::depth::block_max::HirSemanticDepthBlockMaxPass::new(device)?,
            hir_semantic_depth_schedule:
                hir::semantic::depth::schedule::HirSemanticDepthSchedulePass::new(device)?,
            hir_semantic_child_index_clear:
                hir::semantic::child::index::clear::HirSemanticChildIndexClearPass::new(device)?,
            hir_semantic_child_index_links:
                hir::semantic::child::index::links::HirSemanticChildIndexLinksPass::new(device)?,
            hir_semantic_child_index_block_init:
                hir::semantic::child::index::block_init::HirSemanticChildIndexBlockInitPass::new(
                    device,
                )?,
            hir_semantic_child_index_rank_step:
                hir::semantic::child::index::rank_step::HirSemanticChildIndexRankStepPass::new(
                    device,
                )?,
            hir_record_clear_base: hir::record::clear::base::HirRecordClearBasePass::new(device)?,
            hir_record_clear_calls: hir::record::clear::calls::HirRecordClearCallsPass::new(
                device,
            )?,
            hir_spans: hir::spans::HirSpansPass::new(device)?,
            hir_type_fields: hir::types::fields::HirTypeFieldsPass::new(device)?,
            hir_type_path_leaf_links: hir::types::path::leaf::links::HirTypePathLeafLinksPass::new(
                device,
            )?,
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
            hir_type_arg_links: hir::types::arg::links::HirTypeArgLinksPass::new(device)?,
            hir_type_arg_rank_step: hir::types::arg::rank_step::HirTypeArgRankStepPass::new(
                device,
            )?,
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
            hir_fn_signature_owner_init:
                hir::functions::signature::owner::init::HirFnSignatureOwnerInitPass::new(device)?,
            hir_fn_signature_owner_step:
                hir::functions::signature::owner::step::HirFnSignatureOwnerStepPass::new(device)?,
            hir_fn_return_type: hir::functions::return_type::HirFnReturnTypePass::new(device)?,
            hir_method_signature_status:
                hir::method::signature_status::HirMethodSignatureStatusPass::new(device)?,
            hir_item_fields: hir::item::fields::HirItemFieldsPass::new(device)?,
            hir_item_decl_tokens: hir::item::decl_tokens::HirItemDeclTokensPass::new(device)?,
            hir_canonical_mark: hir::canonical::mark::HirCanonicalMarkPass::new(device)?,
            hir_canonical_local: hir::canonical::local::HirCanonicalLocalPass::new(device)?,
            hir_canonical_scatter: hir::canonical::scatter::HirCanonicalScatterPass::new(device)?,
            hir_canonical_parent_init:
                hir::canonical::parent_init::HirCanonicalParentInitPass::new(device)?,
            hir_canonical_core: hir::canonical::core::HirCanonicalCorePass::new(device)?,
            hir_canonical_nav: hir::canonical::nav::HirCanonicalNavPass::new(device)?,
            hir_canonical_validate: hir::canonical::validate::HirCanonicalValidatePass::new(
                device,
            )?,
            hir_canonical_call_arg_mark:
                hir::canonical::call_args::mark::HirCanonicalCallArgMarkPass::new(device)?,
            hir_canonical_call_arg_local:
                hir::canonical::call_args::local::HirCanonicalCallArgLocalPass::new(device)?,
            hir_canonical_call_arg_scatter:
                hir::canonical::call_args::scatter::HirCanonicalCallArgScatterPass::new(device)?,
            hir_canonical_param_mark: hir::canonical::params::mark::HirCanonicalParamMarkPass::new(
                device,
            )?,
            hir_canonical_param_local:
                hir::canonical::params::local::HirCanonicalParamLocalPass::new(device)?,
            hir_canonical_param_scatter:
                hir::canonical::params::scatter::HirCanonicalParamScatterPass::new(device)?,
            hir_canonical_type_arg_mark:
                hir::canonical::type_args::mark::HirCanonicalTypeArgMarkPass::new(device)?,
            hir_canonical_type_arg_local:
                hir::canonical::type_args::local::HirCanonicalTypeArgLocalPass::new(device)?,
            hir_canonical_type_arg_scatter:
                hir::canonical::type_args::scatter::HirCanonicalTypeArgScatterPass::new(device)?,
            hir_canonical_generic_param_owner_init:
                hir::canonical::generic_params::owner_init::HirCanonicalGenericParamOwnerInitPass::new(device)?,
            hir_canonical_generic_param_finalize:
                hir::canonical::generic_params::finalize::HirCanonicalGenericParamFinalizePass::new(device)?,
            hir_canonical_generic_param_local:
                hir::canonical::generic_params::local::HirCanonicalGenericParamLocalPass::new(device)?,
            hir_canonical_generic_param_scatter:
                hir::canonical::generic_params::scatter::HirCanonicalGenericParamScatterPass::new(device)?,
            hir_canonical_path_segment_mark:
                hir::canonical::paths::segments::mark::HirCanonicalPathSegmentMarkPass::new(device)?,
            hir_canonical_path_segment_local:
                hir::canonical::paths::segments::local::HirCanonicalPathSegmentLocalPass::new(device)?,
            hir_canonical_path_segment_scatter:
                hir::canonical::paths::segments::scatter::HirCanonicalPathSegmentScatterPass::new(device)?,
            hir_canonical_path_mark:
                hir::canonical::paths::mark::HirCanonicalPathMarkPass::new(device)?,
            hir_canonical_path_local:
                hir::canonical::paths::local::HirCanonicalPathLocalPass::new(device)?,
            hir_canonical_path_scatter:
                hir::canonical::paths::scatter::HirCanonicalPathScatterPass::new(device)?,
            hir_canonical_field_mark:
                hir::canonical::fields::mark::HirCanonicalFieldMarkPass::new(device)?,
            hir_canonical_field_local:
                hir::canonical::fields::local::HirCanonicalFieldLocalPass::new(device)?,
            hir_canonical_field_scatter:
                hir::canonical::fields::scatter::HirCanonicalFieldScatterPass::new(device)?,
            hir_canonical_variant_mark:
                hir::canonical::variants::mark::HirCanonicalVariantMarkPass::new(device)?,
            hir_canonical_variant_local:
                hir::canonical::variants::local::HirCanonicalVariantLocalPass::new(device)?,
            hir_canonical_variant_scatter:
                hir::canonical::variants::scatter::HirCanonicalVariantScatterPass::new(device)?,
            hir_canonical_variant_payload_owner_init:
                hir::canonical::variants::payload_owner_init::HirCanonicalVariantPayloadOwnerInitPass::new(device)?,
            hir_canonical_variant_payload_local:
                hir::canonical::variants::payload_local::HirCanonicalVariantPayloadLocalPass::new(device)?,
            hir_canonical_variant_payload_scatter:
                hir::canonical::variants::payload_scatter::HirCanonicalVariantPayloadScatterPass::new(device)?,
            hir_canonical_variant_payload_ordinal:
                hir::canonical::variants::payload_ordinal::HirCanonicalVariantPayloadOrdinalPass::new(device)?,
            hir_canonical_match_arm_mark:
                hir::canonical::matches::arms::mark::HirCanonicalMatchArmMarkPass::new(device)?,
            hir_canonical_match_arm_local:
                hir::canonical::matches::arms::local::HirCanonicalMatchArmLocalPass::new(device)?,
            hir_canonical_match_arm_scatter:
                hir::canonical::matches::arms::scatter::HirCanonicalMatchArmScatterPass::new(device)?,
            hir_canonical_match_payload_mark:
                hir::canonical::matches::payloads::mark::HirCanonicalMatchPayloadMarkPass::new(device)?,
            hir_canonical_match_payload_local:
                hir::canonical::matches::payloads::local::HirCanonicalMatchPayloadLocalPass::new(device)?,
            hir_canonical_match_payload_scatter:
                hir::canonical::matches::payloads::scatter::HirCanonicalMatchPayloadScatterPass::new(device)?,
            hir_canonical_array_element_mark:
                hir::canonical::array_elements::mark::HirCanonicalArrayElementMarkPass::new(device)?,
            hir_canonical_array_element_local:
                hir::canonical::array_elements::local::HirCanonicalArrayElementLocalPass::new(device)?,
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
            hir_expr_forest_edges: hir::expr::forest::edges::HirExprForestEdgesPass::new(device)?,
            hir_expr_forest_root_init:
                hir::expr::forest::root_init::HirExprForestRootInitPass::new(device)?,
            hir_expr_forest_root_step:
                hir::expr::forest::root_step::HirExprForestRootStepPass::new(device)?,
            hir_binary_span_apply: hir::binary::span::apply::HirBinarySpanApplyPass::new(device)?,
            hir_binary_span_step: hir::binary::span::step::HirBinarySpanStepPass::new(device)?,
            hir_binary_spans: hir::binary::spans::HirBinarySpansPass::new(device)?,
            hir_index_spans: hir::index_spans::HirIndexSpansPass::new(device)?,
            hir_member_fields: hir::member::fields::HirMemberFieldsPass::new(device)?,
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
            hir_canonical_method_local:
                hir::canonical::methods::local::HirCanonicalMethodLocalPass::new(device)?,
            hir_canonical_method_scatter:
                hir::canonical::methods::scatter::HirCanonicalMethodScatterPass::new(device)?,
            hir_canonical_predicate_subject_init:
                hir::canonical::predicates::subject_init::HirCanonicalPredicateSubjectInitPass::new(device)?,
            hir_canonical_predicate_finalize:
                hir::canonical::predicates::finalize::HirCanonicalPredicateFinalizePass::new(device)?,
            hir_canonical_predicate_local:
                hir::canonical::predicates::local::HirCanonicalPredicateLocalPass::new(device)?,
            hir_canonical_predicate_scatter:
                hir::canonical::predicates::scatter::HirCanonicalPredicateScatterPass::new(device)?,
            hir_call_fields: hir::call::fields::HirCallFieldsPass::new(device)?,
            hir_call_spans: hir::call::spans::HirCallSpansPass::new(device)?,
            hir_call_arg_links: hir::call::arg::links::HirCallArgLinksPass::new(device)?,
            hir_call_arg_ordinal_step:
                hir::call::arg::ordinal::step::HirCallArgOrdinalStepPass::new(device)?,
            hir_call_arg_ordinal_scatter:
                hir::call::arg::ordinal::scatter::HirCallArgOrdinalScatterPass::new(device)?,
            hir_array_fields: hir::array::fields::HirArrayFieldsPass::new(device)?,
            hir_array_element_links: hir::array::element::links::HirArrayElementLinksPass::new(
                device,
            )?,
            hir_array_element_rank_step:
                hir::array::element::rank_step::HirArrayElementRankStepPass::new(device)?,
            hir_array_element_scatter:
                hir::array::element::scatter::HirArrayElementScatterPass::new(device)?,
            hir_enum_match_fields: hir::enums::match_fields::HirEnumMatchFieldsPass::new(device)?,
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
            hir_match_arm_links: hir::matches::arm::links::HirMatchArmLinksPass::new(device)?,
            hir_match_rank_prefix_local:
                hir::matches::rank::prefix_local::HirMatchRankPrefixLocalPass::new(device)?,
            hir_match_rank_compact_scatter:
                hir::matches::rank::compact_scatter::HirMatchRankCompactScatterPass::new(device)?,
            hir_match_arm_rank_step: hir::matches::arm::rank_step::HirMatchArmRankStepPass::new(
                device,
            )?,
            hir_match_arm_scatter: hir::matches::arm::scatter::HirMatchArmScatterPass::new(device)?,
            hir_struct_fields: hir::structs::fields::HirStructFieldsPass::new(device)?,
            hir_context_relations_init:
                hir::context::relations::init::HirContextRelationsInitPass::new(device)?,
            hir_context_relations_step:
                hir::context::relations::step::HirContextRelationsStepPass::new(device)?,
            hir_context_relations_step_small:
                hir::context::relations::step_small::HirContextRelationsStepSmallPass::new(device)?,
            hir_context_relations_scatter:
                hir::context::relations::scatter::HirContextRelationsScatterPass::new(device)?,
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
pub fn record_all_passes(
    mut ctx: PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1D;

    let n_pairs = ctx.buffers.n_tokens.saturating_sub(1);
    p.llp_pairs.record_pass(&mut ctx, E1D(n_pairs))?;
    p.pack_offsets
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.pack_offsets_status
        .record_pass(ctx.device, ctx.encoder, ctx.buffers)?;
    p.pack_varlen
        .record_pass(&mut ctx, E1D(n_pairs.saturating_mul(256)))?;
    parser_copy_buffer_to_buffer(
        ctx.encoder,
        &ctx.buffers.partial_parse_status,
        0,
        &ctx.buffers.ll1_status,
        0,
        24,
    );

    record_stack_effect_validation(&mut ctx, p, &mut None)?;

    // Tree parent recovery: one independent thread per emitted production.
    let n_tree = ctx.buffers.tree_capacity;
    let n_tree_node_threads = ctx.buffers.tree_n_node_blocks.saturating_mul(256);
    let n_tree_prefix_positions = ctx.buffers.tree_capacity.saturating_add(1);
    p.tree_prefix_01
        .record_pass(&mut ctx, E1D(n_tree_node_threads))?;
    p.tree_prefix_02
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.tree_prefix_03
        .record_pass(&mut ctx, E1D(n_tree_prefix_positions))?;
    p.tree_prefix_04
        .record_build(ctx.device, ctx.encoder, ctx.buffers)?;
    p.tree_parent.record_pass(&mut ctx, E1D(n_tree))?;
    p.tree_spans.record_pass(&mut ctx, E1D(n_tree))?;
    let tree_active_dispatch_args = ctx.buffers.tree_active_dispatch_args.buffer.clone();
    p.tree_depth_init
        .record_pass_indirect(&mut ctx, &tree_active_dispatch_args)?;
    p.tree_depth_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &tree_active_dispatch_args,
    )?;
    p.tree_depth_block_max
        .record_pass_indirect(&mut ctx, &tree_active_dispatch_args)?;
    p.tree_depth_schedule.record_pass(&mut ctx, E1D(256))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    p.tree_prev_sibling_clear
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.tree_prev_sibling_scatter
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_nodes.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_semantic_prefix_local
        .record_pass(&mut ctx, E1D(n_tree_node_threads))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_semantic_compact_scatter
        .record_pass(&mut ctx, E1D(n_tree_node_threads))?;
    p.hir_semantic_dispatch_args.record_pass(&mut ctx, E1D(1))?;
    let hir_semantic_dispatch_args = ctx.buffers.hir_semantic_dispatch_args.buffer.clone();
    let hir_semantic_pointer_jump_dispatch_args = ctx
        .buffers
        .hir_semantic_pointer_jump_dispatch_args
        .buffer
        .clone();
    p.hir_semantic_subtree_end
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_semantic_parent_init
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_semantic_parent_step
        .record_steps(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_semantic_parent_scatter
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_semantic_nav
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_semantic_depth_init
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_semantic_depth_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &hir_semantic_dispatch_args,
    )?;
    p.hir_semantic_depth_block_max
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_semantic_depth_schedule
        .record_pass(&mut ctx, E1D(256))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    p.hir_semantic_child_index_clear
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_semantic_child_index_links
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_semantic_child_index_block_init
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_semantic_child_index_rank_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &hir_semantic_dispatch_args,
    )?;
    p.hir_record_clear_base.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_record_clear_calls
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_type_fields.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_type_path_leaf_links
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_type_path_leaf_step
        .record_steps(ctx.device, ctx.encoder, ctx.buffers)?;
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_type_path_leaf_link_b.buffer,
        0,
        Some(u64::from(ctx.buffers.tree_capacity) * 4),
    );
    p.hir_type_path_leaf_scatter
        .record_pass(&mut ctx, E1D(n_tree))?;
    let token_input_capacity = ctx.buffers.token_input_capacity;
    parser_clear_buffer(ctx.encoder, &ctx.buffers.source_file_token_end, 0, None);
    p.source_file_token_end
        .record_pass(&mut ctx, E1D(token_input_capacity))?;
    p.hir_spans.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_type_arg_links.record_pass(&mut ctx, E1D(n_tree))?;
    clear_type_arg_rank_b(ctx.encoder, ctx.buffers);
    p.hir_list_rank_prefix_local.record_for_owner_link(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_type_fields_params,
        &ctx.buffers.hir_type_arg_owner_a,
        &ctx.buffers.hir_type_arg_link_a,
    )?;
    p.hir_semantic_prefix_blocks
        .record_list_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_list_rank_compact_scatter.record_for_params(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_type_fields_params,
    )?;
    p.hir_type_arg_rank_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_list_rank_dispatch_args,
    )?;
    p.hir_type_arg_scatter.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_type_root_owner_init
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_type_root_owner_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.tree_pointer_jump_dispatch_args,
    )?;
    p.hir_enum_match_fields.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_enum_variant_links
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_enum_rank_prefix_local
        .record_pass(&mut ctx, E1D(n_tree_node_threads))?;
    p.hir_semantic_prefix_blocks
        .record_enum_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_enum_rank_compact_scatter
        .record_pass(&mut ctx, E1D(n_tree_node_threads))?;
    p.hir_enum_variant_rank_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_enum_rank_dispatch_args,
    )?;
    p.hir_enum_variant_scatter
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_item_fields
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    parser_clear_buffer(ctx.encoder, &ctx.buffers.hir_path_root_owner, 0, None);
    p.hir_path_segment_root.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_path_segment_links
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_path_segment_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.tree_pointer_jump_dispatch_args,
    )?;
    p.hir_path_segment_scatter
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_type_alias_owner_init
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_type_alias_owner_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &hir_semantic_pointer_jump_dispatch_args,
    )?;
    p.hir_type_alias_target
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_fn_signature_owner_init
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_fn_signature_owner_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.tree_pointer_jump_dispatch_args,
    )?;
    p.hir_fn_return_type
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_method_signature_status
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_param_links.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_list_rank_prefix_local.record_for_owner_link(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_param_fields_params,
        &ctx.buffers.hir_param_owner_a,
        &ctx.buffers.hir_param_link_a,
    )?;
    p.hir_semantic_prefix_blocks
        .record_list_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_list_rank_compact_scatter.record_for_params(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_param_fields_params,
    )?;
    p.hir_param_id_clear.record_pass(&mut ctx, E1D(n_tree))?;
    let hir_list_rank_dispatch_args = ctx.buffers.hir_list_rank_dispatch_args.buffer.clone();
    p.hir_param_id_base
        .record_pass_indirect(&mut ctx, &hir_list_rank_dispatch_args)?;
    p.hir_param_id_apply
        .record_pass_indirect(&mut ctx, &hir_list_rank_dispatch_args)?;
    p.hir_param_fields
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_method_fields
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_expr_fields
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_expr_result_root_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.tree_pointer_jump_dispatch_args,
    )?;
    p.hir_binary_spans
        .record_pass_indirect(&mut ctx, &tree_active_dispatch_args)?;
    p.hir_binary_span_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &tree_active_dispatch_args,
    )?;
    p.hir_binary_span_apply
        .record_pass_indirect(&mut ctx, &tree_active_dispatch_args)?;
    p.hir_member_fields
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_index_spans
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_member_spans
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_stmt_fields
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_call_fields
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_call_spans
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_range_spans.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_call_arg_links.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_list_rank_prefix_local.record_for_owner_link(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_call_fields_params,
        &ctx.buffers.hir_call_arg_owner_a,
        &ctx.buffers.hir_call_arg_link_a,
    )?;
    p.hir_semantic_prefix_blocks
        .record_list_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_list_rank_compact_scatter.record_for_params(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_call_fields_params,
    )?;
    p.hir_call_arg_ordinal_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_list_rank_dispatch_args,
    )?;
    p.hir_call_arg_ordinal_scatter
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_canonical_call_arg_mark
        .record_pass(&mut ctx, E1D(n_tree))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    p.hir_expr_forest_edges
        .record_pass_indirect(&mut ctx, &tree_active_dispatch_args)?;
    p.hir_expr_forest_root_init
        .record_pass_indirect(&mut ctx, &tree_active_dispatch_args)?;
    p.hir_expr_forest_root_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.tree_pointer_jump_dispatch_args,
    )?;
    p.hir_array_fields.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_array_element_links
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_list_rank_prefix_local.record_for_owner_link(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_array_fields_params,
        &ctx.buffers.hir_array_element_owner_a,
        &ctx.buffers.hir_array_element_link_a,
    )?;
    p.hir_semantic_prefix_blocks
        .record_list_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_list_rank_compact_scatter.record_for_params(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_array_fields_params,
    )?;
    p.hir_array_element_rank_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_list_rank_dispatch_args,
    )?;
    p.hir_array_element_scatter
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_match_arm_links.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_match_rank_prefix_local
        .record_pass(&mut ctx, E1D(n_tree_node_threads))?;
    p.hir_semantic_prefix_blocks
        .record_match_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_match_rank_compact_scatter
        .record_pass(&mut ctx, E1D(n_tree_node_threads))?;
    p.hir_match_arm_rank_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_match_rank_dispatch_args,
    )?;
    p.hir_match_arm_scatter.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_struct_fields.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_context_relations_init
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    if ctx.buffers.tree_capacity
        <= hir::context::relations::step_small::HIR_CONTEXT_RELATIONS_SMALL_CAPACITY
    {
        p.hir_context_relations_step_small
            .record_pass(&mut ctx, E1D(1))?;
    } else {
        p.hir_context_relations_step.record_steps_indirect(
            ctx.device,
            ctx.encoder,
            ctx.buffers,
            &hir_semantic_pointer_jump_dispatch_args,
        )?;
    }
    p.hir_context_relations_scatter
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_stmt_scope.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_struct_field_links
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_struct_lit_spans.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_struct_rank_prefix_local
        .record_pass(&mut ctx, E1D(n_tree_node_threads))?;
    p.hir_semantic_prefix_blocks
        .record_struct_rank_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_struct_rank_compact_scatter
        .record_pass(&mut ctx, E1D(n_tree_node_threads))?;
    p.hir_struct_field_rank_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_struct_rank_dispatch_args,
    )?;
    p.tree_prev_sibling_clear
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_struct_field_scatter
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_item_decl_tokens
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;

    record_canonical_hir(&mut ctx, p)?;

    Ok(())
}

/// Materializes the durable, token-bounded HIR after all raw-tree-derived
/// records have been finalized. The raw-to-dense maps and pointer-jump rows
/// are phase-local workspace and may be overwritten by later phases.
pub fn record_canonical_hir(
    ctx: &mut PassContext<'_, ParserBuffers, DebugOutput>,
    p: &ParserPasses,
) -> Result<(), anyhow::Error> {
    use InputElements::Elements1D as E1D;

    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_canonical_anchor_owner.buffer,
        0,
        None,
    );
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_canonical_count.buffer,
        0,
        None,
    );
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_canonical_status.buffer,
        0,
        None,
    );
    p.hir_canonical_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    // The local scan consumes atomic anchor winners. Keep this as an explicit
    // pass boundary: same-pass dispatch ordering does not provide a portable
    // storage-memory barrier for atomics through wgpu backends.
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    p.hir_canonical_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_parent_init
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_semantic_parent_step
        .record_steps(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_core
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    p.hir_canonical_nav
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_call_arg_table_count.buffer,
        0,
        None,
    );
    p.hir_canonical_call_arg_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_call_arg_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_param_table_count.buffer,
        0,
        None,
    );
    p.hir_canonical_param_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_param_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_param_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_type_arg_table_count.buffer,
        0,
        None,
    );
    p.hir_canonical_type_arg_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_type_arg_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_type_arg_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_generic_param_table_count.buffer,
        0,
        None,
    );
    p.hir_canonical_generic_param_owner_init
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_semantic_parent_step
        .record_steps(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_generic_param_finalize
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_generic_param_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_generic_param_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_path_segment_table_count.buffer,
        0,
        None,
    );
    p.hir_canonical_path_segment_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_path_segment_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_path_segment_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_path_table_count.buffer,
        0,
        None,
    );
    p.hir_canonical_path_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_path_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_path_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_field_table_count.buffer,
        0,
        None,
    );
    p.hir_canonical_field_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_field_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_field_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_variant_table_count.buffer,
        0,
        None,
    );
    p.hir_canonical_variant_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_variant_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_variant_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_variant_payload_table_count.buffer,
        0,
        None,
    );
    p.hir_canonical_variant_payload_owner_init
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_semantic_parent_step
        .record_steps(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_variant_payload_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_variant_payload_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    p.hir_canonical_variant_payload_ordinal
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_match_arm_table_count.buffer,
        0,
        None,
    );
    p.hir_canonical_match_arm_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_match_arm_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_match_arm_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_match_payload_table_count.buffer,
        0,
        None,
    );
    p.hir_canonical_match_payload_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_match_payload_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_match_payload_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_array_element_table_count.buffer,
        0,
        None,
    );
    p.hir_canonical_array_element_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_array_element_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_array_element_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    p.hir_canonical_string_scatter
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_method_table_count.buffer,
        0,
        None,
    );
    p.hir_canonical_method_mark
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_method_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_method_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    parser_clear_buffer(
        ctx.encoder,
        &ctx.buffers.hir_predicate_table_count.buffer,
        0,
        None,
    );
    p.hir_canonical_predicate_subject_init
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_semantic_parent_step
        .record_steps(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_semantic_parent_step.record_steps_for_buffers(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_type_arg_link_a,
        &ctx.buffers.hir_type_arg_rank_a,
        &ctx.buffers.hir_type_arg_link_b,
        &ctx.buffers.hir_type_arg_rank_b,
        "hir_canonical_predicate_owner_step",
    )?;
    p.hir_canonical_predicate_finalize
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    p.hir_canonical_predicate_local
        .record_pass(ctx, E1D(ctx.buffers.tree_n_node_blocks.saturating_mul(256)))?;
    p.hir_semantic_prefix_blocks
        .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_canonical_predicate_scatter
        .record_pass(ctx, E1D(ctx.buffers.tree_capacity))?;
    crate::gpu::passes_core::flush_deferred_compute(ctx.encoder);
    p.hir_canonical_validate
        .record_pass(ctx, E1D(ctx.buffers.hir_canonical_capacity))?;
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

    let n_sc = ctx.buffers.total_sc.max(1);
    let n_layers = ctx.buffers.b_n_layers.max(1);

    parser_clear_buffer(ctx.encoder, &ctx.buffers.b_hist_push, 0, None);
    parser_clear_buffer(ctx.encoder, &ctx.buffers.b_hist_pop, 0, None);
    parser_clear_buffer(ctx.encoder, &ctx.buffers.depths_out, 0, None);

    p.b01.record_pass(ctx, E1D(n_sc))?;
    stamp_stack_effect_timer(timer_ref, ctx.encoder, "parser.stack_effect.histogram");
    p.b02.record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    stamp_stack_effect_timer(timer_ref, ctx.encoder, "parser.stack_effect.histogram_scan");
    p.b03.record_pass(ctx, E1D(n_sc))?;
    stamp_stack_effect_timer(timer_ref, ctx.encoder, "parser.stack_effect.offsets");
    p.b04.record_pass(ctx, E1D(n_sc))?;
    stamp_stack_effect_timer(
        timer_ref,
        ctx.encoder,
        "parser.stack_effect.layer_histogram",
    );
    p.b05.record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    stamp_stack_effect_timer(timer_ref, ctx.encoder, "parser.stack_effect.layer_scan");

    let bytes = (n_layers * 4) as u64;
    parser_copy_buffer_to_buffer(
        ctx.encoder,
        &ctx.buffers.b_off_push,
        0,
        &ctx.buffers.b_cur_push,
        0,
        bytes,
    );
    parser_copy_buffer_to_buffer(
        ctx.encoder,
        &ctx.buffers.b_off_pop,
        0,
        &ctx.buffers.b_cur_pop,
        0,
        bytes,
    );

    p.b06.record_pass(ctx, E1D(n_sc))?;
    stamp_stack_effect_timer(timer_ref, ctx.encoder, "parser.stack_effect.scatter");
    let mut temporary_pair_radix_cache = crate::gpu::passes_core::BindGroupCache::new();
    let pair_radix_cache = ctx
        .bg_cache
        .as_deref_mut()
        .unwrap_or(&mut temporary_pair_radix_cache);
    p.pair_radix
        .record_sort(ctx.device, ctx.encoder, ctx.buffers, pair_radix_cache)?;
    stamp_stack_effect_timer(timer_ref, ctx.encoder, "parser.stack_effect.pair_radix");
    p.pse04.record_pass(ctx, E1D(n_sc))?;
    stamp_stack_effect_timer(timer_ref, ctx.encoder, "parser.stack_effect.pair_by_layer");
    p.status_from_brackets.record_pass(ctx, E1D(1))?;
    stamp_stack_effect_timer(timer_ref, ctx.encoder, "parser.stack_effect.status");

    Ok(())
}

fn stamp_stack_effect_timer(
    timer_ref: &mut Option<&mut GpuTimer>,
    encoder: &mut wgpu::CommandEncoder,
    label: &'static str,
) {
    if let Some(timer) = timer_ref.as_deref_mut() {
        timer.stamp(encoder, label);
    }
}

fn clear_type_arg_rank_b(encoder: &mut wgpu::CommandEncoder, buffers: &ParserBuffers) {
    let bytes = u64::from(buffers.tree_capacity) * 4;
    for buffer in [
        &buffers.hir_type_arg_owner_b,
        &buffers.hir_type_arg_link_b,
        &buffers.hir_type_arg_rank_b,
    ] {
        parser_clear_buffer(encoder, &buffer.buffer, 0, Some(bytes));
    }
}
