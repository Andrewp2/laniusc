// Parser passes use the shared Pass trait from gpu::passes_core.
use anyhow::Result;

use crate::{
    gpu::passes_core::{InputElements, Pass, PassContext},
    parser::{buffers::ParserBuffers, debug::DebugOutput},
};

pub mod brackets_01;
pub mod brackets_02;
pub mod brackets_03;
pub mod brackets_04;
pub mod brackets_05;
pub mod brackets_06;
pub mod brackets_pse_04;

pub mod hir_array_element_links;
pub mod hir_array_element_rank_step;
pub mod hir_array_element_scatter;
pub mod hir_array_fields;
pub mod hir_call_arg_links;
pub mod hir_call_arg_ordinal_scatter;
pub mod hir_call_arg_ordinal_step;
pub mod hir_call_fields;
pub mod hir_enum_match_fields;
pub mod hir_enum_rank_compact_scatter;
pub mod hir_enum_rank_prefix_local;
pub mod hir_enum_variant_links;
pub mod hir_enum_variant_rank_step;
pub mod hir_enum_variant_scatter;
pub mod hir_expr_fields;
pub mod hir_fn_return_type;
pub mod hir_fn_signature_owner_init;
pub mod hir_fn_signature_owner_step;
pub mod hir_item_decl_tokens;
pub mod hir_item_fields;
pub mod hir_list_rank_compact_scatter;
pub mod hir_list_rank_prefix_local;
pub mod hir_literal_values;
pub mod hir_match_arm_links;
pub mod hir_match_arm_rank_step;
pub mod hir_match_arm_scatter;
pub mod hir_match_rank_compact_scatter;
pub mod hir_match_rank_prefix_local;
pub mod hir_member_fields;
pub mod hir_nodes;
pub mod hir_param_fields;
pub mod hir_param_links;
pub mod hir_param_rank_step;
pub mod hir_record_clear_base;
pub mod hir_record_clear_calls;
pub mod hir_semantic_child_index_clear;
pub mod hir_semantic_child_index_links;
pub mod hir_semantic_child_index_rank_step;
pub mod hir_semantic_compact_scatter;
pub mod hir_semantic_depth_init;
pub mod hir_semantic_depth_step;
pub mod hir_semantic_dispatch_args;
pub mod hir_semantic_nav;
pub mod hir_semantic_parent_init;
pub mod hir_semantic_parent_scatter;
pub mod hir_semantic_parent_step;
pub mod hir_semantic_prefix_blocks;
pub mod hir_semantic_prefix_local;
pub mod hir_semantic_subtree_end;
pub mod hir_spans;
pub mod hir_stmt_fields;
pub mod hir_struct_field_links;
pub mod hir_struct_field_rank_step;
pub mod hir_struct_field_scatter;
pub mod hir_struct_fields;
pub mod hir_struct_rank_compact_scatter;
pub mod hir_struct_rank_prefix_local;
pub mod hir_type_alias_owner_init;
pub mod hir_type_alias_owner_step;
pub mod hir_type_alias_target;
pub mod hir_type_arg_links;
pub mod hir_type_arg_rank_step;
pub mod hir_type_arg_scatter;
pub mod hir_type_fields;
pub mod hir_type_path_leaf_links;
pub mod hir_type_path_leaf_scatter;
pub mod hir_type_path_leaf_step;
pub mod ll1_blocks_01;
pub mod ll1_blocks_02;
pub mod ll1_blocks_03;
pub mod ll1_blocks_04;
pub mod ll1_blocks_04_scan;
pub mod llp_pairs;
pub mod pack_offsets;
pub mod pack_offsets_status;
pub mod pack_totals_blocks;
pub mod pack_totals_reduce;
pub mod pack_totals_status;
pub mod pack_varlen;
pub mod tree_parent;
pub mod tree_prefix_01;
pub mod tree_prefix_02;
pub mod tree_prefix_03;
pub mod tree_prefix_04;
pub mod tree_prev_sibling_clear;
pub mod tree_prev_sibling_scatter;
pub mod tree_spans;

