use super::*;
use crate::gpu::buffers::LaniusBuffer;

const TYPECHECK_FRONTEND_WORKSPACE_COUNT: usize =
    crate::parser::buffers::POST_HIR_WORKSPACE_COUNT + 7;

/// Owned parser buffers retained for type-check recording and diagnostics.
pub(super) struct OwnedTypecheckParserBuffers {
    pub(super) hir: crate::parser::buffers::GpuHirView,
    /// Parser-only record storage whose contents are dead after compact HIR
    /// materialization and may back type-check workspace slots.
    pub(super) phase_workspace:
        [LaniusBuffer<u32>; crate::parser::buffers::POST_HIR_WORKSPACE_COUNT],
    pub(super) raw_to_compact_hir: LaniusBuffer<u32>,
    pub(super) parser_feature_flags: u32,
    pub(super) module_record_capacity: u32,
    pub(super) call_param_row_capacity: u32,
    pub(super) call_arg_row_capacity: u32,
    pub(super) ll1_status: LaniusBuffer<u32>,
    pub(super) node_kind: LaniusBuffer<u32>,
    pub(super) parent: LaniusBuffer<u32>,
    pub(super) first_child: LaniusBuffer<u32>,
    pub(super) next_sibling: LaniusBuffer<u32>,
    pub(super) subtree_end: LaniusBuffer<u32>,
    pub(super) hir_kind: LaniusBuffer<u32>,
    pub(super) hir_token_pos: LaniusBuffer<u32>,
    pub(super) hir_token_end: LaniusBuffer<u32>,
    pub(super) hir_token_file_id: LaniusBuffer<u32>,
    pub(super) hir_semantic_count: LaniusBuffer<u32>,
    pub(super) hir_semantic_dense_node: LaniusBuffer<u32>,
    pub(super) hir_semantic_subtree_end: Box<LaniusBuffer<u32>>,
    pub(super) hir_type_form: LaniusBuffer<u32>,
    pub(super) hir_type_len_token: LaniusBuffer<u32>,
    pub(super) hir_type_path_leaf_node: LaniusBuffer<u32>,
    pub(super) hir_bound_path_owner_by_leaf: LaniusBuffer<u32>,
    pub(super) hir_type_arg_start: LaniusBuffer<u32>,
    pub(super) hir_type_arg_count: LaniusBuffer<u32>,
    pub(super) hir_type_arg_next: LaniusBuffer<u32>,
    pub(super) hir_method_impl_receiver_type_node: LaniusBuffer<u32>,
    pub(super) hir_expr_name_role: LaniusBuffer<u32>,
    pub(super) hir_expr_result_root_node: LaniusBuffer<u32>,
    pub(super) hir_member_receiver_node: LaniusBuffer<u32>,
    pub(super) hir_member_receiver_token: LaniusBuffer<u32>,
    pub(super) hir_member_name_token: LaniusBuffer<u32>,
    pub(super) hir_nearest_fn_node: LaniusBuffer<u32>,
    pub(super) hir_array_element_parent_lit: LaniusBuffer<u32>,
    pub(super) hir_nearest_array_element_node: LaniusBuffer<u32>,
    pub(super) hir_struct_lit_head_node: LaniusBuffer<u32>,
    pub(super) hir_struct_lit_field_parent_lit: LaniusBuffer<u32>,
    pub(super) hir_struct_lit_field_value_node: LaniusBuffer<u32>,
}

