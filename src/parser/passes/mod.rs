// Parser passes use the shared Pass trait from gpu::passes_core.
use anyhow::Result;

use crate::{
    gpu::passes_core::{InputElements, Pass, PassContext},
    parser::{buffers::ParserBuffers, debug::DebugOutput},
};

pub mod brackets;
pub mod hir;
pub mod llp_pairs;
pub mod pack;
pub mod source_file_token_end;
pub mod tree;

/// Bundle of all parser passes.
pub struct ParserPasses {
    pub llp_pairs: llp_pairs::LLPPairsPass,
    pub pack_offsets: pack::offsets::PackOffsetsScanPass,
    pub pack_offsets_status: pack::offsets::status::PackOffsetsStatusPass,
    pub pack_totals_blocks: pack::totals::blocks::PackTotalsBlocksPass,
    pub pack_totals_reduce: pack::totals::reduce::PackTotalsReducePass,
    pub pack_totals_status: pack::totals::status::PackTotalsStatusPass,
    pub pack_varlen: pack::varlen::PackVarlenPass,
    pub source_file_token_end: source_file_token_end::SourceFileTokenEndPass,

    // Bracket matching passes
    pub b01: brackets::scan_inblock::BracketsScanInblockPass,
    pub b02: brackets::scan_block_prefix::BracketsScanBlockPrefixPass,
    pub b03: brackets::apply_prefix::BracketsApplyPrefixPass,
    pub b04: brackets::histogram_layers::BracketsHistogramLayersPass,
    pub b05: brackets::scan_histograms::BracketsScanHistogramsPass,
    pub b06: brackets::scatter_by_layer::BracketsScatterByLayerPass,
    pub pse04: brackets::pse_pair::BracketsPsePairPass, // Replaces b07

    // Tree building pass
    pub tree_prefix_01: tree::prefix::local::TreePrefixLocalPass,
    pub tree_prefix_02: tree::prefix::scan_blocks::TreePrefixScanBlocksPass,
    pub tree_prefix_03: tree::prefix::apply::TreePrefixApplyPass,
    pub tree_prefix_04: tree::prefix::build_max_tree::TreePrefixMaxBuildPass,
    pub tree_parent: tree::parent::TreeParentPass,
    pub tree_spans: tree::spans::TreeSpansPass,
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
    pub hir_semantic_child_index_clear:
        hir::semantic::child::index::clear::HirSemanticChildIndexClearPass,
    pub hir_semantic_child_index_links:
        hir::semantic::child::index::links::HirSemanticChildIndexLinksPass,
    pub hir_semantic_child_index_rank_step:
        hir::semantic::child::index::rank_step::HirSemanticChildIndexRankStepPass,
    pub hir_record_clear_base: hir::record::clear::base::HirRecordClearBasePass,
    pub hir_record_clear_calls: hir::record::clear::calls::HirRecordClearCallsPass,
    pub hir_spans: hir::spans::HirSpansPass,
    pub hir_type_fields: hir::types::fields::HirTypeFieldsPass,
    pub hir_type_path_leaf_links: hir::types::path::leaf::links::HirTypePathLeafLinksPass,
    pub hir_type_path_leaf_step: hir::types::path::leaf::step::HirTypePathLeafStepPass,
    pub hir_type_path_leaf_scatter: hir::types::path::leaf::scatter::HirTypePathLeafScatterPass,
    pub hir_list_rank_prefix_local: hir::list::rank::prefix_local::HirListRankPrefixLocalPass,
    pub hir_list_rank_compact_scatter:
        hir::list::rank::compact_scatter::HirListRankCompactScatterPass,
    pub hir_type_arg_links: hir::types::arg::links::HirTypeArgLinksPass,
    pub hir_type_arg_rank_step: hir::types::arg::rank_step::HirTypeArgRankStepPass,
    pub hir_type_arg_scatter: hir::types::arg::scatter::HirTypeArgScatterPass,
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
    pub hir_param_links: hir::param::links::HirParamLinksPass,
    pub hir_param_rank_step: hir::param::rank_step::HirParamRankStepPass,
    pub hir_param_fields: hir::param::fields::HirParamFieldsPass,
    pub hir_method_fields: hir::method::fields::HirMethodFieldsPass,
    pub hir_expr_fields: hir::expr::fields::HirExprFieldsPass,
    pub hir_expr_result_root_step: hir::expr::result_root_step::HirExprResultRootStepPass,
    pub hir_binary_span_apply: hir::binary::span::apply::HirBinarySpanApplyPass,
    pub hir_binary_span_step: hir::binary::span::step::HirBinarySpanStepPass,
    pub hir_binary_spans: hir::binary::spans::HirBinarySpansPass,
    pub hir_index_spans: hir::index_spans::HirIndexSpansPass,
    pub hir_member_fields: hir::member::fields::HirMemberFieldsPass,
    pub hir_member_spans: hir::member::spans::HirMemberSpansPass,
    pub hir_range_spans: hir::range_spans::HirRangeSpansPass,
    pub hir_stmt_fields: hir::stmt_fields::HirStmtFieldsPass,
    pub hir_literal_values: hir::literal_values::HirLiteralValuesPass,
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
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            llp_pairs: llp_pairs::LLPPairsPass::new(device)?,
            pack_offsets: pack::offsets::PackOffsetsScanPass::new(device)?,
            pack_offsets_status: pack::offsets::status::PackOffsetsStatusPass::new(device)?,
            pack_totals_blocks: pack::totals::blocks::PackTotalsBlocksPass::new(device)?,
            pack_totals_reduce: pack::totals::reduce::PackTotalsReducePass::new(device)?,
            pack_totals_status: pack::totals::status::PackTotalsStatusPass::new(device)?,
            pack_varlen: pack::varlen::PackVarlenPass::new(device)?,
            source_file_token_end: source_file_token_end::SourceFileTokenEndPass::new(device)?,