/// Bundle of all parser passes.
pub struct ParserPasses {
    pub ll1_blocks_02: ll1_blocks_02::LL1BlocksStitchPass,
    pub ll1_blocks_03: ll1_blocks_03::LL1BlocksSeededPass,
    pub ll1_blocks_04_scan: ll1_blocks_04_scan::LL1BlocksEmitPrefixScanPass,
    pub ll1_blocks_04: ll1_blocks_04::LL1BlocksFlattenEmitPass,
    pub llp_pairs: llp_pairs::LLPPairsPass,
    pub pack_offsets: pack_offsets::PackOffsetsScanPass,
    pub pack_offsets_status: pack_offsets_status::PackOffsetsStatusPass,
    pub pack_totals_blocks: pack_totals_blocks::PackTotalsBlocksPass,
    pub pack_totals_reduce: pack_totals_reduce::PackTotalsReducePass,
    pub pack_totals_status: pack_totals_status::PackTotalsStatusPass,
    pub pack_varlen: pack_varlen::PackVarlenPass,

    // Bracket matching passes
    pub b01: brackets_01::BracketsScanInblockPass,
    pub b02: brackets_02::BracketsScanBlockPrefixPass,
    pub b03: brackets_03::BracketsApplyPrefixPass,
    pub b04: brackets_04::BracketsHistogramLayersPass,
    pub b05: brackets_05::BracketsScanHistogramsPass,
    pub b06: brackets_06::BracketsScatterByLayerPass,
    pub pse04: brackets_pse_04::BracketsPsePairPass, // Replaces b07

    // Tree building pass
    pub tree_prefix_01: tree_prefix_01::TreePrefixLocalPass,
    pub tree_prefix_02: tree_prefix_02::TreePrefixScanBlocksPass,
    pub tree_prefix_03: tree_prefix_03::TreePrefixApplyPass,
    pub tree_prefix_04: tree_prefix_04::TreePrefixMaxBuildPass,
    pub tree_parent: tree_parent::TreeParentPass,
    pub tree_spans: tree_spans::TreeSpansPass,
    pub tree_prev_sibling_clear: tree_prev_sibling_clear::TreePrevSiblingClearPass,
    pub tree_prev_sibling_scatter: tree_prev_sibling_scatter::TreePrevSiblingScatterPass,

