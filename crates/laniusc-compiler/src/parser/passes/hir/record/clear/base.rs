use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that clears base HIR record buffers before reconstruction.
pub struct HirRecordClearBasePass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirRecordClearBasePass,
    label: "hir_record_clear_base",
    shader: "parser/hir/record/clear/base"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirRecordClearBasePass {
    const NAME: &'static str = "hir_record_clear_base";
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
            ("gClear".into(), b.hir_params.as_entire_binding()),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
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
                "hir_item_path_start".into(),
                b.hir_item_path_start.as_entire_binding(),
            ),
            (
                "hir_item_path_end".into(),
                b.hir_item_path_end.as_entire_binding(),
            ),
            (
                "hir_item_path_node".into(),
                b.hir_item_path_node.as_entire_binding(),
            ),
            (
                "hir_item_import_target_kind".into(),
                b.hir_item_import_target_kind.as_entire_binding(),
            ),
            (
                "hir_type_alias_target_node".into(),
                b.hir_type_alias_target_node.as_entire_binding(),
            ),
            (
                "hir_fn_return_type_node".into(),
                b.hir_fn_return_type_node.as_entire_binding(),
            ),
            (
                "hir_type_len_value".into(),
                b.hir_type_len_value.as_entire_binding(),
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
                "hir_method_owner_node".into(),
                b.hir_method_owner_node.as_entire_binding(),
            ),
            (
                "hir_method_impl_node".into(),
                b.hir_method_impl_node.as_entire_binding(),
            ),
            (
                "hir_method_name_token".into(),
                b.hir_method_name_token.as_entire_binding(),
            ),
            (
                "hir_method_first_param_token".into(),
                b.hir_method_first_param_token.as_entire_binding(),
            ),
            (
                "hir_method_receiver_mode".into(),
                b.hir_method_receiver_mode.as_entire_binding(),
            ),
            (
                "hir_method_visibility".into(),
                b.hir_method_visibility.as_entire_binding(),
            ),
            (
                "hir_method_signature_flags".into(),
                b.hir_method_signature_flags.as_entire_binding(),
            ),
            (
                "hir_method_impl_receiver_type_node".into(),
                b.hir_method_impl_receiver_type_node.as_entire_binding(),
            ),
            (
                "hir_expr_record".into(),
                b.hir_expr_record.as_entire_binding(),
            ),
            (
                "hir_expr_name_role".into(),
                b.hir_expr_name_role.as_entire_binding(),
            ),
            (
                "hir_expr_result_node".into(),
                b.hir_expr_result_node.as_entire_binding(),
            ),
            (
                "hir_expr_result_root_node".into(),
                b.hir_expr_result_root_node.as_entire_binding(),
            ),
            (
                "hir_expr_result_root_scratch_node".into(),
                b.hir_expr_result_root_scratch_node.as_entire_binding(),
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
                "hir_nearest_stmt_node".into(),
                b.hir_nearest_stmt_node.as_entire_binding(),
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
                "hir_nearest_loop_node".into(),
                b.hir_nearest_loop_node.as_entire_binding(),
            ),
            (
                "hir_nearest_fn_node".into(),
                b.hir_nearest_fn_node.as_entire_binding(),
            ),
            (
                "hir_nearest_array_element_node".into(),
                b.hir_nearest_array_element_node.as_entire_binding(),
            ),
        ])
    }
}
