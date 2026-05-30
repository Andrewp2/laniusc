use std::collections::HashMap;

use super::super::super::*;

pub(super) struct EmptyHirBuffers {
    node_kind: LaniusBuffer<u32>,
    parent: LaniusBuffer<u32>,
    first_child: LaniusBuffer<u32>,
    next_sibling: LaniusBuffer<u32>,
}

impl EmptyHirBuffers {
    pub(super) fn new(device: &wgpu::Device, hir_node_capacity: u32) -> Self {
        let len = hir_node_capacity.max(1) as usize;
        let zero_nodes = vec![0u32; len];
        let invalid_nodes = vec![u32::MAX; len];
        Self {
            node_kind: storage_ro_from_u32s(
                device,
                "type_check.tokens.node_kind.empty",
                &zero_nodes,
            ),
            parent: storage_ro_from_u32s(device, "type_check.tokens.parent.empty", &invalid_nodes),
            first_child: storage_ro_from_u32s(
                device,
                "type_check.tokens.first_child.empty",
                &invalid_nodes,
            ),
            next_sibling: storage_ro_from_u32s(
                device,
                "type_check.tokens.next_sibling.empty",
                &invalid_nodes,
            ),
        }
    }

    pub(super) fn insert_resources<'a>(
        &'a self,
        resources: &mut HashMap<String, wgpu::BindingResource<'a>>,
    ) {
        self.insert_tree_resources(resources);
        self.insert_type_resources(resources);
        self.insert_expr_resources(resources);
        self.insert_call_and_variant_resources(resources);
        self.insert_match_resources(resources);
        self.insert_struct_resources(resources);
        self.insert_predicate_resources(resources);
    }

    fn insert_tree_resources<'a>(
        &'a self,
        resources: &mut HashMap<String, wgpu::BindingResource<'a>>,
    ) {
        resources.insert("node_kind".into(), self.node_kind.as_entire_binding());
        resources.insert("parent".into(), self.parent.as_entire_binding());
        resources.insert("parent_record".into(), self.parent.as_entire_binding());
        resources.insert("first_child".into(), self.first_child.as_entire_binding());
        resources.insert("next_sibling".into(), self.next_sibling.as_entire_binding());
        resources.insert("subtree_end".into(), self.parent.as_entire_binding());
        resources.insert("hir_item_kind".into(), self.node_kind.as_entire_binding());
        resources.insert(
            "hir_item_name_token".into(),
            self.parent.as_entire_binding(),
        );
    }

    fn insert_type_resources<'a>(
        &'a self,
        resources: &mut HashMap<String, wgpu::BindingResource<'a>>,
    ) {
        resources.insert("hir_type_form".into(), self.node_kind.as_entire_binding());
        resources.insert(
            "hir_type_value_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert("hir_type_len_token".into(), self.parent.as_entire_binding());
        resources.insert("hir_type_len_value".into(), self.parent.as_entire_binding());
        resources.insert(
            "hir_type_path_leaf_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert("hir_type_arg_start".into(), self.parent.as_entire_binding());
        resources.insert(
            "hir_type_arg_count".into(),
            self.node_kind.as_entire_binding(),
        );
        resources.insert("hir_type_arg_next".into(), self.parent.as_entire_binding());
        resources.insert(
            "hir_type_alias_target_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_fn_return_type_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_method_signature_flags".into(),
            self.node_kind.as_entire_binding(),
        );
        resources.insert("hir_param_record".into(), self.parent.as_entire_binding());
        resources.insert(
            "hir_param_type_node".into(),
            self.parent.as_entire_binding(),
        );
    }

    fn insert_expr_resources<'a>(
        &'a self,
        resources: &mut HashMap<String, wgpu::BindingResource<'a>>,
    ) {
        resources.insert("hir_expr_record".into(), self.parent.as_entire_binding());
        resources.insert(
            "hir_expr_result_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_expr_result_root_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_expr_int_value".into(),
            self.node_kind.as_entire_binding(),
        );
        resources.insert(
            "hir_member_receiver_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_member_receiver_token".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_member_name_token".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert("hir_stmt_record".into(), self.parent.as_entire_binding());
        resources.insert("hir_stmt_scope_end".into(), self.parent.as_entire_binding());
        resources.insert(
            "hir_array_lit_first_element".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_array_lit_element_count".into(),
            self.node_kind.as_entire_binding(),
        );
        resources.insert(
            "hir_array_lit_context_stmt_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_array_element_parent_lit".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_array_element_next".into(),
            self.parent.as_entire_binding(),
        );
    }

    fn insert_call_and_variant_resources<'a>(
        &'a self,
        resources: &mut HashMap<String, wgpu::BindingResource<'a>>,
    ) {
        resources.insert(
            "hir_call_callee_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_call_context_stmt_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert("hir_call_arg_start".into(), self.parent.as_entire_binding());
        resources.insert("hir_call_arg_end".into(), self.parent.as_entire_binding());
        resources.insert(
            "hir_call_arg_count".into(),
            self.node_kind.as_entire_binding(),
        );
        resources.insert(
            "hir_call_arg_parent_call".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_call_arg_ordinal".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_variant_parent_enum".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_variant_payload_start".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_variant_payload_count".into(),
            self.node_kind.as_entire_binding(),
        );
        resources.insert(
            "hir_variant_payload_node".into(),
            self.parent.as_entire_binding(),
        );
    }

    fn insert_match_resources<'a>(
        &'a self,
        resources: &mut HashMap<String, wgpu::BindingResource<'a>>,
    ) {
        resources.insert(
            "hir_match_arm_result_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_match_payload_owner_arm".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_match_payload_match_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_match_payload_ordinal".into(),
            self.parent.as_entire_binding(),
        );
    }

    fn insert_struct_resources<'a>(
        &'a self,
        resources: &mut HashMap<String, wgpu::BindingResource<'a>>,
    ) {
        resources.insert(
            "hir_struct_field_parent_struct".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_struct_field_ordinal".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_struct_field_type_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_struct_decl_field_start".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_struct_decl_field_count".into(),
            self.node_kind.as_entire_binding(),
        );
        resources.insert(
            "hir_struct_lit_head_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_struct_lit_context_stmt_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_struct_lit_field_start".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_struct_lit_field_count".into(),
            self.node_kind.as_entire_binding(),
        );
        resources.insert(
            "hir_struct_lit_field_parent_lit".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "hir_struct_lit_field_value_node".into(),
            self.parent.as_entire_binding(),
        );
    }

    fn insert_predicate_resources<'a>(
        &'a self,
        resources: &mut HashMap<String, wgpu::BindingResource<'a>>,
    ) {
        resources.insert(
            "predicate_owner_node".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "predicate_subject_token".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "predicate_bound_token".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "predicate_bound_decl_id".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "predicate_bound_arg_count".into(),
            self.node_kind.as_entire_binding(),
        );
        resources.insert(
            "predicate_bound_first_arg_token".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert(
            "predicate_bound_second_arg_token".into(),
            self.parent.as_entire_binding(),
        );
        resources.insert("predicate_status".into(), self.parent.as_entire_binding());
    }
}