    // HIR-facing classification
    pub hir_nodes: hir_nodes::HirNodesPass,
    pub hir_semantic_prefix_local: hir_semantic_prefix_local::HirSemanticPrefixLocalPass,
    pub hir_semantic_prefix_blocks: hir_semantic_prefix_blocks::HirSemanticPrefixBlocksPass,
    pub hir_semantic_compact_scatter: hir_semantic_compact_scatter::HirSemanticCompactScatterPass,
    pub hir_semantic_dispatch_args: hir_semantic_dispatch_args::HirSemanticDispatchArgsPass,
    pub hir_semantic_subtree_end: hir_semantic_subtree_end::HirSemanticSubtreeEndPass,
    pub hir_semantic_parent_init: hir_semantic_parent_init::HirSemanticParentInitPass,
    pub hir_semantic_parent_step: hir_semantic_parent_step::HirSemanticParentStepPass,
    pub hir_semantic_parent_scatter: hir_semantic_parent_scatter::HirSemanticParentScatterPass,
    pub hir_semantic_nav: hir_semantic_nav::HirSemanticNavPass,
    pub hir_semantic_depth_init: hir_semantic_depth_init::HirSemanticDepthInitPass,
    pub hir_semantic_depth_step: hir_semantic_depth_step::HirSemanticDepthStepPass,
    pub hir_semantic_child_index_clear:
        hir_semantic_child_index_clear::HirSemanticChildIndexClearPass,
    pub hir_semantic_child_index_links:
        hir_semantic_child_index_links::HirSemanticChildIndexLinksPass,
    pub hir_semantic_child_index_rank_step:
        hir_semantic_child_index_rank_step::HirSemanticChildIndexRankStepPass,
    pub hir_record_clear_base: hir_record_clear_base::HirRecordClearBasePass,
    pub hir_record_clear_calls: hir_record_clear_calls::HirRecordClearCallsPass,
    pub hir_spans: hir_spans::HirSpansPass,
    pub hir_type_fields: hir_type_fields::HirTypeFieldsPass,
    pub hir_type_path_leaf_links: hir_type_path_leaf_links::HirTypePathLeafLinksPass,
    pub hir_type_path_leaf_step: hir_type_path_leaf_step::HirTypePathLeafStepPass,
    pub hir_type_path_leaf_scatter: hir_type_path_leaf_scatter::HirTypePathLeafScatterPass,
    pub hir_list_rank_prefix_local: hir_list_rank_prefix_local::HirListRankPrefixLocalPass,
    pub hir_list_rank_compact_scatter: hir_list_rank_compact_scatter::HirListRankCompactScatterPass,
    pub hir_type_arg_links: hir_type_arg_links::HirTypeArgLinksPass,
    pub hir_type_arg_rank_step: hir_type_arg_rank_step::HirTypeArgRankStepPass,
    pub hir_type_arg_scatter: hir_type_arg_scatter::HirTypeArgScatterPass,
    pub hir_type_alias_owner_init: hir_type_alias_owner_init::HirTypeAliasOwnerInitPass,
    pub hir_type_alias_owner_step: hir_type_alias_owner_step::HirTypeAliasOwnerStepPass,
    pub hir_type_alias_target: hir_type_alias_target::HirTypeAliasTargetPass,
    pub hir_fn_signature_owner_init: hir_fn_signature_owner_init::HirFnSignatureOwnerInitPass,
    pub hir_fn_signature_owner_step: hir_fn_signature_owner_step::HirFnSignatureOwnerStepPass,
    pub hir_fn_return_type: hir_fn_return_type::HirFnReturnTypePass,
    pub hir_item_fields: hir_item_fields::HirItemFieldsPass,
    pub hir_item_decl_tokens: hir_item_decl_tokens::HirItemDeclTokensPass,
    pub hir_param_links: hir_param_links::HirParamLinksPass,
    pub hir_param_rank_step: hir_param_rank_step::HirParamRankStepPass,
    pub hir_param_fields: hir_param_fields::HirParamFieldsPass,
    pub hir_expr_fields: hir_expr_fields::HirExprFieldsPass,
    pub hir_member_fields: hir_member_fields::HirMemberFieldsPass,
    pub hir_stmt_fields: hir_stmt_fields::HirStmtFieldsPass,
    pub hir_literal_values: hir_literal_values::HirLiteralValuesPass,
    pub hir_call_fields: hir_call_fields::HirCallFieldsPass,
    pub hir_call_arg_links: hir_call_arg_links::HirCallArgLinksPass,
    pub hir_call_arg_ordinal_step: hir_call_arg_ordinal_step::HirCallArgOrdinalStepPass,
    pub hir_call_arg_ordinal_scatter: hir_call_arg_ordinal_scatter::HirCallArgOrdinalScatterPass,
    pub hir_array_fields: hir_array_fields::HirArrayFieldsPass,
    pub hir_array_element_links: hir_array_element_links::HirArrayElementLinksPass,
    pub hir_array_element_rank_step: hir_array_element_rank_step::HirArrayElementRankStepPass,
    pub hir_array_element_scatter: hir_array_element_scatter::HirArrayElementScatterPass,
    pub hir_enum_match_fields: hir_enum_match_fields::HirEnumMatchFieldsPass,
    pub hir_enum_variant_links: hir_enum_variant_links::HirEnumVariantLinksPass,
    pub hir_enum_rank_prefix_local: hir_enum_rank_prefix_local::HirEnumRankPrefixLocalPass,
    pub hir_enum_rank_compact_scatter: hir_enum_rank_compact_scatter::HirEnumRankCompactScatterPass,
    pub hir_enum_variant_rank_step: hir_enum_variant_rank_step::HirEnumVariantRankStepPass,
    pub hir_enum_variant_scatter: hir_enum_variant_scatter::HirEnumVariantScatterPass,
    pub hir_match_arm_links: hir_match_arm_links::HirMatchArmLinksPass,
    pub hir_match_rank_prefix_local: hir_match_rank_prefix_local::HirMatchRankPrefixLocalPass,
    pub hir_match_rank_compact_scatter:
        hir_match_rank_compact_scatter::HirMatchRankCompactScatterPass,
    pub hir_match_arm_rank_step: hir_match_arm_rank_step::HirMatchArmRankStepPass,
    pub hir_match_arm_scatter: hir_match_arm_scatter::HirMatchArmScatterPass,
    pub hir_struct_fields: hir_struct_fields::HirStructFieldsPass,
    pub hir_struct_field_links: hir_struct_field_links::HirStructFieldLinksPass,
    pub hir_struct_rank_prefix_local: hir_struct_rank_prefix_local::HirStructRankPrefixLocalPass,
    pub hir_struct_rank_compact_scatter:
        hir_struct_rank_compact_scatter::HirStructRankCompactScatterPass,
    pub hir_struct_field_rank_step: hir_struct_field_rank_step::HirStructFieldRankStepPass,
    pub hir_struct_field_scatter: hir_struct_field_scatter::HirStructFieldScatterPass,
}

