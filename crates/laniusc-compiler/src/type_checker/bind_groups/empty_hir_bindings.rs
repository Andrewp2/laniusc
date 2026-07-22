use super::super::*;

/// Minimal HIR buffers used when type checking runs without parser item tables.
pub(super) struct EmptyHirBindings {
    node_kind: LaniusBuffer<u32>,
    parent: LaniusBuffer<u32>,
    first_child: LaniusBuffer<u32>,
    next_sibling: LaniusBuffer<u32>,
    semantic_dense_node: LaniusBuffer<u32>,
    compact_param_count: LaniusBuffer<u32>,
    compact_params: LaniusBuffer<u32>,
    compact_param_ranges: LaniusBuffer<u32>,
    compact_path_count: LaniusBuffer<u32>,
    compact_paths: LaniusBuffer<u32>,
    compact_path_segment_count: LaniusBuffer<u32>,
    compact_path_segments: LaniusBuffer<u32>,
    compact_generic_param_count: LaniusBuffer<u32>,
    compact_generic_params: LaniusBuffer<u32>,
    compact_generic_param_ranges: LaniusBuffer<u32>,
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
        let compact_generic_param_count = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_generic_param_count.empty",
            &[0],
        );
        let compact_generic_params = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_generic_params.empty",
            &[u32::MAX; 4],
        );
        let compact_generic_param_ranges = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_generic_param_ranges.empty",
            &[u32::MAX, 0],
        );
        let compact_param_count = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_param_count.empty",
            &[0],
        );
        let compact_params = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_params.empty",
            &[u32::MAX; 4],
        );
        let compact_param_ranges = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_param_ranges.empty",
            &[u32::MAX, 0],
        );
        let compact_path_count =
            storage_ro_from_u32s(device, "type_check.resident.compact_path_count.empty", &[0]);
        let compact_paths = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_paths.empty",
            &[u32::MAX; 4],
        );
        let compact_path_segment_count = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_path_segment_count.empty",
            &[0],
        );
        let compact_path_segments = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_path_segments.empty",
            &[u32::MAX; 4],
        );

        Self {
            node_kind,
            parent,
            first_child,
            next_sibling,
            semantic_dense_node,
            compact_param_count,
            compact_params,
            compact_param_ranges,
            compact_path_count,
            compact_paths,
            compact_path_segment_count,
            compact_path_segments,
            compact_generic_param_count,
            compact_generic_params,
            compact_generic_param_ranges,
        }
    }
}