            b01: brackets::scan_inblock::BracketsScanInblockPass::new(device)?,
            b02: brackets::scan_block_prefix::BracketsScanBlockPrefixPass::new(device)?,
            b03: brackets::apply_prefix::BracketsApplyPrefixPass::new(device)?,
            b04: brackets::histogram_layers::BracketsHistogramLayersPass::new(device)?,
            b05: brackets::scan_histograms::BracketsScanHistogramsPass::new(device)?,
            b06: brackets::scatter_by_layer::BracketsScatterByLayerPass::new(device)?,
            pse04: brackets::pse_pair::BracketsPsePairPass::new(device)?,

            tree_parent: tree::parent::TreeParentPass::new(device)?,
            tree_prefix_01: tree::prefix::local::TreePrefixLocalPass::new(device)?,
            tree_prefix_02: tree::prefix::scan_blocks::TreePrefixScanBlocksPass::new(device)?,
            tree_prefix_03: tree::prefix::apply::TreePrefixApplyPass::new(device)?,
            tree_prefix_04: tree::prefix::build_max_tree::TreePrefixMaxBuildPass::new(device)?,
            tree_spans: tree::spans::TreeSpansPass::new(device)?,
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
            hir_semantic_child_index_clear:
                hir::semantic::child::index::clear::HirSemanticChildIndexClearPass::new(device)?,
            hir_semantic_child_index_links:
                hir::semantic::child::index::links::HirSemanticChildIndexLinksPass::new(device)?,
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
            hir_list_rank_prefix_local:
                hir::list::rank::prefix_local::HirListRankPrefixLocalPass::new(device)?,
            hir_list_rank_compact_scatter:
                hir::list::rank::compact_scatter::HirListRankCompactScatterPass::new(device)?,
            hir_type_arg_links: hir::types::arg::links::HirTypeArgLinksPass::new(device)?,
            hir_type_arg_rank_step: hir::types::arg::rank_step::HirTypeArgRankStepPass::new(
                device,
            )?,
            hir_type_arg_scatter: hir::types::arg::scatter::HirTypeArgScatterPass::new(device)?,
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
            hir_param_links: hir::param::links::HirParamLinksPass::new(device)?,
            hir_param_rank_step: hir::param::rank_step::HirParamRankStepPass::new(device)?,
            hir_param_fields: hir::param::fields::HirParamFieldsPass::new(device)?,
            hir_method_fields: hir::method::fields::HirMethodFieldsPass::new(device)?,
            hir_expr_fields: hir::expr::fields::HirExprFieldsPass::new(device)?,
            hir_expr_result_root_step: hir::expr::result_root_step::HirExprResultRootStepPass::new(
                device,
            )?,
            hir_binary_span_apply: hir::binary::span::apply::HirBinarySpanApplyPass::new(device)?,
            hir_binary_span_step: hir::binary::span::step::HirBinarySpanStepPass::new(device)?,
            hir_binary_spans: hir::binary::spans::HirBinarySpansPass::new(device)?,
            hir_index_spans: hir::index_spans::HirIndexSpansPass::new(device)?,
            hir_member_fields: hir::member::fields::HirMemberFieldsPass::new(device)?,
            hir_member_spans: hir::member::spans::HirMemberSpansPass::new(device)?,
            hir_range_spans: hir::range_spans::HirRangeSpansPass::new(device)?,
            hir_stmt_fields: hir::stmt_fields::HirStmtFieldsPass::new(device)?,
            hir_literal_values: hir::literal_values::HirLiteralValuesPass::new(device)?,
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

/// Record the whole pipeline in order.
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