impl OwnedTypecheckParserBuffers {
    /// Clones parser buffers needed by type-check recording.
    pub(super) fn from_parser_buffers(bufs: &ParserBuffers) -> Self {
        Self {
            hir: crate::parser::buffers::GpuHirView::from_parser_buffers(bufs),
            phase_workspace: bufs.post_hir_workspace(),
            raw_to_compact_hir: bufs.hir_canonical_raw_to_dense.clone(),
            parser_feature_flags: bufs.parser_feature_flags,
            // These compact families contain source-anchored semantic rows,
            // never grammar scaffolding. Their worst-case capacity is the
            // canonical token bound, not the raw production-tree bound.
            module_record_capacity: bufs.n_tokens.saturating_sub(2).max(1),
            call_param_row_capacity: bufs.n_tokens.saturating_sub(2).max(1),
            call_arg_row_capacity: bufs.n_tokens.saturating_sub(2).max(1),
            ll1_status: bufs.ll1_status.clone(),
            node_kind: bufs.node_kind.clone(),
            parent: bufs.parent.clone(),
            first_child: bufs.first_child.clone(),
            next_sibling: bufs.next_sibling.clone(),
            subtree_end: bufs.subtree_end.clone(),
            hir_kind: bufs.hir_kind.clone(),
            hir_token_pos: bufs.hir_token_pos.clone(),
            hir_token_end: bufs.hir_token_end.clone(),
            hir_token_file_id: bufs.hir_token_file_id.clone(),
            hir_semantic_count: bufs.hir_semantic_count.clone(),
            hir_semantic_dense_node: bufs.hir_semantic_dense_node.clone(),
            hir_semantic_subtree_end: Box::new(bufs.hir_semantic_subtree_end.clone()),
            hir_type_form: bufs.hir_type_form.clone(),
            hir_type_len_token: bufs.hir_type_len_token.clone(),
            hir_type_path_leaf_node: bufs.hir_type_path_leaf_node.clone(),
            hir_bound_path_owner_by_leaf: bufs.hir_bound_path_owner_by_leaf.clone(),
            hir_type_arg_start: bufs.hir_type_arg_start.clone(),
            hir_type_arg_count: bufs.hir_type_arg_count.clone(),
            hir_type_arg_next: bufs.hir_type_arg_next.clone(),
            hir_method_impl_receiver_type_node: bufs.hir_method_impl_receiver_type_node.clone(),
            hir_expr_name_role: bufs.hir_expr_name_role.clone(),
            hir_expr_result_root_node: bufs.hir_expr_result_root_node.clone(),
            hir_member_receiver_node: bufs.hir_member_receiver_node.clone(),
            hir_member_receiver_token: bufs.hir_member_receiver_token.clone(),
            hir_member_name_token: bufs.hir_member_name_token.clone(),
            hir_nearest_fn_node: bufs.hir_nearest_fn_node.clone(),
            hir_array_element_parent_lit: bufs.hir_array_element_parent_lit.clone(),
            hir_nearest_array_element_node: bufs.hir_nearest_array_element_node.clone(),
            hir_struct_lit_head_node: bufs.hir_struct_lit_head_node.clone(),
            hir_struct_lit_field_parent_lit: bufs.hir_struct_lit_field_parent_lit.clone(),
            hir_struct_lit_field_value_node: bufs.hir_struct_lit_field_value_node.clone(),
        }
    }