impl ParserPasses {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            ll1_blocks_02: ll1_blocks_02::LL1BlocksStitchPass::new(device)?,
            ll1_blocks_03: ll1_blocks_03::LL1BlocksSeededPass::new(device)?,
            ll1_blocks_04_scan: ll1_blocks_04_scan::LL1BlocksEmitPrefixScanPass::new(device)?,
            ll1_blocks_04: ll1_blocks_04::LL1BlocksFlattenEmitPass::new(device)?,
            llp_pairs: llp_pairs::LLPPairsPass::new(device)?,
            pack_offsets: pack_offsets::PackOffsetsScanPass::new(device)?,
            pack_offsets_status: pack_offsets_status::PackOffsetsStatusPass::new(device)?,
            pack_totals_blocks: pack_totals_blocks::PackTotalsBlocksPass::new(device)?,
            pack_totals_reduce: pack_totals_reduce::PackTotalsReducePass::new(device)?,
            pack_totals_status: pack_totals_status::PackTotalsStatusPass::new(device)?,
            pack_varlen: pack_varlen::PackVarlenPass::new(device)?,

            b01: brackets_01::BracketsScanInblockPass::new(device)?,
            b02: brackets_02::BracketsScanBlockPrefixPass::new(device)?,
            b03: brackets_03::BracketsApplyPrefixPass::new(device)?,
            b04: brackets_04::BracketsHistogramLayersPass::new(device)?,
            b05: brackets_05::BracketsScanHistogramsPass::new(device)?,
            b06: brackets_06::BracketsScatterByLayerPass::new(device)?,
            pse04: brackets_pse_04::BracketsPsePairPass::new(device)?,

