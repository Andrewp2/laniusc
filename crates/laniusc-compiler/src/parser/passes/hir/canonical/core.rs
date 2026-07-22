use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalCorePass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalCorePass,
    label: "hir_canonical_core",
    shader: "parser/hir/canonical/core"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalCorePass {
    const NAME: &'static str = "hir_canonical_core";
    const DIM: DispatchDim = DispatchDim::D1;
    fn from_data(data: PassData) -> Self {
        Self { data }
    }
    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        b: &'a ParserBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            (
                "gCanonical".into(),
                b.hir_canonical_params.as_entire_binding(),
            ),
            (
                "canonical_count".into(),
                b.hir_canonical_count.as_entire_binding(),
            ),
            (
                "canonical_prefix_before_raw".into(),
                b.hir_canonical_prefix_before_raw.as_entire_binding(),
            ),
            (
                "canonical_dense_to_raw".into(),
                b.hir_canonical_dense_to_raw.as_entire_binding(),
            ),
            (
                "canonical_raw_to_dense".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "parent_value".into(),
                b.hir_semantic_parent_value_a.as_entire_binding(),
            ),
            ("subtree_end".into(), b.subtree_end.as_entire_binding()),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            ("hir_token_end".into(), b.hir_token_end.as_entire_binding()),
            (
                "hir_token_file_id".into(),
                b.hir_token_file_id.as_entire_binding(),
            ),
            ("hir_item_kind".into(), b.hir_item_kind.as_entire_binding()),
            (
                "hir_item_name_token".into(),
                b.hir_item_name_token.as_entire_binding(),
            ),
            (
                "hir_item_namespace".into(),
                b.hir_item_namespace.as_entire_binding(),
            ),
            (
                "hir_item_visibility".into(),
                b.hir_item_visibility.as_entire_binding(),
            ),
            (
                "hir_item_import_target_kind".into(),
                b.hir_item_import_target_kind.as_entire_binding(),
            ),
            (
                "hir_method_name_token".into(),
                b.hir_method_name_token.as_entire_binding(),
            ),
            ("hir_type_form".into(), b.hir_type_form.as_entire_binding()),
            (
                "hir_type_value_node".into(),
                b.hir_type_value_node.as_entire_binding(),
            ),
            (
                "hir_type_len_token".into(),
                b.hir_type_len_token.as_entire_binding(),
            ),
            (
                "hir_type_len_value".into(),
                b.hir_type_len_value.as_entire_binding(),
            ),
            (
                "hir_fn_return_type_node".into(),
                b.hir_fn_return_type_node.as_entire_binding(),
            ),
            (
                "hir_type_alias_target_node".into(),
                b.hir_type_alias_target_node.as_entire_binding(),
            ),
            (
                "hir_param_record".into(),
                b.hir_param_record.as_entire_binding(),
            ),
            (
                "hir_param_type_node".into(),
                b.hir_param_type_node.as_entire_binding(),
            ),
            (
                "hir_stmt_record".into(),
                b.hir_stmt_record.as_entire_binding(),
            ),
            (
                "hir_stmt_scope_end".into(),
                b.hir_stmt_scope_end.as_entire_binding(),
            ),
            (
                "hir_expr_record".into(),
                b.hir_expr_record.as_entire_binding(),
            ),
            (
                "hir_expr_int_value".into(),
                b.hir_expr_int_value.as_entire_binding(),
            ),
            (
                "hir_expr_float_bits".into(),
                b.hir_expr_float_bits.as_entire_binding(),
            ),
            (
                "hir_expr_result_root_node".into(),
                b.hir_expr_result_root_node.as_entire_binding(),
            ),
            (
                "hir_call_callee_node".into(),
                b.hir_call_callee_node.as_entire_binding(),
            ),
            (
                "hir_call_arg_count".into(),
                b.hir_call_arg_count.as_entire_binding(),
            ),
            (
                "hir_call_context_stmt_node".into(),
                b.hir_call_context_stmt_node.as_entire_binding(),
            ),
            (
                "hir_member_receiver_node".into(),
                b.hir_member_receiver_node.as_entire_binding(),
            ),
            (
                "hir_member_receiver_token".into(),
                b.hir_member_receiver_token.as_entire_binding(),
            ),
            (
                "hir_member_name_token".into(),
                b.hir_member_name_token.as_entire_binding(),
            ),
            (
                "hir_array_lit_context_stmt_node".into(),
                b.hir_array_lit_context_stmt_node.as_entire_binding(),
            ),
            (
                "hir_struct_lit_context_stmt_node".into(),
                b.hir_struct_lit_context_stmt_node.as_entire_binding(),
            ),
            (
                "hir_match_scrutinee_node".into(),
                b.hir_match_scrutinee_node.as_entire_binding(),
            ),
            (
                "hir_nearest_loop_node".into(),
                b.hir_nearest_loop_node.as_entire_binding(),
            ),
            (
                "hir_nearest_block_node".into(),
                b.hir_nearest_block_node.as_entire_binding(),
            ),
            (
                "hir_nearest_enclosing_control_node".into(),
                b.hir_nearest_enclosing_control_node.as_entire_binding(),
            ),
            (
                "hir_nearest_fn_node".into(),
                b.hir_nearest_fn_node.as_entire_binding(),
            ),
            ("hir_core".into(), b.hir_core.as_entire_binding()),
            ("hir_links".into(), b.hir_links.as_entire_binding()),
            ("hir_payload".into(), b.hir_payload.as_entire_binding()),
            (
                "hir_canonical_scope_end".into(),
                b.hir_canonical_scope_end.as_entire_binding(),
            ),
            (
                "hir_canonical_nearest_loop".into(),
                b.hir_canonical_nearest_loop.as_entire_binding(),
            ),
            (
                "hir_canonical_nearest_block".into(),
                b.hir_canonical_nearest_block.as_entire_binding(),
            ),
            (
                "hir_canonical_nearest_control".into(),
                b.hir_canonical_nearest_control.as_entire_binding(),
            ),
            (
                "hir_canonical_nearest_fn".into(),
                b.hir_canonical_nearest_fn.as_entire_binding(),
            ),
            (
                "hir_canonical_fn_return_type".into(),
                b.hir_canonical_fn_return_type.as_entire_binding(),
            ),
            (
                "hir_canonical_type_alias_target".into(),
                b.hir_canonical_type_alias_target.as_entire_binding(),
            ),
            (
                "hir_canonical_const_type".into(),
                b.hir_canonical_const_type.as_entire_binding(),
            ),
            (
                "hir_canonical_const_value".into(),
                b.hir_canonical_const_value.as_entire_binding(),
            ),
        ])
    }
}
