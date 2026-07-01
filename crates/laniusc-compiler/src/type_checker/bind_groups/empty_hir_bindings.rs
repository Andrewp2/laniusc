use super::super::*;

/// Minimal HIR buffers used when type checking runs without parser item tables.
pub(super) struct EmptyHirBindings {
    node_kind: LaniusBuffer<u32>,
    parent: LaniusBuffer<u32>,
    first_child: LaniusBuffer<u32>,
    next_sibling: LaniusBuffer<u32>,
    semantic_dense_node: LaniusBuffer<u32>,
}

impl EmptyHirBindings {
    /// Creates placeholder HIR resources that satisfy every reflected binding.
    pub(super) fn new(device: &wgpu::Device, uses_hir_items: bool, hir_node_capacity: u32) -> Self {
        let empty_hir_len = if uses_hir_items {
            1
        } else {
            hir_node_capacity.max(1) as usize
        };
        let invalid_node = vec![u32::MAX; empty_hir_len];
        let zero_node = vec![0u32; empty_hir_len];
        let identity_node: Vec<u32> = if uses_hir_items {
            vec![0]
        } else {
            (0..empty_hir_len as u32).collect()
        };
        let node_kind =
            storage_ro_from_u32s(device, "type_check.resident.node_kind.empty", &zero_node);
        let parent =
            storage_ro_from_u32s(device, "type_check.resident.parent.empty", &invalid_node);
        let first_child = storage_ro_from_u32s(
            device,
            "type_check.resident.first_child.empty",
            &invalid_node,
        );
        let next_sibling = storage_ro_from_u32s(
            device,
            "type_check.resident.next_sibling.empty",
            &invalid_node,
        );
        let semantic_dense_node = storage_ro_from_u32s(
            device,
            "type_check.resident.hir_semantic_dense_node.identity",
            &identity_node,
        );

        Self {
            node_kind,
            parent,
            first_child,
            next_sibling,
            semantic_dense_node,
        }
    }
}

