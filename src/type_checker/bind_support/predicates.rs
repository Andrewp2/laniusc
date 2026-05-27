use super::{super::*, common::reflected_bind_group_from_resources};

pub(in crate::type_checker) fn create_predicate_bind_groups(
    device: &wgpu::Device,
    passes: &TypeCheckPasses,
    input: PredicateInput<'_>,
    resident_resources: &HashMap<String, wgpu::BindingResource<'_>>,
) -> Result<PredicateBindGroups> {
    let items = input.hir_items;
    let path = input.module_path;
    let rows = input.rows;

    Ok(PredicateBindGroups {
        collect: bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_resident_predicates_collect"),
            &passes.predicates_collect,
            0,
            &[
                ("gParams", input.params.as_entire_binding()),
                ("hir_status", input.hir_status.as_entire_binding()),
                ("node_kind", items.node_kind.as_entire_binding()),
                ("parent", items.parent.as_entire_binding()),
                ("first_child", items.first_child.as_entire_binding()),
                ("subtree_end", items.subtree_end.as_entire_binding()),
                ("hir_token_pos", input.hir_token_pos.as_entire_binding()),
                (
                    "hir_type_len_value",
                    items.type_len_value.as_entire_binding(),
                ),
                ("hir_item_kind", items.kind.as_entire_binding()),
                (
                    "name_id_by_token",
                    input.name_id_by_token.as_entire_binding(),
                ),
                (
                    "type_decl_generic_param_count_by_node",
                    input.generic_param_count_by_node.as_entire_binding(),
                ),
                (
                    "language_type_code_by_name_id",
                    input.type_code_by_name.as_entire_binding(),
                ),
                ("decl_count_out", path.decl_count_out.as_entire_binding()),
                ("decl_name_id", path.decl_name_id.as_entire_binding()),
                ("decl_kind", path.decl_kind.as_entire_binding()),
                ("decl_namespace", path.decl_namespace.as_entire_binding()),
                ("decl_hir_node", path.decl_hir_node.as_entire_binding()),
                (
                    "module_count_out",
                    path.module_count_out.as_entire_binding(),
                ),
                (
                    "sorted_module_key_order",
                    path.module_key_to_module_id.as_entire_binding(),
                ),
                (
                    "module_key_segment_count",
                    path.module_key_segment_count.as_entire_binding(),
                ),
                (
                    "module_key_segment_base",
                    path.module_key_segment_base.as_entire_binding(),
                ),
                (
                    "module_key_segment_name_id",
                    path.module_key_segment_name_id.as_entire_binding(),
                ),
                (
                    "decl_type_key_count_out",
                    path.decl_type_key_count_out.as_entire_binding(),
                ),
                (
                    "decl_type_key_to_decl_id",
                    path.decl_type_key_to_decl_id.as_entire_binding(),
                ),
                ("decl_module_id", path.decl_module_id.as_entire_binding()),
                ("predicate_owner_node", rows.owner_node.as_entire_binding()),
                (
                    "predicate_subject_token",
                    rows.subject_token.as_entire_binding(),
                ),
                (
                    "predicate_bound_token",
                    rows.bound_token.as_entire_binding(),
                ),
                (
                    "predicate_bound_arg_count",
                    rows.bound_arg_count.as_entire_binding(),
                ),
                (
                    "predicate_bound_first_arg_token",
                    rows.first_arg_token.as_entire_binding(),
                ),
                (
                    "predicate_bound_second_arg_token",
                    rows.second_arg_token.as_entire_binding(),
                ),
                ("predicate_status", rows.status.as_entire_binding()),
            ],
        )?,
        obligations: reflected_bind_group_from_resources(
            device,
            "type_check_resident_predicates_obligations",
            &passes.predicates_obligations,
            resident_resources,
        )?,
    })
}