/// Registers real parser HIR item buffers under the shader resource names.
pub(super) fn register_hir_item_resources<'a>(
    resources: &mut ResourceMap<'a>,
    hir_items: GpuTypeCheckHirItemBuffers<'a>,
) {
    resources.buffer("compact_hir_count", &hir_items.hir.count);
    resources.buffer("compact_hir_core", &hir_items.hir.core);
    resources.buffer("raw_to_compact_hir", &hir_items.raw_to_compact_hir);
    resources.buffer("compact_hir_links", &hir_items.hir.links);
    resources.buffer("compact_hir_payload", &hir_items.hir.payload);
    resources.buffer("compact_hir_scope_end", &hir_items.hir.scope_end);
    resources.buffer("compact_hir_nearest_loop", &hir_items.hir.nearest_loop);
    resources.buffer("compact_hir_nearest_block", &hir_items.hir.nearest_block);
    resources.buffer(
        "compact_hir_nearest_control",
        &hir_items.hir.nearest_control,
    );
    resources.buffer("compact_hir_nearest_fn", &hir_items.hir.nearest_fn);
    resources.buffer("compact_hir_expr_parent", &hir_items.hir.expr_parent);
    resources.buffer("compact_call_arg_count", &hir_items.hir.call_arg_count);
    resources.buffer("compact_call_args", &hir_items.hir.call_args);
    resources.buffer("compact_fn_return_type", &hir_items.hir.fn_return_type);
    resources.buffer(
        "compact_type_alias_target",
        &hir_items.hir.type_alias_target,
    );
    resources.buffer("compact_const_type", &hir_items.hir.const_type);
    resources.buffer("compact_param_count", &hir_items.hir.param_count);
    resources.buffer("compact_params", &hir_items.hir.params);
    resources.buffer("compact_param_ranges", &hir_items.hir.param_ranges);
    resources.buffer("compact_method_count", &hir_items.hir.method_count);
    resources.buffer("compact_method_cores", &hir_items.hir.method_cores);
    resources.buffer(
        "compact_method_signatures",
        &hir_items.hir.method_signatures,
    );
    resources.buffer("compact_predicate_count", &hir_items.hir.predicate_count);
    resources.buffer("compact_predicates", &hir_items.hir.predicates);
    resources.buffer("compact_type_arg_count", &hir_items.hir.type_arg_count);
    resources.buffer("compact_type_args", &hir_items.hir.type_args);
    resources.buffer("compact_type_arg_ranges", &hir_items.hir.type_arg_ranges);
    resources.buffer("compact_path_count", &hir_items.hir.path_count);
    resources.buffer("compact_paths", &hir_items.hir.paths);
    resources.buffer(
        "compact_path_segment_count",
        &hir_items.hir.path_segment_count,
    );
    resources.buffer("compact_path_segments", &hir_items.hir.path_segments);
    resources.buffer(
        "compact_generic_param_count",
        &hir_items.hir.generic_param_count,
    );
    resources.buffer("compact_generic_params", &hir_items.hir.generic_params);
    resources.buffer(
        "compact_generic_param_ranges",
        &hir_items.hir.generic_param_ranges,
    );
    resources.buffer("compact_field_count", &hir_items.hir.field_count);
    resources.buffer("compact_fields", &hir_items.hir.fields);
    resources.buffer("compact_variant_count", &hir_items.hir.variant_count);
    resources.buffer("compact_variants", &hir_items.hir.variants);
    resources.buffer(
        "compact_variant_payload_start",
        &hir_items.hir.variant_payload_start,
    );
    resources.buffer(
        "compact_variant_payload_count",
        &hir_items.hir.variant_payload_count,
    );
    resources.buffer(
        "compact_variant_payload_row_count",
        &hir_items.hir.variant_payload_row_count,
    );
    resources.buffer("compact_variant_payloads", &hir_items.hir.variant_payloads);
    resources.buffer("compact_match_arm_count", &hir_items.hir.match_arm_count);
    resources.buffer("compact_match_arms", &hir_items.hir.match_arms);
    resources.buffer(
        "compact_match_payload_start",
        &hir_items.hir.match_payload_start,
    );
    resources.buffer(
        "compact_match_payload_count",
        &hir_items.hir.match_payload_count,
    );
    resources.buffer(
        "compact_match_payload_row_count",
        &hir_items.hir.match_payload_row_count,
    );
    resources.buffer("compact_match_payloads", &hir_items.hir.match_payloads);
    resources.buffer(
        "compact_array_element_start",
        &hir_items.hir.array_element_start,
    );
    resources.buffer(
        "compact_array_element_count",
        &hir_items.hir.array_element_count,
    );
    resources.buffer(
        "compact_array_element_row_count",
        &hir_items.hir.array_element_row_count,
    );
    resources.buffer("compact_array_elements", &hir_items.hir.array_elements);
    resources.buffer("node_kind", &hir_items.node_kind);
    resources.buffer("parent", &hir_items.parent);
    resources.buffer("parent_record", &hir_items.parent);
    resources.buffer("first_child", &hir_items.first_child);
    resources.buffer("next_sibling", &hir_items.next_sibling);
    resources.buffer("subtree_end", &hir_items.subtree_end);
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
    resources.buffer("hir_path_segment_owner", &hir_items.path_segment_owner);
    resources.buffer("hir_path_segment_rank", &hir_items.path_segment_rank);
    resources.buffer("hir_path_segment_count", &hir_items.path_segment_count);
    resources.buffer("hir_type_arg_start", &hir_items.type_arg_start);
    resources.buffer("hir_type_arg_count", &hir_items.type_arg_count);
    resources.buffer("hir_type_arg_next", &hir_items.type_arg_next);
    resources.buffer("hir_type_arg_owner", &hir_items.type_arg_owner);
    resources.buffer("hir_type_arg_rank", &hir_items.type_arg_rank);
    resources.buffer("hir_type_root_owner", &hir_items.type_root_owner);
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
    resources.buffer("hir_expr_name_role", &hir_items.expr_name_role);
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
    resources.buffer(
        "hir_nearest_array_element_node",
        &hir_items.nearest_array_element_node,
    );
    resources.buffer("hir_array_element_next", &hir_items.array_element_next);
    resources.buffer("hir_item_path_node", &hir_items.path_node);
    resources.buffer("hir_call_callee_node", &hir_items.call_callee_node);
    resources.buffer(
        "hir_call_callee_path_node",
        &hir_items.call_callee_path_node,
    );
    resources.buffer(
        "hir_call_parent_by_callee",
        &hir_items.call_parent_by_callee,
    );
    resources.buffer(
        "hir_call_context_stmt_node",
        &hir_items.call_context_stmt_node,
    );
    resources.buffer("hir_call_arg_start", &hir_items.call_arg_start);
    resources.buffer("hir_call_arg_count", &hir_items.call_arg_count);
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
    resources.buffer("hir_semantic_subtree_end", &hir_items.semantic_subtree_end);
}

