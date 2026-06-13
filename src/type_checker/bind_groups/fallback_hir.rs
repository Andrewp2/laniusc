use super::super::*;

pub(super) struct FallbackHirBuffers {
    node_kind: LaniusBuffer<u32>,
    parent: LaniusBuffer<u32>,
    first_child: LaniusBuffer<u32>,
    next_sibling: LaniusBuffer<u32>,
    semantic_dense_node: LaniusBuffer<u32>,
}

impl FallbackHirBuffers {
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
    resources.buffer("hir_type_path_leaf_node", &hir_items.type_path_leaf_node);
    resources.buffer(
        "hir_bound_path_owner_by_leaf",
        &hir_items.bound_path_owner_by_leaf,
    );
    resources.buffer("hir_type_arg_start", &hir_items.type_arg_start);
    resources.buffer("hir_type_arg_count", &hir_items.type_arg_count);
    resources.buffer("hir_type_arg_next", &hir_items.type_arg_next);
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

pub(super) fn register_fallback_hir_resources<'a>(
    resources: &mut ResourceMap<'a>,
    fallback: &'a FallbackHirBuffers,
    hir_active_count: &'a wgpu::Buffer,
) {
    resources.buffer("node_kind", &fallback.node_kind);
    resources.buffer("parent", &fallback.parent);
    resources.buffer("parent_record", &fallback.parent);
    resources.buffer("first_child", &fallback.first_child);
    resources.buffer("next_sibling", &fallback.next_sibling);
    resources.buffer("hir_item_kind", &fallback.node_kind);
    resources.buffer("hir_item_name_token", &fallback.parent);
    resources.buffer("hir_type_form", &fallback.node_kind);
    resources.buffer("hir_type_value_node", &fallback.parent);
    resources.buffer("hir_type_len_token", &fallback.parent);
    resources.buffer("hir_type_len_value", &fallback.parent);
    resources.buffer("hir_type_path_leaf_node", &fallback.parent);
    resources.buffer("hir_bound_path_owner_by_leaf", &fallback.parent);
    resources.buffer("hir_type_arg_start", &fallback.parent);
    resources.buffer("hir_type_arg_count", &fallback.node_kind);
    resources.buffer("hir_type_arg_next", &fallback.parent);
    resources.buffer("hir_type_alias_target_node", &fallback.parent);
    resources.buffer("hir_fn_return_type_node", &fallback.parent);
    resources.buffer("hir_param_record", &fallback.parent);
    resources.buffer("hir_param_type_node", &fallback.parent);
    resources.buffer("hir_method_owner_node", &fallback.parent);
    resources.buffer("hir_method_impl_node", &fallback.parent);
    resources.buffer("hir_method_name_token", &fallback.parent);
    resources.buffer("hir_method_first_param_token", &fallback.parent);
    resources.buffer("hir_method_receiver_mode", &fallback.node_kind);
    resources.buffer("hir_method_visibility", &fallback.node_kind);
    resources.buffer("hir_method_signature_flags", &fallback.node_kind);
    resources.buffer("hir_method_impl_receiver_type_node", &fallback.parent);
    resources.buffer("hir_expr_record", &fallback.parent);
    resources.buffer("hir_expr_result_node", &fallback.parent);
    resources.buffer("hir_expr_result_root_node", &fallback.parent);
    resources.buffer("hir_expr_int_value", &fallback.node_kind);
    resources.buffer("hir_member_receiver_node", &fallback.parent);
    resources.buffer("hir_member_receiver_token", &fallback.parent);
    resources.buffer("hir_member_name_token", &fallback.parent);
    resources.buffer("hir_stmt_record", &fallback.parent);
    resources.buffer("hir_stmt_scope_end", &fallback.parent);
    resources.buffer("hir_nearest_stmt_node", &fallback.parent);
    resources.buffer("hir_nearest_block_node", &fallback.parent);
    resources.buffer("hir_nearest_loop_node", &fallback.parent);
    resources.buffer("hir_nearest_fn_node", &fallback.parent);
    resources.buffer("hir_array_lit_first_element", &fallback.parent);
    resources.buffer("hir_array_lit_element_count", &fallback.node_kind);
    resources.buffer("hir_array_lit_context_stmt_node", &fallback.parent);
    resources.buffer("hir_array_element_parent_lit", &fallback.parent);
    resources.buffer("hir_array_element_next", &fallback.parent);
    resources.buffer("hir_call_callee_node", &fallback.parent);
    resources.buffer("hir_call_context_stmt_node", &fallback.parent);
    resources.buffer("hir_call_arg_start", &fallback.parent);
    resources.buffer("hir_call_arg_end", &fallback.parent);
    resources.buffer("hir_call_arg_count", &fallback.node_kind);
    resources.buffer("hir_call_arg_parent_call", &fallback.parent);
    resources.buffer("hir_call_arg_ordinal", &fallback.parent);
    resources.buffer("hir_variant_parent_enum", &fallback.parent);
    resources.buffer("hir_variant_payload_start", &fallback.parent);
    resources.buffer("hir_variant_payload_count", &fallback.node_kind);
    resources.buffer("hir_variant_payload_node", &fallback.parent);
    resources.buffer("hir_match_arm_result_node", &fallback.parent);
    resources.buffer("hir_match_payload_owner_arm", &fallback.parent);
    resources.buffer("hir_match_payload_match_node", &fallback.parent);
    resources.buffer("hir_match_payload_ordinal", &fallback.parent);
    resources.buffer("hir_struct_field_parent_struct", &fallback.parent);
    resources.buffer("hir_struct_field_ordinal", &fallback.parent);
    resources.buffer("hir_struct_field_type_node", &fallback.parent);
    resources.buffer("hir_struct_decl_field_start", &fallback.parent);
    resources.buffer("hir_struct_decl_field_count", &fallback.node_kind);
    resources.buffer("hir_struct_lit_head_node", &fallback.parent);
    resources.buffer("hir_struct_lit_context_stmt_node", &fallback.parent);
    resources.buffer("hir_struct_lit_field_start", &fallback.parent);
    resources.buffer("hir_struct_lit_field_count", &fallback.node_kind);
    resources.buffer("hir_struct_lit_field_parent_lit", &fallback.parent);
    resources.buffer("hir_struct_lit_field_value_node", &fallback.parent);
    resources.buffer("hir_semantic_dense_node", &fallback.semantic_dense_node);
    resources.buffer("hir_semantic_count", hir_active_count);
}