/// Registers real parser HIR item buffers under the shader resource names.
pub(super) fn register_hir_item_resources<'a>(
    resources: &mut ResourceMap<'a>,
    hir_items: GpuTypeCheckHirItemBuffers<'a>,
) {
    resources.buffer("node_kind", &hir_items.node_kind);
    resources.buffer("parent", &hir_items.parent);
    resources.buffer("parent_record", &hir_items.parent);
    resources.buffer("first_child", &hir_items.first_child);
    resources.buffer("next_sibling", &hir_items.next_sibling);
    resources.buffer("subtree_end", &hir_items.subtree_end);
    resources.buffer("hir_item_kind", &hir_items.kind);
    resources.buffer("hir_item_name_token", &hir_items.name_token);
    resources.buffer("hir_type_form", &hir_items.type_form);
    resources.buffer("hir_type_value_node", &hir_items.type_value_node);
    resources.buffer("hir_type_len_token", &hir_items.type_len_token);
    resources.buffer("hir_type_len_value", &hir_items.type_len_value);
    resources.buffer("hir_type_file_id", &hir_items.type_file_id);
    resources.buffer("hir_type_path_leaf_node", &hir_items.type_path_leaf_node);
    resources.buffer(
        "hir_bound_path_owner_by_leaf",
        &hir_items.bound_path_owner_by_leaf,
    );
    resources.buffer("hir_type_arg_start", &hir_items.type_arg_start);
    resources.buffer("hir_type_arg_count", &hir_items.type_arg_count);
    resources.buffer("hir_type_arg_next", &hir_items.type_arg_next);
    resources.buffer("hir_type_arg_owner", &hir_items.type_arg_owner);
    resources.buffer("hir_type_arg_rank", &hir_items.type_arg_rank);
    resources.buffer(
        "hir_type_alias_target_node",
        &hir_items.type_alias_target_node,
    );
    resources.buffer("hir_fn_return_type_node", &hir_items.fn_return_type_node);
    resources.buffer("hir_param_record", &hir_items.param_record);
    resources.buffer("hir_param_type_node", &hir_items.param_type_node);
    resources.buffer("hir_method_owner_node", &hir_items.method_owner_node);
    resources.buffer("hir_method_impl_node", &hir_items.method_impl_node);
    resources.buffer("hir_method_name_token", &hir_items.method_name_token);
    resources.buffer(
        "hir_method_first_param_token",
        &hir_items.method_first_param_token,
    );
    resources.buffer("hir_method_receiver_mode", &hir_items.method_receiver_mode);
    resources.buffer("hir_method_visibility", &hir_items.method_visibility);
    resources.buffer(
        "hir_method_signature_flags",
        &hir_items.method_signature_flags,
    );
    resources.buffer(
        "hir_method_impl_receiver_type_node",
        &hir_items.method_impl_receiver_type_node,
    );
    resources.buffer("hir_expr_record", &hir_items.expr_record);
    resources.buffer("hir_expr_result_node", &hir_items.expr_result_node);
    resources.buffer(
        "hir_expr_result_root_node",
        &hir_items.expr_result_root_node,
    );
    resources.buffer("hir_expr_int_value", &hir_items.expr_int_value);
    resources.buffer("hir_member_receiver_node", &hir_items.member_receiver_node);
    resources.buffer(
        "hir_member_receiver_token",
        &hir_items.member_receiver_token,
    );
    resources.buffer("hir_member_name_token", &hir_items.member_name_token);
    resources.buffer("hir_stmt_record", &hir_items.stmt_record);
    resources.buffer("hir_stmt_scope_end", &hir_items.stmt_scope_end);
    resources.buffer("hir_nearest_stmt_node", &hir_items.nearest_stmt_node);
    resources.buffer("hir_nearest_block_node", &hir_items.nearest_block_node);
    resources.buffer(
        "hir_nearest_enclosing_control_node",
        &hir_items.nearest_enclosing_control_node,
    );
    resources.buffer("hir_nearest_loop_node", &hir_items.nearest_loop_node);
    resources.buffer("hir_nearest_fn_node", &hir_items.nearest_fn_node);
    resources.buffer(
        "hir_array_lit_first_element",
        &hir_items.array_lit_first_element,
    );
    resources.buffer(
        "hir_array_lit_element_count",
        &hir_items.array_lit_element_count,
    );
    resources.buffer(
        "hir_array_lit_context_stmt_node",
        &hir_items.array_lit_context_stmt_node,
    );
    resources.buffer(
        "hir_array_element_parent_lit",
        &hir_items.array_element_parent_lit,
    );
    resources.buffer("hir_array_element_next", &hir_items.array_element_next);
    resources.buffer("hir_item_path_node", &hir_items.path_node);
    resources.buffer("hir_call_callee_node", &hir_items.call_callee_node);
    resources.buffer(
        "hir_call_context_stmt_node",
        &hir_items.call_context_stmt_node,
    );
    resources.buffer("hir_call_arg_start", &hir_items.call_arg_start);
    resources.buffer("hir_call_arg_end", &hir_items.call_arg_end);
    resources.buffer("hir_call_arg_count", &hir_items.call_arg_count);
    resources.buffer("hir_call_arg_parent_call", &hir_items.call_arg_parent_call);
    resources.buffer("hir_call_arg_ordinal", &hir_items.call_arg_ordinal);
    resources.buffer("hir_variant_parent_enum", &hir_items.variant_parent_enum);
    resources.buffer(
        "hir_variant_payload_start",
        &hir_items.variant_payload_start,
    );
    resources.buffer(
        "hir_variant_payload_count",
        &hir_items.variant_payload_count,
    );
    resources.buffer("hir_variant_payload_node", &hir_items.variant_payload_node);
    resources.buffer(
        "hir_match_arm_result_node",
        &hir_items.match_arm_result_node,
    );
    resources.buffer(
        "hir_match_payload_owner_arm",
        &hir_items.match_payload_owner_arm,
    );
    resources.buffer(
        "hir_match_payload_match_node",
        &hir_items.match_payload_match_node,
    );
    resources.buffer(
        "hir_match_payload_ordinal",
        &hir_items.match_payload_ordinal,
    );
    resources.buffer(
        "hir_struct_field_parent_struct",
        &hir_items.struct_field_parent_struct,
    );
    resources.buffer("hir_struct_field_ordinal", &hir_items.struct_field_ordinal);
    resources.buffer(
        "hir_struct_field_type_node",
        &hir_items.struct_field_type_node,
    );
    resources.buffer(
        "hir_struct_decl_field_start",
        &hir_items.struct_decl_field_start,
    );
    resources.buffer(
        "hir_struct_decl_field_count",
        &hir_items.struct_decl_field_count,
    );
    resources.buffer("hir_struct_lit_head_node", &hir_items.struct_lit_head_node);
    resources.buffer(
        "hir_struct_lit_context_stmt_node",
        &hir_items.struct_lit_context_stmt_node,
    );
    resources.buffer(
        "hir_struct_lit_field_start",
        &hir_items.struct_lit_field_start,
    );
    resources.buffer(
        "hir_struct_lit_field_count",
        &hir_items.struct_lit_field_count,
    );
    resources.buffer(
        "hir_struct_lit_field_parent_lit",
        &hir_items.struct_lit_field_parent_lit,
    );
    resources.buffer(
        "hir_struct_lit_field_value_node",
        &hir_items.struct_lit_field_value_node,
    );
    resources.buffer("hir_semantic_dense_node", &hir_items.semantic_dense_node);
    resources.buffer("hir_semantic_count", &hir_items.semantic_count);
}

