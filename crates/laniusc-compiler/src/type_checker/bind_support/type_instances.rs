use super::super::*;

/// Returns the propagation passes needed to attach generic params to owners.
pub(in crate::type_checker) fn generic_decl_owner_step_count(hir_node_capacity: u32) -> u32 {
    let mut covered_depth = 1u32;
    let mut steps = 0u32;
    let target = hir_node_capacity.max(1);
    while covered_depth < target {
        covered_depth = covered_depth.saturating_mul(16);
        steps = steps.saturating_add(1);
    }
    if steps % 2 == 0 {
        steps
    } else {
        steps.saturating_add(1)
    }
}

/// Builds bind groups for collecting, sorting, and projecting type instances.
pub(in crate::type_checker) fn create_type_instance_bind_groups(
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    passes: &TypeCheckPasses,
    resources: &ResourceMap<'_>,
    token_capacity: u32,
    hir_node_capacity: u32,
) -> Result<TypeInstanceBindGroups> {
    let owner_steps = generic_decl_owner_step_count(hir_node_capacity);
    let generic_parameter_index =
        GenericParameterIndex::new(device, graph, passes, resources, token_capacity.max(1))?;
    let struct_field_index =
        StructFieldIndex::new(device, graph, passes, resources, token_capacity.max(1))?;

    let mut propagate_generic_decl_owner = Vec::with_capacity(owner_steps as usize);
    for step in 0..owner_steps {
        let read_owner = if step % 2 == 0 {
            resources["generic_decl_owner_by_node_a"].clone()
        } else {
            resources["generic_decl_owner_by_node_b"].clone()
        };
        let read_jump = if step % 2 == 0 {
            resources["generic_decl_parent_jump_a"].clone()
        } else {
            resources["generic_decl_parent_jump_b"].clone()
        };
        let read_bound_list = if step % 2 == 0 {
            resources["predicate_bound_list_by_node_a"].clone()
        } else {
            resources["predicate_bound_list_by_node_b"].clone()
        };
        let write_owner = if step % 2 == 0 {
            resources["generic_decl_owner_by_node_b"].clone()
        } else {
            resources["generic_decl_owner_by_node_a"].clone()
        };
        let write_jump = if step % 2 == 0 {
            resources["generic_decl_parent_jump_b"].clone()
        } else {
            resources["generic_decl_parent_jump_a"].clone()
        };
        let write_bound_list = if step % 2 == 0 {
            resources["predicate_bound_list_by_node_b"].clone()
        } else {
            resources["predicate_bound_list_by_node_a"].clone()
        };
        propagate_generic_decl_owner.push(resources.reflected_bind_group_with_overrides(
            device,
            "type_check_type_instances_00a1_propagate_generic_decl_owner",
            &passes.kernel("type_checker/type/instances/00a1_propagate_generic_decl_owner"),
            &[
                ("gParams", resources["gParams"].clone()),
                ("compact_hir_count", resources["compact_hir_count"].clone()),
                ("generic_decl_owner_by_node_in", read_owner),
                ("predicate_bound_list_by_node_in", read_bound_list),
                ("generic_decl_parent_jump_in", read_jump),
                ("generic_decl_owner_by_node_out", write_owner),
                ("predicate_bound_list_by_node_out", write_bound_list),
                ("generic_decl_parent_jump_out", write_jump),
            ],
        )?);
    }

    let type_instance_arg_row_scan = PrefixScanOperation::from_spec(
        device,
        passes,
        resources,
        compiler_graph::TYPE_INSTANCE_ARG_ROW_SCAN,
    )?;
    // These scans are recorded before aggregate comparison begins, so the
    // aggregate scan workspace can safely serve both relations without
    // increasing resident scratch memory.
    Ok(TypeInstanceBindGroups {
        clear: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_clear",
            &passes.kernel("type_checker/type/instances/00_clear"),
            resources,
        )?,
        mark_generic_param_records: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_mark_generic_param_records",
            &passes.kernel("type_checker/type/instances/00a_mark_generic_param_records"),
            resources,
        )?,
        propagate_generic_decl_owner,
        type_instance_arg_row_scan,
        decl_generic_params: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_decl_generic_params",
            &passes.kernel("type_checker/type/instances/00b_decl_generic_params"),
            resources,
        )?,
        generic_parameter_index,
        generic_param_use_slots: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_generic_param_use_slots",
            &passes.kernel("type_checker/type/instances/00e_generic_param_use_slots"),
            resources,
        )?,
        struct_field_index,
        collect: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect",
            &passes.kernel("type_checker/type/instances/01_collect"),
            resources,
        )?,
        collect_named: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_named",
            &passes.kernel("type_checker/type/instances/01b_collect_named_instances"),
            resources,
        )?,
        collect_aggregate_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_aggregate_refs",
            &passes.kernel("type_checker/type/instances/01c_collect_aggregate_refs"),
            resources,
        )?,
        collect_aggregate_details: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_aggregate_details",
            &passes.kernel("type_checker/type/instances/01d_collect_aggregate_details"),
            resources,
        )?,
        collect_named_arg_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_named_arg_refs",
            &passes.kernel("type_checker/type/instances/01e_collect_named_arg_refs"),
            resources,
        )?,
        hash_arg_rows: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_hash_arg_rows",
            &passes.kernel("type_checker/type/instances/01g_hash_arg_rows"),
            resources,
        )?,
        clear_semantic_type_rows: Box::new(reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_clear_semantic_type_rows",
            &passes.kernel("type_checker/type/instances/01h_clear_semantic_type_rows"),
            resources,
        )?),
        semantic_type_rows: Box::new(CompactionOperation::indirect(
            device,
            graph,
            resources,
            passes,
            TYPE_SEMANTIC_COMPACTION,
            &typed_buffer_from_resources(resources, "hir_active_dispatch_args")?,
        )?),
        decl_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_decl_refs",
            &passes.kernel("type_checker/type/instances/01f_decl_refs"),
            resources,
        )?,
        member_receivers: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_member_receivers",
            &passes.kernel("type_checker/type/instances/03a_member_receivers"),
            resources,
        )?,
        member_results: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_member_results",
            &passes.kernel("type_checker/type/instances/03_member_results"),
            resources,
        )?,
        member_substitute: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_member_substitute",
            &passes.kernel("type_checker/type/instances/03b_member_substitute"),
            resources,
        )?,
        struct_init_clear: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_clear",
            &passes.kernel("type_checker/type/instances/04a_struct_init_clear"),
            resources,
        )?,
        struct_init_contexts: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_contexts",
            &passes.kernel("type_checker/type/instances/04a2_struct_init_contexts"),
            resources,
        )?,
        struct_init_fields: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_fields",
            &passes.kernel("type_checker/type/instances/04_struct_init_fields"),
            resources,
        )?,
        struct_init_substitute: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_substitute",
            &passes.kernel("type_checker/type/instances/04b_struct_init_substitute"),
            resources,
        )?,
        array_return_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_array_return_refs",
            &passes.kernel("type_checker/type/instances/05_array_return_refs"),
            resources,
        )?,
        array_literal_return_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_array_literal_return_refs",
            &passes.kernel("type_checker/type/instances/05b_array_literal_return_refs"),
            resources,
        )?,
        validate_aggregate_access: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_validate_aggregate_access",
            &passes.kernel("type_checker/type/instances/08_validate_aggregate_access"),
            resources,
        )?,
    })
}