/// Registers placeholder HIR resources for modes without parser item metadata.
pub(super) fn register_empty_hir_resources<'a>(
    resources: &mut ResourceMap<'a>,
    empty_hir: &'a EmptyHirBindings,
    hir_active_count: &'a wgpu::Buffer,
) {
    resources.buffer("compact_hir_count", &empty_hir.compact_generic_param_count);
    resources.buffer("compact_hir_core", &empty_hir.compact_generic_params);
    resources.buffer("raw_to_compact_hir", &empty_hir.parent);
    resources.buffer("compact_hir_links", &empty_hir.compact_generic_params);
    resources.buffer("compact_hir_payload", &empty_hir.compact_generic_params);
    resources.buffer("compact_hir_scope_end", &empty_hir.parent);
    resources.buffer("compact_hir_nearest_loop", &empty_hir.parent);
    resources.buffer("compact_hir_nearest_block", &empty_hir.parent);
    resources.buffer("compact_hir_nearest_control", &empty_hir.parent);
    resources.buffer("compact_hir_nearest_fn", &empty_hir.parent);
    resources.buffer("compact_hir_expr_parent", &empty_hir.parent);
    resources.buffer("compact_call_arg_count", &empty_hir.compact_param_count);
    resources.buffer("compact_call_args", &empty_hir.compact_params);
    resources.buffer("compact_fn_return_type", &empty_hir.parent);
    resources.buffer("compact_type_alias_target", &empty_hir.parent);
    resources.buffer("compact_const_type", &empty_hir.parent);
    resources.buffer("compact_param_count", &empty_hir.compact_param_count);
    resources.buffer("compact_params", &empty_hir.compact_params);
    resources.buffer("compact_param_ranges", &empty_hir.compact_param_ranges);
    resources.buffer("compact_method_count", &empty_hir.compact_param_count);
    resources.buffer("compact_method_cores", &empty_hir.compact_params);
    resources.buffer("compact_method_signatures", &empty_hir.compact_params);
    resources.buffer("compact_predicate_count", &empty_hir.compact_param_count);
    resources.buffer("compact_predicates", &empty_hir.compact_params);
    resources.buffer("compact_type_arg_count", &empty_hir.compact_param_count);
    resources.buffer("compact_type_args", &empty_hir.compact_params);
    resources.buffer("compact_type_arg_ranges", &empty_hir.compact_param_ranges);
    resources.buffer("compact_path_count", &empty_hir.compact_path_count);
    resources.buffer("compact_paths", &empty_hir.compact_paths);
    resources.buffer(
        "compact_path_segment_count",
        &empty_hir.compact_path_segment_count,
    );
    resources.buffer("compact_path_segments", &empty_hir.compact_path_segments);
    resources.buffer(
        "compact_generic_param_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer("compact_generic_params", &empty_hir.compact_generic_params);
    resources.buffer(
        "compact_generic_param_ranges",
        &empty_hir.compact_generic_param_ranges,
    );
    resources.buffer(
        "compact_field_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer("compact_fields", &empty_hir.compact_generic_params);
    resources.buffer(
        "compact_variant_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer("compact_variants", &empty_hir.compact_generic_params);
    resources.buffer(
        "compact_variant_payload_start",
        &empty_hir.compact_generic_param_ranges,
    );
    resources.buffer(
        "compact_variant_payload_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer(
        "compact_variant_payload_row_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer(
        "compact_variant_payloads",
        &empty_hir.compact_generic_params,
    );
    resources.buffer(
        "compact_match_arm_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer("compact_match_arms", &empty_hir.compact_generic_params);
    resources.buffer(
        "compact_match_payload_start",
        &empty_hir.compact_generic_param_ranges,
    );
    resources.buffer(
        "compact_match_payload_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer(
        "compact_match_payload_row_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer("compact_match_payloads", &empty_hir.compact_generic_params);
    resources.buffer(
        "compact_array_element_start",
        &empty_hir.compact_generic_param_ranges,
    );
    resources.buffer(
        "compact_array_element_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer(
        "compact_array_element_row_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer("compact_array_elements", &empty_hir.compact_generic_params);
    resources.buffer("node_kind", &empty_hir.node_kind);
    resources.buffer("parent", &empty_hir.parent);
    resources.buffer("parent_record", &empty_hir.parent);
    resources.buffer("first_child", &empty_hir.first_child);
    resources.buffer("next_sibling", &empty_hir.next_sibling);
    resources.buffer("subtree_end", &empty_hir.node_kind);
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
    resources.buffer("hir_type_root_owner", &empty_hir.parent);
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
    resources.buffer("hir_expr_name_role", &empty_hir.node_kind);
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
    resources.buffer("hir_nearest_array_element_node", &empty_hir.parent);
    resources.buffer("hir_array_element_next", &empty_hir.parent);
    resources.buffer("hir_item_path_node", &empty_hir.parent);
    resources.buffer("hir_call_callee_node", &empty_hir.parent);
    resources.buffer("hir_call_callee_path_node", &empty_hir.parent);
    resources.buffer("hir_call_parent_by_callee", &empty_hir.parent);
    resources.buffer("hir_call_context_stmt_node", &empty_hir.parent);
    resources.buffer("hir_call_arg_start", &empty_hir.parent);
    resources.buffer("hir_call_arg_count", &empty_hir.node_kind);
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
    resources.buffer("hir_semantic_subtree_end", &empty_hir.node_kind);
}