/// Registers placeholder HIR resources for modes without parser item metadata.
pub(super) fn register_empty_hir_resources<'a>(
    resources: &mut ResourceMap<'a>,
    empty_hir: &'a EmptyHirBindings,
    hir_active_count: &'a wgpu::Buffer,
) {
    resources.buffer("node_kind", &empty_hir.node_kind);
    resources.buffer("parent", &empty_hir.parent);
    resources.buffer("parent_record", &empty_hir.parent);
    resources.buffer("first_child", &empty_hir.first_child);
    resources.buffer("next_sibling", &empty_hir.next_sibling);
    resources.buffer("subtree_end", &empty_hir.node_kind);
    resources.buffer("hir_item_kind", &empty_hir.node_kind);
    resources.buffer("hir_item_name_token", &empty_hir.parent);
    resources.buffer("hir_type_form", &empty_hir.node_kind);
    resources.buffer("hir_type_value_node", &empty_hir.parent);
    resources.buffer("hir_type_len_token", &empty_hir.parent);
    resources.buffer("hir_type_len_value", &empty_hir.parent);
    resources.buffer("hir_type_file_id", &empty_hir.parent);
    resources.buffer("hir_type_path_leaf_node", &empty_hir.parent);
    resources.buffer("hir_bound_path_owner_by_leaf", &empty_hir.parent);
    resources.buffer("hir_type_arg_start", &empty_hir.parent);
    resources.buffer("hir_type_arg_count", &empty_hir.node_kind);
    resources.buffer("hir_type_arg_next", &empty_hir.parent);
    resources.buffer("hir_type_arg_owner", &empty_hir.parent);
    resources.buffer("hir_type_arg_rank", &empty_hir.node_kind);
    resources.buffer("hir_type_alias_target_node", &empty_hir.parent);
    resources.buffer("hir_fn_return_type_node", &empty_hir.parent);
    resources.buffer("hir_param_record", &empty_hir.parent);
    resources.buffer("hir_param_type_node", &empty_hir.parent);
    resources.buffer("hir_method_owner_node", &empty_hir.parent);
    resources.buffer("hir_method_impl_node", &empty_hir.parent);
    resources.buffer("hir_method_name_token", &empty_hir.parent);
    resources.buffer("hir_method_first_param_token", &empty_hir.parent);
    resources.buffer("hir_method_receiver_mode", &empty_hir.node_kind);
    resources.buffer("hir_method_visibility", &empty_hir.node_kind);
    resources.buffer("hir_method_signature_flags", &empty_hir.node_kind);
    resources.buffer("hir_method_impl_receiver_type_node", &empty_hir.parent);
    resources.buffer("hir_expr_record", &empty_hir.parent);
    resources.buffer("hir_expr_result_node", &empty_hir.parent);
    resources.buffer("hir_expr_result_root_node", &empty_hir.parent);
    resources.buffer("hir_expr_int_value", &empty_hir.node_kind);
    resources.buffer("hir_member_receiver_node", &empty_hir.parent);
    resources.buffer("hir_member_receiver_token", &empty_hir.parent);
    resources.buffer("hir_member_name_token", &empty_hir.parent);
    resources.buffer("hir_stmt_record", &empty_hir.parent);
    resources.buffer("hir_stmt_scope_end", &empty_hir.parent);
    resources.buffer("hir_nearest_stmt_node", &empty_hir.parent);
    resources.buffer("hir_nearest_block_node", &empty_hir.parent);
    resources.buffer("hir_nearest_enclosing_control_node", &empty_hir.parent);
    resources.buffer("hir_nearest_loop_node", &empty_hir.parent);
    resources.buffer("hir_nearest_fn_node", &empty_hir.parent);
    resources.buffer("hir_array_lit_first_element", &empty_hir.parent);
    resources.buffer("hir_array_lit_element_count", &empty_hir.node_kind);
    resources.buffer("hir_array_lit_context_stmt_node", &empty_hir.parent);
    resources.buffer("hir_array_element_parent_lit", &empty_hir.parent);
    resources.buffer("hir_array_element_next", &empty_hir.parent);
    resources.buffer("hir_item_path_node", &empty_hir.parent);
    resources.buffer("hir_call_callee_node", &empty_hir.parent);
    resources.buffer("hir_call_context_stmt_node", &empty_hir.parent);
    resources.buffer("hir_call_arg_start", &empty_hir.parent);
    resources.buffer("hir_call_arg_end", &empty_hir.parent);
    resources.buffer("hir_call_arg_count", &empty_hir.node_kind);
    resources.buffer("hir_call_arg_parent_call", &empty_hir.parent);
    resources.buffer("hir_call_arg_ordinal", &empty_hir.parent);
    resources.buffer("hir_variant_parent_enum", &empty_hir.parent);
    resources.buffer("hir_variant_payload_start", &empty_hir.parent);
    resources.buffer("hir_variant_payload_count", &empty_hir.node_kind);
    resources.buffer("hir_variant_payload_node", &empty_hir.parent);
    resources.buffer("hir_match_arm_result_node", &empty_hir.parent);
    resources.buffer("hir_match_payload_owner_arm", &empty_hir.parent);
    resources.buffer("hir_match_payload_match_node", &empty_hir.parent);
    resources.buffer("hir_match_payload_ordinal", &empty_hir.parent);
    resources.buffer("hir_struct_field_parent_struct", &empty_hir.parent);
    resources.buffer("hir_struct_field_ordinal", &empty_hir.parent);
    resources.buffer("hir_struct_field_type_node", &empty_hir.parent);
    resources.buffer("hir_struct_decl_field_start", &empty_hir.parent);
    resources.buffer("hir_struct_decl_field_count", &empty_hir.node_kind);
    resources.buffer("hir_struct_lit_head_node", &empty_hir.parent);
    resources.buffer("hir_struct_lit_context_stmt_node", &empty_hir.parent);
    resources.buffer("hir_struct_lit_field_start", &empty_hir.parent);
    resources.buffer("hir_struct_lit_field_count", &empty_hir.node_kind);
    resources.buffer("hir_struct_lit_field_parent_lit", &empty_hir.parent);
    resources.buffer("hir_struct_lit_field_value_node", &empty_hir.parent);
    resources.buffer("hir_semantic_dense_node", &empty_hir.semantic_dense_node);
    resources.buffer("hir_semantic_count", hir_active_count);
}