            tree_parent: tree_parent::TreeParentPass::new(device)?,
            tree_prefix_01: tree_prefix_01::TreePrefixLocalPass::new(device)?,
            tree_prefix_02: tree_prefix_02::TreePrefixScanBlocksPass::new(device)?,
            tree_prefix_03: tree_prefix_03::TreePrefixApplyPass::new(device)?,
            tree_prefix_04: tree_prefix_04::TreePrefixMaxBuildPass::new(device)?,
            tree_spans: tree_spans::TreeSpansPass::new(device)?,
            tree_prev_sibling_clear: tree_prev_sibling_clear::TreePrevSiblingClearPass::new(
                device,
            )?,
            tree_prev_sibling_scatter: tree_prev_sibling_scatter::TreePrevSiblingScatterPass::new(
                device,
            )?,
            hir_nodes: hir_nodes::HirNodesPass::new(device)?,
            hir_semantic_prefix_local: hir_semantic_prefix_local::HirSemanticPrefixLocalPass::new(
                device,
            )?,
            hir_semantic_prefix_blocks:
                hir_semantic_prefix_blocks::HirSemanticPrefixBlocksPass::new(device)?,
            hir_semantic_compact_scatter:
                hir_semantic_compact_scatter::HirSemanticCompactScatterPass::new(device)?,
            hir_semantic_dispatch_args:
                hir_semantic_dispatch_args::HirSemanticDispatchArgsPass::new(device)?,
            hir_semantic_subtree_end: hir_semantic_subtree_end::HirSemanticSubtreeEndPass::new(
                device,
            )?,
            hir_semantic_parent_init: hir_semantic_parent_init::HirSemanticParentInitPass::new(
                device,
            )?,
            hir_semantic_parent_step: hir_semantic_parent_step::HirSemanticParentStepPass::new(
                device,
            )?,
            hir_semantic_parent_scatter:
                hir_semantic_parent_scatter::HirSemanticParentScatterPass::new(device)?,
            hir_semantic_nav: hir_semantic_nav::HirSemanticNavPass::new(device)?,
            hir_semantic_depth_init: hir_semantic_depth_init::HirSemanticDepthInitPass::new(
                device,
            )?,
            hir_semantic_depth_step: hir_semantic_depth_step::HirSemanticDepthStepPass::new(
                device,
            )?,
            hir_semantic_child_index_clear:
                hir_semantic_child_index_clear::HirSemanticChildIndexClearPass::new(device)?,
            hir_semantic_child_index_links:
                hir_semantic_child_index_links::HirSemanticChildIndexLinksPass::new(device)?,
            hir_semantic_child_index_rank_step:
                hir_semantic_child_index_rank_step::HirSemanticChildIndexRankStepPass::new(device)?,
            hir_record_clear_base: hir_record_clear_base::HirRecordClearBasePass::new(device)?,
            hir_record_clear_calls: hir_record_clear_calls::HirRecordClearCallsPass::new(device)?,
            hir_spans: hir_spans::HirSpansPass::new(device)?,
            hir_type_fields: hir_type_fields::HirTypeFieldsPass::new(device)?,
            hir_type_path_leaf_links: hir_type_path_leaf_links::HirTypePathLeafLinksPass::new(
                device,
            )?,
            hir_type_path_leaf_step: hir_type_path_leaf_step::HirTypePathLeafStepPass::new(device)?,
            hir_type_path_leaf_scatter:
                hir_type_path_leaf_scatter::HirTypePathLeafScatterPass::new(device)?,
            hir_list_rank_prefix_local:
                hir_list_rank_prefix_local::HirListRankPrefixLocalPass::new(device)?,
            hir_list_rank_compact_scatter:
                hir_list_rank_compact_scatter::HirListRankCompactScatterPass::new(device)?,
            hir_type_arg_links: hir_type_arg_links::HirTypeArgLinksPass::new(device)?,
            hir_type_arg_rank_step: hir_type_arg_rank_step::HirTypeArgRankStepPass::new(device)?,
            hir_type_arg_scatter: hir_type_arg_scatter::HirTypeArgScatterPass::new(device)?,
            hir_type_alias_owner_init: hir_type_alias_owner_init::HirTypeAliasOwnerInitPass::new(
                device,
            )?,
            hir_type_alias_owner_step: hir_type_alias_owner_step::HirTypeAliasOwnerStepPass::new(
                device,
            )?,
            hir_type_alias_target: hir_type_alias_target::HirTypeAliasTargetPass::new(device)?,
            hir_fn_signature_owner_init:
                hir_fn_signature_owner_init::HirFnSignatureOwnerInitPass::new(device)?,
            hir_fn_signature_owner_step:
                hir_fn_signature_owner_step::HirFnSignatureOwnerStepPass::new(device)?,
            hir_fn_return_type: hir_fn_return_type::HirFnReturnTypePass::new(device)?,
            hir_item_fields: hir_item_fields::HirItemFieldsPass::new(device)?,
            hir_item_decl_tokens: hir_item_decl_tokens::HirItemDeclTokensPass::new(device)?,
            hir_param_links: hir_param_links::HirParamLinksPass::new(device)?,
            hir_param_rank_step: hir_param_rank_step::HirParamRankStepPass::new(device)?,
            hir_param_fields: hir_param_fields::HirParamFieldsPass::new(device)?,
            hir_expr_fields: hir_expr_fields::HirExprFieldsPass::new(device)?,
            hir_member_fields: hir_member_fields::HirMemberFieldsPass::new(device)?,
            hir_stmt_fields: hir_stmt_fields::HirStmtFieldsPass::new(device)?,
            hir_literal_values: hir_literal_values::HirLiteralValuesPass::new(device)?,
            hir_call_fields: hir_call_fields::HirCallFieldsPass::new(device)?,
            hir_call_arg_links: hir_call_arg_links::HirCallArgLinksPass::new(device)?,
            hir_call_arg_ordinal_step: hir_call_arg_ordinal_step::HirCallArgOrdinalStepPass::new(
                device,
            )?,
            hir_call_arg_ordinal_scatter:
                hir_call_arg_ordinal_scatter::HirCallArgOrdinalScatterPass::new(device)?,
            hir_array_fields: hir_array_fields::HirArrayFieldsPass::new(device)?,
            hir_array_element_links: hir_array_element_links::HirArrayElementLinksPass::new(
                device,
            )?,
            hir_array_element_rank_step:
                hir_array_element_rank_step::HirArrayElementRankStepPass::new(device)?,
            hir_array_element_scatter: hir_array_element_scatter::HirArrayElementScatterPass::new(
                device,
            )?,
            hir_enum_match_fields: hir_enum_match_fields::HirEnumMatchFieldsPass::new(device)?,
            hir_enum_variant_links: hir_enum_variant_links::HirEnumVariantLinksPass::new(device)?,
            hir_enum_rank_prefix_local:
                hir_enum_rank_prefix_local::HirEnumRankPrefixLocalPass::new(device)?,
            hir_enum_rank_compact_scatter:
                hir_enum_rank_compact_scatter::HirEnumRankCompactScatterPass::new(device)?,
            hir_enum_variant_rank_step:
                hir_enum_variant_rank_step::HirEnumVariantRankStepPass::new(device)?,
            hir_enum_variant_scatter: hir_enum_variant_scatter::HirEnumVariantScatterPass::new(
                device,
            )?,
            hir_match_arm_links: hir_match_arm_links::HirMatchArmLinksPass::new(device)?,
            hir_match_rank_prefix_local:
                hir_match_rank_prefix_local::HirMatchRankPrefixLocalPass::new(device)?,
            hir_match_rank_compact_scatter:
                hir_match_rank_compact_scatter::HirMatchRankCompactScatterPass::new(device)?,
            hir_match_arm_rank_step: hir_match_arm_rank_step::HirMatchArmRankStepPass::new(device)?,
            hir_match_arm_scatter: hir_match_arm_scatter::HirMatchArmScatterPass::new(device)?,
            hir_struct_fields: hir_struct_fields::HirStructFieldsPass::new(device)?,
            hir_struct_field_links: hir_struct_field_links::HirStructFieldLinksPass::new(device)?,
            hir_struct_rank_prefix_local:
                hir_struct_rank_prefix_local::HirStructRankPrefixLocalPass::new(device)?,
            hir_struct_rank_compact_scatter:
                hir_struct_rank_compact_scatter::HirStructRankCompactScatterPass::new(device)?,
            hir_struct_field_rank_step:
                hir_struct_field_rank_step::HirStructFieldRankStepPass::new(device)?,
            hir_struct_field_scatter: hir_struct_field_scatter::HirStructFieldScatterPass::new(
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

    if ctx.buffers.tree_stream_uses_ll1 {
        let n_ll1_blocks = ctx.buffers.ll1_n_blocks;
        p.ll1_blocks_02
            .record_pass(&mut ctx, E1D(n_ll1_blocks.saturating_mul(256)))?;
        p.ll1_blocks_03
            .record_pass(&mut ctx, E1D(n_ll1_blocks.saturating_mul(256)))?;
        p.ll1_blocks_04_scan
            .record_scan(ctx.device, ctx.encoder, ctx.buffers)?;
        p.ll1_blocks_04
            .record_pass(&mut ctx, E1D(n_ll1_blocks.max(2).saturating_mul(256)))?;
    } else {
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
        ctx.encoder.copy_buffer_to_buffer(
            &ctx.buffers.b_off_pop,
            0,
            &ctx.buffers.b_cur_pop,
            0,
            bytes,
        );

        p.b06.record_pass(&mut ctx, E1D(n_sc))?;
        p.pse04.record_pass(&mut ctx, E1D(n_sc))?;
    }

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
    let tree_active_dispatch_args = ctx.buffers.tree_active_dispatch_args.buffer.clone();
    p.hir_record_clear_base
        .record_pass_indirect(&mut ctx, &tree_active_dispatch_args)?;
    p.hir_record_clear_calls
        .record_pass_indirect(&mut ctx, &tree_active_dispatch_args)?;
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
        .record_pass_indirect(&mut ctx, &tree_active_dispatch_args)?;
    p.hir_fn_signature_owner_step.record_steps_indirect(
        ctx.device,
        ctx.encoder,
        ctx.buffers,
        &tree_active_dispatch_args,
    )?;
    p.hir_fn_return_type
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
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
    p.hir_expr_fields
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_member_fields
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_stmt_fields
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
    p.hir_call_fields
        .record_pass_indirect(&mut ctx, &hir_semantic_dispatch_args)?;
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
    p.hir_struct_field_links
        .record_pass(&mut ctx, E1D(n_tree))?;
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