    let n_sc = ctx.buffers.total_sc;
    let n_layers = ctx.buffers.b_n_layers;
    p.b01.record_pass(&mut ctx, E1D(n_sc))?;
    p.b02.record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
    p.b03.record_pass(&mut ctx, E1D(n_sc))?;
    p.b04.record_pass(&mut ctx, E1D(n_sc))?;
    p.b05.record_scan(ctx.device, ctx.encoder, ctx.buffers)?;

    let bytes = (n_layers.max(1) * 4) as u64;
    ctx.encoder.copy_buffer_to_buffer(
        &ctx.buffers.b_off_push,
        0,
        &ctx.buffers.b_cur_push,
        0,
        bytes,
    );
    ctx.encoder
        .copy_buffer_to_buffer(&ctx.buffers.b_off_pop, 0, &ctx.buffers.b_cur_pop, 0, bytes);

    p.b06.record_pass(&mut ctx, E1D(n_sc))?;
    p.pse04.record_pass(&mut ctx, E1D(n_sc))?;

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
    p.hir_semantic_child_index_clear
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_semantic_child_index_links
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
    ctx.encoder.clear_buffer(
        &ctx.buffers.hir_type_path_leaf_link_b.buffer,
        0,
        Some(u64::from(ctx.buffers.tree_capacity) * 4),
    );
    p.hir_type_path_leaf_scatter
        .record_pass(&mut ctx, E1D(n_tree))?;
    let token_input_capacity = ctx.buffers.token_input_capacity;
    ctx.encoder
        .clear_buffer(&ctx.buffers.source_file_token_end, 0, None);
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
    p.hir_type_alias_owner_init
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_type_alias_owner_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &hir_semantic_dispatch_args,
    )?;
    p.hir_type_alias_target
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_fn_signature_owner_init
        .record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_fn_signature_owner_step
        .record_steps(ctx.device, ctx.encoder, ctx.buffers)?;
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
    p.hir_param_rank_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &ctx.buffers.hir_list_rank_dispatch_args,
    )?;
    p.hir_param_fields
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_method_fields
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_expr_fields
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_expr_result_root_step
        .record_steps(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_binary_spans.record_pass(&mut ctx, E1D(n_tree))?;
    p.hir_binary_span_step
        .record_steps(ctx.device, ctx.encoder, ctx.buffers)?;
    p.hir_binary_span_apply.record_pass(&mut ctx, E1D(n_tree))?;
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
    p.hir_context_relations_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &hir_semantic_dispatch_args,
    )?;
    p.hir_context_relations_scatter
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
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

    Ok(())
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