    /// Builds the borrowed HIR-item buffer view expected by type-check kernels.
    pub(super) fn typecheck_workspace<'a>(
        &'a self,
        lexer: &'a LexerBuffers,
    ) -> [crate::gpu::buffers::TrackedBufferView<'a>; TYPECHECK_FRONTEND_WORKSPACE_COUNT] {
        let parser = self.phase_workspace.each_ref().map(Into::into);
        let lexer = [
            (&lexer.tok_types).into(),
            (&lexer.flags_packed).into(),
            (&lexer.s_all_final).into(),
            (&lexer.s_keep_final).into(),
            (&lexer.end_positions).into(),
            (&lexer.types_compact).into(),
            (&lexer.all_index_compact).into(),
        ];
        std::array::from_fn(|index| {
            if index < parser.len() {
                parser[index]
            } else {
                lexer[index - parser.len()]
            }
        })
    }

    pub(super) fn hir_item_buffers<'a>(
        &'a self,
        upstream_workspace: &'a [crate::gpu::buffers::TrackedBufferView<'a>],
    ) -> gpu_type_checker::GpuTypeCheckHirItemBuffers<'a> {
        gpu_type_checker::GpuTypeCheckHirItemBuffers {
            parser_feature_flags: self.parser_feature_flags,
            module_record_capacity: self.module_record_capacity,
            call_param_row_capacity: self.call_param_row_capacity,
            call_arg_row_capacity: self.call_arg_row_capacity,
            hir: &self.hir,
            upstream_workspace,
            raw_to_compact_hir: &self.raw_to_compact_hir,
            node_kind: &self.node_kind,
            parent: &self.parent,
            first_child: &self.first_child,
            next_sibling: &self.next_sibling,
            subtree_end: &self.subtree_end,
            type_form: &self.hir_type_form,
            type_len_token: &self.hir_type_len_token,
            type_path_leaf_node: &self.hir_type_path_leaf_node,
            bound_path_owner_by_leaf: &self.hir_bound_path_owner_by_leaf,
            type_arg_start: &self.hir_type_arg_start,
            type_arg_count: &self.hir_type_arg_count,
            type_arg_next: &self.hir_type_arg_next,
            method_impl_receiver_type_node: &self.hir_method_impl_receiver_type_node,
            expr_name_role: &self.hir_expr_name_role,
            expr_result_root_node: &self.hir_expr_result_root_node,
            member_receiver_node: &self.hir_member_receiver_node,
            member_receiver_token: &self.hir_member_receiver_token,
            member_name_token: &self.hir_member_name_token,
            nearest_fn_node: &self.hir_nearest_fn_node,
            array_element_parent_lit: &self.hir_array_element_parent_lit,
            nearest_array_element_node: &self.hir_nearest_array_element_node,
            struct_lit_head_node: &self.hir_struct_lit_head_node,
            struct_lit_field_parent_lit: &self.hir_struct_lit_field_parent_lit,
            struct_lit_field_value_node: &self.hir_struct_lit_field_value_node,
            semantic_dense_node: &self.hir_semantic_dense_node,
            semantic_count: &self.hir_semantic_count,
            semantic_subtree_end: &self.hir_semantic_subtree_end,
        }
    }

    /// Builds the checked HIR view used by semantic-interface type discovery.
    pub(super) fn semantic_interface_hir_buffers(
        &self,
    ) -> gpu_type_checker::GpuSemanticInterfaceHirBuffers<'_> {
        gpu_type_checker::GpuSemanticInterfaceHirBuffers {
            compact_hir_capacity: u32::try_from(self.hir.core.count).unwrap_or(u32::MAX),
            compact_hir_count: &self.hir.count,
            compact_hir_core: &self.hir.core,
            compact_hir_payload: &self.hir.payload,
            compact_const_value: &self.hir.const_value,
            compact_fn_return_type: &self.hir.fn_return_type,
            compact_type_alias_target: &self.hir.type_alias_target,
            compact_const_type: &self.hir.const_type,
            compact_param_count: &self.hir.param_count,
            compact_params: &self.hir.params,
            compact_param_ranges: &self.hir.param_ranges,
            compact_type_arg_count: &self.hir.type_arg_count,
            compact_type_args: &self.hir.type_args,
            compact_type_arg_ranges: &self.hir.type_arg_ranges,
            compact_field_count: &self.hir.field_count,
            compact_fields: &self.hir.fields,
            compact_variant_count: &self.hir.variant_count,
            compact_variants: &self.hir.variants,
            compact_variant_payload_count: &self.hir.variant_payload_count,
            compact_variant_payload_row_count: &self.hir.variant_payload_row_count,
            compact_variant_payloads: &self.hir.variant_payloads,
            compact_method_count: &self.hir.method_count,
            compact_method_cores: &self.hir.method_cores,
            compact_method_signatures: &self.hir.method_signatures,
        }
    }
}
